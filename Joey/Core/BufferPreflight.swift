import Foundation
import CryptoKit

public struct MediaURLVerification: Codable, Sendable {
    public var checkedAt: Date
    public var validUntil: Date
    public var method: String
    public var contentType: String
    public var bytesVerified: Int64
    public var fullFileSHA256: String?
    public var totalBytes: Int64
    public var ranges: [String]
    public var rangeSHA256: [String]
    public var finalURLs: [String]
}

public struct BufferMediaPreflight: Codable, Sendable {
    public var checkedAt: Date
    public var validUntil: Date
    public var sha256: String
    public var bytes: Int64
    public var duration: Double
    public var width: Int
    public var height: Int
    public var fps: Double
    public var videoCodec: String
    public var audioCodec: String?
    public var pixelFormat: String
    public var videoBitrate: Int
    public var audioBitrate: Int
    public var driveID: String
    public var driveURL: String
    public var directURL: String
    public var technicalChecks: [String:String]
    public var urlEvidence: MediaURLVerification
    public var capabilityEvidence: SharedProfile
    public var warnings: [String]
}

/// Read-only distribution checks. This component has no Buffer write or Drive
/// permission mutation path, and never repairs or replaces accepted media.
public enum BufferPreflight {
    static let maximumRangeBytes = 64 * 1024

    public static func check(job: JobRecord, clip: ClipRecord, root: URL, profile: SharedProfile) async throws -> BufferMediaPreflight {
        try validateProfile(profile,owner:job.request.owner,workflow:job.request.productionWorkflow)
        let source = try validateJob(job,clip:clip)
        let output = try acceptedFile(root:root,jobID:job.id,filename:clip.filename)
        let bytes = try size(output), sha = try Integrity.sha256(output)
        guard bytes == clip.bytes, sha == clip.sha256, sha == clip.qa?.outputSHA256,
              bytes == clip.drive?.bytes, sha == clip.drive?.sha256 else {
            throw JoeyError.failed("Buffer preflight: accepted file, QA and Drive receipt identities disagree")
        }
        let outputProfile = try profile.outputProfile(for:source.kind)
        let (probe,mediaChecks) = try await inspectMedia(output,expectedDuration:clip.expectedDuration,hasAudio:source.hasAudio,profile:outputProfile)
        var checks = mediaChecks
        checks["production_qa"] = "Accepted QA output SHA-256 matches current complete local file"
        checks["audio_video_synchronization"] = source.hasAudio
            ? "Current stream timing passed; original source-fidelity/synchronization QA reused, bound to unchanged output SHA-256: \(clip.qa!.checks["audio_fidelity_sync"]!)"
            : "Source and output have no audio stream"
        checks["authorization"] = source.authorizationBasis
        // Read existing settings directly: preflight must not discover helpers,
        // canonicalize configuration or write settings during a production run.
        let configuration: Configuration = try Persistence.load(root.appendingPathComponent("settings.json"))
        let drive = try DriveDelivery(remote:configuration.rcloneRemote)
        let receipt = clip.drive!
        async let file = drive.metadata(receipt.id)
        async let folder = drive.metadata(job.folderID!)
        let metadata = try await file, folderMetadata = try await folder
        try validateDrive(file:metadata,folder:folderMetadata,source:source,request:job.request,clip:clip,folderID:job.folderID!,md5:try Integrity.md5(output))
        _ = try await drive.verifyLocation(parent:job.folderID!,destination:DestinationResolver.resolve(source:source,request:job.request,asset:.clip))
        let matches = try await drive.children(job.folderID!).filter { $0["name"] as? String == clip.filename }
        guard matches.count == 1, matches[0]["id"] as? String == receipt.id else {
            throw JoeyError.dependency("Buffer preflight: duplicate or missing Drive output requires reconciliation")
        }
        checks["drive"] = "Current ID, name, parent, source/owner folder, bytes, MD5, existing permissions and duplicate readback passed"
        var direct = URLComponents(string:"https://drive.google.com/uc")!
        direct.queryItems = [URLQueryItem(name:"export",value:"download"),URLQueryItem(name:"id",value:receipt.id)]
        let url = direct.url!
        let urlEvidence = try await verifyMediaURL(url,local:output,totalBytes:bytes)
        // Expiry or mutation during network/decode work invalidates the result.
        try validateProfile(profile,owner:source.owner,workflow:job.request.productionWorkflow)
        guard try Integrity.sha256(output) == sha else {throw JoeyError.failed("Buffer preflight: accepted output changed during verification")}
        let now = Date(), validUntil = min(urlEvidence.validUntil,min(profile.x!.validUntil,profile.instagram!.validUntil))
        guard validUntil > now else {throw JoeyError.dependency("Buffer preflight evidence expired during verification")}
        return BufferMediaPreflight(checkedAt:now,validUntil:validUntil,sha256:sha,bytes:bytes,duration:probe.duration,
            width:probe.video!.width!,height:probe.video!.height!,fps:probe.video!.fps,videoCodec:probe.video!.codec_name!,
            audioCodec:probe.audio?.codec_name,pixelFormat:probe.video!.pix_fmt!,videoBitrate:Int(probe.video!.bit_rate!)!,
            audioBitrate:Int(probe.audio?.bit_rate ?? "0") ?? 0,driveID:receipt.id,
            driveURL:"https://drive.google.com/file/d/\(receipt.id)/view",directURL:url.absoluteString,technicalChecks:checks,
            urlEvidence:urlEvidence,capabilityEvidence:profile,warnings:[
                "GPT must recheck anonymous URL availability, current accounts and capabilities immediately before any separately authorized submission.",
                "Anonymous byte-range checks establish sampled identity, not a complete remote SHA-256 comparison.",
                "No scheduled-publication URL lifetime is established. Block scheduling unless retrieval suitability until publication is separately verified.",
                "Technical readiness does not establish Buffer ingestion or platform publication."
            ])
    }

