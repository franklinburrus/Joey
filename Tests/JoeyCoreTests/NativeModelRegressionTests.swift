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
