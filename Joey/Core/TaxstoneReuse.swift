import Foundation
import Darwin

public struct TaxstoneReuseInput: Codable, Equatable, Sendable {
    public var driveID: String
    public var intervals: [Interval]
    public var sourceSHA256: String
    public var md5: String
    public var evidence: String
}

protocol TaxstoneReuseProvider {
    func metadata(_ id: String) async throws -> [String: Any]
    func downloadOriginal(reference: String, directory: URL) async throws -> URL
}

extension DriveDelivery: TaxstoneReuseProvider {}

/// QA proves a particular source mapping and presentation, not just output bytes.
/// Keep the entire binding and report in one atomic receipt so interruption cannot
/// pair a new report with an older interval or artwork identity.
struct TaxstoneReuseAcceptance: Codable {
    private struct Context: Codable, Equatable {
        var sourceID: String
        var owner: Owner
        var sourceSHA256: String
        var sourceDuration: Double
        var sourceKind: MediaKind
        var hasAudio: Bool
        var intervals: [Interval]
        var title: String
        var profile: SharedProfile
        var artworkOwner: Owner
        var artworkSourceID: String?
        var artworkDriveID: String
        var artworkSHA256: String

        init(source: SourceRecord, clip: ClipRecord, profile: SharedProfile, artwork: Artwork) {
            sourceID = source.id; owner = source.owner; sourceSHA256 = source.sha256
            sourceDuration = source.duration; sourceKind = source.kind; hasAudio = source.hasAudio
            intervals = clip.intervals; title = clip.title; self.profile = profile.identityContract
            artworkOwner = artwork.owner; artworkSourceID = artwork.sourceID
            artworkDriveID = artwork.driveID; artworkSHA256 = artwork.file.sha256
        }
    }
    private var version: Int
    private var context: Context
    var qa: QAReport

    init(source: SourceRecord, clip: ClipRecord, profile: SharedProfile, artwork: Artwork, qa: QAReport) {
        version = 1
        context = Context(source:source,clip:clip,profile:profile,artwork:artwork)
        self.qa = qa
    }

    func matches(source: SourceRecord, clip: ClipRecord, profile: SharedProfile, artwork: Artwork) -> Bool {
        version == 1 && context == Context(source:source,clip:clip,profile:profile,artwork:artwork)
    }
}

