import XCTest
@testable import JoeyCore

final class ProcessCaptureTests: XCTestCase {
    func testCapturedStreamsUseAnonymousPipes() async throws {
        let script = "import json,os,stat; print(json.dumps([stat.S_ISFIFO(os.fstat(1).st_mode),stat.S_ISFIFO(os.fstat(2).st_mode)]))"
        let result = try await Processes.run("/usr/bin/python3", ["-c", script], timeout: 5)
        XCTAssertEqual(try JSONDecoder().decode([Bool].self, from: result.stdout), [true, true])
    }

    func testStdoutOverflowStopsProducerBeforeItsNormalExit() async throws {
        let start = ProcessInfo.processInfo.systemUptime
        do {
            _ = try await Processes.run("/usr/bin/python3", ["-c", "import os,time; os.write(1,b'x'*2097152); time.sleep(3)"], maxOutput: 1024, timeout: 6)
            XCTFail("Oversized stdout was accepted")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("bounded capture limit"), error.localizedDescription)
        }
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 2)
    }

    func testStderrOverflowStopsProducerBeforeItsNormalExit() async throws {
        let start = ProcessInfo.processInfo.systemUptime
        do {
            _ = try await Processes.run("/usr/bin/python3", ["-c", "import os,time; os.write(2,b'x'*2097152); time.sleep(3)"], maxOutput: 1024, timeout: 6)
            XCTFail("Oversized stderr was accepted")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("bounded capture limit"), error.localizedDescription)
        }
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 2)
    }

    func testConcurrentStreamsDrainFinalBytesAndKeepDiagnosticTail() async throws {
        let script = "import os,threading; t=threading.Thread(target=lambda:os.write(2,b'e'*100000+b'TAIL')); t.start(); os.write(1,b'o'*100000+b'END'); t.join()"
        let result = try await Processes.run("/usr/bin/python3", ["-c", script], maxOutput: 200000, timeout: 5)
        XCTAssertEqual(result.stdout, Data(repeating: 111, count: 100000) + Data("END".utf8))
        XCTAssertEqual(result.stderr.utf8.count, 6000)
        XCTAssertTrue(result.stderr.hasSuffix("TAIL"))
    }

    func testExactCaptureLimitAndEmptyCaptureRemainSupported() async throws {
        let exact = try await Processes.run("/usr/bin/printf", ["abcd"], maxOutput: 4, timeout: 5)
        XCTAssertEqual(exact.stdout, Data("abcd".utf8))
        let empty = try await Processes.run("/usr/bin/true", [], maxOutput: 0, timeout: 5)
        XCTAssertTrue(empty.stdout.isEmpty)
        do {
            _ = try await Processes.run("/usr/bin/printf", ["abcde"], maxOutput: 4, timeout: 5)
            XCTFail("One byte over the limit was accepted")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("bounded capture limit"))
        }
    }

    func testExplicitLargeFileOutputPreservesBytes() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("large.bin")
        let result = try await Processes.run("/usr/bin/python3", ["-c", "import os; os.write(1,b'x'*100000)"], output: output, maxOutput: 4, timeout: 5)
        XCTAssertTrue(result.stdout.isEmpty)
        XCTAssertEqual(try Data(contentsOf: output), Data(repeating: 120, count: 100000))
    }

    func testOverflowKillsTermIgnoringDescendantsForBothStreams() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for stream in [1, 2] {
            let pidFile = directory.appendingPathComponent("child-\(stream).pid")
            let script = "import os,signal,subprocess,sys,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); child=subprocess.Popen(['/bin/sleep','30']); open(sys.argv[1],'w').write(str(child.pid)); os.write(\(stream),b'x'*2097152); time.sleep(30)"
            do {
                _ = try await Processes.run("/usr/bin/python3", ["-c", script, pidFile.path], maxOutput: 1024, timeout: 5)
                XCTFail("Oversized stream was accepted")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("bounded capture limit"))
            }
            let pid = try XCTUnwrap(Int32(String(contentsOf: pidFile, encoding: .utf8)))
            for _ in 0..<100 where kill(pid, 0) == 0 { try await Task.sleep(nanoseconds: 20_000_000) }
            XCTAssertNotEqual(kill(pid, 0), 0, "Overflow left a TERM-ignoring descendant")
        }
    }

    func testSuccessfulWrapperDrainsAndStopsBackgroundDescendants() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pidFile = directory.appendingPathComponent("child.pid")
        let script = "import os,signal,subprocess,sys; signal.signal(signal.SIGTERM,signal.SIG_IGN); child=subprocess.Popen(['/bin/sleep','30']); open(sys.argv[1],'w').write(str(child.pid)); os.write(1,b'final bytes')"
        let result = try await Processes.run("/usr/bin/python3", ["-c", script, pidFile.path], timeout: 5)
        XCTAssertEqual(result.stdout, Data("final bytes".utf8))
        let pid = try XCTUnwrap(Int32(String(contentsOf: pidFile, encoding: .utf8)))
        for _ in 0..<100 where kill(pid, 0) == 0 { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertNotEqual(kill(pid, 0), 0, "Successful wrapper left a descriptor-owning descendant")
    }

    func testDownloaderArgumentsDelegateRetryBudgetToNativeOwner() {
        let url = URL(string: "https://www.youtube.com/watch?v=abcdefghijk")!
        for arguments in [Acquisition.metadataArguments(for: url), Acquisition.downloadArguments(for: url, directory: URL(fileURLWithPath: "/unused"))] {
            for flag in ["--retries", "--fragment-retries", "--extractor-retries"] {
                guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else {
                    XCTFail("Missing explicit retry flag \(flag)")
                    continue
                }
                XCTAssertEqual(arguments[index + 1], "0", flag)
            }
        }
    }
}
