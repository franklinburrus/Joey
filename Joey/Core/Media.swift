import Foundation
import CoreGraphics

public struct StreamInfo: Codable, Equatable, Sendable {
    public var codec_type: String?
    public var codec_name: String?
    public var profile: String?
    public var width: Int?
    public var height: Int?
    public var pix_fmt: String?
    public var field_order: String?
    public var sample_aspect_ratio: String?
    public var avg_frame_rate: String?
    public var duration: String?
    public var start_time: String?
    public var channels: Int?
    public var sample_rate: String?
    public var fps: Double {
        let p = (avg_frame_rate ?? "0/1").split(separator:"/").compactMap { Double($0) }
        return p.count == 2 && p[1] != 0 ? p[0]/p[1] : (p.first ?? 0)
    }
}
public struct MediaProbe: Codable, Sendable {
    public struct Format: Codable, Sendable { public var duration: String?; public var size: String?; public var format_name: String? }
    public var streams: [StreamInfo]
    public var format: Format
    public var duration: Double { Double(format.duration ?? "") ?? 0 }
    public var video: StreamInfo? { streams.first { $0.codec_type == "video" } }
    public var audio: StreamInfo? { streams.first { $0.codec_type == "audio" } }
}
public struct RenderReceipt: Codable, Sendable {
    public var recipe = "shared-source-only-v1"
    public var selectedAudio: String?
    public var waveformPCM: String?
    public var background: String?
    public var waveform: AudioEnvelope?
    public var pictureWidth: Int
    public var pictureHeight: Int
}
public enum Media {
    public static func probe(_ url: URL) async throws -> MediaProbe {
        let result = try await Processes.run("ffprobe",["-v","error","-show_streams","-show_format","-of","json",url.path])
        let probe = try JSONDecoder().decode(MediaProbe.self, from: result.stdout)
        guard probe.duration.isFinite, probe.duration > 0, probe.audio != nil || probe.video != nil else { throw JoeyError.invalid("Media has no valid finite streams") }
        return probe
    }
    public static func decode(_ url: URL) async throws {
        _ = try await Processes.run("ffmpeg", ["-nostdin","-v","error","-xerror","-err_detect","explode","-i",url.path,"-map","0:v?","-map","0:a?","-f","null","-"])
    }
    public static func inspect(_ url: URL, request: JobRequest) async throws -> SourceRecord {
        let p = try await probe(url)
        if let expected = request.expectedDuration {
            guard expected.isFinite, abs(p.duration-expected) <= max(0.1,expected*0.001) else { throw JoeyError.invalid("Incomplete source: duration conflicts with source evidence") }
        }
        guard p.streams.filter({$0.codec_type == "audio"}).count <= 1 else { throw JoeyError.dependency("Multiple source audio tracks require an explicit preservation mapping") }
        guard p.streams.allSatisfy({$0.codec_type != "subtitle"}) else { throw JoeyError.dependency("Separate subtitle stream needs a preservation mapping; source has not been changed") }
        try await decode(url)
        let attrs = try FileManager.default.attributesOfItem(atPath:url.path)
        var kind: MediaKind = .audio
        var evidence = "No video stream"
        if p.video != nil {
            var frames: [Data] = []
            for i in 0..<8 {
                let at = min(max(0,p.duration-0.05),Double(i)*p.duration/8)
                let result = try await Processes.run("ffmpeg",["-nostdin","-v","error","-ss",String(at),"-i",url.path,"-frames:v","1","-vf","scale=64:64,format=gray","-f","rawvideo","-"])
                if result.stdout.count == 4096 { frames.append(result.stdout) }
            }
            let differences = zip(frames,frames.dropFirst()).map { a,b in zip(a,b).reduce(0.0) {$0+abs(Double($1.0)-Double($1.1))}/4096 }
            let moving = differences.filter {$0 > 1}.count
            kind = moving >= 2 ? .nativeVideo : .audio
            evidence = "Eight distributed 64x64 grayscale samples; \(moving) changes above mean absolute pixel difference 1. Static presentation treated as audio; sampling is not semantic certainty."
            if kind == .audio, p.audio == nil { throw JoeyError.invalid("Static visual source has no audio program") }
        }
        return SourceRecord(id:request.sourceID,owner:request.owner,title:request.title,episodeDate:request.episodeDate,
            originalURL:request.originalURL,path:url.path,bytes:(attrs[.size] as? NSNumber)?.int64Value ?? 0,
            sha256:try Integrity.sha256(url),duration:p.duration,width:p.video?.width ?? 0,height:p.video?.height ?? 0,
            fps:p.video?.fps ?? 0,hasAudio:p.audio != nil,kind:kind,streams:p.streams,
            authorizationBasis:request.authorizationBasis,archiveReference:request.archiveReference,classificationEvidence:evidence)
    }
    static func intervalInputs(source: SourceRecord, intervals: [Interval]) -> [String] {
        intervals.flatMap { ["-ss",String(format:"%.9f",$0.start),"-t",String(format:"%.9f",$0.duration),"-i",source.path] }
    }
    static func audioFilter(_ intervals: [Interval]) -> String {
        var filters = intervals.indices.map { "[\($0):a:0]aresample=48000,asetpts=PTS-STARTPTS[a\($0)]" }
        filters.append(intervals.indices.map {"[a\($0)]"}.joined()+"concat=n=\(intervals.count):v=0:a=1[a]")
        return filters.joined(separator:";")
    }
    static func fitFilter(_ profile: SharedProfile) -> String {
        "fps=30,scale=w='min(iw,\(profile.width))':h='min(ih,\(profile.height))':force_original_aspect_ratio=decrease:force_divisible_by=2:reset_sar=1,pad=\(profile.width):\(profile.height):(ow-iw)/2:(oh-ih)/2:black,setsar=1,format=yuv420p"
    }
    static func nativeFilter(_ source: SourceRecord, _ clip: ClipRecord, _ profile: SharedProfile) -> String {
        var filters: [String] = []
        for i in clip.intervals.indices {
            filters.append("[\(i):v:0]setpts=PTS-STARTPTS,\(fitFilter(profile))[v\(i)]")
            if source.hasAudio { filters.append("[\(i):a:0]aresample=48000,asetpts=PTS-STARTPTS[a\(i)]") }
        }
        filters.append(clip.intervals.indices.map {"[v\($0)]"+(source.hasAudio ? "[a\($0)]":"")}.joined()+"concat=n=\(clip.intervals.count):v=1:a=\(source.hasAudio ? 1:0)[v]"+(source.hasAudio ? "[a]":""))
        return filters.joined(separator:";")
    }
    public static func render(source: SourceRecord, clip: ClipRecord, profile: SharedProfile, artwork: Artwork?, work: URL, output: URL) async throws -> RenderReceipt {
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at:work,withIntermediateDirectories:true)
        try Persistence.checkDisk(at:work,requiredBytes:Int64(clip.expectedDuration*1_500_000))
        var receipt = RenderReceipt(pictureWidth:0,pictureHeight:0)
        let scale = min(1,min(Double(profile.width)/Double(max(1,source.width)),Double(profile.height)/Double(max(1,source.height))))
        receipt.pictureWidth = Int(Double(source.width)*scale/2)*2
        receipt.pictureHeight = Int(Double(source.height)*scale/2)*2
        let input = intervalInputs(source:source,intervals:clip.intervals)
        if source.hasAudio {
            let selected = work.appendingPathComponent("selected.wav")
            _ = try await Processes.run("ffmpeg",["-nostdin","-v","error","-y"]+input+["-filter_complex",audioFilter(clip.intervals),"-map","[a]","-c:a","pcm_s16le",selected.path])
            receipt.selectedAudio = selected.path
        }
        let maxVideoRate = Int(max(64_000,min(6_000_000,Double(profile.maxBytes)*8/clip.expectedDuration*0.90-192_000)))
        if source.kind == .nativeVideo {
            var args = ["-nostdin","-v","error","-y"]+input+["-filter_complex",nativeFilter(source,clip,profile),"-map","[v]"]
            if source.hasAudio { args += ["-map","[a]","-c:a","aac","-profile:a","aac_low","-b:a","192k"] }
            args += ["-c:v","libx264","-preset","veryfast","-crf","18","-maxrate",String(maxVideoRate),"-bufsize",String(maxVideoRate*2),"-pix_fmt","yuv420p","-r","30","-g","60","-movflags","+faststart","-t",String(clip.expectedDuration),output.path]
            _ = try await Processes.run("ffmpeg",args)
        } else {
            guard let artwork, artwork.owner == source.owner,
                  source.owner != .taxstone || artwork.sourceID == source.id,
                  source.owner != .dub || artwork.driveID == "1fRg-Dfd-V_VdZQuPZVGDM3kdHD-qi6V1",
                  source.owner != .dub || artwork.file.sha256 == "1522d2fbbbb6d943cd08cb07b617212be4fafcb841c7dcdba713fe81c4fdc790",
                  let selected = receipt.selectedAudio else { throw JoeyError.dependency("Missing approved \(source.owner.rawValue) artwork matching source \(source.id)") }
            let audio = work.appendingPathComponent("final-audio.m4a")
            _ = try await Processes.run("ffmpeg",["-nostdin","-v","error","-y","-i",selected,"-c:a","aac","-profile:a","aac_low","-b:a","192k",audio.path])
            let pcm = work.appendingPathComponent("waveform.f32")
            _ = try await Processes.run("ffmpeg",["-nostdin","-v","error","-i",audio.path,"-vn","-ac","1","-ar","48000","-f","f32le","-"],output:pcm)
            let wave = AudioPresentation.envelope(samples:try AudioPresentation.samples(pcm),sampleRate:48000)
            let background = try AudioPresentation.background(artwork:artwork,title:clip.title,width:profile.width,height:profile.height)
            let backgroundURL = work.appendingPathComponent("background.png")
            try AudioPresentation.writePNG(background,to:backgroundURL)
            let video = work.appendingPathComponent("audio-video.mp4")
            if FileManager.default.fileExists(atPath:video.path) { try FileManager.default.removeItem(at:video) }
            try await AudioPresentation.render(background:background,envelope:wave,owner:source.owner,duration:clip.expectedDuration,output:video)
            _ = try await Processes.run("ffmpeg",["-nostdin","-v","error","-y","-i",video.path,"-i",audio.path,"-map","0:v:0","-map","1:a:0",
                "-c:v","libx264","-preset","veryfast","-crf","18","-maxrate",String(maxVideoRate),"-bufsize",String(maxVideoRate*2),"-pix_fmt","yuv420p","-vf","setsar=1","-r","30","-c:a","copy","-movflags","+faststart","-t",String(clip.expectedDuration),output.path])
            receipt.recipe = "approved-\(source.owner.rawValue)-audio-fixed-bars-v1"
            receipt.background = backgroundURL.path; receipt.waveformPCM = pcm.path; receipt.waveform = wave
            receipt.pictureWidth = profile.width; receipt.pictureHeight = profile.height
        }
        try Persistence.save(receipt,to:work.appendingPathComponent("render.json"))
        return receipt
    }
    public static func validate(output: URL, source: SourceRecord, clip: ClipRecord, profile: SharedProfile, render: RenderReceipt, work: URL) async throws -> QAReport {
        try await decode(output)
        let p = try await probe(output)
        let bytes = ((try FileManager.default.attributesOfItem(atPath:output.path))[.size] as? NSNumber)?.int64Value ?? 0
        guard let v = p.video, v.codec_name == "h264", v.pix_fmt == "yuv420p", v.width == profile.width, v.height == profile.height,
              abs(v.fps-30) < 0.001, v.sample_aspect_ratio == "1:1", v.field_order == "progressive",
              abs(p.duration-clip.expectedDuration) <= 0.075, p.duration <= profile.maxDuration+Planning.tolerance,
              bytes > 0, bytes <= profile.maxBytes,
              (source.hasAudio ? p.audio?.codec_name == "aac" && p.audio?.profile == "LC" : p.audio == nil),
              p.streams.count == (source.hasAudio ? 2:1) else { throw JoeyError.failed("Output technical profile/duration/stream/size validation failed") }
        var checks = ["complete_decode":"FFmpeg full decode with error escalation passed",
            "technical":"H.264/yuv420p/progressive/SAR 1:1/30fps; AAC-LC where source has audio; measured \(p.duration)s, \(bytes) bytes",
            "intervals":"Exact planned source intervals assembled; measured duration tolerance 0.075s",
            "framing":"Source \(source.width)x\(source.height); effective picture \(render.pictureWidth)x\(render.pictureHeight) inside \(profile.width)x\(profile.height), no quality-upscale claim"]
        let file = try FileHandle(forReadingFrom:output); defer {try? file.close()}
        let header = try file.read(upToCount:min(Int(bytes),4*1024*1024)) ?? Data()
        guard let moov = header.range(of:Data("moov".utf8)), let mdat = header.range(of:Data("mdat".utf8)), moov.lowerBound < mdat.lowerBound else { throw JoeyError.failed("MP4 faststart metadata not before media") }
        checks["web_playback"] = "moov precedes mdat"
        if let selected = render.selectedAudio {
            let expectedPCM = work.appendingPathComponent("qa-expected.f32"), actualPCM = work.appendingPathComponent("qa-actual.f32")
            let channels = min(2,source.streams.first {$0.codec_type == "audio"}?.channels ?? 1)
            for (input,path) in [(selected,expectedPCM),(output.path,actualPCM)] {
                _ = try await Processes.run("ffmpeg",["-nostdin","-v","error","-i",input,"-vn","-ac",String(channels),"-ar","12000","-f","f32le","-"],output:path)
            }
            let a = try AudioPresentation.samples(expectedPCM), b = try AudioPresentation.samples(actualPCM)
            guard abs(a.count-b.count) <= 900*channels else { throw JoeyError.failed("Audio duration differs beyond 75ms encoding tolerance") }
            var minimum = 1.0, comparisons = 0
            let count = min(a.count,b.count)
            for channel in 0..<channels {
                for start in stride(from:channel,to:count,by:12000*channels) {
                    let end = min(count,start+12000*channels)
                    var aa = 0.0, bb = 0.0, ab = 0.0
                    for i in stride(from:start,to:end,by:channels) { aa += Double(a[i])*Double(a[i]); bb += Double(b[i])*Double(b[i]); ab += Double(a[i])*Double(b[i]) }
                    if aa < 0.000001 {
                        guard bb < 0.001 else { throw JoeyError.failed("Source silence changed to audible output") }
                    } else {
                        let correlation = ab/sqrt(max(1e-20,aa*bb)), gain = sqrt(bb/aa)
                        guard correlation >= 0.90, gain >= 0.7, gain <= 1.4 else { throw JoeyError.failed("Audio fidelity/sync failed at sample \(start): correlation \(correlation), gain \(gain)") }
                        minimum = min(minimum,correlation); comparisons += 1
                    }
                }
            }
            checks["audio_fidelity_sync"] = "\(comparisons) one-second channel windows at 12kHz; minimum zero-lag correlation \(minimum); gain 0.7–1.4; silence checked"
        }
        if source.kind == .nativeVideo {
            let expected = work.appendingPathComponent("expected-picture.gray")
            var filter = nativeFilter(source,clip,profile)
            if source.hasAudio { filter += ";[a]anullsink" }
            filter += ";[v]fps=2,scale=160:284,format=gray[q]"
            _ = try await Processes.run("ffmpeg",["-nostdin","-v","error"]+intervalInputs(source:source,intervals:clip.intervals)+["-filter_complex",filter,"-map","[q]","-t",String(clip.expectedDuration),"-f","rawvideo","-"],output:expected)
            let actual = work.appendingPathComponent("actual-picture.gray")
            _ = try await Processes.run("ffmpeg",["-nostdin","-v","error","-i",output.path,"-vf","fps=2,scale=160:284,format=gray","-an","-f","rawvideo","-"],output:actual)
            let a = try Data(contentsOf:expected,options:.mappedIfSafe), b = try Data(contentsOf:actual,options:.mappedIfSafe)
            guard !a.isEmpty, abs(a.count-b.count) <= 160*284 else { throw JoeyError.failed("Picture sample coverage mismatch") }
            let mean = zip(a,b).reduce(0.0) {$0+abs(Double($1.0)-Double($1.1))}/Double(min(a.count,b.count))
            guard mean <= 6 else { throw JoeyError.failed("Source-only picture fidelity failed: mean pixel error \(mean)") }
            checks["picture_fidelity"] = "2fps whole-frame 160x284 grayscale comparison; mean pixel error \(mean)/255; includes padding and source graphics"
            checks["unrequested_additions"] = "Source-only render recipe and whole-frame comparison; no added artwork, captions, logos or outro"
        } else {
            guard let background = render.background, let waveform = render.waveform, let pcm = render.waveformPCM else { throw JoeyError.failed("Audio presentation evidence absent") }
            let decoded = work.appendingPathComponent("qa-wave.f32")
            _ = try await Processes.run("ffmpeg",["-nostdin","-v","error","-i",output.path,"-vn","-ac","1","-ar","48000","-f","f32le","-"],output:decoded)
            let expectedSamples = try AudioPresentation.samples(URL(fileURLWithPath:pcm)), finalSamples = try AudioPresentation.samples(decoded)
            guard abs(expectedSamples.count-finalSamples.count) <= 3600 else { throw JoeyError.failed("Waveform/final audio mismatch") }
            let wave = AudioPresentation.envelope(samples:finalSamples,sampleRate:48000)
            guard zip(wave.levels,waveform.levels).allSatisfy({abs($0-$1) < 0.05}) else { throw JoeyError.failed("Waveform response does not match final audio") }
            checks["waveform"] = "Fixed 120 horizontal positions, vertical source-PCM amplitude; decoded final audio envelope matched within 0.05; PCM SHA256 \(try Integrity.sha256(URL(fileURLWithPath:pcm)))"
            let box = AudioPresentation.waveBox(owner:source.owner,width:profile.width)
            let wavePixels = work.appendingPathComponent("qa-wave.rgb")
            let bw = Int(box.width), bh = Int(box.height)
            _ = try await Processes.run("ffmpeg",["-nostdin","-v","error","-i",output.path,"-vf",
                "select='not(mod(n,15))',format=rgb24,crop=\(bw):\(bh):\(Int(box.minX)):\(Int(box.minY)):exact=1",
                "-fps_mode","passthrough","-an","-f","rawvideo","-"],output:wavePixels)
            let pixels = try Data(contentsOf:wavePixels,options:.mappedIfSafe)
            let frameBytes = bw*bh*3, sampledFrames = pixels.count/frameBytes
            guard sampledFrames > 0, pixels.count%frameBytes == 0 else {throw JoeyError.failed("Decoded waveform frame geometry mismatch")}
            let target = source.owner == .dub ? [230,174,57] : [255,255,255]
            var measured = 0, matching = 0
            for frame in 0..<sampledFrames {
                let level = waveform.levels[min(frame*15,waveform.levels.count-1)]
                for bar in stride(from:0,to:120,by:3) {
                    let expected = waveform.shape[bar]*level*Double(bh)*0.46
                    let x = min(bw-1,Int((box.minX-floor(box.minX)+(Double(bar)+0.5)*box.width/120+max(1,box.width/250)/2).rounded()))
                    let center = Int((box.minY-floor(box.minY)+box.height/2).rounded())
                    var extent = 0
                    for y in 0..<bh {
                        // Narrow bars acquire chroma-edge interpolation in
                        // yuv420p. Inspect their center and immediate neighbors,
                        // without moving to the next fixed horizontal bar.
                        for dx in -1...1 where x+dx >= 0 && x+dx < bw {
                            let offset = frame*frameBytes+(y*bw+x+dx)*3
                            let difference = (0..<3).reduce(0) {$0+abs(Int(pixels[offset+$1])-target[$1])}
                            if difference < 110 {extent = max(extent,abs(y-center))}
                        }
                    }
                    measured += 1
                    if abs(Double(extent)-expected) <= 4 {matching += 1}
                }
            }
            guard measured > 0, Double(matching)/Double(measured) >= 0.92 else {
                throw JoeyError.failed("Rendered waveform missing/frozen/misaligned: \(matching)/\(measured) bar heights match final audio")
            }
            checks["waveform_pixels"] = "Decoded 2fps fixed-position/color bar-height comparison: \(matching)/\(measured) within 4 pixels of final-audio envelope"
            let sample = work.appendingPathComponent("qa-art.raw")
            _ = try await Processes.run("ffmpeg",["-nostdin","-v","error","-i",output.path,"-vf","fps=2,drawbox=x=\(Int(box.minX)-4):y=\(Int(box.minY)-4):w=\(Int(box.width)+8):h=\(Int(box.height)+8):color=black:t=fill,scale=160:284,format=rgb24","-an","-f","rawvideo","-"],output:sample)
            let baseline = try await Processes.run("ffmpeg",["-nostdin","-v","error","-i",background,"-vf","drawbox=x=\(Int(box.minX)-4):y=\(Int(box.minY)-4):w=\(Int(box.width)+8):h=\(Int(box.height)+8):color=black:t=fill,scale=160:284,format=rgb24","-frames:v","1","-f","rawvideo","-"])
            let actual = try Data(contentsOf:sample,options:.mappedIfSafe), ref = [UInt8](baseline.stdout)
            guard !actual.isEmpty, ref.count == 160*284*3 else { throw JoeyError.failed("Artwork comparison has no samples") }
            var sum = 0.0
            for (i,b) in actual.enumerated() { sum += abs(Double(b)-Double(ref[i%ref.count])) }
            let mean = sum/Double(actual.count)
            guard mean < 6 else { throw JoeyError.failed("Approved artwork/layout fidelity failed: \(mean)") }
            checks["artwork_layout"] = "2fps protected full artwork/title/background RGB comparison; mean pixel error \(mean)/255; waveform region excluded"
        }
        return QAReport(checkedAt:Date(),checks:checks,outputSHA256:try Integrity.sha256(output),passed:true,
            limitations:["Automated technical/editorial checks are not infallible semantic judgment.","Picture sampling is 2fps, not exhaustive visual recognition.","Packaging compliance does not establish platform ingestion or Instagram placement."])
    }
}
