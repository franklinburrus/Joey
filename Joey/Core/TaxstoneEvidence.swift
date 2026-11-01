import Foundation

/// Historical evidence is a candidate for reconciliation, never a completion flag.
public struct TaxstoneLegacyClip: Codable, Sendable {
    public var driveID: String
    public var intervals: [Interval]
    public var expectedSHA256: String?
    public var expectedMD5: String?
    public var bytes: Int64?
    public var width: Int?
    public var height: Int?
    public var fps: Double?
    public var evidencePath: String
    /// The episode-local catalog clip number is joined by exact source interval.
    /// It is a lookup hint, not proof of output identity; ledger row numbers are global.
    public var sequence: Int?
    /// Apply only after the candidate's current provider hash matches expectedSHA256/MD5.
    public var incompatibilities: [String]?
}

public struct TaxstoneEvidenceEntry: Codable, Sendable {
    public var driveID: String
    public var trackID: String
    public var title: String
    public var episodeDate: String?
    public var duration: Double?
    public var sourceSHA256: String?
    public var transcript: EvidenceFile?
    public var transcriptEngine: String?
    public var artwork: Artwork?
    public var legacyClips: [TaxstoneLegacyClip]
    public var notes: [String]
}

public enum TaxstoneEvidence {
    private typealias Object = [String: Any]
    private static let maximumJSONBytes = 16 * 1024 * 1024

