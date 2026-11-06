import XCTest
@testable import JoeyCore

final class MediaTests: XCTestCase {
    func testNativeRGBSourceConversionAndReencodingPassColorQA() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("joey-color-conversion-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:directory)}
        let original = directory.appendingPathComponent("rgb-source.mkv")
        _ = try await Processes.run("ffmpeg",["-nostdin","-v","error","-f","lavfi","-i","testsrc=s=320x180:r=30:d=2",
            "-an","-c:v","ffv1","-pix_fmt","bgr0",original.path])
        let request = try Fixtures.request(dir:directory,path:original.path)
        let source = try await Media.inspect(original,request:request)
        XCTAssertEqual(source.streams.first?.pix_fmt,"bgr0","The control must exercise RGB-to-YUV conversion")
        let clip = ClipRecord(id:1,title:"RGB conversion",intervals:[Interval(0,2)],filename:"converted.mp4")
        let output = directory.appendingPathComponent(clip.filename)
        let render = try await Media.render(source:source,clip:clip,profile:request.profile,artwork:nil,work:directory,output:output)
        let qa = try await Media.validate(output:output,source:source,clip:clip,profile:request.profile,render:render,work:directory)
        XCTAssertTrue(qa.passed)
        let reencoded = directory.appendingPathComponent("reencoded.mp4")
        _ = try await Processes.run("ffmpeg",["-nostdin","-v","error","-i",output.path,
            "-an","-c:v","libx264","-preset","veryfast","-crf","18","-pix_fmt","yuv420p","-movflags","+faststart",reencoded.path])
        let second = try await Media.validate(output:reencoded,source:source,clip:clip,profile:request.profile,render:render,work:directory)
        XCTAssertTrue(second.passed,"Ordinary YUV420 encoding noise must remain within the color fidelity tolerance")
    }

