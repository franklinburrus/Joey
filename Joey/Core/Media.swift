import Foundation
import CoreGraphics

public struct StreamInfo: Codable, Equatable, Sendable {
    public struct SideData: Codable, Equatable, Sendable {
        public var rotation: Double?
    }
    public var index: Int?
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
    public var bit_rate: String?
    public var side_data_list: [SideData]?
    public var fps: Double {
        let p = (avg_frame_rate ?? "0/1").split(separator:"/").compactMap { Double($0) }
        return p.count == 2 && p[1] != 0 ? p[0]/p[1] : (p.first ?? 0)
    }
}
public struct MediaProbe: Codable, Sendable {
    public struct Format: Codable, Sendable { public var duration: String?; public var size: String?; public var format_name: String?; public var start_time: String? }
    public var streams: [StreamInfo]
    public var format: Format
    public var duration: Double { Double(format.duration ?? "") ?? 0 }
    public var video: StreamInfo? { streams.first { $0.codec_type == "video" } }
    public var audio: StreamInfo? { streams.first { $0.codec_type == "audio" } }
}
public struct RenderReceipt: Codable, Sendable {
    public var recipe = "shared-source-only-v1"
    public var joeBranding: JoeBranding?
    public var selectedAudio: String?
    public var waveformPCM: String?
    public var background: String?
    public var waveform: AudioEnvelope?
    public var pictureWidth: Int
    public var pictureHeight: Int
}
public enum Media {
    // Buffer's Instagram surface caps audio at 128 kbps. Leave room for
    // AAC's variable packet sizes, then verify the measured stream bitrate.
    static let audioEncodingBitrate = 120_000
    static let maximumAudioBitrate = 128_000
    static let maximumVideoBitrate = 25_000_000
    public static func probe(_ url: URL) async throws -> MediaProbe {
        let result = try await Processes.run("ffprobe",["-v","error","-show_streams","-show_format","-of","json",url.path])
        let probe = try JSONDecoder().decode(MediaProbe.self, from: result.stdout)
        guard probe.duration.isFinite, probe.duration > 0, probe.audio != nil || probe.video != nil else { throw JoeyError.invalid("Media has no valid finite streams") }
        return probe
    }
    public static func decode(_ url: URL) async throws {
        _ = try await Processes.run("ffmpeg", ["-nostdin","-v","error","-xerror","-err_detect","explode","-i",url.path,"-map","0:v?","-map","0:a?","-f","null","-"])
    }
    private static func lines(in url: URL, _ visit: (String) throws -> Void) throws {
        let file = try FileHandle(forReadingFrom:url);defer {try? file.close()}
        var pending = Data()
        while let chunk = try file.read(upToCount:64*1024), !chunk.isEmpty {
            pending.append(chunk)
            while let end = pending.firstIndex(of:10) {
                try visit(String(decoding:pending[..<end],as:UTF8.self))
                pending.removeSubrange(...end)
            }
        }
        if !pending.isEmpty {try visit(String(decoding:pending,as:UTF8.self))}
    }
    static func sourceTimeline(_ url: URL, probe: MediaProbe) async throws -> (duration: Double, streams: [StreamInfo]) {
        let origin = Double(probe.format.start_time ?? "") ?? probe.streams.compactMap {Double($0.start_time ?? "")}.min() ?? 0
        var streams = probe.streams
        let media = streams.indices.filter {["audio","video"].contains(streams[$0].codec_type ?? "")}
        // Container duration is not uniformly a span: NUT can report the last
        // absolute timestamp, while MPEG-TS reports a span despite a nonzero
        // start. Prefer stream spans, or measure packet endpoints when absent.
        if media.contains(where:{Double(streams[$0].duration ?? "") == nil}) {
            let packets = FileManager.default.temporaryDirectory.appendingPathComponent("joey-source-packets-"+UUID().uuidString)
            defer {try? FileManager.default.removeItem(at:packets)}
            _ = try await Processes.run("ffprobe",["-v","error","-show_packets","-show_entries","packet=stream_index,pts_time,duration_time","-of","compact=p=0:nk=0",url.path],output:packets)
            var first: [Int:Double] = [:], last: [Int:Double] = [:]
            try lines(in:packets) { line in
                let fields = Dictionary(line.split(separator:"|").compactMap {part -> (String,String)? in
                    let pieces = part.split(separator:"=",maxSplits:1)
                    return pieces.count == 2 ? (String(pieces[0]),String(pieces[1])) : nil
                },uniquingKeysWith:{_,new in new})
                guard let index = Int(fields["stream_index"] ?? ""), let pts = Double(fields["pts_time"] ?? ""), pts.isFinite,
                      let position = media.first(where:{(streams[$0].index ?? $0) == index}) else {return}
                let fallback = streams[position].codec_type == "video" && streams[position].fps > 0 ? 1/streams[position].fps : 0
                let duration = Double(fields["duration_time"] ?? "") ?? fallback
                guard duration.isFinite, duration >= 0 else {return}
                first[index] = min(first[index] ?? pts,pts)
                last[index] = max(last[index] ?? pts,pts+duration)
            }
            for position in media where Double(streams[position].duration ?? "") == nil {
                let index = streams[position].index ?? position
                guard let end = last[index], let observedStart = first[index] else {continue}
                let start = Double(streams[position].start_time ?? "") ?? observedStart
                streams[position].start_time = String(start)
                streams[position].duration = String(max(0,end-start))
            }
        }
        let ends = media.compactMap {position -> Double? in
            let start = Double(streams[position].start_time ?? "") ?? origin
            guard let duration = Double(streams[position].duration ?? ""),
                  start.isFinite,duration.isFinite,duration >= 0 else {return nil}
            return start+duration
        }
        guard ends.count == media.count,let end = ends.max(),end > origin else {throw JoeyError.failed("Cannot establish the source's actual timestamped timeline extent")}
        return (end-origin,streams)
    }
    static func validateVideoMapping(_ streams: [StreamInfo]) throws {
        guard streams.filter({$0.codec_type == "video"}).count <= 1 else {
            throw JoeyError.dependency("Multiple source video tracks require an explicit preservation mapping")
        }
    }
    public static func inspect(_ url: URL, request: JobRequest) async throws -> SourceRecord {
        let p = try await probe(url)
        let timeline = try await sourceTimeline(url,probe:p)
        if let expected = request.expectedDuration {
            guard expected.isFinite, abs(timeline.duration-expected) <= max(0.1,expected*0.001) else { throw JoeyError.invalid("Incomplete source: duration conflicts with source evidence") }
        }
        guard p.streams.filter({$0.codec_type == "audio"}).count <= 1 else { throw JoeyError.dependency("Multiple source audio tracks require an explicit preservation mapping") }
        try validateVideoMapping(p.streams)
        guard p.streams.allSatisfy({$0.codec_type != "subtitle"}) else { throw JoeyError.dependency("Separate subtitle stream needs a preservation mapping; source has not been changed") }
        try await decode(url)
        let attrs = try FileManager.default.attributesOfItem(atPath:url.path)
        var kind: MediaKind = .audio
        var evidence = "No video stream"
        if p.video != nil {
            var frames: [Data] = []
            for i in 0..<8 {
                let at = min(max(0,timeline.duration-0.05),Double(i)*timeline.duration/8)
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
            sha256:try Integrity.sha256(url),duration:timeline.duration,width:p.video?.width ?? 0,height:p.video?.height ?? 0,
            fps:p.video?.fps ?? 0,hasAudio:p.audio != nil,kind:kind,streams:timeline.streams,
            authorizationBasis:request.authorizationBasis,archiveReference:request.archiveReference,classificationEvidence:evidence)
    }
    static func intervalInputs(source: SourceRecord, intervals: [Interval]) -> [String] {
        let origin = source.streams.compactMap {Double($0.start_time ?? "")}.min() ?? 0
        let videoStart = (source.streams.first {$0.codec_type == "video"}.flatMap {Double($0.start_time ?? "")} ?? origin)-origin
        return ["-copyts","-start_at_zero"] + intervals.flatMap { interval in
            // Seeking even to zero can jump to the first video keyframe and
            // discard earlier audio when the source picture starts later.
            // Before that first picture, decode from the common file origin.
            let seek = interval.start > 0 && interval.start >= videoStart
            return (seek ? ["-ss",String(format:"%.9f",interval.start)] : [])
                + ["-t",String(format:"%.9f",seek ? interval.duration : interval.end),"-i",source.path]
        }
    }
    static func intervalAudioFilter(_ interval: Interval) -> String {
        // Both streams use the requested source interval as their origin.
        // Silence represents time where the source has no audio packets; it
        // must not move later samples forward or move a concat boundary.
        // The default resampler threshold ignores small timestamp gaps. Hard
        // compensation at 100 microseconds preserves millisecond packet gaps
        // without stretching subsequent source audio to absorb the difference.
        "atrim=start=\(interval.start):end=\(interval.end),asetpts=PTS-\(interval.start)/TB,aresample=48000:async=1:min_comp=0.0001:min_hard_comp=0.0001:first_pts=0,atrim=duration=\(interval.duration)"
    }
    static func hasSourceAudio(_ source: SourceRecord, in interval: Interval) -> Bool {
        guard let audio = source.streams.first(where: {$0.codec_type == "audio"}) else {return false}
        let origin = source.streams.compactMap {Double($0.start_time ?? "")}.min() ?? 0
        let start = (Double(audio.start_time ?? "") ?? origin)-origin
        let end = Double(audio.duration ?? "").map {start+$0} ?? .infinity
        return interval.end > start && interval.start < end
    }
    static func intervalAudioInput(_ source: SourceRecord, interval: Interval, index: Int) -> String {
        let channels = source.streams.first {$0.codec_type == "audio"}?.channels ?? 1
        let layout = channels == 1 ? "mono" : channels == 2 ? "stereo" : "\(channels)c"
        if !hasSourceAudio(source,in:interval) {return "anullsrc=r=48000:cl=\(layout):d=\(interval.duration)[a\(index)]"}
        // A finite silence input also covers an interior packet gap or unknown
        // audio end. Mix without normalization to preserve every source sample.
        return "anullsrc=r=48000:cl=\(layout):d=\(interval.duration)[silence\(index)];"
            + "[\(index):a:0]\(intervalAudioFilter(interval))[samples\(index)];"
            + "[silence\(index)][samples\(index)]amix=inputs=2:duration=first:normalize=0,atrim=duration=\(interval.duration)[a\(index)]"
    }
    static func audioFilter(_ source: SourceRecord, _ intervals: [Interval]) -> String {
        var filters = intervals.indices.map {intervalAudioInput(source,interval:intervals[$0],index:$0)}
        filters.append(intervals.indices.map {"[a\($0)]"}.joined()+"concat=n=\(intervals.count):v=0:a=1[a]")
        return filters.joined(separator:";")
    }
    static func fitFilter(_ profile: SharedProfile) -> String {
        "fps=30,scale=w='min(iw,\(profile.width))':h='min(ih,\(profile.height))':force_original_aspect_ratio=decrease:force_divisible_by=2:reset_sar=1,pad=\(profile.width):\(profile.height):(ow-iw)/2:(oh-ih)/2:black,setsar=1,format=yuv420p"
    }
    static func fittedPictureDimensions(_ video: StreamInfo, profile: SharedProfile) throws -> (width: Int, height: Int) {
        guard let codedWidth = video.width, let codedHeight = video.height, codedWidth > 0, codedHeight > 0 else {
            throw JoeyError.failed("Source picture display dimensions are unavailable")
        }
        let parts = (video.sample_aspect_ratio ?? "1:1").split(separator:":").compactMap {Double($0)}
        let ratio = parts.count == 2 && parts[0] > 0 && parts[1] > 0 ? parts[0]/parts[1] : 1
        guard ratio.isFinite, ratio > 0 else {throw JoeyError.failed("Source picture sample aspect is invalid")}
        var width = Double(codedWidth), height = Double(codedHeight), aspect = ratio
        let rotation = video.side_data_list?.compactMap(\.rotation).first ?? 0
        // FFmpeg autorotation precedes the fit filter. Quarter turns swap both
        // coded axes and the pixel aspect; other display rotations keep its
        // decoded frame dimensions. The output is always square-pixel video.
        let turn = abs(rotation.truncatingRemainder(dividingBy:180))
        if abs(turn-90) < 0.001 {swap(&width,&height); aspect = 1/aspect}
        let displayWidth = width*aspect
        let scale = min(min(width,Double(profile.width))/displayWidth,min(height,Double(profile.height))/height)
        return (Int(displayWidth*scale/2)*2,Int(height*scale/2)*2)
    }
    static func nativeFilter(_ source: SourceRecord, _ clip: ClipRecord, _ profile: SharedProfile) -> String {
        var filters: [String] = []
        for i in clip.intervals.indices {
            let interval = clip.intervals[i]
            filters.append("[\(i):v:0]trim=start=\(interval.start):end=\(interval.end),setpts=PTS-\(interval.start)/TB,\(fitFilter(profile))[picture\(i)]")
            // A finite black canvas retains absent source-picture time without
            // advancing video or repeating a frame before it actually exists.
            filters.append("color=c=black:s=\(profile.width)x\(profile.height):r=30:d=\(interval.duration)[canvas\(i)]")
            filters.append("[canvas\(i)][picture\(i)]overlay=eof_action=pass:repeatlast=0,trim=duration=\(interval.duration),setsar=1[v\(i)]")
            if source.hasAudio { filters.append(intervalAudioInput(source,interval:interval,index:i)) }
        }
        filters.append(clip.intervals.indices.map {"[v\($0)]"+(source.hasAudio ? "[a\($0)]":"")}.joined()+"concat=n=\(clip.intervals.count):v=1:a=\(source.hasAudio ? 1:0)[v]"+(source.hasAudio ? "[a]":""))
        return filters.joined(separator:";")
    }
    static func compositionInputs(source: SourceRecord, clip: ClipRecord, branding: JoeBranding?) -> [String] {
        intervalInputs(source:source,intervals:clip.intervals) + (branding.map {["-i",$0.logo.path,"-i",$0.outro.path]} ?? [])
    }
    static func joeAudioSegment(duration: Double) -> String {
        // Fix the layout before concatenation so WAV reference and AAC output
        // cannot negotiate different mono/stereo mixes at the outro boundary.
        "aformat=sample_fmts=fltp:sample_rates=48000:channel_layouts=stereo,apad,atrim=duration=\(duration),asetpts=PTS-STARTPTS"
    }
    static func compositionFilter(_ source: SourceRecord, _ clip: ClipRecord, _ profile: SharedProfile, branding: JoeBranding?) -> String {
        let base = nativeFilter(source,clip,profile)
        guard let branding else {return base}
        let native = base.replacingOccurrences(of:"[v]",with:"[nv]").replacingOccurrences(of:"[a]",with:"[na]")
        let logo = clip.intervals.count, outro = logo+1
        return native + ";[nv]null[content];[na]\(joeAudioSegment(duration:clip.expectedDuration))[ca]"
            + ";[\(logo):v]scale=180:180,format=rgba[logo];[content][logo]overlay=x=34:y=866:eof_action=repeat[branded]"
            + ";[\(outro):v]setpts=PTS-STARTPTS,\(fitFilter(profile)),trim=duration=\(branding.outroDuration)[ov]"
            + ";[\(outro):a]\(joeAudioSegment(duration:branding.outroDuration))[oa]"
            // A/V concat pads audio to the rounded video-frame boundary. Keep
            // the exact source/outro audio boundary independent of that rounding.
            + ";[branded][ov]concat=n=2:v=1:a=0[v];[ca][oa]concat=n=2:v=0:a=1[a]"
    }
    public static func render(source: SourceRecord, clip: ClipRecord, profile: SharedProfile, artwork: Artwork?, work: URL, output: URL, branding: JoeBranding? = nil) async throws -> RenderReceipt {
        try Task.checkCancellation()
        try validateVideoMapping(source.streams)
        let outputProfile = try profile.outputProfile(for:source.kind)
        try FileManager.default.createDirectory(at:work,withIntermediateDirectories:true)
        try Persistence.checkDisk(at:work,requiredBytes:StorageManager.peakBytes(duration:clip.expectedDuration,sourceBytes:0,clipDuration:clip.expectedDuration+(branding?.outroDuration ?? 0),audio:source.kind == .audio))
        var receipt = RenderReceipt(pictureWidth:0,pictureHeight:0)
        if let branding {
            try branding.validate()
            guard profile.driveOnlyJoe == true, source.kind == .nativeVideo, source.hasAudio else {throw JoeyError.invalid("Joe branding requires native video with audio and the Drive-only export contract")}
            receipt.joeBranding = branding;receipt.recipe = "joe-dub-lower-left-and-approved-outro-v1"
        }
        let outputDuration = clip.expectedDuration + (branding?.outroDuration ?? 0)
        // Preserve mono/stereo and fit multichannel sources to the shared
        // upload contract. Joe's approved composition already uses stereo.
        let audioChannels = branding != nil ? 2 : min(2,source.streams.first {$0.codec_type == "audio"}?.channels ?? 1)
        if source.kind == .nativeVideo {
            // Re-probe display metadata so older source checkpoints, which did
            // not serialize display matrices, remain recoverable unchanged.
            guard let video = try await probe(URL(fileURLWithPath:source.path)).video else {throw JoeyError.failed("Native source picture is unavailable")}
            let picture = try fittedPictureDimensions(video,profile:outputProfile)
            receipt.pictureWidth = picture.width;receipt.pictureHeight = picture.height
        }
        let input = intervalInputs(source:source,intervals:clip.intervals)
        if source.hasAudio {
            let selected = work.appendingPathComponent("selected.wav")
            _ = try await Processes.run("ffmpeg",["-nostdin","-v","error","-y"]+input+["-filter_complex",audioFilter(source,clip.intervals),"-map","[a]","-c:a","pcm_s16le",selected.path])
            if let branding {
                let composed = work.appendingPathComponent("selected-with-outro.wav")
                let filter = "[0:a]\(joeAudioSegment(duration:clip.expectedDuration))[c];[1:a]\(joeAudioSegment(duration:branding.outroDuration))[o];[c][o]concat=n=2:v=0:a=1[a]"
                _ = try await Processes.run("ffmpeg",["-nostdin","-v","error","-y","-i",selected.path,"-i",branding.outro.path,"-filter_complex",filter,"-map","[a]","-c:a","pcm_s16le",composed.path])
                receipt.selectedAudio = composed.path
            } else {receipt.selectedAudio = selected.path}
        }
        let maxVideoRate = Int(max(64_000,min(6_000_000,Double(profile.maxBytes)*8/outputDuration*0.90-Double(audioEncodingBitrate))))
        if source.kind == .nativeVideo {
            var args = ["-nostdin","-v","error","-y"]+compositionInputs(source:source,clip:clip,branding:branding)+["-filter_complex",compositionFilter(source,clip,outputProfile,branding:branding),"-map","[v]"]
            if source.hasAudio { args += ["-map","[a]","-c:a","aac","-profile:a","aac_low","-ac",String(audioChannels),"-b:a",String(audioEncodingBitrate)] }
            args += ["-c:v","libx264","-preset","veryfast","-crf","18","-maxrate",String(maxVideoRate),"-bufsize",String(maxVideoRate*2),"-pix_fmt","yuv420p","-r","30","-g","60","-movflags","+faststart","-t",String(outputDuration),output.path]
            _ = try await Processes.run("ffmpeg",args)
        } else {
            guard let artwork, artwork.owner == source.owner,
                  source.owner != .taxstone || artwork.sourceID == source.id,
                  source.owner != .dub || artwork.driveID == "1fRg-Dfd-V_VdZQuPZVGDM3kdHD-qi6V1",
                  source.owner != .dub || artwork.file.sha256 == "1522d2fbbbb6d943cd08cb07b617212be4fafcb841c7dcdba713fe81c4fdc790",
                  let selected = receipt.selectedAudio else { throw JoeyError.dependency("Missing approved \(source.owner.rawValue) artwork matching source \(source.id)") }
            let audio = work.appendingPathComponent("final-audio.m4a")
            _ = try await Processes.run("ffmpeg",["-nostdin","-v","error","-y","-i",selected,"-c:a","aac","-profile:a","aac_low","-ac",String(audioChannels),"-b:a",String(audioEncodingBitrate),audio.path])
            let pcm = work.appendingPathComponent("waveform.f32")
            _ = try await Processes.run("ffmpeg",["-nostdin","-v","error","-i",audio.path,"-vn","-ac","1","-ar","48000","-f","f32le","-"],output:pcm)
            let wave = AudioPresentation.envelope(samples:try AudioPresentation.samples(pcm),sampleRate:48000)
            let background = try AudioPresentation.background(artwork:artwork,title:clip.title,width:outputProfile.width,height:outputProfile.height)
            let backgroundURL = work.appendingPathComponent("background.png")
            try AudioPresentation.writePNG(background,to:backgroundURL)
            let video = work.appendingPathComponent("audio-video.mp4")
            if FileManager.default.fileExists(atPath:video.path) { try FileManager.default.removeItem(at:video) }
            try await AudioPresentation.render(background:background,envelope:wave,owner:source.owner,duration:clip.expectedDuration,output:video)
            _ = try await Processes.run("ffmpeg",["-nostdin","-v","error","-y","-i",video.path,"-i",audio.path,"-map","0:v:0","-map","1:a:0",
                "-c:v","libx264","-preset","veryfast","-crf","18","-maxrate",String(maxVideoRate),"-bufsize",String(maxVideoRate*2),"-pix_fmt","yuv420p","-vf","setsar=1","-r","30","-c:a","copy","-movflags","+faststart","-t",String(clip.expectedDuration),output.path])
            receipt.recipe = "approved-\(source.owner.rawValue)-audio-fixed-bars-v1"
            receipt.background = backgroundURL.path; receipt.waveformPCM = pcm.path; receipt.waveform = wave
            receipt.pictureWidth = outputProfile.width; receipt.pictureHeight = outputProfile.height
        }
        try Persistence.save(receipt,to:work.appendingPathComponent("render.json"))
        return receipt
    }
    static func audioReference(source: SourceRecord, clip: ClipRecord, profile: SharedProfile, artwork: Artwork, output: URL, work: URL) async throws -> RenderReceipt {
        let selected = work.appendingPathComponent("expected-source.wav")
        _ = try await Processes.run("ffmpeg",["-nostdin","-v","error","-y"]+intervalInputs(source:source,intervals:clip.intervals)+["-filter_complex",audioFilter(source,clip.intervals),"-map","[a]","-c:a","pcm_s16le",selected.path])
        let pcm = work.appendingPathComponent("final-waveform.f32")
        _ = try await Processes.run("ffmpeg",["-nostdin","-v","error","-i",output.path,"-vn","-ac","1","-ar","48000","-f","f32le","-"],output:pcm)
        let wave = AudioPresentation.envelope(samples:try AudioPresentation.samples(pcm),sampleRate:48000)
        let background = work.appendingPathComponent("expected-artwork.png")
        try AudioPresentation.writePNG(AudioPresentation.background(artwork:artwork,title:clip.title,width:profile.width,height:profile.height),to:background)
        var receipt = RenderReceipt(pictureWidth:profile.width,pictureHeight:profile.height)
        receipt.selectedAudio = selected.path;receipt.background = background.path
        receipt.waveformPCM = pcm.path;receipt.waveform = wave;receipt.recipe = "reconciled-existing-taxstone-audio"
        return receipt
    }
    static func validateAudioSamples(_ a: [Float], _ b: [Float], channels: Int, duration: Double) throws -> String {
        guard abs(a.count-b.count) <= 900*channels else { throw JoeyError.failed("Audio duration differs beyond 75ms encoding tolerance") }
        var minimum = 1.0, comparisons = 0
        // Decoding and resampling can retain packet padding after the cut.
        // Compare every intended sample, including a fractional final window,
        // but never treat padding beyond the planned interval as source audio.
        let plannedCount = Int((duration * 12000).rounded(.down)) * channels
        let count = min(a.count,b.count,plannedCount)
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
        return "\(comparisons) channel windows at 12kHz within the planned interval; minimum zero-lag correlation \(minimum); gain 0.7–1.4; silence checked"
    }
    static func sourceTimelineAudio(source: SourceRecord, intervals: [Interval], channels: Int, work: URL) async throws -> [Float] {
        let rate = 12_000
        let total = intervals.reduce(0.0) {$0+$1.duration}
        var samples = [Float](repeating:0,count:Int((total*Double(rate)).rounded())*channels)
        var outputStart = 0.0
        for interval in intervals {
            try Task.checkCancellation()
            if !hasSourceAudio(source,in:interval) {
                outputStart += interval.duration
                continue
            }
            let stem = "qa-source-timeline-"+UUID().uuidString
            let timed = work.appendingPathComponent(stem+".framecrc"), raw = work.appendingPathComponent(stem+".f32")
            defer {try? FileManager.default.removeItem(at:timed);try? FileManager.default.removeItem(at:raw)}
            // This oracle never resets timestamps, pads, mixes or concatenates
            // streams. Decode PCM with its source PTS, then place every packet
            // on the requested output timeline independently of render filters.
            let layout = channels == 1 ? "mono" : "stereo"
            let filter = "[0:a:0]atrim=start=\(interval.start):end=\(interval.end),aresample=\(rate),aformat=sample_fmts=flt:channel_layouts=\(layout),asplit=2[pcm][clock]"
            // The text sidecar remains valid with zero frames. Empty NUT
            // containers cannot be probed, so they cannot represent packet gaps.
            _ = try await Processes.run("ffmpeg",["-nostdin","-v","error","-y"] + intervalInputs(source:source,intervals:[interval]) +
                ["-filter_complex",filter,"-map","[pcm]","-c:a","pcm_f32le","-f","f32le",raw.path,
                 "-map","[clock]","-c:a","pcm_f32le","-f","framecrc",timed.path])
            let rawBytes = (try FileManager.default.attributesOfItem(atPath:raw.path)[.size] as? NSNumber)?.intValue ?? -1
            let decoded: [Float] = rawBytes == 0 ? [] : try AudioPresentation.samples(raw)
            var cursor = 0
            var timebase: Double?
            let intervalEnd = Int(((outputStart+interval.duration)*Double(rate)).rounded())*channels
            try lines(in:timed) {line in
                if line.hasPrefix("#tb 0:") {
                    let terms = line.dropFirst(6).trimmingCharacters(in:.whitespaces).split(separator:"/").compactMap {Double($0)}
                    if terms.count == 2,terms[1] > 0 {timebase = terms[0]/terms[1]}
                    return
                }
                if line.isEmpty || line.hasPrefix("#") {return}
                let fields = line.split(separator:",").map {$0.trimmingCharacters(in:.whitespaces)}
                guard fields.count >= 6, fields[0] == "0",let base = timebase,base.isFinite,base > 0,
                      let ticks = Double(fields[2]),ticks.isFinite,let bytes = Int(fields[4]),bytes >= 0,bytes%(4*channels) == 0 else {
                    throw JoeyError.failed("Audio source timeline packet metadata is invalid")
                }
                let pts = ticks*base
                let count = bytes/4
                guard cursor+count <= decoded.count else {throw JoeyError.failed("Audio source timeline packet coverage differs from decoded PCM")}
                let destination = Int(((outputStart+pts-interval.start)*Double(rate)).rounded())*channels
                let lower = max(0,-destination), upper = min(count,min(samples.count,intervalEnd)-destination)
                if lower < upper {
                    samples.replaceSubrange((destination+lower)..<(destination+upper),with:decoded[(cursor+lower)..<(cursor+upper)])
                }
                cursor += count
            }
            guard cursor == decoded.count else {throw JoeyError.failed("Audio source timeline has unaccounted decoded samples")}
            outputStart += interval.duration
        }
        return samples
    }
    static func validateSourcePictureTiming(output: URL, source: SourceRecord, clip: ClipRecord, profile: SharedProfile, render: RenderReceipt) async throws -> String {
        let probe = try await probe(URL(fileURLWithPath:source.path))
        let origin = Double(probe.format.start_time ?? "") ?? source.streams.compactMap {Double($0.start_time ?? "")}.min() ?? 0
        let first = (Double(probe.video?.start_time ?? "") ?? origin)-origin
        var offset = 0.0, comparisons = 0
        let width = render.pictureWidth, height = render.pictureHeight
        guard width > 0, height > 0, width <= profile.width, height <= profile.height else {throw JoeyError.failed("Source picture timeline geometry is absent")}
        guard let video = probe.video else {throw JoeyError.failed("Source picture timeline stream is absent")}
        let picture = try fittedPictureDimensions(video,profile:profile)
        guard width == picture.width, height == picture.height else {throw JoeyError.failed("Source picture timeline geometry conflicts with display metadata")}
        var comparison = "scale=160:90,format=gray"
        if render.joeBranding != nil {
            // Map only the approved logo footprint into the fitted picture
            // rectangle. Apply the identical mask before sampling both images;
            // source timing elsewhere remains independent of compositionFilter.
            let left = (profile.width-width)/2, top = (profile.height-height)/2
            let x = max(0,34-left), y = max(0,866-top)
            let right = min(width,214-left), bottom = min(height,1046-top)
            if right > x, bottom > y {
                comparison = "drawbox=x=\(x):y=\(y):w=\(right-x):h=\(bottom-y):color=black:t=fill,"+comparison
            }
        }
        for interval in clip.intervals {
            // Independent direct seeks catch a reference graph that accidentally
            // repeats the renderer's timestamp normalization. Compare only the
            // picture rectangle so black portrait padding cannot hide a shift.
            for fraction in [0.1,0.5,0.9] {
                let outputTime = floor((offset+interval.duration*fraction)*30)/30
                let sourceTime = interval.start+outputTime-offset
                let actual = try await Processes.run("ffmpeg",["-nostdin","-v","error","-ss",String(outputTime),"-i",output.path,"-frames:v","1",
                    "-vf","crop=\(width):\(height):(iw-\(width))/2:(ih-\(height))/2,\(comparison)","-an","-f","rawvideo","-"])
                var expected = Data(repeating:0,count:160*90)
                if sourceTime >= first {
                    let result = try await Processes.run("ffmpeg",["-nostdin","-v","error","-ss",String(sourceTime),"-i",source.path,"-frames:v","1",
                        "-vf","scale=\(width):\(height),\(comparison)","-an","-f","rawvideo","-"])
                    if !result.stdout.isEmpty {expected = result.stdout}
                }
                guard actual.stdout.count == expected.count else {throw JoeyError.failed("Source picture timeline sample coverage mismatch")}
                let mean = zip(actual.stdout,expected).reduce(0.0) {$0+abs(Double($1.0)-Double($1.1))}/Double(expected.count)
                // Independent source seeks can select the neighboring frame at
                // a fractional cut. This bound allows that single-frame error.
                guard mean <= 16 else {throw JoeyError.failed("Source picture timeline differs at output \(outputTime)s: mean pixel error \(mean)")}
                comparisons += 1
            }
            offset += interval.duration
        }
        return "\(comparisons) independent source/output seeks inside the picture rectangle; common file origin and interval positions checked"
            + (render.joeBranding == nil ? "" : "; only the approved logo footprint masked during source content; outro checked separately")
    }
    public static func validate(output: URL, source: SourceRecord, clip: ClipRecord, profile: SharedProfile, render: RenderReceipt, work: URL) async throws -> QAReport {
        try validateVideoMapping(source.streams)
        let outputProfile = try profile.outputProfile(for:source.kind)
        try await decode(output)
        let p = try await probe(output)
        let branding = render.joeBranding
        if let branding {try branding.validate()}
        guard (profile.driveOnlyJoe == true) == (branding != nil) else {throw JoeyError.failed("Export contract and branding evidence disagree")}
        let outputDuration = clip.expectedDuration + (branding?.outroDuration ?? 0)
        try DurationPolicy(profile:profile).validateMeasured(p.duration,expected:outputDuration)
        let bytes = ((try FileManager.default.attributesOfItem(atPath:output.path))[.size] as? NSNumber)?.int64Value ?? 0
        let videoBitrate = Int(p.video?.bit_rate ?? "") ?? 0
        let audioBitrate = Int(p.audio?.bit_rate ?? "") ?? 0
        guard let v = p.video, v.codec_name == "h264", v.pix_fmt == "yuv420p", v.width == outputProfile.width, v.height == outputProfile.height,
              abs(v.fps-30) < 0.001, v.sample_aspect_ratio == "1:1", v.field_order == "progressive",
              bytes > 0, bytes <= profile.maxBytes,
              videoBitrate > 0, videoBitrate < maximumVideoBitrate,
              (source.hasAudio ? p.audio?.codec_name == "aac" && p.audio?.profile == "LC"
                  && p.audio?.sample_rate == "48000" && (1...2).contains(p.audio?.channels ?? 0)
                  && audioBitrate > 0 && audioBitrate < maximumAudioBitrate : p.audio == nil),
              p.streams.count == (source.hasAudio ? 2:1) else { throw JoeyError.failed("Output technical profile/duration/stream/size validation failed") }
        var checks = ["complete_decode":"FFmpeg full decode with error escalation passed",
            "technical":"H.264/yuv420p/progressive/SAR 1:1/30fps; measured video bitrate \(videoBitrate) bps below 25000000; AAC-LC/48kHz/mono or stereo where source has audio, measured audio bitrate \(audioBitrate) bps below 128000; measured \(p.duration)s, \(bytes) bytes",
            "intervals":"Exact planned source intervals assembled; measured duration tolerance 0.075s",
            "framing":"Source \(source.width)x\(source.height); effective picture \(render.pictureWidth)x\(render.pictureHeight) inside \(outputProfile.width)x\(outputProfile.height), no quality-upscale claim"]
        let file = try FileHandle(forReadingFrom:output); defer {try? file.close()}
        let header = try file.read(upToCount:min(Int(bytes),4*1024*1024)) ?? Data()
        guard let moov = header.range(of:Data("moov".utf8)), let mdat = header.range(of:Data("mdat".utf8)), moov.lowerBound < mdat.lowerBound else { throw JoeyError.failed("MP4 faststart metadata not before media") }
        checks["web_playback"] = "moov precedes mdat"
        if source.hasAudio {
            let actualPCM = work.appendingPathComponent("qa-actual.f32")
            let channels = branding != nil ? 2 : min(2,source.streams.first {$0.codec_type == "audio"}?.channels ?? 1)
            var a = try await sourceTimelineAudio(source:source,intervals:clip.intervals,channels:channels,work:work)
            if let branding {
                var outro = source
                outro.path = branding.outro.path; outro.streams = try await probe(URL(fileURLWithPath:outro.path)).streams
                a += try await sourceTimelineAudio(source:outro,intervals:[Interval(0,branding.outroDuration)],channels:channels,work:work)
            }
            _ = try await Processes.run("ffmpeg",["-nostdin","-v","error","-i",output.path,"-vn","-ac",String(channels),"-ar","12000","-f","f32le","-"],output:actualPCM)
            let b = try AudioPresentation.samples(actualPCM)
            checks["audio_fidelity_sync"] = "Independent source-PTS oracle; "+(try validateAudioSamples(a,b,channels:channels,duration:outputDuration))
        }
        if source.kind == .nativeVideo {
            let expected = work.appendingPathComponent("expected-picture.gray")
            var filter = compositionFilter(source,clip,outputProfile,branding:branding)
            if source.hasAudio { filter += ";[a]anullsink" }
            filter += ";[v]fps=2,scale=160:284,format=gray[q]"
            _ = try await Processes.run("ffmpeg",["-nostdin","-v","error"]+compositionInputs(source:source,clip:clip,branding:branding)+["-filter_complex",filter,"-map","[q]","-t",String(outputDuration),"-f","rawvideo","-"],output:expected)
            let actual = work.appendingPathComponent("actual-picture.gray")
            _ = try await Processes.run("ffmpeg",["-nostdin","-v","error","-i",output.path,"-vf","fps=2,scale=160:284,format=gray","-an","-f","rawvideo","-"],output:actual)
            let a = try Data(contentsOf:expected,options:.mappedIfSafe), b = try Data(contentsOf:actual,options:.mappedIfSafe)
            guard !a.isEmpty, abs(a.count-b.count) <= 160*284 else { throw JoeyError.failed("Picture sample coverage mismatch") }
            let mean = zip(a,b).reduce(0.0) {$0+abs(Double($1.0)-Double($1.1))}/Double(min(a.count,b.count))
            guard mean <= 6 else { throw JoeyError.failed("Source-only picture fidelity failed: mean pixel error \(mean)") }
            checks["picture_fidelity"] = "2fps whole-frame 160x284 grayscale comparison; mean pixel error \(mean)/255; includes padding and source graphics"
            checks["source_picture_timeline"] = try await validateSourcePictureTiming(output:output,source:source,clip:clip,profile:outputProfile,render:render)
            checks["unrequested_additions"] = branding == nil ? "Source-only render recipe and whole-frame comparison; no added artwork, captions, logos or outro" : "Only hash-pinned DUB logo at x34 y866 size180×180, plus the full approved 7.300-second outro; whole-composition picture and audio comparison passed"
            if let branding {
                checks["approved_logo"] = JoeBranding.logoID+" SHA-256 "+branding.logo.sha256
                checks["approved_outro"] = JoeBranding.outroID+" SHA-256 "+branding.outro.sha256+"; full video ending and silent tail preserved"
            }
        } else {
            guard let background = render.background, let waveform = render.waveform, let pcm = render.waveformPCM else { throw JoeyError.failed("Audio presentation evidence absent") }
            let decoded = work.appendingPathComponent("qa-wave.f32")
            _ = try await Processes.run("ffmpeg",["-nostdin","-v","error","-i",output.path,"-vn","-ac","1","-ar","48000","-f","f32le","-"],output:decoded)
            let expectedSamples = try AudioPresentation.samples(URL(fileURLWithPath:pcm)), finalSamples = try AudioPresentation.samples(decoded)
            guard abs(expectedSamples.count-finalSamples.count) <= 3600 else { throw JoeyError.failed("Waveform/final audio mismatch") }
            let wave = AudioPresentation.envelope(samples:finalSamples,sampleRate:48000)
            guard zip(wave.levels,waveform.levels).allSatisfy({abs($0-$1) < 0.05}) else { throw JoeyError.failed("Waveform response does not match final audio") }
            checks["waveform"] = "Fixed 120 horizontal positions, vertical source-PCM amplitude; decoded final audio envelope matched within 0.05; PCM SHA256 \(try Integrity.sha256(URL(fileURLWithPath:pcm)))"
            let box = AudioPresentation.waveBox(owner:source.owner,width:outputProfile.width)
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
