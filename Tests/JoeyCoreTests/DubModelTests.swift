import XCTest
@testable import JoeyCore
@testable import JoeyInterface

final class DubModelTests: XCTestCase {
    @MainActor func testCheckNowAutomaticallyStartsSavedJobWithoutAnotherAction() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let item = DubBroadcastTests().broadcast()
        let request = try DubBroadcastDiscovery.request(item)
        var job = JobRecord(id:try request.stableID(),request:request)
        job.source = SourceRecord(id:request.sourceID,owner:.dub,title:request.title,episodeDate:request.episodeDate,
            originalURL:request.originalURL,path:root.appendingPathComponent("missing-original.mp4").path,bytes:1,sha256:String(repeating:"a",count:64),duration:3600,
            width:128,height:72,fps:30,hasAudio:true,kind:.nativeVideo,streams:[],authorizationBasis:"Synthetic fixture",classificationEvidence:"Synthetic fixture")
        try Persistence.save(job,to:root.appendingPathComponent("jobs/\(job.id)/job.json"))
        let model = JobModel(root:root,startsAutomatically:false)
        model.dubScan = {DubDiscoveryScan(urls:[],status:"Synthetic manual scan")}
        let calls = DubTestCalls()
        model.dubLookup = {url in await calls.append(url);return item}
        XCTAssertNil(model.dubBroadcasts.lastCheckedAt)
        model.checkDubBroadcasts([item.source.url])
        for _ in 0..<400 {
            if !model.scanningDub && !model.dubRunning {break}
            try await Task.sleep(nanoseconds:25_000_000)
        }
        XCTAssertFalse(model.scanningDub)
        XCTAssertFalse(model.dubRunning)
        XCTAssertEqual(model.selected,job.id,"Check Now must start the existing coordinator job automatically")
        XCTAssertEqual(model.dubBroadcasts.entries.first?.jobID,job.id)
        XCTAssertEqual(model.dubBroadcasts.entries.first?.state,.failed)
        XCTAssertNotNil(model.dubBroadcasts.entries.first?.error)
        let urls = await calls.ids()
        XCTAssertEqual(urls,[item.source.url])
        XCTAssertEqual(model.jobs.count,1)
    }
    @MainActor func testPauseCancelsOutstandingDiscoveryWithoutRestartingWork() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let item = DubBroadcastTests().broadcast(),model = JobModel(root:root,startsAutomatically:false)
        let calls = DubTestCalls()
        model.busy = true
        model.dubScan = {
            try await Task.sleep(nanoseconds:150_000_000)
            return DubDiscoveryScan(urls:[item.source.url],status:"Synthetic scan")
        }
        model.dubLookup = {url in await calls.append(url);return item}
        model.checkDubBroadcasts([])
        try await Task.sleep(nanoseconds:25_000_000)
        model.pauseDubBroadcasts()
        for _ in 0..<200 {
            if !model.scanningDub && !model.cancelling {break}
            try await Task.sleep(nanoseconds:10_000_000)
        }
        let lookedUp = await calls.ids()
        XCTAssertTrue(lookedUp.isEmpty)
        XCTAssertTrue(model.dubBroadcasts.paused)
        XCTAssertFalse(model.dubRunning)
    }

}
