import Foundation

public enum Acquisition {
    static func metadataArguments(for url: URL) -> [String] {
        ["--ignore-config","--no-playlist","--skip-download","--dump-single-json",url.absoluteString]
    }
    static func downloadArguments(for url: URL, directory: URL) -> [String] {
        ["--ignore-config","--no-playlist","--continue","--no-overwrites","--retries","3","--fragment-retries","3",
         "--abort-on-unavailable-fragments","--write-info-json","--merge-output-format","mp4","-o",directory.appendingPathComponent("original.%(ext)s").path,url.absoluteString]
    }
    static func sourceMetadata(_ data: Data, request: JobRequest,
                               loadPlaylist: (URL) async throws -> Data = {try await ReplayPlaylist.load($0)}) async throws -> DiscoveredSource {
        guard let raw = request.originalURL, let identity = SourceIdentitySuggestion.from(raw),
              let id = identity.split(separator:":").last,
              request.sourceID == String(id) || request.sourceID.hasSuffix("-"+id) || request.sourceID.hasSuffix(":"+id) else {
            throw JoeyError.invalid("Original identity mismatch")
        }
        return try await SourceDiscovery.parseSource(data,url:raw,loadPlaylist:loadPlaylist)
    }
    static func validateDownloadedDuration(_ measured: Double, expected: Double) throws {
        guard measured.isFinite, expected.isFinite, measured > 0, expected > 0,
              abs(measured-expected) <= max(1,expected*0.001) else {
            throw JoeyError.failed("Incomplete original: measured \(measured), expected \(expected)")
        }
    }
    public static func validateOriginalURL(_ raw: String) throws -> URL {
        guard let u = URL(string:raw), u.scheme == "https", u.user == nil, u.password == nil,
              u.port == nil || u.port == 443,
              let host = u.host?.lowercased(), ["youtube.com","www.youtube.com","youtu.be","x.com","www.x.com","twitter.com"].contains(host) else {
            throw JoeyError.invalid("Paste an original YouTube or X HTTPS link")
        }
        if host.contains("x.com") || host == "twitter.com" {
            guard u.path.contains("/broadcasts/") || u.path.contains("/spaces/") || u.path.contains("/status/") else {
                throw JoeyError.invalid("X source must identify the original broadcast, Space or post")
            }
        }
        return u
    }
    public static func acquire(_ request: JobRequest, directory: URL) async throws -> URL {
        if let path = request.localPath {
            let url = URL(fileURLWithPath:(path as NSString).expandingTildeInPath).standardizedFileURL
            guard FileManager.default.fileExists(atPath:url.path), !url.lastPathComponent.hasSuffix(".part") else { throw JoeyError.dependency("Complete local original unavailable: \(url.path)") }
            return url
        }
        guard let raw = request.originalURL else { throw JoeyError.dependency("No original source") }
        let url = try validateOriginalURL(raw)
        let metadataURL = directory.appendingPathComponent("acquisition.json")
        let metadata = try await Processes.retry {
            try await Processes.run("yt-dlp",metadataArguments(for:url))
        }
        let expected = try await sourceMetadata(metadata.stdout,request:request).duration
        try metadata.stdout.write(to: metadataURL, options:.atomic)
        try Persistence.checkDisk(at:directory,requiredBytes:Int64(expected*1_500_000))
        _ = try await Processes.retry {
            try await Processes.run("yt-dlp",downloadArguments(for:url,directory:directory))
        }
        let files = try FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil)
            .filter { $0.deletingPathExtension().lastPathComponent == "original" && ["mp4","mkv","webm","m4a","mp3","opus"].contains($0.pathExtension) }
        guard files.count == 1 else { throw JoeyError.failed("Acquisition did not produce one complete original") }
        let probe = try await Media.probe(files[0])
        try validateDownloadedDuration(probe.duration,expected:expected)
        return files[0]
    }
    public static func transcript(source: SourceRecord, request: JobRequest, configuration: Configuration, directory: URL) async throws -> Transcript? {
        let canonical = directory.appendingPathComponent("transcript.json")
        if FileManager.default.fileExists(atPath:canonical.path) {
            let old: Transcript = try Persistence.load(canonical)
            try old.validate(sourceID:source.id,sha256:source.sha256,duration:source.duration)
            return old
        }
        var input: URL
        if let provided = request.transcriptPath { input = URL(fileURLWithPath:provided) }
        else {
            // A missing optional transcript is not permission to invoke ASR.
            // Malformed/mismatched supplied or cached transcripts still fail.
            if request.transcriptPolicy == .modelIndependent {return nil}
            guard let python = configuration.pythonPath, let script = configuration.transcriptionScript,
                  let model = configuration.modelPath else { throw JoeyError.dependency("Local transcript unavailable: configure existing Python ASR helper and installed model, or supply source-bound full transcript") }
            input = directory.appendingPathComponent("asr-source.json")
            _ = try await Processes.run(python,[script,"--source",source.path,"--source-id",source.id,"--output",input.path,"--model-dir",model,"--cpu-threads","2"])
        }
        let data = try Data(contentsOf:input)
        let value: Transcript
        if let typed = try? Persistence.decoder.decode(Transcript.self,from:data) { value = typed }
        else {
            guard let obj = try JSONSerialization.jsonObject(with:data) as? [String:Any],
                  obj["source_id"] as? String == source.id, obj["source_sha256"] as? String == source.sha256,
                  let segments = obj["segments"] as? [[String:Any]],
                  let engine = obj["model"] as? String else { throw JoeyError.invalid("Imported transcript lacks exact source ID/hash or ASR provenance") }
            let parts = try segments.map { s -> TranscriptSegment in
                guard let start = (s["start_seconds"] ?? s["start"]) as? Double,
                      let end = (s["end_seconds"] ?? s["end"]) as? Double, let text = s["text"] as? String else { throw JoeyError.invalid("Malformed transcript segment") }
                return TranscriptSegment(start:start,end:end,text:text)
            }
            value = Transcript(sourceID:source.id,sourceSHA256:source.sha256,duration:source.duration,engine:engine,segments:parts)
        }
        try value.validate(sourceID:source.id,sha256:source.sha256,duration:source.duration)
        try Persistence.save(value,to:canonical)
        return value
    }
}
