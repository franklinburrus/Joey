import XCTest
import SwiftUI
@testable import JoeyCore
@testable import JoeyInterface

final class NativeModelRegressionTests: XCTestCase {
    @MainActor private func model() throws -> JobModel {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        addTeardownBlock {try? FileManager.default.removeItem(at:root)}
        return JobModel(root:root,startsAutomatically:false)
    }

    @MainActor func testManualResumePreflightRejectsExpiredEvidenceWithoutStartingOrMutatingCheckpoint() async throws {
        let model = try model()
        var request = try Fixtures.request(dir:model.root,path:"unused synthetic source")
        request.owner = .taxstone
        request.profile.x!.account = "synthetic-private-account"
        request.profile.x!.surface = "synthetic-private-surface"
        request.profile.x!.validUntil = Date().addingTimeInterval(-10)
        request.profile.x!.checkedAt = Date().addingTimeInterval(-100)
        request.profile.instagram!.validUntil = Date().addingTimeInterval(-10)
        request.profile.instagram!.checkedAt = Date().addingTimeInterval(-100)
        var config = Configuration()
        config.taxstoneProfile = request.profile
        try Persistence.save(config,to:model.root.appendingPathComponent("settings.json"))
        let job = JobRecord(id:try request.stableID(),request:request)
        let checkpoint = model.root.appendingPathComponent("jobs/\(job.id)/job.json")
        try Persistence.save(job,to:checkpoint)
        let before = try Data(contentsOf:checkpoint)
        let issue = model.resumeIssue(for:job)
        XCTAssertNotNil(issue)
        let details = model.resumeDiagnostics(for:job).joined(separator:" ")
        XCTAssertTrue(details.contains("expires"))
        XCTAssertFalse(details.contains("synthetic-private-account"))
        XCTAssertFalse(details.contains("synthetic-private-surface"))
        XCTAssertFalse(details.contains(model.root.path))
        XCTAssertEqual(model.resume(job),.unavailable)
        XCTAssertFalse(model.busy)
        XCTAssertNil(model.task)
        XCTAssertEqual(try Data(contentsOf:checkpoint),before)
    }

    @MainActor func testInterleavedJoeTurnsAdvancePastFailuresAcrossReconciliationAndRestart() async throws {
        let model = try model()
        model.libraryBusy = true;model.joeAutomation.enabled = true;model.joeAutomation.afterEpisode = 0
        let episodes = (1...2).map {(number: Int) -> DiscoveredSource in
            DiscoveredSource(id:"youtube:abcdefghij\(number)",title:"Episode \(number)",url:"https://www.youtube.com/watch?v=abcdefghij\(number)",
                             duration:600,channelID:SourceDiscovery.joeChannelID,episodeNumber:number)
        }
        var ids: [String] = []
        for episode in episodes {
            let request = try ProductionIntake.request(source:episode,content:.joeBudden,mode:.fullShow,sharedProfile:nil)
            var job = JobRecord(id:try request.stableID(),request:request)
            job.state = .failed;job.updatedAt = .distantPast
            // No branding is configured in this isolated root: the real
            // coordinator fails locally before provider lookup or media work.
            try Persistence.save(job,to:model.root.appendingPathComponent("jobs/\(job.id)/job.json"))
            ids.append(job.id)
        }
        model.joeAutomation.queue = episodes
        await model.refresh()
        await model.runJoeQueue(interleaved:true)
        XCTAssertEqual(model.selected,ids[0])
        XCTAssertEqual(model.jobs.first {$0.id == ids[1]}?.updatedAt,.distantPast)
        XCTAssertEqual(model.joeAutomation.queue.count,2)
        // A feed refresh re-sorts the queue; restart must not lose the turn.
        model.joeAutomation.reconcile(episodes,completed:[])
        let saved: JoeAutomationState = try Persistence.load(model.root.appendingPathComponent("joe-automation.json"))
        model.joeAutomation = saved
        model.joeAutomation.reconcile(episodes,completed:[])
        await model.runJoeQueue(interleaved:true)
        XCTAssertEqual(model.selected,ids[1])
        XCTAssertEqual(model.joeAutomation.queue.count,2)
        await model.runJoeQueue(interleaved:true)
        XCTAssertEqual(model.selected,ids[0])
    }

