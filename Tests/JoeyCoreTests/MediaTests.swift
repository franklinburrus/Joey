import XCTest
@testable import JoeyCore

final class MediaTests: XCTestCase {
    private func assertDisplayGeometry(sampleAspect: String, rotation: Int?, width: Int, height: Int) async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("joey-geometry-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:dir)}
        let encoded = dir.appendingPathComponent("encoded.mp4")
        _ = try await Processes.run("ffmpeg",["-v","error","-f","lavfi","-i","testsrc2=s=320x180:r=30:d=2",
            "-vf","setsar=\(sampleAspect)","-c:v","libx264","-pix_fmt","yuv420p",encoded.path])
        let sourceURL: URL
        if let rotation {
            sourceURL = dir.appendingPathComponent("rotated.mp4")
            _ = try await Processes.run("ffmpeg",["-v","error","-display_rotation",String(rotation),"-i",encoded.path,"-c","copy",sourceURL.path])
        } else {sourceURL = encoded}
        var source = try await Media.inspect(sourceURL,request:Fixtures.request(dir:dir,path:sourceURL.path))
        XCTAssertEqual(source.kind,.nativeVideo)
        if let rotation {
            XCTAssertEqual(source.streams.first(where: {$0.codec_type == "video"})?.side_data_list?.compactMap(\.rotation).first,Double(rotation),"The fixture must carry actual display rotation")
            // Legacy checkpoints did not serialize display matrices. Rendering
            // must recover metadata from the unchanged original, not rerun intake.
            for index in source.streams.indices {source.streams[index].side_data_list = nil}
        }
        let profile = try Fixtures.profile(dir:dir)
        let clip = ClipRecord(id:1,title:"Display geometry",intervals:[Interval(0,2)],filename:"clip.mp4")
        let output = dir.appendingPathComponent(clip.filename)
        let render = try await Media.render(source:source,clip:clip,profile:profile,artwork:nil,work:dir,output:output)
        XCTAssertEqual(render.pictureWidth,width,"Effective picture width must describe the displayed source, not coded pixels")
        XCTAssertEqual(render.pictureHeight,height,"Effective picture height must include sample aspect and display rotation")
        let qa = try await Media.validate(output:output,source:source,clip:clip,profile:profile,render:render,work:dir)
        XCTAssertTrue(qa.passed,"A correctly fitted source must pass the independent picture-timing check")
    }

    func testAnamorphicSourceRetainsDisplayProportionsAndPassesQA() async throws {
        try await assertDisplayGeometry(sampleAspect:"2/1",rotation:nil,width:320,height:90)
    }

    func testRotatedSourceRetainsDisplayOrientationAndPassesQA() async throws {
        try await assertDisplayGeometry(sampleAspect:"1/1",rotation:90,width:180,height:320)
    }

