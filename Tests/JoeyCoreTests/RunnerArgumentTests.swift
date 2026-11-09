import XCTest
@testable import JoeyCore


final class RunnerArgumentTests: XCTestCase {
    func testInvalidRootAndEpisodeLimitNeverFallBackToDefaults() {
        for arguments in [
            ["storage-clean", "--root"], ["storage-clean", "--root", ""],
            ["taxstone-run", "--root", "--limit", "1"],
            ["taxstone-run", "--limit"], ["taxstone-run", "--limit", "none"],
            ["taxstone-run", "--limit", "0"], ["taxstone-run", "--limit", "-1"],
            ["taxstone-run", "--limit", "999999999999999999999999999"],
            ["taxstone-run", "--limit", "1", "--limit", "2"],
            ["run"], ["run", "one.json", "two.json"], ["unknown"]
        ] {
            XCTAssertThrowsError(try RunnerArguments(arguments), arguments.joined(separator: " "))
        }
    }

    func testValidInvocationPreservesExplicitScopeAndLimit() throws {
        let bounded = try RunnerArguments(["taxstone-run", "--limit", "2", "--root", "/tmp/Joey Test Runtime"])
        XCTAssertEqual(bounded.command, .taxstoneRun)
        XCTAssertEqual(bounded.root.path, "/tmp/Joey Test Runtime")
        XCTAssertEqual(bounded.limit, 2)
        let run = try RunnerArguments(["run", "--root", "/tmp/Joey Test Runtime", "/tmp/request.json"])
        XCTAssertEqual(run.request?.path, "/tmp/request.json")
        XCTAssertEqual(run.root.path, "/tmp/Joey Test Runtime")
        XCTAssertNil(run.limit)
        let defaults = try RunnerArguments(["list"])
        XCTAssertEqual(defaults.root, Persistence.defaultRoot)
        XCTAssertNil(defaults.request)
    }

    func testMalformedOptionsFailBeforeOpeningRuntime() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {try? FileManager.default.removeItem(at: directory)}
        let executable = Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("joey-run")
        for (index, invalid) in [["--root"], ["--unknown"], ["--limit", "not-a-number"], ["extra-argument"]].enumerated() {
            let runtime = directory.appendingPathComponent("runtime-\(index)")
            let process = Process(), output = Pipe()
            process.executableURL = executable
            process.arguments = ["list", "--root", runtime.path] + invalid
            process.environment = ["PATH": "/usr/bin:/bin", "HOME": directory.path]
            process.standardOutput = output; process.standardError = output
            try process.run(); process.waitUntilExit()
            let diagnostic = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            XCTAssertNotEqual(process.terminationStatus, 0, diagnostic)
            XCTAssertFalse(FileManager.default.fileExists(atPath: runtime.path), "Invalid arguments must fail before initializing or mutating runtime data")
        }
    }
}