    static func validateProfile(_ profile: SharedProfile, owner: Owner, workflow: ProductionWorkflow?, now: Date = Date()) throws {
        guard workflow != .joeBudden, profile.driveOnlyJoe != true else {
            throw JoeyError.dependency("Joe Budden is Drive-only; an explicit authorized social destination mapping is required")
        }
        try profile.validate(now:now)
        func handle(_ value: String) -> String {value.trimmingCharacters(in:.whitespacesAndNewlines).trimmingCharacters(in:CharacterSet(charactersIn:"@")).lowercased()}
        let accounts = owner == .dub ? ("dubwiththefiles","dubwiththefiles") : ("jailcallwithtax","thejailcallwithtaxstone")
        guard let x = profile.x, let ig = profile.instagram,
              handle(x.account) == accounts.0, handle(ig.account) == accounts.1 else {
            throw JoeyError.dependency("Buffer preflight: current account capability does not match the content owner")
        }
        for capability in [x,ig] {
            guard capability.surface.lowercased().contains("buffer"),
                  capability.officialURLs.contains(where:{URL(string:$0)?.host == "support.buffer.com"}) else {
                throw JoeyError.dependency("Buffer preflight requires current Buffer upload-surface evidence for \(capability.platform)")
            }
        }
    }

    static func validateJob(_ job: JobRecord, clip: ClipRecord) throws -> SourceRecord {
        guard job.state == .completed, job.hasRequiredCompletionEvidence, let source = job.source, let transcript = job.transcript,
              job.unavailableTranscriptFeatures.isEmpty,
              source.id == job.request.sourceID, source.owner == job.request.owner,
              !source.authorizationBasis.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,
              !job.request.authorizationBasis.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,
              !job.clips.isEmpty, job.clips.filter({$0.id == clip.id}).count == 1,
              job.clips.first(where:{$0.id == clip.id}) == clip,
              let folder = job.folderID, validDriveID(folder), let receipt = clip.drive,
              validDriveID(receipt.id), receipt.parent == folder, receipt.name == clip.filename,
              let qa = clip.qa, qa.passed, !qa.outputSHA256.isEmpty,
              clip.error == nil, clip.failureStage == nil,
              job.clips.allSatisfy({$0.qa?.passed == true && $0.drive != nil}),
              job.companions["clip_manifest.json"] != nil, job.companions["RECONCILE.md"] != nil,
              job.companions.keys.contains(where:{$0.hasPrefix("Clip Index") && $0.hasSuffix(".csv")}),
              job.companions.keys.contains(where:{$0.hasSuffix(" — Full Transcript.txt")}),
              job.request.owner != .dub || job.registerRows.count == job.clips.count else {
            throw JoeyError.dependency("Buffer preparation requires a completed, transcript-assisted job with accepted QA, filing and required companion/register receipts")
        }
        try transcript.validate(sourceID:source.id,sha256:source.sha256,duration:source.duration)
        guard !clip.intervals.isEmpty, clip.intervals.allSatisfy({$0.start.isFinite && $0.end.isFinite && $0.start >= 0 && $0.end > $0.start && $0.end <= source.duration + 0.075}),
              zip(clip.intervals,clip.intervals.dropFirst()).allSatisfy({$0.end <= $1.start}),
              !source.hasAudio || qa.checks["audio_fidelity_sync"]?.isEmpty == false else {
            throw JoeyError.dependency("Buffer preflight: missing valid source intervals or hash-bound source audio/synchronization QA")
        }
        return source
    }