    func testInspectionRejectsUnmappedMultipleVideoTracks() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("joey-multivideo-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:dir)}
        let source = dir.appendingPathComponent("two-angles.mp4")
        _ = try await Processes.run("ffmpeg",["-v","error","-f","lavfi","-i","testsrc2=s=160x90:r=30:d=1",
            "-f","lavfi","-i","testsrc2=s=128x96:r=30:d=1","-map","0:v","-map","1:v","-c:v","libx264","-pix_fmt","yuv420p",source.path])
        do {
            _ = try await Media.inspect(source,request:Fixtures.request(dir:dir,path:source.path))
            XCTFail("A second source video track would be silently omitted by the single-video render mapping")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("video tracks") && error.localizedDescription.contains("preservation mapping"),"Unexpected inspection error: \(error)")
        }
    }

    func testSingleArtworkVideoStreamRemainsAudioContent() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("joey-audio-artwork-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:dir)}
        let source = dir.appendingPathComponent("artwork.mp4")
        _ = try await Processes.run("ffmpeg",["-v","error","-f","lavfi","-i","color=blue:s=160x90:r=30:d=1",
            "-f","lavfi","-i","sine=frequency=440:duration=1","-c:v","libx264","-pix_fmt","yuv420p","-c:a","aac",source.path])
        let inspected = try await Media.inspect(source,request:Fixtures.request(dir:dir,path:source.path))
        XCTAssertEqual(inspected.kind,.audio)
        XCTAssertTrue(inspected.hasAudio)
    }

    func testResumedMultivideoCheckpointCannotRenderOrPassQA() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("joey-multivideo-resume-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:dir)}
        let sourceURL = dir.appendingPathComponent("two-angles.mp4")
        _ = try await Processes.run("ffmpeg",["-v","error","-f","lavfi","-i","testsrc2=s=160x90:r=30:d=1",
            "-f","lavfi","-i","testsrc2=s=128x96:r=30:d=1","-map","0:v","-map","1:v","-c:v","libx264","-pix_fmt","yuv420p",sourceURL.path])
        let probe = try await Media.probe(sourceURL)
        // Older inspection accepted both visual tracks. Its saved source can
        // reach render or partial-output QA without another inspection.
        let legacy = SourceRecord(id:"two-angles",owner:.dub,title:"Two source angles",path:sourceURL.path,
            bytes:Int64(try Data(contentsOf:sourceURL).count),sha256:try Integrity.sha256(sourceURL),duration:1,
            width:160,height:90,fps:30,hasAudio:false,kind:.nativeVideo,streams:probe.streams,
            authorizationBasis:"Generated test media",classificationEvidence:"Legacy multiple-track inspection")
        let profile = try Fixtures.profile(dir:dir)
        let clip = ClipRecord(id:1,title:"Two angles",intervals:[Interval(0,1)],filename:"clip.mp4")
        do {
            _ = try await Media.render(source:legacy,clip:clip,profile:profile,artwork:nil,work:dir,output:dir.appendingPathComponent(clip.filename))
            XCTFail("Resuming an old source checkpoint silently discarded its second video track")
        } catch {XCTAssertTrue(error.localizedDescription.contains("preservation mapping"),"Unexpected render error: \(error)")}

        let partial = dir.appendingPathComponent("legacy-partial.mp4")
        _ = try await Processes.run("ffmpeg",["-v","error","-i",sourceURL.path,"-map","0:v:0","-vf",
            "pad=720:1280:(ow-iw)/2:(oh-ih)/2:black,setsar=1","-c:v","libx264","-pix_fmt","yuv420p","-movflags","+faststart",partial.path])
        do {
            _ = try await Media.validate(output:partial,source:legacy,clip:clip,profile:profile,
                render:RenderReceipt(pictureWidth:160,pictureHeight:90),work:dir)
            XCTFail("QA accepted a legacy output after a source video track was silently omitted")
        } catch {XCTAssertTrue(error.localizedDescription.contains("preservation mapping"),"Unexpected QA error: \(error)")}
    }

    func testAudioFidelityUsesPlannedIntervalAndStillRejectsDamage() throws {
        // A decoder/resampler can produce a few samples after an exact cut.
        // These are not source coverage and cannot form a fidelity window.
        let source = (0..<24_008).map { Float(sin(Double($0 / 2) * 0.2) * 0.3) }
        var output = source
        for i in 24_000..<output.count { output[i] = -source[i] }
        XCTAssertNoThrow(try Media.validateAudioSamples(source,output,channels:2,duration:1))
        // Fractional final windows inside the requested interval remain checked.
        XCTAssertThrowsError(try Media.validateAudioSamples(source,output,channels:2,duration:1.0003333334))
        var damaged = source
        for i in 12_000..<24_000 { damaged[i] = 0 }
        XCTAssertThrowsError(try Media.validateAudioSamples(source,damaged,channels:2,duration:1))
        XCTAssertThrowsError(try Media.validateAudioSamples(source,Array(source.dropLast(2_000)),channels:2,duration:1))
        XCTAssertThrowsError(try Media.validateAudioSamples(Array(repeating:0,count:24_000),Array(repeating:0.1,count:24_000),channels:2,duration:1))
    }
    func testSharedExportMeetsInstagramAudioLimitAndRejectsExcessBitrate() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:dir) }
        let sourceURL = dir.appendingPathComponent("source.mp4")
        _ = try await Processes.run("ffmpeg",["-v","error","-f","lavfi","-i","testsrc2=s=160x90:r=30:d=4","-f","lavfi","-i","anoisesrc=color=pink:amplitude=0.2:duration=4:seed=42","-ac","2","-c:v","libx264","-pix_fmt","yuv420p","-c:a","aac","-b:a","256k","-shortest",sourceURL.path])
        let source = try await Media.inspect(sourceURL,request:Fixtures.request(dir:dir,path:sourceURL.path))
        let clip = ClipRecord(id:1,title:"Audio contract",intervals:[Interval(0,4)],filename:"clip.mp4")
        let output = dir.appendingPathComponent(clip.filename)
        let profile = try Fixtures.profile(dir:dir)
        let render = try await Media.render(source:source,clip:clip,profile:profile,artwork:nil,work:dir,output:output)
        let result = try await Processes.run("ffprobe",["-v","error","-select_streams","a:0","-show_entries","stream=bit_rate","-of","json",output.path])
        let object = try JSONSerialization.jsonObject(with:result.stdout) as! [String:Any]
        let stream = (object["streams"] as! [[String:Any]])[0]
        let rate = try XCTUnwrap(Int(stream["bit_rate"] as? String ?? ""))
        XCTAssertLessThanOrEqual(rate,128_000,"Shared delivery must satisfy Instagram's actual audio bitrate ceiling")
        let qa = try await Media.validate(output:output,source:source,clip:clip,profile:profile,render:render,work:dir)
        XCTAssertTrue(qa.passed)
        let excessive = dir.appendingPathComponent("excessive.mp4")
        _ = try await Processes.run("ffmpeg",["-v","error","-i",output.path,"-i",sourceURL.path,"-map","0:v","-map","1:a","-c:v","copy","-c:a","aac","-b:a","256k","-movflags","+faststart","-t","4",excessive.path])
        do {
            _ = try await Media.validate(output:excessive,source:source,clip:clip,profile:profile,render:render,work:dir)
            XCTFail("Output above Instagram's audio bitrate ceiling was accepted")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("technical"),"Expected technical-contract rejection, got: \(error)")
        }
    }
    func testNativeRenderPreservesFrameAndRejectsCorruption() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:dir) }
        let sourceURL = dir.appendingPathComponent("source.mp4")
        _ = try await Processes.run("ffmpeg",["-v","error","-f","lavfi","-i","testsrc2=s=320x180:r=30:d=3","-f","lavfi","-i","sine=frequency=440:duration=3","-c:v","libx264","-pix_fmt","yuv420p","-c:a","aac","-shortest",sourceURL.path])
        let source = try await Media.inspect(sourceURL,request:Fixtures.request(dir:dir,path:sourceURL.path))
        XCTAssertEqual(source.kind,.nativeVideo)
        let clip = ClipRecord(id:1,title:"fixture",intervals:[Interval(0.25,1.25),Interval(2,3)],filename:"clip.mp4")
        let output = dir.appendingPathComponent("clip.mp4")
        let profile = try Fixtures.profile(dir:dir)
        let render = try await Media.render(source:source,clip:clip,profile:profile,artwork:nil,work:dir,output:output)
        let qa = try await Media.validate(output:output,source:source,clip:clip,profile:profile,render:render,work:dir)
        XCTAssertTrue(qa.passed)
        let p = try await Media.probe(output)
        XCTAssertEqual(p.video?.width,720); XCTAssertEqual(p.video?.height,1280)
        XCTAssertEqual(p.duration,2,accuracy:0.075)
        XCTAssertEqual(render.pictureWidth,320); XCTAssertEqual(render.pictureHeight,180)
        try Data("corrupt".utf8).write(to:output)
        do { _ = try await Media.validate(output:output,source:source,clip:clip,profile:profile,render:render,work:dir); XCTFail("Corrupt output accepted") }
        catch { XCTAssertFalse(error is CancellationError) }
    }
    func testSilentWaveformDoesNotInventMotion() {
        let result = AudioPresentation.envelope(samples:Array(repeating:Float(0),count:4800),sampleRate:48000)
        XCTAssertTrue(result.levels.allSatisfy {$0 == 0})
        XCTAssertTrue(result.shape.allSatisfy {$0 == 0})
    }
    func testWaveformRespondsToSelectedAudio() {
        let samples = (0..<48000).map { i in i < 24000 ? Float(0) : Float(sin(Double(i)*0.05)*0.4) }
        let wave = AudioPresentation.envelope(samples:samples,sampleRate:48000)
        XCTAssertLessThan(wave.levels[5],0.001)
        XCTAssertGreaterThan(wave.levels[25],0.5)
        XCTAssertEqual(wave.shape.count,120)
    }
}

