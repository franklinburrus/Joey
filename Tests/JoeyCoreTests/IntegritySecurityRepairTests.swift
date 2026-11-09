import XCTest
@testable import JoeyCore
@testable import JoeyInterface

/// Regression coverage for the 1e6092c integrity/security repair set.
final class IntegritySecurityRepairTests: XCTestCase {
    func testSanitizeDiagnosticRedactsSyntheticSecretsAndKeepsExitCode() {
        let canary = "JOEY_DUMMY_HELPER_SECRET_DO_NOT_USE"
        let text = Processes.sanitizeDiagnostic(
            """
            OPENAI_API_KEY=\(canary)
            Authorization: Bearer \(canary)
            password=\(canary)
            operational detail remains
            """,
            status:9,executable:"/usr/local/bin/rclone")
        XCTAssertTrue(text.contains("rclone exit 9"))
        XCTAssertTrue(text.contains("[redacted]"))
        XCTAssertTrue(text.contains("operational detail remains"))
        XCTAssertFalse(text.contains(canary))
    }

    func testCredentialPythonRejectsRelativeShellAndSystemInterpreters() {
        XCTAssertThrowsError(try Processes.credentialPython("python3"))
        XCTAssertThrowsError(try Processes.credentialPython("/bin/sh"))
        XCTAssertThrowsError(try Processes.credentialPython("/usr/bin/python3"))
    }

    func testShellHelperCannotReceiveCredentialStdin() async {
        do {
            _ = try await Processes.run("/bin/sh",["-c","true"],input:Data("secret".utf8))
            XCTFail("Shell accepted credential stdin")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Shell interpreters"),error.localizedDescription)
        }
    }

    func testParentDirectoryFsyncPathStillRoundTripsCheckpoint() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        addTeardownBlock {try? FileManager.default.removeItem(at:root)}
        let url = root.appendingPathComponent("job.json")
        try Persistence.save(["state":"processing","marker":"parent-fsync"],to:url)
        let loaded: [String:String] = try Persistence.load(url)
        XCTAssertEqual(loaded["marker"],"parent-fsync")
    }

    func testCapacityWaitCleanupUsesHeldLockWithoutCompetingExclusiveOpen() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        addTeardownBlock {try? FileManager.default.removeItem(at:root)}
        let lock = try ProcessingLock(directory:root)
        defer {withExtendedLifetime(lock) {}}
        // Static clean opens a second exclusive processing.lock and must fail
        // while capacity wait (or any owner) holds the lock.
        XCTAssertThrowsError(try StorageManager.clean(root:root))
        let storage = try StorageManager(root:root,lock:lock)
        let cleaned = try storage.clean()
        XCTAssertEqual(cleaned.removedFiles,0)
        XCTAssertThrowsError(try ProcessingLock(directory:root))
    }

    @MainActor func testReceiveProgressDoesNotStealForeignSelection() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        addTeardownBlock {try? FileManager.default.removeItem(at:root)}
        let model = JobModel(root:root,startsAutomatically:false)
        let first = try Fixtures.request(dir:root,path:"first")
        let second = try Fixtures.request(dir:root,path:"second")
        var jobA = JobRecord(id:"job-a",request:first)
        var jobB = JobRecord(id:"job-b",request:second)
        model.receive(jobA,select:true)
        XCTAssertEqual(model.selected,"job-a")
        model.busy = true
        model.receive(jobB)
        XCTAssertEqual(model.selected,"job-a")
        jobB.stage = "render"
        model.receive(jobB)
        XCTAssertEqual(model.selected,"job-a")
        model.receive(jobB,select:true)
        XCTAssertEqual(model.selected,"job-b")
        jobA.stage = "qa"
        model.receive(jobA)
        XCTAssertEqual(model.selected,"job-b")
    }
}
