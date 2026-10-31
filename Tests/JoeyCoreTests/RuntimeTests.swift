import XCTest
@testable import JoeyCore

final class RuntimeTests: XCTestCase {
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
