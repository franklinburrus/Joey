import XCTest
@testable import JoeyCore
@testable import JoeyInterface

final class IsolatedNativeFixtureVerification: XCTestCase {
    @MainActor func testIsolatedRootControlsAcrossResumeStorageWaitAndCancel() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Joey-process-control-ui-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("jobs"), withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        XCTAssertNotEqual(root.standardizedFileURL, Persistence.defaultRoot.standardizedFileURL)
        try Persistence.save(Configuration(), to: root.appendingPathComponent("settings.json"))

        var request = try Fixtures.request(dir: root, path: root.appendingPathComponent("synthetic-stopped.mp4").path)
        request.transcriptPolicy = .modelIndependent
        request.title = "Process Control Fixture | Stopped"
        var stoppedJob = JobRecord(id: try request.stableID(), request: request)
        stoppedJob.state = .cancelled
        stoppedJob.stage = "Paused while storage blocked"
        stoppedJob.error = "Paused while storage blocked; progress preserved"
        stoppedJob.clips = (1...3).map {
            ClipRecord(id: $0, title: "Clip \($0)", intervals: [Interval(Double($0), Double($0) + 1)], filename: "\($0).mp4")
        }
        try Persistence.save(stoppedJob, to: root.appendingPathComponent("jobs/\(stoppedJob.id)/job.json"))

        let model = JobModel(root: root, startsAutomatically: false)
        await model.refresh()
        let job = try XCTUnwrap(model.jobs.first)
        XCTAssertEqual(job.id, stoppedJob.id)
        XCTAssertFalse(model.isRunning(job))
        let stopped = JobPresentation(job: job).processControls(isRunning: false)
        XCTAssertEqual(stopped.status, "Stopped — progress saved")
        XCTAssertTrue(stopped.showsResume)
        XCTAssertFalse(stopped.showsCancel)
        XCTAssertEqual(JobPresentation(job: job).accepted, 0)

        var blocked = job
        blocked.state = .processing
        blocked.storageRequiredBytes = 14_950_834_612
        blocked.error = "Storage blocked: need 14950834612 bytes including operating-system reserve; available 8201310208. Progress retained."
        let wait = JobPresentation(job: blocked).processControls(isRunning: true)
        XCTAssertEqual(wait.status, "Paused while storage blocked — need 14950834612 bytes; 8201310208 bytes available when paused")
        XCTAssertTrue(wait.showsCancel)
        XCTAssertFalse(wait.showsResume)

        let stopping = JobPresentation(job: job).processControls(isRunning: true, isCancelling: true)
        XCTAssertEqual(stopping.status, "Stopping — saving progress")
        XCTAssertTrue(stopping.showsCancel)

        let liveRoot = FileManager.default.temporaryDirectory.appendingPathComponent("Joey-process-control-live-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: liveRoot.appendingPathComponent("jobs"), withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: liveRoot) }
        try Persistence.save(Configuration(), to: liveRoot.appendingPathComponent("settings.json"))
        let live = JobModel(root: liveRoot, startsAutomatically: false)
        var liveRequest = try Fixtures.request(dir: liveRoot, path: liveRoot.appendingPathComponent("not-acquired.mp4").path)
        liveRequest.transcriptPolicy = .modelIndependent
        XCTAssertEqual(StorageManager.$capacityOverride.withValue({ 0 }) { live.start(liveRequest) }, .accepted)
        let processing = try XCTUnwrap(live.task)
        for _ in 0..<200 where live.jobs.first?.storageRequiredBytes == nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let blockedLive = try XCTUnwrap(live.jobs.first)
        let mid = JobPresentation(job: blockedLive).processControls(isRunning: live.isRunning(blockedLive))
        XCTAssertTrue(mid.status.hasPrefix("Paused while storage blocked — need "))
        XCTAssertTrue(mid.showsCancel)
        XCTAssertTrue(live.busy)

        live.cancel()
        for _ in 0..<200 {
            if let current = live.jobs.first(where: { $0.id == blockedLive.id }) {
                let chrome = JobPresentation(job: current).processControls(isRunning: live.isRunning(current), isCancelling: live.cancelling)
                if current.state == .cancelled && live.isRunning(current) {
                    XCTAssertEqual(chrome.status, "Stopping — saving progress")
                    XCTAssertTrue(chrome.showsCancel)
                    XCTAssertFalse(chrome.showsResume)
                    break
                }
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        await processing.value
        for _ in 0..<100 where live.cancelling { try await Task.sleep(nanoseconds: 1_000_000) }
        let final = try XCTUnwrap(live.jobs.first { $0.id == blockedLive.id })
        XCTAssertFalse(live.busy)
        XCTAssertFalse(live.isRunning(final))
        let done = JobPresentation(job: final).processControls(isRunning: false)
        XCTAssertEqual(done.status, "Stopped — progress saved")
        XCTAssertTrue(done.showsResume)
        XCTAssertFalse(done.showsCancel)

    }
}
