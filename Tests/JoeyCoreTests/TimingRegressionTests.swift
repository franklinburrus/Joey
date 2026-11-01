import XCTest
@testable import JoeyCore

final class TimingRegressionTests: XCTestCase {
    private func fixture(videoDelay: Double = 0, audioDelay: Double = 1, origin: Double = 0,
                         audioDuration: Double? = nil, audioGap: Bool = false) async throws -> (URL, SourceRecord, SharedProfile) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("joey-timing-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        let path = dir.appendingPathComponent("source.nut")
        // Lossless timestamps and hand-defined tone bursts establish an oracle
        // independent of Joey's render filters and QA reference construction.
        _ = try await Processes.run("ffmpeg",["-v","error","-f","lavfi","-i","testsrc2=s=160x90:r=30:d=\(4-videoDelay)",
            "-f","lavfi","-i","aevalsrc=if(lt(mod(t\\,2)\\,0.5)\\,0.25*sin(2*PI*440*t)*pow(sin(2*PI*mod(t\\,2))\\,2)\\,0):s=48000:d=\(audioDuration ?? (4-audioDelay))",
            "-filter_complex","[0:v]setpts=PTS+\(origin+videoDelay)/TB[v];[1:a]"+(audioGap ? "aselect='not(between(t,1,3))'," : "")+"asetpts=PTS+\(origin+audioDelay)/TB[a]",
            "-map","[v]","-map","[a]","-c:v","ffv1","-c:a","pcm_s16le","-fps_mode","passthrough",path.path])
        let source = try await Media.inspect(path,request:Fixtures.request(dir:dir,path:path.path))
        XCTAssertEqual(source.duration,4,accuracy:0.0001,"Inspected duration must be the actual timeline span, including the last packet")
        XCTAssertEqual(source.kind,.nativeVideo)
        return (dir,source,try Fixtures.landscapeProfile(dir:dir))
    }

    private func render(_ source: SourceRecord, _ dir: URL, _ profile: SharedProfile, intervals: [Interval]) async throws -> (URL, ClipRecord, RenderReceipt) {
        let clip = ClipRecord(id:1,title:"Timing",intervals:intervals,filename:"clip.mp4")
        let output = dir.appendingPathComponent(clip.filename)
        let receipt = try await Media.render(source:source,clip:clip,profile:profile,artwork:nil,work:dir,output:output)
        return (output,clip,receipt)
    }

    private func rms(_ output: URL, at: Double) async throws -> Double {
        let result = try await Processes.run("ffmpeg",["-v","error","-ss",String(at),"-i",output.path,"-t","0.15","-vn","-ac","1","-ar","12000","-f","f32le","-"])
        let values = result.stdout.withUnsafeBytes {Array($0.bindMemory(to:Float.self))}
        XCTAssertGreaterThan(values.count,1_000)
        return sqrt(values.reduce(0.0) {$0+Double($1)*Double($1)}/Double(max(1,values.count)))
    }

    private func picture(_ output: URL, at: Double) async throws -> Double {
        let result = try await Processes.run("ffmpeg",["-v","error","-ss",String(at),"-i",output.path,"-frames:v","1",
            "-vf","crop=160:90:(iw-160)/2:(ih-90)/2,format=gray","-f","rawvideo","-"])
        XCTAssertEqual(result.stdout.count,160*90)
        return result.stdout.reduce(0.0) {$0+Double($1)}/Double(max(1,result.stdout.count))
    }

    func testDelayedAudioRetainsSourceSilenceBeforeFirstSamples() async throws {
        let (dir,source,profile) = try await fixture()
        defer {try? FileManager.default.removeItem(at:dir)}
        let (output,clip,receipt) = try await render(source,dir,profile,intervals:[Interval(0,4)])
        let before = try await rms(output,at:0.2), burst = try await rms(output,at:1.1)
        XCTAssertLessThan(before,0.001,"Audio must retain its one-second delay relative to video")
        XCTAssertGreaterThan(burst,0.1)
        let qa = try await Media.validate(output:output,source:source,clip:clip,profile:profile,render:receipt,work:dir)
        XCTAssertTrue(qa.passed)
    }