    func testCoordinatorRepairsColorRejectedOutputBeforeAcceptingItsHash() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("joey-color-recovery-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:directory)}
        let original = directory.appendingPathComponent("source.mp4")
        _ = try await Processes.run("ffmpeg",["-nostdin","-v","error","-f","lavfi","-i","testsrc2=s=320x180:r=30:d=2",
            "-an","-c:v","libx264","-pix_fmt","yuv420p",original.path])
        var request = try Fixtures.request(dir:directory,path:original.path)
        let transcriptURL = directory.appendingPathComponent("transcript.json")
        try Persistence.save(Transcript(sourceID:request.sourceID,sourceSHA256:try Integrity.sha256(original),duration:2,
            engine:"Synthetic test only",segments:[TranscriptSegment(start:0,end:2,text:"Complete synthetic source.")]),to:transcriptURL)
        request.transcriptPath = transcriptURL.path
        let root = directory.appendingPathComponent("runtime")
        let coordinator = try Coordinator(root:root)
        let corruption = ColorCorruptionEvidence()
        let result = try await coordinator.run(request) {job in
            guard job.stage == "QA clip 1", await corruption.hashes.isEmpty else {return}
            let attempts = root.appendingPathComponent("jobs/\(job.id)/scratch/1")
            let directories = try FileManager.default.contentsOfDirectory(at:attempts,includingPropertiesForKeys:nil)
            let partial = try XCTUnwrap(directories.map {$0.appendingPathComponent("render.partial.mp4")}
                .first {FileManager.default.fileExists(atPath:$0.path)})
            let damaged = partial.deletingLastPathComponent().appendingPathComponent("color-corrupted.mp4")
            _ = try await Processes.run("ffmpeg",["-nostdin","-v","error","-i",partial.path,"-vf","lutyuv=u=128:v=128",
                "-an","-c:v","libx264","-preset","veryfast","-crf","18","-pix_fmt","yuv420p","-movflags","+faststart",damaged.path])
            try FileManager.default.removeItem(at:partial)
            try FileManager.default.moveItem(at:damaged,to:partial)
            await corruption.record(try Integrity.sha256(partial))
            XCTAssertNil(job.clips.first?.qa,"The pending candidate must not have accepted QA")
            XCTAssertNil(job.clips.first?.drive)
        }
        let rejectedHashes = await corruption.hashes
        XCTAssertEqual(rejectedHashes.count,1,"The test must alter the actual coordinator candidate before QA")
        XCTAssertEqual(result.state,.qaPassed,result.error ?? "")
        let accepted = try XCTUnwrap(result.clips.first)
        XCTAssertTrue(accepted.qa?.passed == true)
        XCTAssertFalse(rejectedHashes.contains(accepted.sha256 ?? ""),"Rejected color-corrupted bytes must never become accepted filing input")
        var filed = accepted
        let corruptReceipt = DriveReceipt(id:"synthetic-rejected-file",name:accepted.filename,parent:"synthetic-folder",
            bytes:try XCTUnwrap(accepted.bytes),sha256:try XCTUnwrap(rejectedHashes.first),url:"https://example.invalid/rejected",
            permissions:[],verifiedAt:Date())
        XCTAssertThrowsError(try Coordinator.acceptDelivery(corruptReceipt,for:&filed),"Delivery must not bind the rejected candidate to the repaired clip")
        XCTAssertNil(filed.drive)
        let jobDirectory = await coordinator.directory(for:result.id)
        XCTAssertTrue((result.storageWarnings ?? []).isEmpty,"RGB QA scratch must retain supported cleanup ownership")
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath:jobDirectory.appendingPathComponent("scratch/1").path).isEmpty)
        let output = jobDirectory.appendingPathComponent(accepted.filename)
        XCTAssertEqual(try Integrity.sha256(output),accepted.qa?.outputSHA256)
        let render: RenderReceipt = try Persistence.load(jobDirectory.appendingPathComponent("evidence/1/render.json"))
        _ = try await Media.validate(output:output,source:XCTUnwrap(result.source),clip:accepted,profile:request.profile,render:render,work:directory)
    }

    func testNativeColorLossAndHueCorruptionFailProductionQA() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("joey-color-fidelity-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:directory)}
        let original = directory.appendingPathComponent("source.mp4")
        _ = try await Processes.run("ffmpeg",["-nostdin","-v","error","-f","lavfi","-i","testsrc2=s=320x180:r=30:d=2",
            "-an","-c:v","libx264","-pix_fmt","yuv420p",original.path])
        let request = try Fixtures.request(dir:directory,path:original.path)
        let source = try await Media.inspect(original,request:request)
        let clip = ClipRecord(id:1,title:"Color fidelity",intervals:[Interval(0,2)],filename:"correct.mp4")
        let output = directory.appendingPathComponent(clip.filename)
        let render = try await Media.render(source:source,clip:clip,profile:request.profile,artwork:nil,work:directory,output:output)
        let baseline = try await Media.validate(output:output,source:source,clip:clip,profile:request.profile,render:render,work:directory)
        XCTAssertTrue(baseline.passed)
        let sourceHash = try Integrity.sha256(original), outputHash = try Integrity.sha256(output)
        // The small source picture is surrounded by black padding. A whole-
        // composition average alone cannot establish color fidelity inside it.
        for (name,filter) in [("chroma-loss","lutyuv=u=128:v=128"),("hue-change","hue=h=120")] {
            let damaged = directory.appendingPathComponent(name+".mp4")
            _ = try await Processes.run("ffmpeg",["-nostdin","-v","error","-i",output.path,"-vf",filter,
                "-an","-c:v","libx264","-preset","veryfast","-crf","18","-pix_fmt","yuv420p","-movflags","+faststart",damaged.path])
            do {
                _ = try await Media.validate(output:damaged,source:source,clip:clip,profile:request.profile,render:render,work:directory)
                XCTFail("Production QA accepted \(name) with unchanged luminance and timing")
            } catch {
                XCTAssertTrue(error.localizedDescription.lowercased().contains("picture"),"Expected picture rejection: \(error)")
            }
            do {
                _ = try await Media.validateSourcePictureTiming(output:damaged,source:source,clip:clip,
                    profile:request.profile.outputProfile(for:.nativeVideo),render:render)
                XCTFail("Independent source-PTS QA accepted \(name) inside the picture rectangle")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("picture timeline"),"Expected source-PTS rejection: \(error)")
            }
        }
        XCTAssertEqual(try Integrity.sha256(original),sourceHash)
        XCTAssertEqual(try Integrity.sha256(output),outputHash)
    }

    func testNativeLandscapeContractForDUBAndTaxstone() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:directory)}
        let original = directory.appendingPathComponent("native-source.mp4")
        _ = try await Processes.run("ffmpeg",["-nostdin","-v","error","-f","lavfi","-i","testsrc2=s=320x180:r=30:d=2",
            "-an","-c:v","libx264","-pix_fmt","yuv420p",original.path])
        let originalHash = try Integrity.sha256(original)
        for owner in [Owner.dub,.taxstone] {
            var request = try Fixtures.request(dir:directory,path:original.path)
            request.owner = owner
            let source = try await Media.inspect(original,request:request)
            let clip = ClipRecord(id:1,title:"Landscape contract",intervals:[Interval(0,2)],filename:owner.rawValue+"-landscape.mp4")
            let work = directory.appendingPathComponent(owner.rawValue)
            try FileManager.default.createDirectory(at:work,withIntermediateDirectories:true)
            let output = work.appendingPathComponent(clip.filename)
            let render = try await Media.render(source:source,clip:clip,profile:request.profile,artwork:nil,work:work,output:output)
            let qa = try await Media.validate(output:output,source:source,clip:clip,profile:request.profile,render:render,work:work)
            let measured = try await Media.probe(output)
            XCTAssertTrue(qa.passed,owner.rawValue)
            XCTAssertEqual(measured.video?.width,1920,owner.rawValue)
            XCTAssertEqual(measured.video?.height,1080,owner.rawValue)
            XCTAssertEqual(render.pictureWidth,320,owner.rawValue)
            XCTAssertEqual(render.pictureHeight,180,owner.rawValue)
            XCTAssertNil(qa.checks["approved_logo"],owner.rawValue)
            XCTAssertNil(qa.checks["approved_outro"],owner.rawValue)
            XCTAssertTrue(qa.checks["unrequested_additions"]?.contains("Source-only") == true,owner.rawValue)
        }
        XCTAssertEqual(try Integrity.sha256(original),originalHash)
    }

    func testNativeExportAndQARejectDimensionsOutsideEitherSharedCapability() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:dir)}
        let sourceURL = dir.appendingPathComponent("source.mp4")
        _ = try await Processes.run("ffmpeg",["-v","error","-f","lavfi","-i","testsrc2=s=160x90:r=30:d=1",
            "-c:v","libx264","-pix_fmt","yuv420p",sourceURL.path])
        let source = try await Media.inspect(sourceURL,request:Fixtures.request(dir:dir,path:sourceURL.path))
        XCTAssertEqual(source.kind,.nativeVideo)
        let clip = ClipRecord(id:1,title:"Synthetic dimensions",intervals:[Interval(0,1)],filename:"clip.mp4")
        let compatible = try Fixtures.landscapeProfile(dir:dir)
        let output = dir.appendingPathComponent(clip.filename)
        let receipt = try await Media.render(source:source,clip:clip,profile:compatible,artwork:nil,work:dir,output:output)
        let before = try Integrity.sha256(output)
        for platform in ["X","Instagram"] {
            var narrow = compatible
            if platform == "X" {narrow.x!.maxWidth = 720} else {narrow.instagram!.maxWidth = 720}
            try narrow.validate() // The selected portrait profile itself is valid.
            do {
                _ = try await Media.validate(output:output,source:source,clip:clip,profile:narrow,render:receipt,work:dir)
                XCTFail("QA accepted native output wider than the verified \(platform) capability")
            } catch {XCTAssertTrue(error.localizedDescription.contains("1920×1080"),error.localizedDescription)}
            let rejected = dir.appendingPathComponent("rejected-\(platform).mp4")
            do {
                _ = try await Media.render(source:source,clip:clip,profile:narrow,artwork:nil,work:dir,output:rejected)
                XCTFail("Rendered native output wider than the verified \(platform) capability")
            } catch {XCTAssertTrue(error.localizedDescription.contains("1920×1080"),error.localizedDescription)}
            XCTAssertFalse(FileManager.default.fileExists(atPath:rejected.path))
        }
        XCTAssertEqual(try Integrity.sha256(output),before,"Rejected QA must preserve accepted bytes")
    }

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
        let profile = try Fixtures.landscapeProfile(dir:dir)
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
        let profile = try Fixtures.landscapeProfile(dir:dir)
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
        let profile = try Fixtures.landscapeProfile(dir:dir)
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
    func testNativeRenderPreservesCompleteFrameAt1920x1080AndRejectsCorruption() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:dir) }
        let sourceURL = dir.appendingPathComponent("source.mp4")
        _ = try await Processes.run("ffmpeg",["-v","error","-f","lavfi","-i","testsrc2=s=320x180:r=30:d=3","-f","lavfi","-i","sine=frequency=440:duration=3","-c:v","libx264","-pix_fmt","yuv420p","-c:a","aac","-shortest",sourceURL.path])
        let source = try await Media.inspect(sourceURL,request:Fixtures.request(dir:dir,path:sourceURL.path))
        XCTAssertEqual(source.kind,.nativeVideo)
        let clip = ClipRecord(id:1,title:"fixture",intervals:[Interval(0.25,1.25),Interval(2,3)],filename:"clip.mp4")
        let output = dir.appendingPathComponent("clip.mp4")
        let profile = try Fixtures.landscapeProfile(dir:dir)
        let render = try await Media.render(source:source,clip:clip,profile:profile,artwork:nil,work:dir,output:output)
        let qa = try await Media.validate(output:output,source:source,clip:clip,profile:profile,render:render,work:dir)
        XCTAssertTrue(qa.passed)
        let p = try await Media.probe(output)
        XCTAssertEqual(p.video?.width,1920); XCTAssertEqual(p.video?.height,1080)
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

private actor ColorCorruptionEvidence {
    private(set) var hashes: [String] = []
    func record(_ hash: String) {hashes.append(hash)}
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
    static func landscapeProfile(dir: URL) throws -> SharedProfile {
        var profile = try profile(dir:dir)
        profile.x!.maxWidth = 1920;profile.x!.maxHeight = 1920
        profile.instagram!.maxWidth = 1920;profile.instagram!.maxHeight = 1920
        return profile
    }
    static func request(dir: URL, path: String) throws -> JobRequest {
        // Successful native-job fixtures need capability for their actual
        // landscape canvas. profile(dir:) remains the narrow portrait fixture.
        JobRequest(owner:.dub,sourceID:"fixture-source",title:"Fixture",localPath:path,authorizationBasis:"Generated test media",profile:try landscapeProfile(dir:dir),fileToDrive:false)
    }
}
