import XCTest
@testable import JoeyCore

final class SharedAudioChannelTests: XCTestCase {
    private func workspace() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("joey-audio-channels-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        addTeardownBlock {try? FileManager.default.removeItem(at:directory)}
        return directory
    }

    private func source(in directory: URL, channels: Int, video: Bool) async throws -> (SourceRecord, SharedProfile) {
        let file = directory.appendingPathComponent(video ? "source.mov" : "source.wav")
        let tones = (0..<channels).map {"0.03*sin(2*PI*\(300+$0*100)*t)"}.joined(separator:"|")
        let layout = channels == 1 ? "mono" : channels == 2 ? "stereo" : "5.1"
        var arguments = ["-v","error","-f","lavfi","-i","aevalsrc=\(tones):s=48000:d=6:c=\(layout)"]
        if video {arguments += ["-f","lavfi","-i","testsrc2=s=160x90:r=30:d=6","-c:v","libx264","-pix_fmt","yuv420p"]}
        arguments += ["-c:a","pcm_s16le",file.path]
        _ = try await Processes.run("ffmpeg",arguments)
        var request = try Fixtures.request(dir:directory,path:file.path)
        request.owner = .taxstone
        request.profile.x!.surface = "Buffer X video"
        request.profile.instagram!.surface = "Buffer Instagram Reel"
        request.profile.x!.maxDuration = 140
        let record = try await Media.inspect(file,request:request)
        XCTAssertEqual(record.streams.first(where:{$0.codec_type == "audio"})?.channels,channels)
        return (record,request.profile)
    }

    func testNativeSharedExportsPreserveMonoStereoAndDownmixSurround() async throws {
        for channels in [1,2,6] {
            let directory = try workspace()
            let (source,profile) = try await source(in:directory,channels:channels,video:true)
            let clip = ClipRecord(id:1,title:"Channel contract",intervals:[Interval(0,6)],filename:"clip.mp4")
            let output = directory.appendingPathComponent(clip.filename)
            let render = try await Media.render(source:source,clip:clip,profile:profile,artwork:nil,work:directory,output:output)
            let probe = try await Media.probe(output)
            XCTAssertEqual(probe.audio?.channels,channels == 6 ? 2 : channels)
            let qa = try await Media.validate(output:output,source:source,clip:clip,profile:profile,render:render,work:directory)
            XCTAssertTrue(qa.passed)
            XCTAssertNoThrow(try BufferPreflight.validateTechnical(probe,bytes:Int64(Data(contentsOf:output).count),expectedDuration:6,hasAudio:true,profile:profile.outputProfile(for:.nativeVideo)))
        }
    }

    func testAudioPresentationDownmixesSurroundBeforeGeneratingFinalWaveform() async throws {
        let directory = try workspace()
        let (source,profile) = try await source(in:directory,channels:6,video:false)
        let art = directory.appendingPathComponent("art.png")
        _ = try await Processes.run("ffmpeg",["-v","error","-f","lavfi","-i","testsrc2=s=300x300","-frames:v","1",art.path])
        let artwork = Artwork(owner:.taxstone,sourceID:source.id,driveID:"synthetic-art",
            file:EvidenceFile(path:art.path,sha256:try Integrity.sha256(art),basis:"Synthetic test artwork"))
        let clip = ClipRecord(id:1,title:"Audio channel contract",intervals:[Interval(0,6)],filename:"clip.mp4")
        let output = directory.appendingPathComponent(clip.filename)
        let render = try await Media.render(source:source,clip:clip,profile:profile,artwork:artwork,work:directory,output:output)
        let probe = try await Media.probe(output)
        XCTAssertEqual(probe.audio?.channels,2)
        let qa = try await Media.validate(output:output,source:source,clip:clip,profile:profile,render:render,work:directory)
        XCTAssertTrue(qa.passed,"Source fidelity and waveform validation must use the final stereo audio")
        XCTAssertNoThrow(try BufferPreflight.validateTechnical(probe,bytes:Int64(Data(contentsOf:output).count),expectedDuration:6,hasAudio:true,profile:profile))
    }

    func testProductionQARejectsMultichannelOutputEvenWithMatchingSource() async throws {
        let directory = try workspace()
        let (source,profile) = try await source(in:directory,channels:6,video:true)
        let clip = ClipRecord(id:1,title:"Unsupported output",intervals:[Interval(0,6)],filename:"clip.mp4")
        let output = directory.appendingPathComponent(clip.filename)
        let render = try await Media.render(source:source,clip:clip,profile:profile,artwork:nil,work:directory,output:output)
        let incompatible = directory.appendingPathComponent("surround.mp4")
        _ = try await Processes.run("ffmpeg",["-v","error","-i",output.path,"-i",source.path,"-map","0:v","-map","1:a",
            "-c:v","copy","-c:a","aac","-profile:a","aac_low","-b:a","120000","-movflags","+faststart","-t","6",incompatible.path])
        let probe = try await Media.probe(incompatible)
        XCTAssertEqual(probe.audio?.channels,6)
        XCTAssertLessThan(try XCTUnwrap(Int(probe.audio?.bit_rate ?? "")),128_000)
        do {
            _ = try await Media.validate(output:incompatible,source:source,clip:clip,profile:profile,render:render,work:directory)
            XCTFail("Production QA accepted an output that the shared mono/stereo contract rejects")
        } catch {XCTAssertTrue(error.localizedDescription.contains("technical"),error.localizedDescription)}
    }
}
