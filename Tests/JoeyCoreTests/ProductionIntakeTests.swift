import XCTest
@testable import JoeyCore

final class ProductionIntakeTests: XCTestCase {
    func episode(_ number: Int) -> DiscoveredSource {
        DiscoveredSource(id:"youtube:abcde\(number)xyz",title:"Joe Budden Podcast Episode \(number) | Example",url:"https://www.youtube.com/watch?v=abcde\(number)xyz",duration:3600,channelID:SourceDiscovery.joeChannelID,episodeNumber:number)
    }
    func testQueueBaselineDeduplicationPauseAndRecovery() throws {
        var state = JoeAutomationState()
        try state.enable(after:episode(976))
        state.reconcile([episode(976),episode(978),episode(978)],completed:[])
        XCTAssertEqual(state.queue.map(\.episodeNumber),[978])
        state.reconcile([episode(979),episode(978)],completed:[episode(978).id])
        XCTAssertEqual(state.afterEpisode,976)
        // An older numbered episode appearing late must not be skipped.
        state.reconcile([episode(979),episode(977)],completed:[episode(978).id])
        XCTAssertEqual(state.queue.map(\.episodeNumber),[977,979])
        state.enabled = false
        let bytes = try Persistence.encoder.encode(state)
        state = try Persistence.decoder.decode(JoeAutomationState.self,from:bytes)
        state.reconcile([episode(980)],completed:[])
        XCTAssertEqual(state.queue.map(\.episodeNumber),[977,979])
        try state.enable(after:nil)
        state.reconcile([episode(980)],completed:[episode(979).id])
        XCTAssertEqual(state.queue.map(\.episodeNumber),[977,980])
        XCTAssertEqual(state.afterEpisode,976)
    }
    func testFeedRejectsWrongChannelAndUnfinishedOrUnnumberedUploads() throws {
        let entries: [[String:Any]] = [
            ["id":"abcde976xyz","title":"Joe Budden Podcast Episode 976 | Complete","duration":3600],
            ["id":"abcde977xyz","title":"Joe Budden Podcast Episode 977 | Live","duration":3600,"live_status":"is_live"],
            ["id":"abcde978xyz","title":"Joe Budden Podcast Episode 978 | Pending","duration":3600,"live_status":"post_live"],
            ["id":"abcde979xyz","title":"A clip from episode 979","duration":100]
        ]
        let data = try JSONSerialization.data(withJSONObject:["channel_id":SourceDiscovery.joeChannelID,"entries":entries])
        XCTAssertEqual(try SourceDiscovery.parseJoeFeed(data).map(\.episodeNumber),[976])
        XCTAssertThrowsError(try SourceDiscovery.parseJoeFeed(JSONSerialization.data(withJSONObject:["channel_id":"wrong","entries":entries])))
    }
    func testJoeIntakeKeepsDriveContractSeparateAndRequiresFullProduction() throws {
        var request = try ProductionIntake.request(source:episode(976),content:.joeBudden,mode:.highlights,sharedProfile:nil)
        XCTAssertEqual(request.mode,.fullShow)
        XCTAssertNil(request.archiveRootID,"Joe retains delivered clips, not a permanent full-episode archive")
        XCTAssertEqual(request.profile.driveOnlyJoe,true)
        XCTAssertNil(request.profile.x)
        XCTAssertThrowsError(try ProductionIntake.request(source:episode(976),content:.taxstone,mode:.fullShow,sharedProfile:nil))
        request.transcriptPolicy = .modelIndependent
        XCTAssertThrowsError(try request.validate())
        request.transcriptPolicy = nil;request.fileToDrive = false
        XCTAssertThrowsError(try request.validate())
    }
    func testEveryProductionLaneRequiresDriveForAllClipWorkflows() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let profile = try Fixtures.profile(dir:root)
        let source = DiscoveredSource(id:"youtube:abcdefghijk",title:"Synthetic episode",
            url:"https://www.youtube.com/watch?v=abcdefghijk",duration:1800)
        for content in LinkContent.allCases {
            for mode in [JobMode.fullShow,.highlights] {
                var request = try ProductionIntake.request(source:content == .joeBudden ? episode(976):source,
                    content:content,mode:mode,sharedProfile:profile)
                XCTAssertTrue(request.fileToDrive)
                request.fileToDrive = false
                XCTAssertThrowsError(try request.validate(),"\(content) / \(mode) must require Drive")
            }
        }
    }
    func testHighlightsUseFifteenMinuteBlocksAndSharedLimit() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:dir)}
        var profile = try Fixtures.profile(dir:dir);profile.x!.maxDuration = 140
        let input = DiscoveredSource(id:"youtube:abcdefghijk",title:"Example",url:"https://www.youtube.com/watch?v=abcdefghijk",duration:1801)
        let request = try ProductionIntake.request(source:input,content:.dub,mode:.highlights,sharedProfile:profile)
        let source = SourceRecord(id:input.id,owner:.dub,title:input.title,path:"fixture",bytes:1,sha256:"fixture",duration:1801,width:320,height:180,fps:30,hasAudio:true,kind:.nativeVideo,streams:[],authorizationBasis:"fixture",classificationEvidence:"fixture")
        let transcript = Transcript(sourceID:source.id,sourceSHA256:source.sha256,duration:1801,engine:"fixture",segments:[TranscriptSegment(start:0,end:1801,text:"Complete source.")])
        let clips = try Editorial.plan(request:request,source:source,transcript:transcript,exclusions:[])
        XCTAssertEqual(clips.map(\.intervals),[[Interval(0,140)],[Interval(900,1040)],[Interval(1800,1801)]])
        XCTAssertEqual(try Planning.highlightCount(duration:1800),2)
        XCTAssertThrowsError(try Planning.highlightCount(duration:.infinity))
    }
}

final class JoeCompositionTests: XCTestCase {
    func testApprovedCompositionIncludesFullOutroAndPassesQA() async throws {
        let root = Persistence.defaultRoot
        guard FileManager.default.fileExists(atPath:root.appendingPathComponent("assets/joe-approved-outro.mov").path) else {
            throw XCTSkip("Approved local Joe assets are not installed on this test host")
        }
        let branding = try JoeBranding.load(root:root)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:dir)}
        let media = dir.appendingPathComponent("synthetic.mp4")
        _ = try await Processes.run("ffmpeg",["-v","error","-f","lavfi","-i","testsrc2=s=320x180:r=30:d=2","-f","lavfi","-i","sine=frequency=440:duration=2","-c:v","libx264","-c:a","aac","-shortest",media.path])
        let request = try Fixtures.request(dir:dir,path:media.path)
        let source = try await Media.inspect(media,request:request)
        let clip = ClipRecord(id:1,title:"Synthetic composition",intervals:[Interval(0,2)],filename:"synthetic-output.mp4")
        let output = dir.appendingPathComponent(clip.filename)
        let render = try await Media.render(source:source,clip:clip,profile:.joeBuddenDrive,artwork:nil,work:dir,output:output,branding:branding)
        let qa = try await Media.validate(output:output,source:source,clip:clip,profile:.joeBuddenDrive,render:render,work:dir)
        XCTAssertTrue(qa.passed)
        let probe = try await Media.probe(output)
        XCTAssertEqual(probe.duration,9.3,accuracy:0.075)
        XCTAssertNotNil(qa.checks["approved_logo"])
        XCTAssertNotNil(qa.checks["approved_outro"])
    }
}