/// Reconcile legacy candidates through the existing media QA. No historical
/// approved flag or filename can bypass source audio, artwork, waveform or profile checks.
public enum TaxstoneReuse {
    public static func plan(request: JobRequest, source: SourceRecord, transcript: Transcript,
                            exclusions: [AdExclusion], provider: DriveDelivery, directory: URL) async throws -> [ClipRecord] {
        try await plan(request:request,source:source,transcript:transcript,exclusions:exclusions,
                       provider:provider as any TaxstoneReuseProvider,directory:directory)
    }
    static func plan(request: JobRequest, source: SourceRecord, transcript: Transcript,
                     exclusions: [AdExclusion], provider: any TaxstoneReuseProvider, directory: URL) async throws -> [ClipRecord] {
        guard let artwork = request.artwork else {throw JoeyError.dependency("Taxstone reuse requires episode artwork")}
        let candidates = request.taxstoneReuse ?? []
        // Imported provider IDs are identities, never relative filesystem paths.
        // Validate the complete inventory before creating anything or contacting Drive.
        guard candidates.allSatisfy({$0.driveID.range(of:"^[A-Za-z0-9_-]{20,}$",options:.regularExpression) != nil}) else {
            throw JoeyError.invalid("Invalid legacy Drive object ID")
        }
        let workspace = try ReuseWorkspace(directory)
        var accepted: [(ClipRecord,URL)] = []
        let reuseDirectory = workspace.root.appendingPathComponent("legacy-reuse")
        try workspace.checkTree(reuseDirectory)
        try workspace.checkTree(workspace.root.appendingPathComponent("evidence"))
        try workspace.createDirectory(reuseDirectory)
        for candidate in candidates.sorted(by:{($0.intervals.first?.start ?? 0,$0.driveID) < ($1.intervals.first?.start ?? 0,$1.driveID)}) {
            try Task.checkCancellation()
            let work = reuseDirectory.appendingPathComponent(candidate.driveID)
            try workspace.createDirectory(work)
            let resultURL = work.appendingPathComponent("reconciliation.json")
            guard candidate.sourceSHA256 == source.sha256,!candidate.evidence.isEmpty,!candidate.md5.isEmpty else {
                throw JoeyError.failed("Legacy reuse candidate is not bound to this source and provider object")
            }
            // Exact duplicate and intersecting candidates are reconciled before
            // downloading. Their speech must never appear twice in the package.
            do {_ = try TaxstoneLibrary.missing(duration:source.duration,exclusions:exclusions.map(\.interval),accepted:accepted.map {$0.0.intervals}+[candidate.intervals])}
            catch {
                try workspace.save(["status":"NOT_ADOPTED","reason":error.localizedDescription,"driveID":candidate.driveID],to:resultURL)
                continue
            }
            // Each legacy object may contain multiple retained intervals.
            let title = transcript.segments.first {s in candidate.intervals.contains {s.start >= $0.start && s.end <= $0.end}}?.text ?? source.title
            var clip = ClipRecord(id:0,title:String(title.split(separator:" ").prefix(12).joined(separator:" ")),intervals:candidate.intervals,filename:"candidate.mp4",durationException:"Reused verified source intervals")
            do {
                let metadata = try await provider.metadata(candidate.driveID)
                guard metadata["md5Checksum"] as? String == candidate.md5 else {throw JoeyError.failed("Legacy provider object changed since inventory")}
                try workspace.checkTree(work)
                let local = try await provider.downloadOriginal(reference:"https://drive.google.com/file/d/"+candidate.driveID+"/view",directory:work)
                try workspace.check(local)
                let probe = try await Media.probe(local)
                guard probe.video?.width == request.profile.width,probe.video?.height == request.profile.height,
                      abs((probe.video?.fps ?? 0)-30) < 0.001,probe.duration <= request.profile.maxDuration else {
                    try workspace.save(["status":"INCOMPATIBLE","reason":"Measured dimensions/frame rate/duration differ from current shared contract","driveID":candidate.driveID],to:resultURL)
                    continue
                }
                do {
                    try DurationPolicy(profile:request.profile).validateMeasured(probe.duration,expected:clip.expectedDuration)
                } catch {
                    // Cached QA cannot grandfather media outside the current
                    // measured contract. Preserve its bytes and record why it
                    // cannot be adopted before planning replacement coverage.
                    try workspace.save(["status":"INCOMPATIBLE","reason":error.localizedDescription,"driveID":candidate.driveID],to:resultURL)
                    continue
                }
                // Historical accepted-qa.json lacks input bindings. Preserve it,
                // but independently validate its media before issuing a bound receipt.
                let qaURL = work.appendingPathComponent("accepted-qa-bound.json")
                try workspace.check(qaURL)
                let cached: TaxstoneReuseAcceptance? = try? Persistence.load(qaURL)
                var qa: QAReport
                if let cached,cached.matches(source:source,clip:clip,profile:request.profile,artwork:artwork),
                   cached.qa.passed,try Integrity.sha256(local) == cached.qa.outputSHA256 {
                    try artwork.file.validate()
                    qa = cached.qa
                } else {
                    try workspace.checkTree(work)
                    let reference = try await Media.audioReference(source:source,clip:clip,profile:request.profile,artwork:artwork,output:local,work:work)
                    try workspace.checkTree(work)
                    qa = try await Media.validate(output:local,source:source,clip:clip,profile:request.profile,render:reference,work:work)
                    qa.checks["reused_original_output"] = "Drive "+candidate.driveID+" MD5 "+candidate.md5+"; "+candidate.evidence
                }
                clip.qa = qa;clip.sha256 = qa.outputSHA256;clip.measuredDuration = probe.duration
                clip.bytes = ((try FileManager.default.attributesOfItem(atPath:local.path))[.size] as? NSNumber)?.int64Value
                accepted.append((clip,local))
                try workspace.save(TaxstoneReuseAcceptance(source:source,clip:clip,profile:request.profile,artwork:artwork,qa:qa),to:qaURL)
                try workspace.save(["status":"ADOPTED","driveID":candidate.driveID],to:resultURL)
            } catch {
                if error is CancellationError {throw error}
                // An inaccessible original is uncertainty, not evidence that it
                // needs replacement. Only a measured QA failure permits a fresh render.
                if case JoeyError.failed(let reason) = error,
                   reason.contains("validation failed") || reason.contains("Approved artwork/layout fidelity failed") || reason.contains("waveform") || reason.contains("Waveform") || reason.contains("faststart") {
                    try workspace.save(["status":"INCOMPATIBLE","reason":reason,"driveID":candidate.driveID],to:resultURL)
                } else {throw error}
            }
        }
        let missing = try TaxstoneLibrary.missing(duration:source.duration,exclusions:exclusions.map(\.interval),accepted:accepted.map {$0.0.intervals})
        var planned: [ClipRecord] = []
        if missing > Planning.tolerance {
            let gaps = try Planning.retained(duration:source.duration,
                exclusions:accepted.flatMap {$0.0.intervals})
            // Plan each uncovered region independently. Compacting all gaps into
            // one retained timeline can put speech from both sides of an accepted
            // clip into an earlier clip, breaking chronological exactly-once coverage.
            for gap in gaps {
                let regionExclusions = exclusions.compactMap { exclusion -> AdExclusion? in
                    let start = max(exclusion.interval.start,gap.start), end = min(exclusion.interval.end,gap.end)
                    guard end > start else {return nil}
                    var local = exclusion; local.interval = Interval(start-gap.start,end-gap.start)
                    return local
                }
                // An ad-only gap needs no clip. Within every other region the
                // ordinary planner can join retained speech across excluded ads,
                // including short pieces that together meet the shared minimum.
                guard gap.duration-regionExclusions.reduce(0,{$0+$1.interval.duration}) > Planning.tolerance else {continue}
                var regionSource = source; regionSource.duration = gap.duration
                var regionTranscript = transcript; regionTranscript.duration = gap.duration
                regionTranscript.segments = transcript.segments.compactMap { segment in
                    let start = max(segment.start,gap.start), end = min(segment.end,gap.end)
                    guard end > start else {return nil}
                    return TranscriptSegment(start:start-gap.start,end:end-gap.start,text:segment.text)
                }
                let region = try Editorial.plan(request:request,source:regionSource,transcript:regionTranscript,exclusions:regionExclusions)
                planned += region.map { record in
                    var clip = record
                    clip.intervals = clip.intervals.map {Interval($0.start+gap.start,$0.end+gap.start)}
                    return clip
                }
            }
        }
        var combined = (planned.map {($0,Optional<URL>.none)}+accepted.map {($0.0,Optional($0.1))}).sorted {($0.0.intervals.first?.start ?? 0) < ($1.0.intervals.first?.start ?? 0)}
        for i in combined.indices {
            var clip = combined[i].0;clip.id = i+1
            clip.filename = String(format:"%02d",i+1)+"_"+Persistence.safeName(clip.title)+"_"+Persistence.safeName(source.id)+"_"+Editorial.stamp(clip.intervals.first!.start)+"_to_"+Editorial.stamp(clip.intervals.last!.end)+".mp4"
            if let local = combined[i].1 {
                let target = workspace.root.appendingPathComponent(clip.filename)
                try workspace.check(local)
                try workspace.check(target)
                if FileManager.default.fileExists(atPath:target.path) {
                    guard try Integrity.sha256(target) == clip.sha256 else {throw JoeyError.failed("Different existing accepted output preserved during reuse")}
                } else {try FileManager.default.copyItem(at:local,to:target)}
                try workspace.save(clip.qa,to:workspace.root.appendingPathComponent("evidence/\(clip.id)/qa.json"))
            }
            combined[i].0 = clip
        }
        let result = combined.map {$0.0}
        try Planning.validateCoverage(duration:source.duration,exclusions:exclusions.map(\.interval),clips:result.map(\.intervals))
        return result
    }
}

