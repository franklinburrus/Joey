import XCTest
@testable import JoeyCore
@testable import JoeyInterface

final class JobInventoryTests: XCTestCase {
    private func workspace() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        addTeardownBlock {try? FileManager.default.removeItem(at:root)}
        return root
    }
    private func saveHealthy(in root: URL) throws -> JobRecord {
        let request = try Fixtures.request(dir:root,path:"unused synthetic source")
        let job = JobRecord(id:try request.stableID(),request:request)
        try Persistence.save(job,to:root.appendingPathComponent("jobs/\(job.id)/job.json"))
        return job
    }
    private func damaged(in root: URL) throws -> URL {
        let file = root.appendingPathComponent("jobs/legacy-damaged/job.json")
        try FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true)
        try Data("{ invalid JSON with synthetic-private-canary".utf8).write(to:file)
        return file
    }
    func testReadableHistoryAndSafeFailureRemainVisibleWithoutMutatingFiles() async throws {
        let root = try workspace(), healthy = try saveHealthy(in:root), bad = try damaged(in:root)
        let original = try Data(contentsOf:bad)
        let coordinator = try Coordinator(root:root)
        let inventory = try await coordinator.inventory()
        XCTAssertEqual(inventory.jobs.map(\.id),[healthy.id])
        XCTAssertEqual(inventory.failures.count,1)
        XCTAssertEqual(inventory.failures.first?.directoryID,"legacy-damaged")
        XCTAssertFalse(inventory.failures[0].message.contains("synthetic-private-canary"))
        XCTAssertEqual(try Data(contentsOf:bad),original)
        let compatible = try await coordinator.jobs()
        XCTAssertEqual(compatible.map(\.id),[healthy.id])
    }
    func testUnknownCheckpointPreventsNewIdentityBeforeAnyJobWrite() async throws {
        let root = try workspace(), bad = try damaged(in:root)
        let request = try Fixtures.request(dir:root,path:"unused synthetic source")
        let original = try Data(contentsOf:bad)
        do {
            _ = try await Coordinator(root:root).run(request)
            XCTFail("An unresolved legacy identity must prevent a competing job")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("checkpoint"),error.localizedDescription)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:root.appendingPathComponent("jobs").path),["legacy-damaged"])
        XCTAssertEqual(try Data(contentsOf:bad),original)
    }
    func testKnownReadableJobCanResumeAndRestoringCheckpointClearsIssue() async throws {
        let root = try workspace(), healthy = try saveHealthy(in:root), bad = try damaged(in:root)
        let result = try await Coordinator(root:root).run(healthy.request) {job in
            if job.stage == "source",job.error == nil {throw CancellationError()}
        }
        XCTAssertEqual(result.id,healthy.id)
        XCTAssertEqual(result.state,.cancelled)
        var repaired = healthy
        repaired.id = "legacy-damaged"
        try Persistence.save(repaired,to:bad)
        let inventory = try await Coordinator(root:root).inventory()
        XCTAssertTrue(inventory.failures.isEmpty)
        XCTAssertEqual(inventory.jobs.count,2)
    }
    func testMismatchedIdentityMissingCheckpointAndSymlinkAreReported() async throws {
        let root = try workspace(), healthy = try saveHealthy(in:root)
        let jobs = root.appendingPathComponent("jobs")
        try Persistence.save(healthy,to:jobs.appendingPathComponent("wrong-directory/job.json"))
        let missing = jobs.appendingPathComponent("missing-checkpoint")
        try FileManager.default.createDirectory(at:missing,withIntermediateDirectories:true)
        try Data("retained synthetic artifact".utf8).write(to:missing.appendingPathComponent("clip.mp4"))
        let outside = try workspace()
        try FileManager.default.createSymbolicLink(at:jobs.appendingPathComponent("linked"),withDestinationURL:outside)
        try FileManager.default.createDirectory(at:jobs.appendingPathComponent("empty-scaffold"),withIntermediateDirectories:true)
        let inventory = try await Coordinator(root:root).inventory()
        XCTAssertEqual(Set(inventory.failures.map(\.directoryID)),["wrong-directory","missing-checkpoint","linked"])
        XCTAssertEqual(inventory.jobs.map(\.id),[healthy.id])
    }
    @MainActor func testModelRefreshRetainsHealthyHistoryAndExposesRecovery() async throws {
        let root = try workspace(), healthy = try saveHealthy(in:root)
        _ = try damaged(in:root)
        let model = JobModel(root:root,startsAutomatically:false)
        await model.refresh()
        XCTAssertEqual(model.jobs.map(\.id),[healthy.id])
        XCTAssertEqual(model.checkpointFailures.count,1)
    }
}
