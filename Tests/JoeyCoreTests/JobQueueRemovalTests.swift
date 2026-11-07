import XCTest
@testable import JoeyCore
@testable import JoeyInterface

final class JobQueueRemovalTests: XCTestCase {
    private func workspace() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        addTeardownBlock {try? FileManager.default.removeItem(at:root)}
        return root
    }
    private func saveJob(_ name: String, root: URL) throws -> JobRecord {
        var request = try Fixtures.request(dir:root,path:"unused synthetic source")
        request.sourceID = name
        let job = JobRecord(id:try request.stableID(),request:request)
        try Persistence.save(job,to:root.appendingPathComponent("jobs/\(job.id)/job.json"))
        return job
    }
    @MainActor func testBulkRemovalSurvivesRestartWithoutDeletingIdentityOrArtifactsAndCanRestore() async throws {
        let root = try workspace()
        let a = try saveJob("a",root:root), b = try saveJob("b",root:root), c = try saveJob("c",root:root)
        let checkpoint = root.appendingPathComponent("jobs/\(a.id)/job.json")
        let original = try Data(contentsOf:checkpoint)
        let media = root.appendingPathComponent("jobs/\(a.id)/accepted.mp4")
        try Data("retained accepted synthetic bytes".utf8).write(to:media)
        let model = JobModel(root:root,startsAutomatically:false)
        await model.refresh()
        let removed = await model.removeJobs([a.id,b.id])
        XCTAssertTrue(removed)
        XCTAssertEqual(model.visibleJobs.map(\.id),[c.id])
        XCTAssertEqual(Set(model.removedJobs.map(\.id)),[a.id,b.id])
        let reopened = JobModel(root:root,startsAutomatically:false)
        await reopened.refresh()
        XCTAssertEqual(reopened.visibleJobs.map(\.id),[c.id])
        XCTAssertTrue(reopened.restoreJobs([a.id]))
        XCTAssertEqual(Set(reopened.visibleJobs.map(\.id)),[a.id,c.id])
        let inventory = try await Coordinator(root:root).inventory()
        XCTAssertEqual(Set(inventory.jobs.map(\.id)),[a.id,b.id,c.id])
        XCTAssertTrue(inventory.failures.isEmpty)
        XCTAssertEqual(try Data(contentsOf:checkpoint),original)
        XCTAssertEqual(try String(contentsOf:media,encoding:.utf8),"retained accepted synthetic bytes")
    }
    func testRemovedIdentityCannotRunUntilRestoredAndCheckpointIsUntouched() async throws {
        let root = try workspace(), job = try saveJob("removed",root:root)
        let checkpoint = root.appendingPathComponent("jobs/\(job.id)/job.json")
        let original = try Data(contentsOf:checkpoint)
        try JobQueue.setRemoved([job.id],removed:true,root:root)
        do {
            _ = try await Coordinator(root:root).run(job.request)
            XCTFail("Removed jobs must not acquire or process a source")
        } catch {XCTAssertTrue(error.localizedDescription.contains("removed"),error.localizedDescription)}
        XCTAssertEqual(try Data(contentsOf:checkpoint),original)
        try JobQueue.setRemoved([job.id],removed:false,root:root)
        let resumed = try await Coordinator(root:root).run(job.request) { job in
            if job.state != .cancelled {throw CancellationError()}
        }
        XCTAssertEqual(resumed.id,job.id)
        XCTAssertEqual(resumed.state,.cancelled)
    }
    @MainActor func testRemovalSaveFailureLeavesVisibleQueueAndWorkerUntouched() async throws {
        let root = try workspace(), job = try saveJob("retained",root:root)
        let model = JobModel(root:root,startsAutomatically:false)
        await model.refresh()
        let lock = try ProcessingLock(directory:root,name:"job-queue.lock")
        defer {withExtendedLifetime(lock) {}}
        let removed = await model.removeJobs([job.id])
        XCTAssertFalse(removed)
        XCTAssertEqual(model.visibleJobs.map(\.id),[job.id])
        XCTAssertNotNil(model.error)
        XCTAssertTrue(model.removedJobs.isEmpty)
    }
    @MainActor func testRemovingActiveJobCancelsAndDrainsRealStorageWaitWithoutResumingIt() async throws {
        let root = try workspace(), model = JobModel(root:root,startsAutomatically:false)
        var request = try Fixtures.request(dir:root,path:root.appendingPathComponent("unused.mp4").path)
        request.transcriptPolicy = .modelIndependent
        let result = StorageManager.$capacityOverride.withValue({0}) {model.start(request)}
        XCTAssertEqual(result,.accepted)
        let processing = try XCTUnwrap(model.task)
        defer {processing.cancel()}
        for _ in 0..<200 where model.jobs.first?.storageRequiredBytes == nil {
            try await Task.sleep(nanoseconds:10_000_000)
        }
        let job = try XCTUnwrap(model.jobs.first)
        XCTAssertNotNil(job.storageRequiredBytes)
        let removed = await model.removeJobs([job.id])
        XCTAssertTrue(removed)
        XCTAssertTrue(processing.isCancelled)
        XCTAssertFalse(model.busy)
        XCTAssertTrue(model.visibleJobs.isEmpty)
        let saved: JobRecord = try Persistence.load(root.appendingPathComponent("jobs/\(job.id)/job.json"))
        XCTAssertEqual(saved.state,.cancelled)
        XCTAssertFalse(saved.resumesAutomatically)
        XCTAssertNil(model.error)
    }
    @MainActor func testRemovingInactiveJobDoesNotCancelUnselectedActiveJob() async throws {
        let root = try workspace(), old = try saveJob("old",root:root)
        let model = JobModel(root:root,startsAutomatically:false)
        await model.refresh()
        var request = try Fixtures.request(dir:root,path:"unused")
        request.sourceID = "active";request.transcriptPolicy = .modelIndependent
        XCTAssertEqual(StorageManager.$capacityOverride.withValue({0}) {model.start(request)},.accepted)
        let processing = try XCTUnwrap(model.task)
        defer {processing.cancel()}
        for _ in 0..<200 where model.jobs.first?.storageRequiredBytes == nil {
            try await Task.sleep(nanoseconds:10_000_000)
        }
        let removed = await model.removeJobs([old.id])
        XCTAssertTrue(removed)
        XCTAssertFalse(processing.isCancelled)
        XCTAssertTrue(model.busy)
        model.cancel();await processing.value
    }
    @MainActor func testRemovingSameSourceHighlightDoesNotCancelActiveLibraryFullShow() async throws {
        let root = try workspace(), full = try saveJob("shared-source",root:root)
        var highlights = full
        highlights.request.mode = .highlights
        highlights.id = try highlights.request.stableID()
        try Persistence.save(highlights,to:root.appendingPathComponent("jobs/\(highlights.id)/job.json"))
        let model = JobModel(root:root,startsAutomatically:false)
        await model.refresh()
        model.libraryBusy = true
        model.taxstoneLibrary.currentSourceID = full.request.sourceID
        var episode = TaxstoneLibraryEpisode(id:full.request.sourceID,title:"Library fixture",driveID:"original",sourceSHA256:"fixture")
        episode.jobID = full.id
        model.taxstoneLibrary.episodes = [episode]
        let parent = Task {do {try await Task.sleep(nanoseconds:100_000_000)} catch {}}
        model.libraryTask = parent
        XCTAssertTrue(model.isRunning(full))
        XCTAssertFalse(model.isRunning(highlights))
        let removed = await model.removeJobs([highlights.id])
        XCTAssertTrue(removed)
        XCTAssertFalse(parent.isCancelled,"An inactive highlight must not cancel its source's full-show worker")
        parent.cancel();await parent.value
    }
    @MainActor func testRemovedInterruptedJobIsNotRecoveredAtStartup() async throws {
        let root = try workspace()
        var job = try saveJob("interrupted",root:root)
        job.state = .processing
        let checkpoint = root.appendingPathComponent("jobs/\(job.id)/job.json")
        try Persistence.save(job,to:checkpoint)
        let before = try Data(contentsOf:checkpoint)
        try JobQueue.setRemoved([job.id],removed:true,root:root)
        let model = JobModel(root:root,startsAutomatically:true,recentJoeEpisodes:{[]})
        await model.startupTask?.value
        XCTAssertTrue(model.visibleJobs.isEmpty)
        XCTAssertEqual(model.removedJobs.map(\.id),[job.id])
        XCTAssertEqual(try Data(contentsOf:checkpoint),before)
        XCTAssertNil(model.task)
    }
    func testQueueUpdatesPreserveOtherDispositionsAndUnreadableStateFailsClosed() throws {
        let root = try workspace()
        try JobQueue.setRemoved(["a"],removed:true,root:root)
        try JobQueue.setRemoved(["b"],removed:true,root:root)
        try JobQueue.setRemoved(["a"],removed:false,root:root)
        XCTAssertEqual(try JobQueue.removedIDs(root:root),["b"])
        try Data("invalid".utf8).write(to:root.appendingPathComponent("job-queue.json"))
        XCTAssertThrowsError(try JobQueue.setRemoved(["c"],removed:true,root:root))
        XCTAssertEqual(try String(contentsOf:root.appendingPathComponent("job-queue.json"),encoding:.utf8),"invalid")
    }
}
