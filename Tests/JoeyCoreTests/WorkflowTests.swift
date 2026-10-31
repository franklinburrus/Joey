import XCTest
@testable import JoeyCore

final class WorkflowTests: XCTestCase {
    func testLocalJobRecoversWithoutRerenderingAcceptedClip() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:dir)}
        let media = dir.appendingPathComponent("source.mp4")
        _ = try await Processes.run("ffmpeg",["-v","error","-f","lavfi","-i","testsrc2=s=320x180:r=30:d=2","-f","lavfi","-i","sine=frequency=440:duration=2","-c:v","libx264","-c:a","aac","-shortest",media.path])
        var request = try Fixtures.request(dir:dir,path:media.path)
        let transcriptURL = dir.appendingPathComponent("input-transcript.json")
        let transcript = Transcript(sourceID:request.sourceID,sourceSHA256:try Integrity.sha256(media),duration:2,engine:"fixture",segments:[TranscriptSegment(start:0,end:2,text:"A complete synthetic test sentence.")])
        try Persistence.save(transcript,to:transcriptURL); request.transcriptPath = transcriptURL.path
        // Use the serialized snapshot exactly as the app's imported request does.
        request = try Persistence.decoder.decode(JobRequest.self,from:Persistence.encoder.encode(request))
        let coordinator = try Coordinator(root:dir.appendingPathComponent("runtime"))
        let first = try await coordinator.run(request)
        XCTAssertEqual(first.state,.qaPassed,first.error ?? "")
        XCTAssertEqual(first.clips.count,1)
        guard let clip = first.clips.first else {return}
        let jobDir = await coordinator.directory(for:first.id)
        let output = jobDir.appendingPathComponent(clip.filename)
        let date = try output.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate
        var interrupted = first; interrupted.state = .processing; interrupted.stage = "Drive clip 1"
        try Persistence.save(interrupted,to:jobDir.appendingPathComponent("job.json"))
        let recovered = try await coordinator.run(request)
        XCTAssertEqual(recovered.state,.qaPassed,recovered.error ?? "")
        XCTAssertEqual(recovered.clips.first?.sha256,clip.sha256)
        XCTAssertEqual(try output.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate,date)
        XCTAssertTrue(FileManager.default.fileExists(atPath:jobDir.appendingPathComponent("clip_manifest.json").path))
        let manifest = try JSONSerialization.jsonObject(with:Data(contentsOf:jobDir.appendingPathComponent("clip_manifest.json"))) as? [String:Any]
        XCTAssertEqual((manifest?["intervalMappings"] as? [[String:Any]])?.count,1)
        XCTAssertTrue(FileManager.default.fileExists(atPath:jobDir.appendingPathComponent("evidence/1/qa.json").path))
        let attempts = jobDir.appendingPathComponent("scratch/1")
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath:attempts.path).isEmpty)
        let cancelled = try await Task {
            try await coordinator.run(request) { job in
                if job.stage == "source" {withUnsafeCurrentTask {$0?.cancel()}}
            }
        }.value
        XCTAssertEqual(cancelled.state,.cancelled)
        XCTAssertFalse(cancelled.resumesAutomatically)
        XCTAssertEqual(cancelled.clips.first?.qa?.passed,true)
        XCTAssertEqual(try Integrity.sha256(output),clip.sha256)
        var filed = first; filed.state = .filed
        XCTAssertTrue(filed.resumesAutomatically)
    }
    func testExpiredCapabilityAndFixedIntervalConflictFail() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:dir)}
        var profile = try Fixtures.profile(dir:dir)
        XCTAssertEqual(profile.width,720)
        profile.x.validUntil = Date().addingTimeInterval(-1)
        XCTAssertThrowsError(try profile.validate())
        var request = try Fixtures.request(dir:dir,path:"unused")
        request.mode = .highlights; request.fixedIntervals = [Interval(0,700)]
        let source = SourceRecord(id:request.sourceID,owner:.dub,title:"Fixture",path:"unused",bytes:1,sha256:"fixture",duration:1000,width:320,height:180,fps:30,hasAudio:true,kind:.nativeVideo,streams:[],authorizationBasis:"fixture",classificationEvidence:"fixture")
        let transcript = Transcript(sourceID:source.id,sourceSHA256:source.sha256,duration:1000,engine:"fixture",segments:[TranscriptSegment(start:0,end:700,text:"Complete sentence.")])
        XCTAssertThrowsError(try Editorial.plan(request:request,source:source,transcript:transcript,exclusions:[]))
    }
    func testUncertainAdsStayAndBoundedSponsoredReadIsExcluded() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:dir)}
        let request = try Fixtures.request(dir:dir,path:"unused")
        let t = Transcript(sourceID:"fixture",sourceSHA256:"fixture",duration:100,engine:"fixture",segments:[
            TranscriptSegment(start:0,end:10,text:"We mentioned a brand today."),
            TranscriptSegment(start:10,end:20,text:"This episode is sponsored by Example."),
            TranscriptSegment(start:20,end:30,text:"A paid product offer."),
            TranscriptSegment(start:30,end:40,text:"Back to the show."),
            TranscriptSegment(start:40,end:50,text:"Another uncertain promotion.")])
        XCTAssertEqual(Editorial.exclusions(request,transcript:t).map(\.interval),[Interval(10,30)])
    }
    func testCSVProtectsFormulaTitlesAndPreservesQuotes() {
        XCTAssertEqual(Records.csv([["=1+1","a,\"b"]]),"\"'=1+1\",\"a,\"\"b\"\r\n")
        XCTAssertThrowsError(try Records.validateHeaders(["Title","Title"]))
        XCTAssertEqual(Records.columnName(26),"AA")
    }
    func testNativeAudioArtworkAndWaveformRender() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:dir)}
        let audio = dir.appendingPathComponent("source.wav"), art = dir.appendingPathComponent("art.png")
        _ = try await Processes.run("ffmpeg",["-v","error","-f","lavfi","-i","sine=frequency=500:duration=2","-af","volume=if(lt(t\\,1)\\,0\\,1):eval=frame",audio.path])
        _ = try await Processes.run("ffmpeg",["-v","error","-f","lavfi","-i","testsrc2=s=300x300","-frames:v","1",art.path])
        var request = try Fixtures.request(dir:dir,path:audio.path);request.owner = .taxstone
        let source = try await Media.inspect(audio,request:request)
        XCTAssertEqual(source.kind,.audio)
        let artwork = Artwork(owner:.taxstone,sourceID:source.id,driveID:"fixture",file:EvidenceFile(path:art.path,sha256:try Integrity.sha256(art),basis:"Synthetic test artwork"))
        let clip = ClipRecord(id:1,title:"Fixture",intervals:[Interval(0,2)],filename:"clip.mp4")
        let output = dir.appendingPathComponent("clip.mp4")
        let render = try await Media.render(source:source,clip:clip,profile:request.profile,artwork:artwork,work:dir,output:output)
        let qa = try await Media.validate(output:output,source:source,clip:clip,profile:request.profile,render:render,work:dir)
        XCTAssertTrue(qa.passed)
        let corrupted = dir.appendingPathComponent("missing-wave.mp4")
        _ = try await Processes.run("ffmpeg",["-v","error","-i",output.path,"-vf","drawbox=x=60:y=932:w=600:h=124:color=black:t=fill","-c:v","libx264","-pix_fmt","yuv420p","-c:a","copy","-movflags","+faststart",corrupted.path])
        do {_ = try await Media.validate(output:corrupted,source:source,clip:clip,profile:request.profile,render:render,work:dir);XCTFail("Missing waveform accepted")}
        catch {XCTAssertTrue(error.localizedDescription.contains("waveform"),error.localizedDescription)}
    }
}