    static func validateTechnical(_ p: MediaProbe, bytes: Int64, expectedDuration: Double, hasAudio: Bool, profile: SharedProfile) throws -> [String:String] {
        guard p.format.format_name?.split(separator:",").contains("mp4") == true else {throw JoeyError.failed("Buffer preflight: container is not MP4")}
        guard let v = p.video, v.codec_name == "h264", v.pix_fmt == "yuv420p",
              v.field_order == "progressive", v.sample_aspect_ratio == "1:1",
              v.width == profile.width, v.height == profile.height, abs(v.fps-30) < 0.001 else {
            throw JoeyError.failed("Buffer preflight: requires H.264/yuv420p/progressive/square pixels/30 fps and selected shared portrait dimensions")
        }
        let policy = DurationPolicy(profile:profile)
        try policy.validateMeasured(p.duration,expected:expectedDuration)
        let ceiling = policy.measuredMaximum
        guard bytes > 0, bytes <= profile.maxBytes, Int64(p.format.size ?? "") == bytes else {throw JoeyError.failed("Buffer preflight: measured file size exceeds current common capability or probe identity differs")}
        guard let videoRate = Int(v.bit_rate ?? ""), videoRate > 0, videoRate < Media.maximumVideoBitrate else {throw JoeyError.failed("Buffer preflight: video bitrate must be measured and below 25000000 bps")}
        guard p.streams.count == (hasAudio ? 2:1), p.streams.filter({$0.codec_type == "video"}).count == 1,
              p.streams.filter({$0.codec_type == "audio"}).count == (hasAudio ? 1:0) else {throw JoeyError.failed("Buffer preflight: unexpected or missing media streams")}
        if hasAudio {
            guard let a = p.audio, a.codec_name == "aac", a.profile == "LC", a.sample_rate == "48000",
                  let channels = a.channels, (1...2).contains(channels), let rate = Int(a.bit_rate ?? ""), rate > 0, rate < Media.maximumAudioBitrate else {
                throw JoeyError.failed("Buffer preflight: audio requires AAC-LC/48 kHz, one or two channels, measured bitrate below 128000 bps")
            }
            guard let vs = Double(v.start_time ?? ""), let audioStart = Double(a.start_time ?? ""),
                  let vd = Double(v.duration ?? ""), let ad = Double(a.duration ?? ""),
                  [vs,audioStart,vd,ad].allSatisfy(\.isFinite), abs(vs-audioStart) <= 0.075, abs(vd-ad) <= 0.075 else {
                throw JoeyError.failed("Buffer preflight: measured audio/video start or duration synchronization differs")
            }
        }
        return ["container":"MP4","video":"H.264/yuv420p/progressive/SAR 1:1/30 fps; measured \(videoRate) bps",
            "dimensions":"\(profile.width)×\(profile.height)","duration":"Measured \(p.duration)s; current common ceiling \(ceiling)s including 0.1s margin",
            "size":"Measured \(bytes) bytes; current shared maximum \(profile.maxBytes)",
            "audio":hasAudio ? "AAC-LC/48 kHz; measured \(p.audio!.bit_rate!) bps; stream timing within 0.075s" : "No source or output audio"]
    }