enum Fixtures {
    static func profile(dir: URL) throws -> SharedProfile {
        let p = dir.appendingPathComponent("capability-evidence.txt")
        try Data("Synthetic fixture capability; never production evidence".utf8).write(to:p)
        let proof = EvidenceFile(path:p.path,sha256:try Integrity.sha256(p),basis:"TEST ONLY")
        let x = SurfaceCapability(platform:"X",account:"fixture",surface:"fixture",checkedAt:Date().addingTimeInterval(-60),validUntil:Date().addingTimeInterval(3600),maxDuration:600,maxBytes:512_000_000,maxWidth:720,maxHeight:1280,maxFPS:30,officialURLs:["https://help.x.com/en/using-x/x-videos"],accountEvidence:proof)
        let ig = SurfaceCapability(platform:"Instagram",account:"fixture",surface:"fixture",checkedAt:x.checkedAt,validUntil:x.validUntil,maxDuration:900,maxBytes:1_000_000_000,maxWidth:1080,maxHeight:1920,maxFPS:60,officialURLs:["https://developers.facebook.com/docs/instagram-platform/content-publishing"],accountEvidence:proof)
        return try SharedProfile.select(x:x,instagram:ig)
    }
    static func request(dir: URL, path: String) throws -> JobRequest {
        JobRequest(owner:.dub,sourceID:"fixture-source",title:"Fixture",localPath:path,authorizationBasis:"Generated test media",profile:try profile(dir:dir),fileToDrive:false)
    }
}
