import XCTest
@testable import JoeyCore

final class DubWebsiteDiscoveryTests: XCTestCase {
    func testWebsiteCatalogSuppliesCandidatesWithoutTrustingTitlesDatesOrProxyMedia() throws {
        let object: [String:Any] = ["broadcasts":[
            ["id":"original123","sourceUrl":"https://x.com/i/broadcasts/original123","title":"Unverified title","date":"2099-01-01","hlsUrl":"https://example.invalid/proxy"],
            ["id":"space123","sourceUrl":"https://x.com/i/spaces/space123"],
            ["id":"mismatch","sourceUrl":"https://x.com/i/broadcasts/other123"],
            ["id":"reposted","sourceUrl":"https://example.invalid/i/broadcasts/reposted"]]]
        let urls = try DubWebsiteDiscovery.catalogURLs(JSONSerialization.data(withJSONObject:object))
        XCTAssertEqual(urls,["https://x.com/i/broadcasts/original123"])
    }
    func testOfficialProfileURLsAreCanonicalAndDeduplicated() throws {
        let data = try JSONSerialization.data(withJSONObject:["https://x.com/i/broadcasts/abc123?test=1",
            "https://x.com/i/broadcasts/abc123","https://example.invalid/i/broadcasts/evil","https://x.com/other/status/1"])
        XCTAssertEqual(try DubWebsiteDiscovery.profileURLs(data),["https://x.com/i/broadcasts/abc123"])
    }
    func testFirstDiscoveryQueuesLatestDayWithoutHistoricalCatalogBackfill() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let fixtures = DubBroadcastTests()
        let old = fixtures.broadcast("old",date:"2026-09-01",time:100)
        let first = fixtures.broadcast("first",time:200),second = fixtures.broadcast("second",time:300)
        let items = [old,second,first]
        let queue = try DubBroadcastQueue(root:root)
        try await queue.checkNow(urls:[],jobs:[],discoveredURLs:items.map(\.source.url),lookup:{url in items.first {$0.source.url == url}!})
        var state = await queue.snapshot()
        XCTAssertEqual(state.entries.map(\.id),[first.source.id,second.source.id])
        XCTAssertEqual(state.discoveryStartDate,"2026-11-05")
        // An explicit original URL is the historical backfill mechanism.
        try await queue.checkNow(urls:[old.source.url],jobs:[],lookup:{_ in old})
        state = await queue.snapshot()
        XCTAssertEqual(state.entries.first?.id,old.source.id)
        XCTAssertEqual(state.entries.count,3)
    }
    func testUndatedDiscoveredReplayIsQueuedAfterDatedWithoutInventingDate() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let fixtures = DubBroadcastTests(),dated = fixtures.broadcast(),unknown = fixtures.broadcast("unknown",date:nil,time:nil)
        let queue = try DubBroadcastQueue(root:root)
        try await queue.checkNow(urls:[],jobs:[],discoveredURLs:[unknown.source.url,dated.source.url],lookup:{url in url == dated.source.url ? dated:unknown})
        let state = await queue.snapshot()
        XCTAssertEqual(state.entries.map(\.id),[dated.source.id,unknown.source.id])
        XCTAssertNil(state.entries.last?.broadcast.source.episodeDate)
        XCTAssertNil(state.entries.last?.broadcast.startedAt)
    }

}