    static func inspectMedia(_ output: URL, expectedDuration: Double, hasAudio: Bool, profile: SharedProfile) async throws -> (MediaProbe,[String:String]) {
        let probe = try await Media.probe(output)
        var checks = try validateTechnical(probe,bytes:size(output),expectedDuration:expectedDuration,hasAudio:hasAudio,profile:profile)
        // ffprobe's format name is shared by MOV and MP4. Check the actual
        // top-level ftyp brand and faststart boxes before claiming MP4 delivery.
        let handle = try FileHandle(forReadingFrom:output); defer {try? handle.close()}
        let header = try handle.read(upToCount:4*1024*1024) ?? Data()
        var offset = 0, foundBrand = false, foundMoov = false, foundMedia = false
        while offset + 8 <= header.count {
            let count = header[offset..<offset+4].reduce(UInt64(0)) {($0 << 8) | UInt64($1)}
            let type = String(decoding:header[offset+4..<offset+8],as:UTF8.self)
            var length = count, boxHeader = 8
            if count == 1 {
                guard offset + 16 <= header.count else {break}
                length = header[offset+8..<offset+16].reduce(UInt64(0)) {($0 << 8) | UInt64($1)}
                boxHeader = 16
            }
            if type == "mdat" {foundMedia = foundMoov; break}
            guard length >= UInt64(boxHeader), length <= UInt64(header.count - offset) else {break}
            if type == "ftyp", length >= UInt64(boxHeader + 8) {
                let brand = String(decoding:header[offset+boxHeader..<offset+boxHeader+4],as:UTF8.self)
                foundBrand = ["isom","iso2","iso3","iso4","iso5","iso6","mp41","mp42","avc1","M4V "].contains(brand)
            }
            if type == "moov" {foundMoov = true}
            offset += Int(length)
        }
        guard foundBrand, foundMedia else {throw JoeyError.failed("Buffer preflight: MP4 brand or bounded faststart metadata before media could not be verified")}
        try await Media.decode(output)
        checks["container"] = "MP4 ftyp brand and moov before mdat verified from current bytes"
        checks["complete_decode"] = "Current complete FFmpeg decode with error escalation passed"
        return (probe,checks)
    }

    static func validateDrive(file: [String:Any], folder: [String:Any], source: SourceRecord, request: JobRequest, clip: ClipRecord, folderID: String, md5: String) throws {
        let destination = try DestinationResolver.resolve(source:source,request:request,asset:.clip)
        guard let receipt = clip.drive, file["id"] as? String == receipt.id, file["name"] as? String == clip.filename,
              file["mimeType"] as? String == "video/mp4", file["trashed"] as? Bool == false,
              file["parents"] as? [String] == [folderID], Int64(file["size"] as? String ?? "") == clip.bytes,
              file["md5Checksum"] as? String == md5, receipt.md5 == md5,
              (file["sha256Checksum"] as? String).map({$0 == clip.sha256}) ?? true,
              folder["id"] as? String == folderID, folder["trashed"] as? Bool == false,
              folder["mimeType"] as? String == "application/vnd.google-apps.folder",
              folder["parents"] as? [String] == [destination.rootID],
              let properties = folder["appProperties"] as? [String:String], properties["joeySourceID"] == source.id,
              properties["joeyOwner"] == source.owner.rawValue,
              let permissions = file["permissions"] as? [[String:Any]], !permissions.isEmpty else {
            throw JoeyError.dependency("Buffer preflight: current Drive identity, integrity, placement or source/owner metadata does not match the accepted receipt")
        }
        let current = permissions.map {"\($0["type"] as? String ?? "unknown"):\($0["role"] as? String ?? "unknown")"}.sorted()
        guard current == receipt.permissions.sorted(), let fingerprint = receipt.permissionFingerprint,
              try DriveDelivery.permissionFingerprint(file) == fingerprint else {
            throw JoeyError.dependency("Buffer preflight: Drive access changed or lacks accepted permission evidence; reconcile existing permissions without expanding sharing")
        }
    }

