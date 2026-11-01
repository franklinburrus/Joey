import XCTest
@testable import JoeyCore

final class RuntimeTests: XCTestCase {
    func testTestProcessHasNoAIServiceCredentialEnvironment() {
        let names = Set(ProcessInfo.processInfo.environment.keys)
        for name in ["OPENAI_API_KEY", "ANTHROPIC_API_KEY", "GEMINI_API_KEY",
                     "GOOGLE_API_KEY", "AZURE_OPENAI_API_KEY", "HF_TOKEN",
                     "HUGGING_FACE_HUB_TOKEN"] {
            XCTAssertFalse(names.contains(name), "Test process inherited \(name)")
        }
    }
    func testDirectSupervisorDropsUnrelatedSecrets() throws {
        let canary = "JOEY_DUMMY_CREDENTIAL_DO_NOT_USE_20261031"
        let process = Process(), output = Pipe(), errors = Pipe()
        process.executableURL = try ProcessSupervisor.executable()
        process.arguments = ["--supervise", String(getpid()), "/usr/bin/env"]
        // Construct a dummy-only parent, independently of Processes.run.
        process.environment = ["PATH":"/usr/bin:/bin", "LANG":"C",
                               "OPENAI_API_KEY":canary, "UNRELATED_SECRET":canary]
        process.standardOutput = output; process.standardError = errors
        try process.run()
        process.waitUntilExit()
        let diagnostic = String(decoding:output.fileHandleForReading.readDataToEndOfFile()
            + errors.fileHandleForReading.readDataToEndOfFile(),as:UTF8.self)
        XCTAssertEqual(process.terminationStatus,0)
        XCTAssertFalse(diagnostic.contains(canary))
        XCTAssertFalse(diagnostic.contains("OPENAI_API_KEY"))
        XCTAssertFalse(diagnostic.contains("UNRELATED_SECRET"))
        XCTAssertTrue(diagnostic.contains("HF_HUB_OFFLINE=1"))
    }
    func testHelperEnvironmentDropsUnrelatedSecretsAndPreservesOfflinePolicy() async throws {
        let canary = "JOEY_DUMMY_CREDENTIAL_DO_NOT_USE_20261031"
        let injected = ["OPENAI_API_KEY":canary,"UNRELATED_SECRET":canary,"HF_HUB_OFFLINE":"0"]
        let env = Processes.childEnvironment(["HOME":"/test-home","LANG":"C","OPENAI_API_KEY":canary],overrides:injected)
        XCTAssertEqual(env["HOME"],"/test-home");XCTAssertEqual(env["LANG"],"C")
        XCTAssertEqual(env["HF_HUB_OFFLINE"],"1")
        XCTAssertNil(env["OPENAI_API_KEY"]);XCTAssertNil(env["UNRELATED_SECRET"])
        let result = try await Processes.run("/usr/bin/env",[],environment:injected)
        XCTAssertFalse(String(decoding:result.stdout,as:UTF8.self).contains(canary))
        XCTAssertFalse(result.stderr.contains(canary))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:dir)}
        let script = dir.appendingPathComponent("diagnostic.sh")
        try "/usr/bin/env >&2\nexit 7\n".write(to:script,atomically:true,encoding:.utf8)
        do {_ = try await Processes.run("/bin/sh",[script.path],environment:injected);XCTFail("Expected diagnostic failure")}
        catch {
            XCTAssertTrue(error.localizedDescription.contains("exit 7"))
            XCTAssertFalse(error.localizedDescription.contains(canary))
            XCTAssertFalse(error.localizedDescription.contains("OPENAI_API_KEY"))
        }
    }
    func testSHA256AndEvidenceDetectChangedBytes() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("evidence.txt")
        try Data("abc".utf8).write(to: path)
        XCTAssertEqual(try Integrity.sha256(path), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        let evidence = EvidenceFile(path: path.path, sha256: try Integrity.sha256(path), basis: "observed")
        try evidence.validate()
        try Data("changed".utf8).write(to: path)
        XCTAssertThrowsError(try evidence.validate())
    }
    func testAtomicSaveAndExclusiveLockProtectCheckpoint() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let first = try ProcessingLock(directory: dir)
        XCTAssertThrowsError(try ProcessingLock(directory: dir))
        try Persistence.save(["state":"QA_PASSED"], to: dir.appendingPathComponent("job.json"))
        let data: [String:String] = try Persistence.load(dir.appendingPathComponent("job.json"))
        XCTAssertEqual(data["state"], "QA_PASSED")
        withExtendedLifetime(first) {}
    }
    func testProcessCapturesFailureAndDoesNotInterpretShell() async throws {
        let result = try await Processes.run("/usr/bin/printf", ["%s", "$(touch /tmp/joey-must-not-exist); x"])
        XCTAssertEqual(String(decoding: result.stdout, as: UTF8.self), "$(touch /tmp/joey-must-not-exist); x")
        do { _ = try await Processes.run("/usr/bin/false", []); XCTFail("Failure accepted") }
        catch { XCTAssertTrue(error.localizedDescription.contains("exit 1")) }
    }
    func testProcessCancellationStopsLongCommand() async throws {
        let task = Task { try await Processes.run("/bin/sleep", ["30"]) }
        try await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancellation ignored") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
    func testPathComponentsCannotEscapeJobFolder() {
        XCTAssertFalse(Persistence.safeName("../../outside/a\nb").contains("/"))
        XCTAssertFalse(Persistence.safeName("../").hasPrefix("."))
    }
    func testCancellationKillsTermIgnoringDescendants() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:dir)}
        let script = dir.appendingPathComponent("child.sh"), pidFile = dir.appendingPathComponent("child.pid")
        try "trap '' TERM\n/bin/sleep 30 &\necho $! > \"$1\"\nwait\n".write(to:script,atomically:true,encoding:.utf8)
        let task = Task {try await Processes.run("/bin/sh",[script.path,pidFile.path])}
        for _ in 0..<100 where !FileManager.default.fileExists(atPath:pidFile.path) {try await Task.sleep(nanoseconds:20_000_000)}
        let pid = Int32(try String(contentsOf:pidFile,encoding:.utf8).trimmingCharacters(in:.whitespacesAndNewlines))!
        task.cancel()
        do {_ = try await task.value;XCTFail("Cancellation ignored")}
        catch {XCTAssertTrue(error is CancellationError)}
        for _ in 0..<100 where kill(pid,0) == 0 {try await Task.sleep(nanoseconds:20_000_000)}
        XCTAssertNotEqual(kill(pid,0),0,"TERM-ignoring descendant survived cancellation")
    }
}