    func testDelayedVideoKeepsAudioAndAbsentPictureOnCommonTimeline() async throws {
        let (dir,source,profile) = try await fixture(videoDelay:1,audioDelay:0)
        defer {try? FileManager.default.removeItem(at:dir)}
        let (output,clip,receipt) = try await render(source,dir,profile,intervals:[Interval(0,4)])
        let before = try await picture(output,at:0.2), after = try await picture(output,at:1.2)
        XCTAssertLessThan(before,2,"No source picture exists before the delayed video stream starts")
        XCTAssertGreaterThan(after,40)
        let audio = try await rms(output,at:0.1)
        XCTAssertGreaterThan(audio,0.1,"Early source audio must not move with delayed picture")
        let qa = try await Media.validate(output:output,source:source,clip:clip,profile:profile,render:receipt,work:dir)
        XCTAssertTrue(qa.passed)
    }

    func testNonzeroSourceOriginPreservesRelativeStreamOffsetWhenTrimming() async throws {
        let (dir,source,profile) = try await fixture(origin:5)
        defer {try? FileManager.default.removeItem(at:dir)}
        XCTAssertEqual(Double(source.streams.first {$0.codec_type == "video"}!.start_time!),5)
        XCTAssertEqual(Double(source.streams.first {$0.codec_type == "audio"}!.start_time!),6)
        let (output,clip,receipt) = try await render(source,dir,profile,intervals:[Interval(0.5,2)])
        let before = try await rms(output,at:0.1), burst = try await rms(output,at:0.6)
        XCTAssertLessThan(before,0.001)
        XCTAssertGreaterThan(burst,0.1)
        let qa = try await Media.validate(output:output,source:source,clip:clip,profile:profile,render:receipt,work:dir)
        XCTAssertTrue(qa.passed)
    }

    func testInspectionDoesNotSubtractOriginFromContainerReportedDurationSpan() async throws {
        let (dir,source,_) = try await fixture()
        defer {try? FileManager.default.removeItem(at:dir)}
        let transport = dir.appendingPathComponent("nonzero-origin.ts")
        _ = try await Processes.run("ffmpeg",["-v","error","-i",source.path,"-c:v","libx264","-c:a","mp2",
            "-muxdelay","0","-output_ts_offset","5",transport.path])
        let probe = try await Media.probe(transport)
        XCTAssertGreaterThan(Double(probe.format.start_time ?? "") ?? 0,4)
        XCTAssertLessThan(probe.duration,5,"MPEG-TS reports a duration span even with nonzero timestamps")
        let inspected = try await Media.inspect(transport,request:Fixtures.request(dir:dir,path:transport.path))
        XCTAssertEqual(inspected.duration,4,accuracy:0.05)
    }

    func testConcatenationUsesRequestedIntervalLengthsAndSourceEventTimes() async throws {
        let (dir,source,profile) = try await fixture()
        defer {try? FileManager.default.removeItem(at:dir)}
        let (output,clip,receipt) = try await render(source,dir,profile,intervals:[Interval(0.25,1.75),Interval(2.75,3.75)])
        // Source bursts at 1.0 and 3.0 map to output 0.75 and 1.75.
        let silence = try await rms(output,at:0.2), first = try await rms(output,at:0.85)
        let gap = try await rms(output,at:1.53), second = try await rms(output,at:1.85)
        XCTAssertLessThan(silence,0.001); XCTAssertGreaterThan(first,0.1)
        XCTAssertLessThan(gap,0.001); XCTAssertGreaterThan(second,0.1)
        let probe = try await Media.probe(output)
        XCTAssertEqual(probe.duration,2.5,accuracy:0.075)
        let qa = try await Media.validate(output:output,source:source,clip:clip,profile:profile,render:receipt,work:dir)
        XCTAssertTrue(qa.passed)
    }

