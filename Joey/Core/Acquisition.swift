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
    /// A downloader can finish before the Coordinator's full source inspection
    /// is checkpointed. Reuse only its source-bound canonical file; inspection,
    /// source hashing and classification still run in the Coordinator.
    static func completedOriginal(_ request: JobRequest, directory: URL) async throws -> URL? {
        let files = try FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil)
            .filter { $0.deletingPathExtension().lastPathComponent == "original" && ["mp4","mkv","webm","m4a","mp3","opus"].contains($0.pathExtension) }
        // Partial-only downloads retain the normal guarded --continue path.
        guard !files.isEmpty else {return nil}
        guard files.count == 1 else {throw JoeyError.failed("Multiple canonical originals exist; all files preserved. Reconcile the source files before retrying.")}
        let original = files[0]
        do {
            try Task.checkCancellation()
            try StorageManager.noLinks(original)
            let attributes = try FileManager.default.attributesOfItem(atPath:original.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  (attributes[.size] as? NSNumber)?.int64Value ?? 0 > 0 else {
                throw JoeyError.invalid("Canonical original is not a nonempty regular file")
            }
            guard let raw = request.originalURL, let identity = SourceIdentitySuggestion.from(try validateOriginalURL(raw).absoluteString) else {
                throw JoeyError.invalid("Original source identity is unavailable")
            }
            var expected: [Double] = []
            if let duration = request.expectedDuration {
                guard duration.isFinite,duration > 0,duration < 1_000_000 else {throw JoeyError.invalid("Invalid expected original duration")}
                expected.append(duration)
            }
            var retained: [Data] = []
            for name in ["acquisition.json","original.info.json"] {
                let path = directory.appendingPathComponent(name)
                guard FileManager.default.fileExists(atPath:path.path) else {
                    throw JoeyError.dependency("Acquisition metadata \(name) is missing; restore the matching source metadata")
                }
                try StorageManager.noLinks(path)
                let data = try Data(contentsOf:path)
                guard let object = try? JSONSerialization.jsonObject(with:data) as? [String:Any] else {
                    throw JoeyError.invalid("Acquisition metadata \(name) is malformed")
                }
                guard let id = object["id"] as? String,identity.hasSuffix(":"+id),
                      request.sourceID == id || request.sourceID.hasSuffix("-"+id) || request.sourceID.hasSuffix(":"+id),
                      let title = object["title"] as? String,!title.isEmpty,
                      object["is_live"] as? Bool != true,
                      !["is_live","is_upcoming","post_live"].contains(object["live_status"] as? String ?? "") else {
                    throw JoeyError.invalid("Acquisition metadata \(name) has conflicting or unfinished source identity")
                }
                var recordedURLs = 0
                for key in ["original_url","webpage_url"] where object[key] != nil && !(object[key] is NSNull) {
                    guard let value = object[key] as? String,let url = try? validateOriginalURL(value),
                          SourceIdentitySuggestion.from(url.absoluteString) == identity else {
                        throw JoeyError.invalid("Acquisition metadata \(name) has a conflicting source URL")
                    }
                    recordedURLs += 1
                }
                guard recordedURLs > 0 else {throw JoeyError.invalid("Acquisition metadata \(name) lacks source URL evidence")}
                if object["duration"] == nil || object["duration"] is NSNull {
                    guard identity.hasPrefix("x:broadcast:") || identity.hasPrefix("x:space:"),
                          object["is_live"] as? Bool == false,object["live_status"] as? String == "was_live" else {
                        throw JoeyError.invalid("Acquisition metadata \(name) lacks an authoritative complete duration")
                    }
                } else {
                    // The existing parser validates provider duration types,
                    // identity and completion without using the measured file.
                    expected.append(try await sourceMetadata(data,request:request).duration)
                }
                retained.append(data)
            }
            if expected.isEmpty {
                // Legacy X requests without a saved duration still require the
                // existing authoritative ended-replay parser, never self-proof.
                expected.append(try await sourceMetadata(retained[0],request:request).duration)
            }
            let probe = try await Media.probe(original)
            if ["mp4","m4a"].contains(original.pathExtension),probe.format.format_name?.split(separator:",").contains("mpegts") == true {
                throw JoeyError.failed("Original has an unfinished MPEG-TS remux; reconcile acquisition before retrying")
            }
            for duration in expected {try validateDownloadedDuration(probe.duration,expected:duration)}
            return original
        } catch {
            if error is CancellationError {throw error}
            throw JoeyError.failed("Existing original preserved; completed-download reuse failed: "+error.localizedDescription)
        }
    }
    public static func acquire(_ request: JobRequest, directory: URL) async throws -> URL {
        if let path = request.localPath {
            let url = URL(fileURLWithPath:(path as NSString).expandingTildeInPath).standardizedFileURL
            guard FileManager.default.fileExists(atPath:url.path), !url.lastPathComponent.hasSuffix(".part") else { throw JoeyError.dependency("Complete local original unavailable: \(url.path)") }
            return url
        }
        guard let raw = request.originalURL else { throw JoeyError.dependency("No original source") }
        let url = try validateOriginalURL(raw)
        if let original = try await completedOriginal(request,directory:directory) {return original}
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
        let repairReceipt = directory.appendingPathComponent("transcript-repair.json")
        if FileManager.default.fileExists(atPath: repairReceipt.path) {
            let proof: TranscriptTailRepair = try Persistence.load(repairReceipt)
            // A failed attempt does not own an explicitly supplied correction.
            // Accepted repaired transcripts still require their complete proof.
            if proof.transcriptSHA256 != nil || request.transcriptPath == nil {
                try validateTailRepair(proof, source: source, directory: directory)
            }
        }
        if FileManager.default.fileExists(atPath:canonical.path) {
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent("transcript-repair").path),
               !FileManager.default.fileExists(atPath: repairReceipt.path), request.transcriptPath == nil {
                throw JoeyError.invalid("Transcript tail repair receipt is missing; canonical transcript and retained repair files preserved")
            }
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
            input = directory.appendingPathComponent("asr-source.json")
            if !FileManager.default.fileExists(atPath: input.path) {
                let (python, script, model) = try transcriptionTools(configuration)
                _ = try await Processes.run(python,[script,"--source",source.path,"--source-id",source.id,"--output",input.path,"--model-dir",model,"--cpu-threads","2"])
            }
        }
        let data = try Data(contentsOf:input)
        var value = try decodeTranscript(data, source: source)
        do { try value.validate(sourceID:source.id,sha256:source.sha256,duration:source.duration) }
        catch {
            guard request.transcriptPath == nil else { throw error }
            guard let start = repairableTailStart(value, data: data, source: source) else {
                throw JoeyError.invalid("\(error.localizedDescription). Original ASR is preserved at \(input.path). Supply a valid full source-bound transcript; this defect cannot be repaired by a bounded tail retry.")
            }
            do {
                value = try await repairTranscriptTail(value, start: start, source: source,
                    configuration: configuration, directory: directory)
            } catch is CancellationError { throw CancellationError() }
            catch let blocked as StorageBlocked { throw blocked }
            catch {
                throw JoeyError.failed("Bounded transcript tail recovery failed: \(error.localizedDescription). Original ASR and repair evidence are preserved in \(directory.path). Supply a valid full source-bound transcript or inspect the retained ASR output.")
            }
        }
        try Persistence.save(value,to:canonical)
        return value
    }

    private static func transcriptionTools(_ configuration: Configuration) throws -> (String, String, String) {
        guard let python = configuration.pythonPath, let script = configuration.transcriptionScript,
              let model = configuration.modelPath else {
            throw JoeyError.dependency("Local transcript unavailable: configure existing Python ASR helper and installed model, or supply source-bound full transcript")
        }
        return (python, script, model)
    }

    private static func decodeTranscript(_ data: Data, source: SourceRecord) throws -> Transcript {
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
        return value
    }

    /// Only a local engine's out-of-range final timestamps qualify. Imported
    /// transcripts, ordering defects and uncertain prefix boundaries stay strict.
    private static func repairableTailStart(_ value: Transcript, data: Data, source: SourceRecord) -> Double? {
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              value.sourceID == source.id, value.sourceSHA256 == source.sha256,
              abs(value.duration - source.duration) < 0.1, !value.engine.isEmpty, !value.segments.isEmpty,
              raw["source_id"] as? String == source.id, raw["source_sha256"] as? String == source.sha256,
              ["mlx-whisper", "faster-whisper"].contains(raw["model"] as? String ?? ""),
              raw["word_timestamps"] as? Bool == true,
              (raw["transcription_status"] as? String)?.hasPrefix("completed") == true,
              raw["source_file"] as? String == URL(fileURLWithPath: source.path).lastPathComponent,
              source.duration.isFinite, source.duration > 0 else { return nil }
        let earliest = max(0, source.duration - 30)
        var previous = 0.0, damaged = false
        for part in value.segments {
            guard part.start.isFinite, part.end.isFinite, part.start >= previous,
                  part.end >= part.start, !part.text.isEmpty else { return nil }
            if part.end > source.duration + 0.1 {
                guard part.start >= earliest, part.start < source.duration else { return nil }
                damaged = true
            }
            previous = part.start
        }
        guard damaged else { return nil }
        for index in value.segments.indices {
            let start = value.segments[index].start
            if start >= earliest, start < source.duration,
               value.segments[..<index].allSatisfy({ $0.end <= start }) { return start }
        }
        return nil
    }

    private struct TranscriptTailRepair: Codable {
        var sourceID: String
        var sourceSHA256: String
        var sourceDuration: Double
        var originalASRSHA256: String
        var tailStart: Double
        var tailDuration: Double
        var tailSHA256: String
        var regeneratedASRSHA256: String?
        var transcriptSHA256: String?
    }

    private static func validateTailRepair(_ proof: TranscriptTailRepair, source: SourceRecord, directory: URL) throws {
        guard proof.sourceID == source.id, proof.sourceSHA256 == source.sha256,
              proof.sourceDuration == source.duration, proof.tailStart.isFinite,
              proof.tailStart >= max(0, source.duration - 30), proof.tailStart < source.duration,
              proof.tailDuration.isFinite, proof.tailDuration > 0,
              abs(proof.tailDuration - (source.duration - proof.tailStart)) < 0.1 else {
            throw JoeyError.invalid("Transcript tail repair source identity changed; retained files preserved")
        }
        var files = [(URL(fileURLWithPath: source.path), proof.sourceSHA256),
            (directory.appendingPathComponent("asr-source.json"), proof.originalASRSHA256),
            (directory.appendingPathComponent("transcript-repair/source-tail.wav"), proof.tailSHA256)]
        if let hash = proof.regeneratedASRSHA256 {
            files.append((directory.appendingPathComponent("transcript-repair/asr-tail.json"), hash))
        }
        let canonical = directory.appendingPathComponent("transcript.json")
        if FileManager.default.fileExists(atPath: canonical.path) {
            guard let hash = proof.transcriptSHA256 else {
                throw JoeyError.invalid("Transcript tail repair lacks acceptance evidence; retained files preserved")
            }
            files.append((canonical, hash))
        }
        for (file, hash) in files {
            guard (try? Integrity.sha256(file)) == hash else {
                throw JoeyError.invalid("Transcript tail repair evidence changed or is unavailable: \(file.lastPathComponent); retained files preserved")
            }
        }
    }

    private static func repairTranscriptTail(_ original: Transcript, start: Double, source: SourceRecord,
                                            configuration: Configuration, directory: URL) async throws -> Transcript {
        let work = directory.appendingPathComponent("transcript-repair")
        let excerpt = work.appendingPathComponent("source-tail.wav")
        let generated = work.appendingPathComponent("asr-tail.json")
        let raw = directory.appendingPathComponent("asr-source.json")
        let receipt = directory.appendingPathComponent("transcript-repair.json")
        var proof: TranscriptTailRepair
        if FileManager.default.fileExists(atPath: receipt.path) {
            proof = try Persistence.load(receipt)
            try validateTailRepair(proof, source: source, directory: directory)
            guard proof.tailStart == start else { throw JoeyError.invalid("Transcript tail repair boundary changed") }
        } else {
            _ = try transcriptionTools(configuration)
            guard try Integrity.sha256(URL(fileURLWithPath: source.path)) == source.sha256 else {
                throw JoeyError.invalid("Original source changed before transcript recovery")
            }
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            // Only this unaccepted derived excerpt can be replaced after an
            // interrupted extraction. Original and ASR files are never replaced.
            _ = try await Processes.run("ffmpeg", ["-nostdin", "-v", "error", "-y", "-ss", String(start),
                "-i", source.path, "-t", String(source.duration - start), "-vn", "-ac", "1", "-ar", "16000",
                "-c:a", "pcm_s16le", excerpt.path], timeout: 60)
            let measured = try await Media.probe(excerpt)
            guard measured.duration > 0, abs(measured.duration - (source.duration - start)) < 0.1 else {
                throw JoeyError.invalid("Decoded transcript tail does not cover the requested source interval")
            }
            proof = TranscriptTailRepair(sourceID: source.id, sourceSHA256: source.sha256,
                sourceDuration: source.duration, originalASRSHA256: try Integrity.sha256(raw),
                tailStart: start, tailDuration: measured.duration, tailSHA256: try Integrity.sha256(excerpt))
            try Persistence.save(proof, to: receipt)
        }
        var tailSource = source
        tailSource.id = source.id + ":transcript-tail:" + String(start)
        tailSource.path = excerpt.path
        tailSource.sha256 = proof.tailSHA256
        tailSource.duration = proof.tailDuration
        if !FileManager.default.fileExists(atPath: generated.path) {
            let (python, script, model) = try transcriptionTools(configuration)
            var arguments = [script, "--source", excerpt.path, "--source-id", tailSource.id,
                "--output", generated.path, "--model-dir", model, "--cpu-threads", "2"]
            if let payload = try JSONSerialization.jsonObject(with: Data(contentsOf: raw)) as? [String: Any],
               let language = payload["language"] as? String, !language.isEmpty {
                arguments += ["--language", language]
            }
            _ = try await Processes.run(python, arguments, timeout: 180)
        }
        let regeneratedData = try Data(contentsOf: generated)
        let tail = try decodeTranscript(regeneratedData, source: tailSource)
        try tail.validate(sourceID: tailSource.id, sha256: tailSource.sha256, duration: tailSource.duration)
        try validateAlignedTail(regeneratedData, duration: tailSource.duration)
        let prefix = original.segments.prefix { $0.start < start }
        let combined = Transcript(sourceID: source.id, sourceSHA256: source.sha256, duration: source.duration,
            engine: original.engine + "; bounded local tail retranscription",
            segments: Array(prefix) + tail.segments.map {
                TranscriptSegment(start: start + $0.start, end: start + $0.end, text: $0.text)
            })
        try combined.validate(sourceID: source.id, sha256: source.sha256, duration: source.duration)
        let hash = Integrity.textHash(String(decoding: try Persistence.encoder.encode(combined), as: UTF8.self))
        if let accepted = proof.transcriptSHA256, accepted != hash {
            throw JoeyError.invalid("Transcript tail repair result changed; retained files preserved")
        }
        proof.regeneratedASRSHA256 = try Integrity.sha256(generated)
        proof.transcriptSHA256 = hash
        try validateTailRepair(proof, source: source, directory: directory)
        // Save acceptance before the canonical write so interruption can recover
        // from these same validated bytes without invoking inference again.
        try Persistence.save(proof, to: receipt)
        return combined
    }

    private static func validateAlignedTail(_ data: Data, duration: Double) throws {
        guard let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              raw["word_timestamps"] as? Bool == true,
              let segments = raw["segments"] as? [[String: Any]] else {
            throw JoeyError.invalid("Regenerated transcript tail lacks aligned words")
        }
        var previous = 0.0
        for (index, segment) in segments.enumerated() {
            guard let start = segment["start_seconds"] as? Double, let end = segment["end_seconds"] as? Double,
                  let words = segment["words"] as? [[String: Any]], !words.isEmpty else {
                throw JoeyError.invalid("Regenerated transcript tail segment \(index + 1) lacks aligned words")
            }
            for word in words {
                guard let first = word["start_seconds"] as? Double, let last = word["end_seconds"] as? Double,
                      first.isFinite, last.isFinite, first >= previous, first >= start - 0.1,
                      last >= first, last <= end + 0.1, last <= duration + 0.1 else {
                    throw JoeyError.invalid("Regenerated transcript tail segment \(index + 1) has invalid word timing")
                }
                previous = first
            }
        }
    }
}
