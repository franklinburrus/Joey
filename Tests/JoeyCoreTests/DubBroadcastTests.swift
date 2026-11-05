import XCTest
@testable import JoeyCore

final class DubBroadcastTests: XCTestCase {
    func broadcast(_ id: String = "synthetic123", date: String? = "2026-11-05", time: Double? = 100) -> DubBroadcast {
        DubBroadcast(source:DiscoveredSource(id:"x:broadcast:"+id,title:"Synthetic broadcast",url:"https://x.com/i/broadcasts/"+id,
            duration:3600,episodeDate:date),broadcasterID:DubBroadcastDiscovery.broadcasterID,startedAt:time,verifiedAt:Date())
    }
    func testNativeProfileSeparatesBufferAndJoeAndPreservesFullCoverage() throws {
        let item = broadcast()
        let request = try DubBroadcastDiscovery.request(item)
        XCTAssertEqual(request.productionWorkflow,.dubBroadcast)
        XCTAssertTrue(request.profile.isDriveOnly)
        XCTAssertNil(request.profile.driveOnlyJoe)
        XCTAssertNil(request.profile.x)
        try request.validate()
        for kind in [MediaKind.audio,.nativeVideo] {
            var source = SourceRecord(id:item.source.id,owner:.dub,title:item.source.title,episodeDate:item.source.episodeDate,path:"fixture",bytes:1,sha256:String(repeating:"a",count:64),duration:3600,
                width:1920,height:1080,fps:30,hasAudio:true,kind:kind,streams:[],authorizationBasis:"Fixture",classificationEvidence:"Fixture")
            for duration in [3600.0,5400,125,1200.123456] {
                source.duration = duration
                let transcript = Transcript(sourceID:source.id,sourceSHA256:source.sha256,duration:duration,engine:"fixture",
                    segments:[TranscriptSegment(start:0,end:duration,text:"Whole program.")])
                let clips = try Editorial.plan(request:request,source:source,transcript:transcript,exclusions:[])
                if duration == 3600 {XCTAssertEqual(clips.map(\.expectedDuration),Array(repeating:600,count:6))}
                XCTAssertEqual(clips.last?.intervals.last?.end,duration)
                XCTAssertTrue(clips.allSatisfy {$0.expectedDuration <= 600})
                try Planning.validateCoverage(duration:duration,exclusions:[],clips:clips.map(\.intervals))
            }
            let root = try DestinationResolver.resolve(source:source,request:request,asset:.clip).rootID
            XCTAssertEqual(root,kind == .audio ? "1FRi-yy2D9yenjQRailTA2iAbPaqAEPXm":"1380CHJ3a3kl7fXNIKWqUM7_DeTZUwxsy")
            let canvas = try request.profile.outputProfile(for:kind)
            XCTAssertEqual(canvas.width,kind == .audio ? 1080:1920)
        }
        var wrong = request;wrong.owner = .taxstone
        XCTAssertThrowsError(try wrong.validate())
        wrong = request;wrong.productionWorkflow = .link
        XCTAssertThrowsError(try wrong.validate())
        XCTAssertThrowsError(try BufferPreflight.validateProfile(request.profile,owner:.dub,workflow:.dubBroadcast))
    }