    static func validDriveID(_ value: String) -> Bool {value.range(of:"^[A-Za-z0-9_-]{10,}$",options:.regularExpression) != nil}
    static func acceptedFile(root: URL, jobID: String, filename: String) throws -> URL {
        guard [jobID,filename].allSatisfy({!$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("/") && !$0.contains("\\") && !$0.contains("\0")}), filename.lowercased().hasSuffix(".mp4") else {throw JoeyError.invalid("Buffer preflight: unsafe job or output path")}
        let base = root.standardizedFileURL.resolvingSymlinksInPath()
        let file = base.appendingPathComponent("jobs").appendingPathComponent(jobID).appendingPathComponent(filename)
        guard file.resolvingSymlinksInPath().standardizedFileURL.path == file.path,
              (try file.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey])).isRegularFile == true,
              (try file.resourceValues(forKeys:[.isSymbolicLinkKey])).isSymbolicLink != true else {throw JoeyError.invalid("Buffer preflight: accepted output is not a regular owned file or traverses a symlink")}
        return file
    }
    private static func size(_ url: URL) throws -> Int64 {((try FileManager.default.attributesOfItem(atPath:url.path))[.size] as? NSNumber)?.int64Value ?? 0}

    static func allowedMediaURL(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil, url.port == nil || url.port == 443,
              let host = url.host?.lowercased() else {return false}
        return ["drive.google.com","drive.usercontent.google.com"].contains(host)
            || host.range(of:"^doc-[a-z0-9-]+-docs\\.googleusercontent\\.com$",options:.regularExpression) != nil
    }

    static func validateRange(response: HTTPURLResponse, data: Data, expected: Data, start: Int64, total: Int64) throws {
        guard let url = response.url, allowedMediaURL(url) else {throw JoeyError.dependency("Anonymous Drive media URL resolved to an unsafe endpoint")}
        let type = response.value(forHTTPHeaderField:"Content-Type")?.split(separator:";").first?.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()
        guard ["video/mp4","application/octet-stream"].contains(type ?? "") else {throw JoeyError.dependency("Anonymous Drive download returned non-media content or an authentication/virus-scan page")}
        guard response.value(forHTTPHeaderField:"Content-Encoding").map({$0 == "identity"}) ?? true else {throw JoeyError.dependency("Anonymous media response used unsupported content encoding")}
        if response.statusCode == 206 {
            guard response.value(forHTTPHeaderField:"Content-Range") == "bytes \(start)-\(start + Int64(expected.count) - 1)/\(total)" else {throw JoeyError.dependency("Anonymous media Content-Range does not match accepted file length and requested interval")}
        } else {
            guard response.statusCode == 200, start == 0, total == Int64(expected.count) else {throw JoeyError.dependency("Anonymous media HTTP \(response.statusCode); server did not provide the bounded requested range")}
        }
        if let length = response.value(forHTTPHeaderField:"Content-Length"), Int64(length) != Int64(expected.count) {throw JoeyError.dependency("Anonymous media Content-Length differs from requested range")}
        guard !expected.isEmpty, data == expected else {throw JoeyError.failed("Anonymous Drive media bytes differ from the accepted local output or are incomplete")}
    }

    static func verifyMediaURL(_ url: URL, local: URL, totalBytes: Int64, configuration: URLSessionConfiguration = .ephemeral) async throws -> MediaURLVerification {
        guard allowedMediaURL(url), totalBytes > 0 else {throw JoeyError.invalid("Unsafe or empty direct media reference")}
        let file = try FileHandle(forReadingFrom:local); defer {try? file.close()}
        let count = min(Int64(maximumRangeBytes),totalBytes)
        let starts: [Int64] = totalBytes <= count ? [0] : [0,max(count,totalBytes-count)]
        var verified: Int64 = 0, ranges: [String] = [], hashes: [String] = [], finals: [String] = [], contentType = ""
        for start in starts {
            try Task.checkCancellation()
            let length = Int(min(count,totalBytes-start))
            try file.seek(toOffset:UInt64(start))
            let expected = try file.read(upToCount:length) ?? Data()
            guard expected.count == length else {throw JoeyError.failed("Accepted output became incomplete during URL verification")}
            let range = "bytes=\(start)-\(start+Int64(length)-1)"
            configuration.httpCookieStorage = nil; configuration.httpShouldSetCookies = false
            configuration.urlCredentialStorage = nil; configuration.urlCache = nil
            configuration.connectionProxyDictionary = [:]
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.timeoutIntervalForRequest = 30; configuration.timeoutIntervalForResource = 60
            let session = URLSession(configuration:configuration)
            defer {session.invalidateAndCancel()}
            let delegate = AnonymousMediaRedirects(range:range)
            var request = URLRequest(url:url)
            request.setValue(range,forHTTPHeaderField:"Range")
            request.setValue("video/mp4, application/octet-stream",forHTTPHeaderField:"Accept")
            request.setValue("identity",forHTTPHeaderField:"Accept-Encoding")
            let (stream,response) = try await session.bytes(for:request,delegate:delegate)
            guard let http = response as? HTTPURLResponse else {throw JoeyError.dependency("Anonymous media response was not HTTP")}
            if let reason = delegate.failure {throw JoeyError.dependency(reason)}
            // Validate headers before consuming bytes, then enforce a hard body
            // bound even when a server omits or lies about Content-Length.
            try validateRange(response:http,data:expected,expected:expected,start:start,total:totalBytes)
            var data = Data(); data.reserveCapacity(length)
            for try await byte in stream {
                try Task.checkCancellation()
                guard data.count < length else {throw JoeyError.dependency("Anonymous media server exceeded the bounded requested range")}
                data.append(byte)
            }
            try validateRange(response:http,data:data,expected:expected,start:start,total:totalBytes)
            verified += Int64(data.count); ranges.append(range)
            hashes.append(SHA256.hash(data:data).map {String(format:"%02x",$0)}.joined())
            finals.append(http.url!.absoluteString)
            contentType = http.value(forHTTPHeaderField:"Content-Type") ?? ""
        }
        let now = Date()
        return MediaURLVerification(checkedAt:now,validUntil:now.addingTimeInterval(15*60),
            method:"Anonymous HTTPS GET with bounded byte ranges, no cookies/credentials/proxy; exact range-byte comparison to accepted local media",
            contentType:contentType,bytesVerified:verified,fullFileSHA256:nil,totalBytes:totalBytes,ranges:ranges,rangeSHA256:hashes,finalURLs:finals)
    }
}

private final class AnonymousMediaRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var redirects = 0
    private var rejection: String?
    private let range: String
    init(range: String) {self.range = range}
    var failure: String? {lock.lock(); defer {lock.unlock()}; return rejection}
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        lock.lock()
        redirects += 1
        guard redirects <= 5, let url = request.url, BufferPreflight.allowedMediaURL(url) else {
            rejection = "Anonymous media redirect rejected: unexpected host, insecure URL or more than five redirects"
            lock.unlock(); completionHandler(nil); return
        }
        lock.unlock()
        // Rebuild instead of carrying server-provided authorization/cookie headers.
        var clean = URLRequest(url:url)
        clean.setValue(range,forHTTPHeaderField:"Range")
        clean.setValue("video/mp4, application/octet-stream",forHTTPHeaderField:"Accept")
        clean.setValue("identity",forHTTPHeaderField:"Accept-Encoding")
        completionHandler(clean)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            completionHandler(.performDefaultHandling,nil)
        } else {completionHandler(.cancelAuthenticationChallenge,nil)}
    }
}