    /// Reads existing metadata only. It does not open original media, render, or call Drive.
    public static func load() throws -> [TaxstoneEvidenceEntry] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return try load(reconciliationRoot: home.appendingPathComponent("Dub/work/taxstone-buffer/reconciliation"),
                        mediaRoot: home.appendingPathComponent("Library/CloudStorage/GoogleDrive-franklinburrus@gmail.com/My Drive/Dub/Content/Media"))
    }

    public static func load(reconciliationRoot root: URL, mediaRoot: URL) throws -> [TaxstoneEvidenceEntry] {
        let catalog = try object(root.appendingPathComponent("catalog.json"))
        let ledgerURL = root.appendingPathComponent("master-ledger.json")
        let ledger = try object(ledgerURL)
        let qa = try object(root.appendingPathComponent("technical-qa.json"))
        let catalogRows = catalog["episodes"] as? [Object] ?? []
        let mappings = ledger["episodes"] as? [Object] ?? []
        guard !catalogRows.isEmpty, catalogRows.count <= 1000, mappings.count <= 1000 else {
            throw JoeyError.invalid("Taxstone historical catalog is empty or exceeds its bounded inventory")
        }
        var entries: [String: TaxstoneEvidenceEntry] = [:]
        for row in catalogRows {
            guard let track = string(row, "track_id"),
                  let mapping = mappings.first(where: { string($0, "episode_id") == track }),
                  let driveID = string(mapping, "parent_source_drive_file_id"),
                  let title = string(row, "episode_title"), entries[track] == nil else {
                throw JoeyError.invalid("Taxstone catalog lacks an unambiguous source-to-Drive mapping")
            }
            entries[track] = TaxstoneEvidenceEntry(driveID: driveID, trackID: track, title: title,
                episodeDate: string(row, "source_date"), legacyClips: [], notes: [
                    "Historical catalog status is not current shared-profile delivery evidence.",
                    "Prior transcript paths must not be reused without source/hash-bound receipts."
                ])
        }
        let technical = qa["results"] as? [Object] ?? []
        for row in ledger["rows"] as? [Object] ?? [] {
            guard let track = string(row, "episode_id"), var entry = entries[track],
                  string(row, "parent_source_drive_file_id") == entry.driveID,
                  let drive = string(row, "buffer_delivery_file_id"), let interval = interval(row) else {
                throw JoeyError.invalid("Taxstone legacy ledger has an unmapped source or interval")
            }
            let info = technical.first { string($0, "track_id") == track &&
                number($0, "expected_start_seconds") == interval.start &&
                number($0, "expected_end_seconds") == interval.end } ?? [:]
            var candidate = clip(row, drive: drive, intervals: [interval], info: info, path: ledgerURL.path)
            let catalogEpisode = catalogRows.first { string($0, "track_id") == track } ?? [:]
            let selections = (catalogEpisode["shorts"] as? [Object] ?? []).filter {
                number($0, "start_seconds") == interval.start && number($0, "end_seconds") == interval.end
            }
            if selections.count == 1 { candidate.sequence = (selections[0]["clip_number"] as? NSNumber)?.intValue }
            entry.legacyClips.append(candidate)
            entries[track] = entry
        }

        // This short source was excluded by the retired exactly-three-shorts policy.
        // Its verified source and repaired complete transcript remain reusable.
        let repairRoot = root.appendingPathComponent("remediation-802783417")
        let repairURL = repairRoot.appendingPathComponent("remediation-report.json")
        if FileManager.default.fileExists(atPath: repairURL.path) {
            let report = try object(repairURL)
            let episode = report["episode"] as? Object ?? [:]
            guard let track = string(episode, "episode_id"), let drive = string(episode, "source_drive_file_id"),
                  let title = string(episode, "title"), entries[track] == nil else {
                throw JoeyError.invalid("Taxstone remediation source mapping conflicts with the catalog")
            }
            var entry = TaxstoneEvidenceEntry(driveID: drive, trackID: track, title: title,
                episodeDate: "2020-04-20", duration: number(episode, "source_duration_seconds"),
                sourceSHA256: string(episode, "source_sha256"), legacyClips: [],
                notes: ["Historical short-source blocker used a retired minimum/count contract; no historical clips were produced."])
            let remediation = report["remediation"] as? Object ?? [:]
            let transcript = remediation["corrected_transcript"] as? Object ?? [:]
            if let relative = string(transcript, "path"), !relative.hasPrefix("/"), !relative.split(separator: "/").contains(".."),
               let hash = string(transcript, "sha256") {
                attachTranscript(&entry, url: repairRoot.appendingPathComponent(relative), hash: hash,
                                 engine: string(transcript, "model"), receipt: repairURL.path)
            }
            entries[track] = entry
        }

        let roots = [mediaRoot.appendingPathComponent("Clips/Taxstone"),
                     mediaRoot.appendingPathComponent("Clips/X Audio Clips/Dub/X Audio Instagram/Taxstone")]
        for folder in roots {
            guard let enumerator = FileManager.default.enumerator(at: folder,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) else { continue }
            var visited = 0
            while let url = enumerator.nextObject() as? URL {
                visited += 1
                guard visited <= 10000 else { throw JoeyError.invalid("Taxstone evidence scan exceeds 10,000 metadata entries") }
                let name = url.lastPathComponent
                guard url.pathExtension == "json", name.lowercased().contains("manifest"),
                      (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { continue }
                do {
                    let document = try object(url)
                    ingest(document, inheritedTrack: nil, inheritedInfo: [:], path: url.path, entries: &entries, depth: 0)
                } catch {
                    // A malformed unrelated legacy record must not prevent independent episodes.
                    for key in entries.keys.sorted() {
                        entries[key]?.notes.append("Unreadable legacy manifest requires reconciliation: \(url.path): \(error.localizedDescription)")
                    }
                }
            }
        }

        let titan = mediaRoot.appendingPathComponent("Clips/Taxstone/Taxstone X Clips/Taxstone/2026-10-03 — Tax Season Sneak Preview Episode 0 — Full Chronological Titan")
        let closeoutURL = titan.appendingPathComponent("job-closeout.json")
        if var entry = entries["196489572"], FileManager.default.fileExists(atPath: closeoutURL.path) {
            let receipt = try object(closeoutURL)
            if string(receipt, "source_drive_file_id") == entry.driveID,
               string(receipt, "source_id") == entry.trackID,
               let sourceHash = string(receipt, "source_original_sha256"),
               let evidence = (receipt["supporting_files"] as? [Object])?.first(where: { string($0, "filename") == "source-transcript.json" }),
               let hash = string(evidence, "sha256") {
                entry.sourceSHA256 = sourceHash
                entry.duration = number(receipt, "full_source_duration_seconds")
                attachTranscript(&entry, url: titan.appendingPathComponent("source-transcript.json"), hash: hash,
                                 engine: nil, receipt: closeoutURL.path)
            }
            entries[entry.trackID] = entry
        }
        // Keep unfiled local revisions visible without manufacturing provider receipts.
        let workRoot = root.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("taxstone-skill-family/x")
        for revision in ["friend-zone-15-20261029", "friend-zone-15-20261029-logo-r2"] {
            let url = workRoot.appendingPathComponent(revision).appendingPathComponent("job.json")
            guard FileManager.default.fileExists(atPath: url.path), var entry = entries["275592592"] else { continue }
            do {
                let record = try object(url)
                let job = record["job"] as? Object ?? [:]
                let source = job["source"] as? Object ?? [:]
                if string(source, "drive_file_id") == entry.driveID {
                    let outputs = job["outputs"] as? [Object] ?? []
                    let intervals = outputs.compactMap { interval($0) }
                    entry.notes.append("Local revision \(revision) records \(outputs.count) outputs, \(intervals.count) exact intervals; status \(string(record, "status") ?? "unknown"). No verified Drive receipt is inferred: \(url.path)")
                    entry.notes.append("Local revision intervals require cross-revision reconciliation before reuse: " + intervals.map { "\($0.start)-\($0.end)" }.joined(separator: ", "))
                }
            } catch { entry.notes.append("Unreadable local revision: \(url.path): \(error.localizedDescription)") }
            entries[entry.trackID] = entry
        }
        // A separately filed portrait derivative has a full original-source/interval chain.
        // Its receipt is retained even though its measured dimensions are not Joey's profile.
        let derivativeRoot = root.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("dub-skill-family-acceptance/jobs/taxstone-row1431-x-derivative-20261015")
        let derivativeReceipt = derivativeRoot.appendingPathComponent("drive-receipt.json")
        if FileManager.default.fileExists(atPath: derivativeReceipt.path), var entry = entries["261140871"] {
            do {
                let receipt = try object(derivativeReceipt)
                let job = try object(derivativeRoot.appendingPathComponent("job.json"))
                let output = derivativeRoot.appendingPathComponent("output/4565437f38778d421ad55bb747f9fec1e6c2b78f2c68ccac107a70967269ea5a")
                let result = try object(output.appendingPathComponent("result.json"))
                let metadataURL = output.appendingPathComponent("metadata.json")
                let metadata = try object(metadataURL)
                let source = metadata["source"] as? Object ?? [:]
                let probe = result["probe"] as? Object ?? [:]
                let video = (probe["streams"] as? [Object])?.first(where: { string($0, "codec_type") == "video" }) ?? [:]
                if string(job, "source_id") == entry.driveID,
                   string(result, "source_id") == entry.driveID,
                   string(source, "source_id") == entry.driveID,
                   string(result, "source_sha256") == entry.sourceSHA256,
                   string(source, "source_sha256") == entry.sourceSHA256,
                   let selected = interval(job["segment"] as? Object ?? [:]),
                   interval(metadata["segment"] as? Object ?? [:]) == selected,
                   let hash = string(result, "output_sha256"), hash.count == 64,
                   string(receipt, "local_sha256") == hash,
                   string(receipt, "drivefs_readback_sha256") == hash,
                   let metadataHash = string(result, "metadata_sha256"),
                   try Integrity.sha256(metadataURL) == metadataHash,
                   let drive = string(receipt, "drive_id") {
                    var info = video
                    info["frame_rate"] = video["r_frame_rate"]
                    var candidate = clip(["sha256": hash, "size_bytes": receipt["size_bytes"] as Any],
                        drive: drive, intervals: [selected], info: info, path: derivativeReceipt.path)
                    if candidate.width == 1068 && candidate.height == 1900 {
                        candidate.incompatibilities = ["Measured 1068x1900 differs from the shared 1080x1920/720x1280 Joey profile."]
                    }
                    entry.legacyClips.append(candidate)
                } else { entry.notes.append("Portrait derivative receipt does not reconcile source/interval/hash lineage: " + derivativeReceipt.path) }
            } catch { entry.notes.append("Portrait derivative evidence unavailable: \(error.localizedDescription)") }
            entries[entry.trackID] = entry
        }
        for key in entries.keys.sorted() {
            guard var entry = entries[key] else { continue }
            // Repeated receipts for one object are not additional clips. Conflicting intervals
            // remain visible and must be resolved against the provider before adoption.
            var seen = Set<String>()
            entry.legacyClips = entry.legacyClips.filter { candidate in
                let identity = candidate.driveID + ":" + candidate.intervals.map { "\($0.start)-\($0.end)" }.joined(separator: ",")
                return seen.insert(identity).inserted
            }
            if entry.legacyClips.contains(where: { ($0.fps ?? 30) < 30 || ($0.width ?? 0) > ($0.height ?? Int.max) }) {
                entry.notes.append("Legacy landscape/2-fps outputs do not establish compliant Joey portrait coverage; preserve them.")
            }
            entry.notes.append("Episode artwork requires exact provider identity/hash verification; no generic artwork was substituted.")
            entries[key] = entry
        }
        return entries.values.sorted { ($0.episodeDate ?? "", $0.trackID) < ($1.episodeDate ?? "", $1.trackID) }
    }

    public static func convertTranscript(_ entry: TaxstoneEvidenceEntry, source: SourceRecord, to destination: URL) throws -> Transcript? {
        guard let evidence = entry.transcript else { return nil }
        guard source.owner == .taxstone, source.id == "soundcloud:" + entry.trackID,
              source.sha256 == entry.sourceSHA256, let duration = entry.duration,
              abs(duration - source.duration) < 0.1,
              try Integrity.sha256(URL(fileURLWithPath: source.path)) == source.sha256 else {
            throw JoeyError.invalid("Taxstone historical transcript does not match the actual verified original")
        }
        try evidence.validate()
        let raw = try object(URL(fileURLWithPath: evidence.path))
        guard string(raw, "source_id") == "tag:soundcloud,2010:tracks/" + entry.trackID,
              let rawSegments = raw["segments"] as? [Object], rawSegments.count <= 100000 else {
            throw JoeyError.invalid("Taxstone transcript identity or segment schema is invalid")
        }
        let segments = try rawSegments.map { row -> TranscriptSegment in
            guard let start = number(row, "start_seconds"), let end = number(row, "end_seconds"),
                  let text = string(row, "text") else { throw JoeyError.invalid("Taxstone transcript timestamp/text missing") }
            return TranscriptSegment(start: start, end: end, text: text)
        }
        let transcript = Transcript(sourceID: source.id, sourceSHA256: source.sha256, duration: source.duration,
            engine: entry.transcriptEngine ?? string(raw, "model") ?? "historical source-bound local ASR", segments: segments)
        try transcript.validate(sourceID: source.id, sha256: source.sha256, duration: source.duration)
        guard destination.standardizedFileURL != URL(fileURLWithPath: evidence.path).standardizedFileURL,
              destination.standardizedFileURL != URL(fileURLWithPath: source.path).standardizedFileURL else {
            throw JoeyError.invalid("Converted transcript must not replace original evidence or media")
        }
        try Persistence.save(transcript, to: destination)
        return transcript
    }

    private static func attachTranscript(_ entry: inout TaxstoneEvidenceEntry, url: URL, hash: String, engine: String?, receipt: String) {
        do {
            let raw = try object(url)
            guard string(raw, "source_id") == "tag:soundcloud,2010:tracks/" + entry.trackID,
                  let segments = raw["segments"] as? [Object], !segments.isEmpty,
                  hash.count == 64, try Integrity.sha256(url) == hash else {
                throw JoeyError.invalid("Transcript identity/hash or complete segments missing")
            }
            entry.transcript = EvidenceFile(path: url.path, sha256: hash, basis: "Original/source-bound historical receipt: " + receipt)
            entry.transcriptEngine = engine ?? string(raw, "model")
        } catch { entry.notes.append("Historical transcript cannot be reused: \(error.localizedDescription)") }
    }

    private static func object(_ url: URL) throws -> Object {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber, size.intValue <= maximumJSONBytes else {
            throw JoeyError.invalid("Historical JSON is not a bounded regular file: \(url.path)")
        }
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumJSONBytes + 1) ?? Data()
        guard data.count <= maximumJSONBytes,
              let result = try JSONSerialization.jsonObject(with: data) as? Object else {
            throw JoeyError.invalid("Invalid historical JSON object: \(url.path)")
        }
        return result
    }
    private static func string(_ row: Object, _ key: String) -> String? {
        guard let value = row[key] as? String, !value.isEmpty else { return nil }; return value
    }
    private static func number(_ row: Object, _ key: String) -> Double? {
        guard let value = row[key] as? NSNumber, value.doubleValue.isFinite else { return nil }; return value.doubleValue
    }
    private static func interval(_ row: Object) -> Interval? {
        let start = number(row, "source_start_seconds") ?? number(row, "start_seconds") ?? number(row, "start")
        let end = number(row, "source_end_seconds") ?? number(row, "end_seconds") ?? number(row, "end")
        guard let start, let end, start >= 0, end > start else { return nil }; return Interval(start, end)
    }
    private static func clip(_ row: Object, drive: String, intervals: [Interval], info: Object, path: String) -> TaxstoneLegacyClip {
        let fps: Double? = number(info, "fps") ?? number(row, "fps") ?? {
            guard let rate = string(info, "frame_rate") else { return nil }
            let parts = rate.split(separator: "/").compactMap { Double($0) }
            return parts.count == 2 && parts[1] > 0 ? parts[0] / parts[1] : Double(rate)
        }()
        var incompatibilities: [String] = []
        if let outro = number(row, "outro_seconds"), outro > 0 {
            incompatibilities.append("Historical output includes a \(outro)-second separate outro, outside the current Taxstone contract.")
        }
        if let color = string(row, "wave_color"), color.hasPrefix("#"), color.count == 7,
           let rgb = UInt32(color.dropFirst(), radix: 16), rgb != 0xFFFFFF {
            incompatibilities.append("Historical waveform is \(color), not the required Taxstone white waveform.")
        }
        return TaxstoneLegacyClip(driveID: drive, intervals: intervals,
            expectedSHA256: string(row, "sha256"), expectedMD5: string(row, "md5"),
            bytes: (row["size_bytes"] as? NSNumber ?? info["size_bytes"] as? NSNumber)?.int64Value,
            width: (row["width"] as? NSNumber ?? info["width"] as? NSNumber)?.intValue,
            height: (row["height"] as? NSNumber ?? info["height"] as? NSNumber)?.intValue,
            fps: fps, evidencePath: path, sequence: nil,
            incompatibilities: incompatibilities.isEmpty ? nil : incompatibilities)
    }

    private static func ingest(_ row: Object, inheritedTrack: String?, inheritedInfo: Object, path: String,
                               entries: inout [String: TaxstoneEvidenceEntry], depth: Int) {
        guard depth <= 6 else { return }
        let ids = ["episode_id", "track_id", "source_id", "source", "episode"].compactMap { string(row, $0) }
        let tracks = Set(ids.compactMap { id in entries[id] != nil ? id : entries.values.first(where: { $0.driveID == id })?.trackID })
        let driveSource = string(row, "source_drive_file_id") ?? string(row, "parent_source_drive_file_id")
        let driveTrack = driveSource.flatMap { id in entries.values.first(where: { $0.driveID == id })?.trackID }
        let track = tracks.count == 1 ? tracks.first : driveTrack ?? inheritedTrack
        guard tracks.count <= 1, driveSource == nil || driveTrack != nil,
              driveTrack == nil || track == driveTrack else { return }
        var info = inheritedInfo
        for key in ["width", "height", "fps", "frame_rate"] { if let value = row[key] { info[key] = value } }
        if let track, var entry = entries[track] {
            if let hash = string(row, "source_sha256"), hash.count == 64 {
                if entry.sourceSHA256 == nil { entry.sourceSHA256 = hash }
                else if entry.sourceSHA256 != hash { entry.notes.append("Conflicting source hash in legacy manifest: " + path) }
            }
            if let duration = number(row, "source_duration_seconds"), duration > 0, entry.duration == nil { entry.duration = duration }
            let segments = row["source_segments"] as? [Object]
            var intervals = segments?.compactMap { interval($0) } ?? []
            let malformedSegments = segments != nil && (segments!.isEmpty || intervals.count != segments!.count)
            if malformedSegments {
                intervals = []
                entry.notes.append("Malformed legacy source segments are not accepted coverage: " + path)
            }
            if segments == nil, let value = interval(row) { intervals = [value] }
            if intervals.isEmpty, let nested = row["source_interval_seconds"] as? Object, let value = interval(nested) {
                intervals = [value]
            }
            if intervals.isEmpty, let milliseconds = row["source_interval_ms"] as? [Double], milliseconds.count == 2,
               milliseconds[0] >= 0, milliseconds[1] > milliseconds[0] {
                intervals = [Interval(milliseconds[0] / 1000, milliseconds[1] / 1000)]
            }
            let media = row["media"] as? Object ?? row
            if let drive = string(media, "buffer_delivery_file_id") ?? string(media, "drive_file_id") ?? string(media, "drive_id") {
                if !intervals.isEmpty && !malformedSegments {
                    entry.legacyClips.append(clip(media, drive: drive, intervals: intervals, info: info, path: path))
                } else { entry.notes.append("Legacy output lacks exact source intervals; not accepted coverage: \(drive) in \(path)") }
            }
            if (number(row, "outro_seconds") ?? 0) > 0 {
                entry.notes.append("Legacy output includes an outro; current Taxstone compliance must be checked: " + path)
            }
            entries[track] = entry
        }
        if let episode = row["episode"] as? Object {
            ingest(episode, inheritedTrack: track, inheritedInfo: info, path: path, entries: &entries, depth: depth + 1)
        }
        let episodeTrack = (row["episode"] as? Object).flatMap { string($0, "episode_id") }
        for key in ["clips", "chapters", "records", "rows", "episodes", "placements"] {
            for child in (row[key] as? [Object] ?? []).prefix(5000) {
                ingest(child, inheritedTrack: track ?? episodeTrack, inheritedInfo: info, path: path, entries: &entries, depth: depth + 1)
            }
        }
    }
}