    func testConcurrentDiscoveryCannotChangeDispatchedIdentity() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let queue = try DubBroadcastQueue(root:root)
        let later = broadcast("later",time:200),earlier = broadcast("earlier",time:100)
        try await queue.checkNow(urls:[later.source.url],jobs:[],lookup:{_ in later})
        let calls = DubTestCalls()
        try await queue.run(jobs:[],process:{request in
            await calls.append(request.sourceID)
            throw JoeyError.dependency("Expected fixture failure")
        },progress:{state in
            if state.currentID == later.source.id {
                try? await queue.checkNow(urls:[earlier.source.url],jobs:[],lookup:{$0 == earlier.source.url ? earlier:later})
            }
        })
        let actual = await calls.ids()
        XCTAssertEqual(actual,[later.source.id,earlier.source.id])
    }


    func testDubDownloaderUsesOnlyOuterThreeAttemptPolicy() throws {
        let url = URL(string:"https://x.com/i/broadcasts/synthetic123")!
        let args = Acquisition.downloadArguments(for:url,directory:FileManager.default.temporaryDirectory,nativeMaster:true)
        for option in ["--retries","--fragment-retries","--extractor-retries"] {
            XCTAssertEqual(args[args.firstIndex(of:option)!+1],"0")
        }
        let metadata = Acquisition.metadataArguments(for:url,nativeMaster:true)
        XCTAssertEqual(metadata[metadata.firstIndex(of:"--retries")!+1],"0")
    }
    func testQueuePauseRecoveryAndExclusiveOwner() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let queue = try DubBroadcastQueue(root:root),item = broadcast()
        XCTAssertThrowsError(try DubBroadcastQueue(root:root))
        try await queue.checkNow(urls:[item.source.url],jobs:[],lookup:{_ in item})
        try await queue.pause()
        let calls = DubTestCalls()
        try await queue.run(jobs:[],process:{request in
            await calls.append(request.sourceID)
            throw JoeyError.failed("Expected")
        })
        let pausedCalls = await calls.ids()
        XCTAssertTrue(pausedCalls.isEmpty)
        try await queue.resume()
        let resumed = await queue.snapshot()
        XCTAssertTrue(resumed.hasRunnableWork)
        try await queue.run(jobs:[],process:{_ in throw CancellationError()})
        let cancelled = await queue.snapshot()
        XCTAssertTrue(cancelled.paused)
        XCTAssertEqual(cancelled.entries.first?.state,.cancelled)
        XCTAssertNotNil(cancelled.entries.first?.error)
    }
    func testSavedQueueLoadNeverDiscoversAdditionalBroadcasts() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        var state = DubBroadcastState()
        state.urls = [broadcast().source.url]
        try Persistence.save(state,to:root.appendingPathComponent("dub-broadcasts.json"))
        let queue = try DubBroadcastQueue(root:root)
        let loaded = await queue.snapshot()
        XCTAssertNil(loaded.lastCheckedAt)
        XCTAssertTrue(loaded.entries.isEmpty)
        XCTAssertFalse(loaded.hasRunnableWork)
    }


    func testQueueDoesNotTrustCompletedEntryWithoutItsCheckpoint() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let item = broadcast()
        var entry = DubBroadcastEntry(broadcast:item,request:try DubBroadcastDiscovery.request(item))
        entry.state = .completed;entry.jobID = "missing-checkpoint"
        var state = DubBroadcastState();state.entries = [entry]
        try Persistence.save(state,to:root.appendingPathComponent("dub-broadcasts.json"))
        let queue = try DubBroadcastQueue(root:root)
        try await queue.checkNow(urls:[item.source.url],jobs:[],lookup:{_ in item})
        let calls = DubTestCalls()
        try await queue.run(jobs:[],process:{request in
            await calls.append(request.sourceID)
            throw JoeyError.failed("Replacement processing must not start")
        })
        let result = await queue.snapshot(),processed = await calls.ids()
        XCTAssertEqual(result.entries.first?.state,.failed)
        XCTAssertTrue(result.entries.first?.error?.contains("checkpoint") == true)
        XCTAssertTrue(processed.isEmpty)
    }


    func testNormalLinkIntakeUsesNativeMastersAndRequiresVerifiedBroadcaster() throws {
        var item = broadcast()
        XCTAssertThrowsError(try ProductionIntake.request(source:item.source,content:.dub,mode:.fullShow,sharedProfile:nil))
        item.source.channelID = DubBroadcastDiscovery.broadcasterID
        let request = try ProductionIntake.request(source:item.source,content:.dub,mode:.fullShow,sharedProfile:nil)
        XCTAssertEqual(request.productionWorkflow,.dubBroadcast)
        XCTAssertTrue(request.profile.dubNativeMaster == true)
        XCTAssertThrowsError(try ProductionIntake.request(source:item.source,content:.dub,mode:.highlights,sharedProfile:nil))
    }

    func testNativeMasterVideoUsesSourceOnlyRendererWithoutSocialEvidenceOrJoeBranding() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let original = root.appendingPathComponent("synthetic.mp4")
        _ = try await Processes.run("ffmpeg",["-v","error","-f","lavfi","-i","testsrc2=s=128x72:r=30:d=2","-f","lavfi","-i","sine=frequency=440:duration=2","-c:v","libx264","-c:a","aac","-shortest",original.path])
        let source = try await Media.inspect(original,request:Fixtures.request(dir:root,path:original.path))
        let clip = ClipRecord(id:1,title:"Synthetic short-source exception",intervals:[Interval(0,2)],filename:"native-master.mp4")
        let output = root.appendingPathComponent(clip.filename)
        let render = try await Media.render(source:source,clip:clip,profile:.dubBroadcastMaster,artwork:nil,work:root,output:output)
        XCTAssertNil(render.joeBranding)
        let qa = try await Media.validate(output:output,source:source,clip:clip,profile:.dubBroadcastMaster,render:render,work:root)
        XCTAssertTrue(qa.passed)
        let probe = try await Media.probe(output)
        XCTAssertEqual(probe.duration,2,accuracy:0.075)
        XCTAssertEqual(probe.video?.width,1920)
        XCTAssertEqual(render.pictureWidth,128)
        XCTAssertEqual(render.pictureHeight,72)
    }

    func testAdsAndFractionalRemainderRetainExactlyOnce() throws {
        let ranges = try Planning.fullShow(duration:5400.123456,exclusions:[Interval(125.123456,155.654321)])
        try Planning.validateCoverage(duration:5400.123456,exclusions:[Interval(125.123456,155.654321)],clips:ranges)
        XCTAssertEqual(ranges.last?.last?.end,5400.123456)
        XCTAssertThrowsError(try Planning.validateCoverage(duration:600,exclusions:[],clips:[[Interval(0,400)],[Interval(399,600)]]))
    }
    func testIdentityRejectsUnavailableReplayOrWrongOriginalBroadcaster() throws {
        let item = broadcast()
        let info: [String:Any] = ["id":"synthetic123","title":"Synthetic broadcast","duration":3600,"is_live":false,"live_status":"was_live"]
        var evidence: [String:Any] = ["id":"synthetic123","twitter_user_id":DubBroadcastDiscovery.broadcasterID,"state":"ENDED","available_for_replay":true]
        let parsed = try DubBroadcastDiscovery.verify(source:item.source,metadata:info,broadcast:evidence)
        XCTAssertNil(parsed.startedAt)
        evidence["available_for_replay"] = false
        XCTAssertThrowsError(try DubBroadcastDiscovery.verify(source:item.source,metadata:info,broadcast:evidence))
        evidence["available_for_replay"] = true;evidence["twitter_user_id"] = "another-account"
        XCTAssertThrowsError(try DubBroadcastDiscovery.verify(source:item.source,metadata:info,broadcast:evidence))
    }
    func testDurableQueueOldestFirstDedupFailureContinuationAndRestart() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let items = [broadcast("later",time:200),broadcast("earlier",time:100),broadcast("unknown",date:nil,time:nil)]
        let calls = DubTestCalls()
        do {
            let queue = try DubBroadcastQueue(root:root)
            try await queue.checkNow(urls:items.map(\.source.url),jobs:[],lookup:{url in items.first {$0.source.url == url}!})
            try await queue.checkNow(urls:items.map(\.source.url),jobs:[],lookup:{url in items.first {$0.source.url == url}!})
            let state = await queue.snapshot()
            XCTAssertEqual(state.entries.map(\.id),[items[1].source.id,items[0].source.id,items[2].source.id])
            try await queue.run(jobs:[],process:{request in
                await calls.append(request.sourceID)
                throw JoeyError.dependency("Synthetic exact failure "+request.sourceID)
            })
            let failed = await queue.snapshot()
            XCTAssertTrue(failed.entries.allSatisfy {$0.error?.contains("Synthetic exact failure") == true})
            XCTAssertEqual(failed.entries.count,3)
            let processed = await calls.ids()
            XCTAssertEqual(processed,state.entries.map(\.id))
        }
        let reopened = try DubBroadcastQueue(root:root)
        let saved = await reopened.snapshot()
        XCTAssertEqual(saved.entries.count,3)
        XCTAssertTrue(saved.entries.allSatisfy {$0.error != nil})
        XCTAssertFalse(saved.hasRunnableWork,"Failed attempts require Check Now or explicit Resume")
        let before = saved.entries
        try await reopened.checkNow(urls:[items[0].source.url],jobs:[],lookup:{_ in throw JoeyError.dependency("Replay unavailable")})
        let after = await reopened.snapshot()
        XCTAssertEqual(after.entries.map(\.id),before.map(\.id))
        XCTAssertTrue(after.lastError?.contains("Replay unavailable") == true)
    }
}

actor DubTestCalls {
    var values: [String] = []
    func append(_ value: String) {values.append(value)}
    func ids() -> [String] {values}
}