    func testFractionalIntervalConcatenationDoesNotAccumulateFrameRoundingInAudio() async throws {
        let (dir,source,profile) = try await fixture()
        defer {try? FileManager.default.removeItem(at:dir)}
        let (output,clip,receipt) = try await render(source,dir,profile,intervals:[Interval(0.25,1.76),Interval(2.75,3.76)])
        let qa = try await Media.validate(output:output,source:source,clip:clip,profile:profile,render:receipt,work:dir)
        XCTAssertTrue(qa.passed,"Source-PTS audio comparison must reject accumulated video-frame rounding")
    }

    func testIntervalEntirelyBeforeAudioStartsRetainsRequestedSilence() async throws {
        let (dir,source,profile) = try await fixture()
        defer {try? FileManager.default.removeItem(at:dir)}
        let (output,clip,receipt) = try await render(source,dir,profile,intervals:[Interval(0,0.5),Interval(1,1.5)])
        let silence = try await rms(output,at:0.1), burst = try await rms(output,at:0.6)
        XCTAssertLessThan(silence,0.001); XCTAssertGreaterThan(burst,0.1)
        let qa = try await Media.validate(output:output,source:source,clip:clip,profile:profile,render:receipt,work:dir)
        XCTAssertTrue(qa.passed)
    }

    func testIntervalEntirelyBeforeVideoStartsPreservesEarlyAudio() async throws {
        let (dir,source,profile) = try await fixture(videoDelay:1,audioDelay:0)
        defer {try? FileManager.default.removeItem(at:dir)}
        let (output,clip,receipt) = try await render(source,dir,profile,intervals:[Interval(0,0.5),Interval(1,1.5)])
        let black = try await picture(output,at:0.1), visible = try await picture(output,at:0.7)
        let earlyAudio = try await rms(output,at:0.1)
        XCTAssertLessThan(black,2); XCTAssertGreaterThan(visible,40); XCTAssertGreaterThan(earlyAudio,0.1)
        let qa = try await Media.validate(output:output,source:source,clip:clip,profile:profile,render:receipt,work:dir)
        XCTAssertTrue(qa.passed)
    }

    func testTrailingMissingAudioPacketsWithoutDurationMetadataRenderAsSourceSilence() async throws {
        let (dir,source,profile) = try await fixture(audioDelay:0,audioDuration:1)
        defer {try? FileManager.default.removeItem(at:dir)}
        let rawProbe = try await Media.probe(URL(fileURLWithPath:source.path))
        XCTAssertNil(rawProbe.audio?.duration,"Fixture must exercise a container without audio duration metadata")
        // Existing checkpoints retain their original stream metadata. Recovery
        // must also work without reinspection filling in the missing duration.
        var legacySource = source;legacySource.streams = rawProbe.streams
        let (output,clip,receipt) = try await render(legacySource,dir,profile,intervals:[Interval(2.5,3.5)])
        let silence = try await rms(output,at:0.1)
        XCTAssertLessThan(silence,0.001)
        let qa = try await Media.validate(output:output,source:legacySource,clip:clip,profile:profile,render:receipt,work:dir)
        XCTAssertTrue(qa.passed)
    }

    func testInteriorMissingAudioPacketsRemainSilentWithoutInventingSamples() async throws {
        let (dir,source,profile) = try await fixture(audioDelay:0,audioGap:true)
        defer {try? FileManager.default.removeItem(at:dir)}
        let (output,clip,receipt) = try await render(source,dir,profile,intervals:[Interval(1.5,2.5)])
        let silence = try await rms(output,at:0.1)
        XCTAssertLessThan(silence,0.001)
        let qa = try await Media.validate(output:output,source:source,clip:clip,profile:profile,render:receipt,work:dir)
        XCTAssertTrue(qa.passed)
    }