    @MainActor func testCancelInterleavedTaskStopsWorkerAndRetainsQueuesAndCheckpoint() async throws {
        let model = try model(), marker = model.root.appendingPathComponent("worker.pid")
        let checkpoint = model.root.appendingPathComponent("checkpoint.json")
        var queue = JoeAutomationState()
        queue.enabled = true
        queue.queue = [DiscoveredSource(id:"youtube:synthetic",title:"Queued fixture",url:"https://example.invalid/fixture",duration:600,episodeNumber:1)]
        model.joeAutomation = queue
        model.automationRunning = true
        model.taxstoneLibrary.episodes = [TaxstoneLibraryEpisode(id:"soundcloud:synthetic",title:"Retained library fixture",driveID:"fixture-original",sourceSHA256:"fixture")]
        try Persistence.save(model.taxstoneLibrary,to:model.root.appendingPathComponent("taxstone-library.json"))
        let provider = CancellationWriteDouble()
        // Simulate Joe's actual separate task while the library awaits it.
        model.task = Task {
            do {
                try await provider.dispatch()
                try Persistence.save(["stage":"upload uncertain"],to:checkpoint)
                _ = try await Processes.run("/bin/sh",["-c","echo $$ > \"$1\"; exec /bin/sleep 30","fixture",marker.path])
                try Task.checkCancellation()
                try await provider.dispatch()
            } catch {}
        }
        let processing = try XCTUnwrap(model.task)
        model.libraryBusy = true
        model.libraryTask = Task {await processing.value}
        let library = try XCTUnwrap(model.libraryTask)
        for _ in 0..<200 where !FileManager.default.fileExists(atPath:marker.path) {
            try await Task.sleep(nanoseconds:10_000_000)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath:marker.path))
        let pid = Int32(try String(contentsOf:marker,encoding:.utf8).trimmingCharacters(in:.whitespacesAndNewlines))!
        model.cancel()
        // Bound failure while still cleaning up the baseline's orphaned worker.
        for _ in 0..<200 where kill(pid,0) == 0 {try await Task.sleep(nanoseconds:10_000_000)}
        let stopped = kill(pid,0) != 0
        processing.cancel();library.cancel()
        await processing.value;await library.value
        XCTAssertTrue(stopped,"Cancel left the active interleaved Joe worker alive")
        XCTAssertTrue(FileManager.default.fileExists(atPath:checkpoint.path))
        XCTAssertEqual(model.joeAutomation.queue.map(\.id),queue.queue.map(\.id))
        XCTAssertEqual(model.taxstoneLibrary.episodes.map(\.id),["soundcloud:synthetic"])
        let savedQueue: JoeAutomationState = try Persistence.load(model.root.appendingPathComponent("joe-automation.json"))
        XCTAssertEqual(savedQueue.queue.map(\.id),queue.queue.map(\.id))
        XCTAssertFalse(savedQueue.enabled)
        let writes = await provider.writes
        XCTAssertEqual(writes,1,"No provider write may begin after cancellation")
    }

    @MainActor func testLibraryParentCancellationPropagatesAndAwaitsProcessingTask() async throws {
        let model = try model()
        var drained = false
        let processing = Task {
            do {try await Task.sleep(nanoseconds:30_000_000_000)} catch {}
            drained = true
        }
        let parent = Task {await model.waitForProcessing(processing)}
        parent.cancel()
        await parent.value
        XCTAssertTrue(processing.isCancelled)
        XCTAssertTrue(drained,"Parent returned before its worker completed cancellation")
    }

    @MainActor func testCancellingStorageWaitPreservesCheckpointWithoutShowingAnErrorAlert() async throws {
        let model = try model()
        var request = try Fixtures.request(dir: model.root, path: model.root.appendingPathComponent("not-acquired.mp4").path)
        request.transcriptPolicy = .modelIndependent
        // The real coordinator must stop at storage admission, before source
        // acquisition, media tools or provider operations can begin.
        let acceptance = StorageManager.$capacityOverride.withValue({ 0 }) { model.start(request) }
        XCTAssertEqual(acceptance, .accepted)
        let processing = try XCTUnwrap(model.task)
        defer { processing.cancel() }
        for _ in 0..<200 where model.jobs.first?.storageRequiredBytes == nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let blocked = try XCTUnwrap(model.jobs.first)
        XCTAssertNotNil(blocked.storageRequiredBytes)
        XCTAssertEqual(blocked.state, .processing)
        XCTAssertTrue(model.busy)

        model.cancel()
        XCTAssertTrue(model.cancelling)
        await processing.value
        for _ in 0..<100 where model.cancelling { try await Task.sleep(nanoseconds: 1_000_000) }

        XCTAssertNil(model.error, "Expected cancellation must not present Joey needs attention")
        XCTAssertFalse(model.busy)
        XCTAssertFalse(model.cancelling)
        XCTAssertNil(model.task)
        XCTAssertEqual(model.selected, blocked.id)
        let displayed = try XCTUnwrap(model.jobs.first { $0.id == blocked.id })
        let saved: JobRecord = try Persistence.load(model.root.appendingPathComponent("jobs/\(blocked.id)/job.json"))
        XCTAssertEqual(try Persistence.encoder.encode(displayed), try Persistence.encoder.encode(saved))
        XCTAssertEqual(saved.state, .cancelled)
        XCTAssertEqual(saved.stage, "Paused while storage blocked")
        XCTAssertNil(saved.storageRequiredBytes)
        XCTAssertFalse(saved.resumesAutomatically)
        XCTAssertEqual(try saved.request.identityData(), try request.identityData())
        XCTAssertTrue(saved.error?.contains("progress preserved") == true, saved.error ?? "")
    }

    @MainActor func testOrdinaryStartFailureStillShowsAnErrorAlert() async throws {
        let model = try model()
        var invalid = try Fixtures.request(dir: model.root, path: "unused")
        invalid.sourceID = ""
        XCTAssertEqual(model.start(invalid), .accepted)
        let processing = try XCTUnwrap(model.task)
        await processing.value
        XCTAssertTrue(model.error?.contains("Source identity") == true, model.error ?? "Missing failure alert")
        XCTAssertFalse(model.busy)
        XCTAssertNil(model.task)
        XCTAssertTrue(model.jobs.isEmpty)
    }

    @MainActor func testTaxstoneIntakeSetupUsesSelectedOwnerAndOnlySavesTaxstone() throws {
        let model = try model()
        let dub = try Fixtures.profile(dir:model.root)
        var taxstone = dub;taxstone.x!.account = "JailCallwithTax";taxstone.instagram!.account = "thejailcallwithtaxstone"
        model.configuration?.profile = dub
        let intake = NewJobView(model:model,initialContent:.taxstone,started:{})
        let setup = intake.productionSetup
        XCTAssertEqual(setup.owner,.taxstone)
        try setup.persist(profile:taxstone)
        let saved: Configuration = try Persistence.load(model.root.appendingPathComponent("settings.json"))
        XCTAssertEqual(try Persistence.encoder.encode(saved.profile),try Persistence.encoder.encode(dub))
        XCTAssertEqual(try Persistence.encoder.encode(saved.taxstoneProfile),try Persistence.encoder.encode(taxstone))
    }
}

private actor CancellationWriteDouble {
    var writes = 0
    func dispatch() throws {try Task.checkCancellation();writes += 1}
}