/// The coordinator already owns the exclusive processing lock. Recheck existing
/// ancestors and leaves at each filesystem boundary, including helper work files,
/// so imported IDs and previously planted links cannot redirect reuse writes.
private struct ReuseWorkspace {
    let root: URL

    init(_ directory: URL) throws {
        var status = stat()
        guard directory.isFileURL, lstat(directory.path,&status) == 0,
              status.st_mode & S_IFMT == S_IFDIR else {throw JoeyError.invalid("Legacy reuse requires an existing unlinked job directory")}
        // The coordinator supplies a canonical job path. Inspect that original
        // path before resolving it: otherwise a linked ancestor could silently
        // redefine which directory this operation is authorized to write into.
        try StorageManager.noLinks(directory)
        root = try StorageManager.canonicalRoot(directory)
        try StorageManager.noLinks(root)
    }

    func check(_ url: URL) throws {
        guard url.isFileURL, url.path == root.path || url.path.hasPrefix(root.path+"/"),
              !url.pathComponents.contains(".."), !url.pathComponents.contains(".") else {
            throw JoeyError.invalid("Legacy reuse path escapes its job directory")
        }
        var ancestor = url
        var status = stat()
        while lstat(ancestor.path,&status) != 0 {
            guard errno == ENOENT, ancestor.path != root.path else {throw JoeyError.invalid("Legacy reuse path is unavailable")}
            ancestor.deleteLastPathComponent()
        }
        try StorageManager.noLinks(ancestor)
    }

    func checkTree(_ url: URL) throws {
        try check(url)
        var directory: ObjCBool = false
        if FileManager.default.fileExists(atPath:url.path,isDirectory:&directory), directory.boolValue {
            for child in try FileManager.default.contentsOfDirectory(at:url,includingPropertiesForKeys:nil) {
                try checkTree(child)
            }
        }
    }

    func createDirectory(_ url: URL) throws {
        try check(url)
        try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
        try check(url)
    }

    func save<T: Encodable>(_ value: T, to url: URL) throws {
        try check(url)
        try createDirectory(url.deletingLastPathComponent())
        try check(url)
        try Persistence.save(value,to:url)
    }
}