    func testQARejectsShiftedAudioEvenWhenRenderReceiptContainsSameWrongReference() async throws {
        let (dir,source,profile) = try await fixture()
        defer {try? FileManager.default.removeItem(at:dir)}
        let (output,clip,receipt) = try await render(source,dir,profile,intervals:[Interval(0,4)])
        let shifted = dir.appendingPathComponent("shifted.mp4"), wrongReference = dir.appendingPathComponent("wrong.wav")
        // Deliberately recreate the old per-stream STARTPTS error without
        // calling Media's graph builders. Match the receipt to the wrong audio
        // so a self-referential validator cannot pass this regression.
        _ = try await Processes.run("ffmpeg",["-v","error","-i",output.path,"-i",source.path,"-filter_complex",
            "[1:a]asetpts=PTS-STARTPTS,apad,atrim=duration=4[a]","-map","0:v","-map","[a]","-c:v","copy","-c:a","aac","-b:a","120000","-movflags","+faststart","-t","4",shifted.path])
        _ = try await Processes.run("ffmpeg",["-v","error","-i",shifted.path,"-vn","-c:a","pcm_s16le",wrongReference.path])
        var wrongReceipt = receipt; wrongReceipt.selectedAudio = wrongReference.path
        do {
            _ = try await Media.validate(output:shifted,source:source,clip:clip,profile:profile,render:wrongReceipt,work:dir)
            XCTFail("QA accepted a shifted stream because its render reference repeated the error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Audio") || error.localizedDescription.contains("timeline") || error.localizedDescription.contains("silence"),"Expected source timing rejection, got \(error)")
        }
    }

    func testIndependentPictureOracleRejectsShiftedVideoWithCorrectAudio() async throws {
        let (dir,source,profile) = try await fixture(videoDelay:1,audioDelay:0)
        defer {try? FileManager.default.removeItem(at:dir)}
        let (output,clip,receipt) = try await render(source,dir,profile,intervals:[Interval(0,4)])
        let outputProfile = profile.outputProfile(for:.nativeVideo)
        let shifted = dir.appendingPathComponent("shifted-picture.mp4")
        _ = try await Processes.run("ffmpeg",["-v","error","-i",output.path,"-i",source.path,"-filter_complex",
            "[1:v]setpts=PTS-STARTPTS,fps=30,pad=\(outputProfile.width):\(outputProfile.height):(ow-iw)/2:(oh-ih)/2:black,setsar=1,tpad=stop_mode=clone:stop_duration=1[v]",
            "-map","[v]","-map","0:a","-c:v","libx264","-preset","veryfast","-crf","18","-pix_fmt","yuv420p","-c:a","copy","-r","30","-movflags","+faststart","-t","4",shifted.path])
        do {
            _ = try await Media.validateSourcePictureTiming(output:shifted,source:source,clip:clip,profile:outputProfile,render:receipt)
            XCTFail("Independent source-frame oracle accepted video moved one second before its source timestamp")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("picture timeline"),"Unexpected rejection: \(error)")
        }
        do {
            _ = try await Media.validate(output:shifted,source:source,clip:clip,profile:profile,render:receipt,work:dir)
            XCTFail("Full QA accepted shifted video with unchanged correct audio")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("picture timeline"),"Independent cropped-picture timing check should reject: \(error)")
        }
    }

    func testJoeCompositionRejectsShiftedSourcePictureWithUnchangedAudioAndOutro() async throws {
        let assets = Persistence.defaultRoot
        guard FileManager.default.fileExists(atPath:assets.appendingPathComponent("assets/joe-approved-outro.mov").path) else {
            throw XCTSkip("Approved local Joe assets are not installed on this test host")
        }
        let branding = try JoeBranding.load(root:assets)
        let (dir,source,_) = try await fixture(videoDelay:1,audioDelay:0)
        defer {try? FileManager.default.removeItem(at:dir)}
        let profile = SharedProfile.joeBuddenDrive
        let clip = ClipRecord(id:1,title:"Synthetic Joe timing",intervals:[Interval(0,4)],filename:"joe.mp4")
        let output = dir.appendingPathComponent(clip.filename)
        let receipt = try await Media.render(source:source,clip:clip,profile:profile,artwork:nil,work:dir,output:output,branding:branding)
        let correct = try await Media.validate(output:output,source:source,clip:clip,profile:profile,render:receipt,work:dir)
        XCTAssertTrue(correct.passed)
        XCTAssertNotNil(correct.checks["source_picture_timeline"],"Joe content needs the same independent source-timestamp check as other native video")
        XCTAssertNotNil(correct.checks["approved_logo"]);XCTAssertNotNil(correct.checks["approved_outro"])

        // Replace only the tiny source-picture rectangle during the content.
        // Preserve the approved logo, entire outro and exact encoded audio.
        // Whole-canvas averaging alone can hide this one-second picture shift.
        let shifted = dir.appendingPathComponent("joe-shifted-picture.mp4")
        _ = try await Processes.run("ffmpeg",["-v","error","-i",output.path,"-i",source.path,"-filter_complex",
            "[1:v]setpts=PTS-STARTPTS,tpad=stop_mode=clone:stop_duration=1[p];[0:v][p]overlay=x=(main_w-overlay_w)/2:y=(main_h-overlay_h)/2:enable='lt(t,4)':eof_action=pass:repeatlast=0[v]",
            "-map","[v]","-map","0:a","-c:v","libx264","-preset","veryfast","-crf","18","-pix_fmt","yuv420p","-c:a","copy","-r","30","-movflags","+faststart","-t",String(4+branding.outroDuration),shifted.path])
        do {
            _ = try await Media.validate(output:shifted,source:source,clip:clip,profile:profile,render:receipt,work:dir)
            XCTFail("Joe QA accepted shifted source video while its audio, logo and outro remained correct")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("picture timeline"),"Expected independent source-timing rejection, got \(error)")
        }
    }

    func testJoePictureTimingMaskHandlesLogoOverFullSizeSourceImage() async throws {
        let assets = Persistence.defaultRoot
        guard FileManager.default.fileExists(atPath:assets.appendingPathComponent("assets/joe-approved-outro.mov").path) else {
            throw XCTSkip("Approved local Joe assets are not installed on this test host")
        }
        let branding = try JoeBranding.load(root:assets)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("joey-full-picture-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:dir)}
        let original = dir.appendingPathComponent("full-size.mp4")
        _ = try await Processes.run("ffmpeg",["-v","error","-f","lavfi","-i","testsrc2=s=1920x1080:r=30:d=2",
            "-f","lavfi","-i","sine=frequency=440:duration=2","-c:v","libx264","-preset","veryfast","-pix_fmt","yuv420p","-c:a","aac",original.path])
        let source = try await Media.inspect(original,request:Fixtures.request(dir:dir,path:original.path))
        let profile = SharedProfile.joeBuddenDrive
        let clip = ClipRecord(id:1,title:"Synthetic full-size Joe",intervals:[Interval(0,2)],filename:"joe.mp4")
        let output = dir.appendingPathComponent(clip.filename)
        let receipt = try await Media.render(source:source,clip:clip,profile:profile,artwork:nil,work:dir,output:output,branding:branding)
        XCTAssertEqual(receipt.pictureWidth,1920);XCTAssertEqual(receipt.pictureHeight,1080)
        let qa = try await Media.validate(output:output,source:source,clip:clip,profile:profile,render:receipt,work:dir)
        XCTAssertTrue(qa.passed)
        XCTAssertNotNil(qa.checks["source_picture_timeline"])
        XCTAssertNotNil(qa.checks["approved_logo"]);XCTAssertNotNil(qa.checks["approved_outro"])
    }
}
