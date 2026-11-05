import Foundation

public enum JoeyError: Error, LocalizedError {
    case invalid(String), dependency(String), failed(String)
    public var errorDescription: String? {
        switch self { case .invalid(let s), .dependency(let s), .failed(let s): return s }
    }
}

public enum Owner: String, Codable, CaseIterable, Sendable { case dub, taxstone }
public enum MediaKind: String, Codable, Sendable { case nativeVideo, audio }
public enum JobMode: String, Codable, CaseIterable, Sendable { case fullShow, highlights }
public enum TranscriptPolicy: String, Codable, Sendable { case assisted, modelIndependent }
public enum PlanningBasis: String, Codable, Sendable { case transcriptAssisted, deterministicTime }
public enum ProductionWorkflow: String, Codable, Sendable { case link, joeBudden, taxstoneLibrary, dubBroadcast }
public enum JobState: String, Codable, Sendable {
    case planned = "PLANNED", processing = "PROCESSING", qaPassed = "QA_PASSED"
    case filed = "FILED", completed = "COMPLETED", failed = "FAILED", cancelled = "CANCELLED"
}

public struct EvidenceFile: Codable, Equatable, Sendable {
    public var path: String
    public var sha256: String
    public var basis: String
    public init(path: String, sha256: String, basis: String) { self.path = path; self.sha256 = sha256; self.basis = basis }
    public func validate() throws {
        guard !basis.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              sha256.count == 64, try Integrity.sha256(URL(fileURLWithPath: path)) == sha256 else {
            throw JoeyError.dependency("Missing or changed evidence: \(path)")
        }
    }
}

public struct SurfaceCapability: Codable, Equatable, Sendable {
    public var platform: String
    public var account: String
    public var surface: String
    public var checkedAt: Date
    public var validUntil: Date
    public var maxDuration: Double
    public var maxBytes: Int64
    public var maxWidth: Int
    public var maxHeight: Int
    public var maxFPS: Double
    public var officialURLs: [String]
    public var accountEvidence: EvidenceFile
    public init(platform: String, account: String, surface: String, checkedAt: Date, validUntil: Date,
                maxDuration: Double, maxBytes: Int64, maxWidth: Int, maxHeight: Int, maxFPS: Double,
                officialURLs: [String], accountEvidence: EvidenceFile) {
        self.platform = platform;self.account = account;self.surface = surface
        self.checkedAt = checkedAt;self.validUntil = validUntil;self.maxDuration = maxDuration
        self.maxBytes = maxBytes;self.maxWidth = maxWidth;self.maxHeight = maxHeight;self.maxFPS = maxFPS
        self.officialURLs = officialURLs;self.accountEvidence = accountEvidence
    }
    public func validate(now: Date, requireCurrentEvidence: Bool = true) throws {
        let label = ["X", "Instagram"].contains(platform) ? platform : "Platform"
        let recovery = "Open Production Setup and verify the saved account and upload surface with current official limits and matching account evidence."
        guard ["X", "Instagram"].contains(platform), !account.isEmpty, !surface.isEmpty else {
            throw JoeyError.dependency("\(label) account or upload-surface identity is missing or invalid. \(recovery)")
        }
        guard validUntil > checkedAt,
              maxDuration.isFinite, maxDuration > 0, maxBytes > 0,
              maxWidth > 0, maxHeight > 0, maxFPS.isFinite, maxFPS >= 30, !officialURLs.isEmpty else {
            throw JoeyError.dependency("\(label) capability limits, dates or official sources are invalid. \(recovery)")
        }
        if requireCurrentEvidence {
            if checkedAt > now {
                throw JoeyError.dependency("\(label) capability checkedAt is in the future (\(ISO8601DateFormatter().string(from:checkedAt))). \(recovery)")
            }
            if validUntil <= now {
                throw JoeyError.dependency("\(label) capability evidence expired at \(ISO8601DateFormatter().string(from:validUntil)). \(recovery)")
            }
        }
        for raw in officialURLs {
            guard let u = URL(string: raw), u.scheme == "https", let host = u.host,
                  (platform == "X" ? ["help.x.com", "docs.x.com", "developer.x.com", "support.buffer.com"].contains(host)
                    : ["help.instagram.com", "developers.facebook.com", "www.facebook.com", "www.instagram.com", "support.buffer.com"].contains(host)) else {
                throw JoeyError.invalid("\(label) capability requires official platform or upload-surface sources. \(recovery)")
            }
        }
        if requireCurrentEvidence {
            guard !accountEvidence.basis.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,
                  accountEvidence.sha256.count == 64 else {
                throw JoeyError.dependency("\(label) account evidence metadata is missing or invalid. \(recovery)")
            }
            let file = URL(fileURLWithPath:accountEvidence.path)
            guard FileManager.default.fileExists(atPath:file.path) else {
                throw JoeyError.dependency("\(label) account evidence file is missing. \(recovery)")
            }
            let hash: String
            do {hash = try Integrity.sha256(file)}
            catch {throw JoeyError.dependency("\(label) account evidence file cannot be read. \(recovery)")}
            guard hash == accountEvidence.sha256 else {
                throw JoeyError.dependency("\(label) account evidence SHA-256 changed. \(recovery)")
            }
        }
    }

    /// Renewable observations are not part of a media job's immutable contract.
    /// Account, upload surface and every technical limit remain identity-bound.
    var identityContract: SurfaceCapability {
        var copy = self
        copy.checkedAt = Date(timeIntervalSince1970:0);copy.validUntil = copy.checkedAt
        copy.officialURLs = []
        copy.accountEvidence = EvidenceFile(path:"",sha256:"",basis:"")
        return copy
    }

    /// A newer observation may establish broader limits while the job keeps
    /// its original account, surface and conservative technical contract.
    func renewingEvidence(from proposed: SurfaceCapability, requireCurrentEvidence: Bool) throws -> SurfaceCapability {
        let label = ["X", "Instagram"].contains(platform) ? platform : "Platform"
        let requirements = [
            (platform == proposed.platform, "platform identity differs"),
            (account == proposed.account, "saved account differs from the configured account"),
            (surface == proposed.surface, "saved upload surface differs from the configured surface"),
            (proposed.maxDuration >= maxDuration, "maxDuration requires \(maxDuration) seconds, current limit \(proposed.maxDuration) seconds"),
            (proposed.maxBytes >= maxBytes, "maxBytes requires \(maxBytes) bytes, current limit \(proposed.maxBytes) bytes"),
            (proposed.maxWidth >= maxWidth, "maxWidth requires \(maxWidth) pixels, current limit \(proposed.maxWidth) pixels"),
            (proposed.maxHeight >= maxHeight, "maxHeight requires \(maxHeight) pixels, current limit \(proposed.maxHeight) pixels"),
            (proposed.maxFPS >= maxFPS, "maxFPS requires \(maxFPS), current limit \(proposed.maxFPS)")
        ]
        let conflicts = requirements.filter {!$0.0}.map { $0.1 }
        guard conflicts.isEmpty else {
            throw JoeyError.invalid("\(label) capability mismatch. \(conflicts.joined(separator:". ")). Open Production Setup and restore evidence for the saved account, upload surface and required limits. Existing job and accepted clips are preserved.")
        }
        if proposed.checkedAt >= checkedAt, proposed != self {
            do {
                try proposed.validate(now:Date())
                var renewed = self
                renewed.checkedAt = proposed.checkedAt
                renewed.validUntil = proposed.validUntil
                renewed.officialURLs = proposed.officialURLs
                renewed.accountEvidence = proposed.accountEvidence
                return renewed
            } catch {if requireCurrentEvidence {throw error}}
        }
        try validate(now:Date(),requireCurrentEvidence:requireCurrentEvidence)
        return self
    }
}

public struct SharedProfile: Codable, Equatable, Sendable {
    public var x: SurfaceCapability?
    public var instagram: SurfaceCapability?
    public var width: Int
    public var height: Int
    // An explicit Drive-only Joe contract is not account capability evidence.
    // nil keeps every existing shared request's serialized identity unchanged.
    public var driveOnlyJoe: Bool?
    /// Separate ownership and presentation from Joe's historical branding contract.
    /// Absence preserves every existing serialized request and stable identity.
    public var dubNativeMaster: Bool?
    public var isDriveOnly: Bool {driveOnlyJoe == true || dubNativeMaster == true}
    public static var dubBroadcastMaster: SharedProfile {
        SharedProfile(x:nil,instagram:nil,width:1080,height:1920,dubNativeMaster:true)
    }
    public static var joeBuddenDrive: SharedProfile {
        SharedProfile(x:nil,instagram:nil,width:1920,height:1080,driveOnlyJoe:true)
    }
    public var maxDuration: Double { dubNativeMaster == true ? 600.075 : driveOnlyJoe == true ? 607.3 : min(x?.maxDuration ?? 0, instagram?.maxDuration ?? 0) }
    public var maxBytes: Int64 { isDriveOnly ? 2_000_000_000 : min(x?.maxBytes ?? 0, instagram?.maxBytes ?? 0) }
    func outputProfile(for kind: MediaKind) throws -> SharedProfile {
        var output = self
        if kind == .nativeVideo, driveOnlyJoe != true {
            output.width = 1920;output.height = 1080
        }
        // Validate the resolved canvas, not only the portrait selection stored
        // in the request. A native-video override cannot expand account limits.
        if !isDriveOnly {
            guard let x, let instagram,
                  output.width <= min(x.maxWidth,instagram.maxWidth),
                  output.height <= min(x.maxHeight,instagram.maxHeight) else {
                throw JoeyError.dependency("Shared capability evidence does not support \(output.width)×\(output.height) output; existing media preserved")
            }
        }
        return output
    }
    public func validate(now: Date = Date(), requireCurrentEvidence: Bool = true) throws {
        if dubNativeMaster == true {
            guard driveOnlyJoe != true, x == nil, instagram == nil, width == 1080, height == 1920 else {
                throw JoeyError.invalid("Dub native masters require their Drive-only contract and approved audio canvas")
            }
            return
        }
        if driveOnlyJoe == true {
            guard x == nil, instagram == nil, width == 1920, height == 1080 else {
                throw JoeyError.invalid("Joe Budden Drive exports require the explicit 1920×1080 local contract, without platform capability claims")
            }
            return
        }
        guard let x, let instagram else {throw JoeyError.dependency("Verified shared X/Instagram limits are missing")}
        try x.validate(now: now,requireCurrentEvidence:requireCurrentEvidence)
        try instagram.validate(now: now,requireCurrentEvidence:requireCurrentEvidence)
        guard x.platform == "X", instagram.platform == "Instagram",
              [(1080,1920),(720,1280)].contains(where: { $0.0 == width && $0.1 == height }),
              width <= min(x.maxWidth,instagram.maxWidth), height <= min(x.maxHeight,instagram.maxHeight) else {
            throw JoeyError.dependency("No compliant selected shared portrait profile")
        }
    }
    var identityContract: SharedProfile {
        var copy = self;copy.x = x?.identityContract;copy.instagram = instagram?.identityContract
        return copy
    }
    /// Refresh evidence only. A different account, surface or encoding contract
    /// requires an explicit new decision, never a silent resume or rerender.
    func renewingEvidence(from proposed: SharedProfile, requireCurrentEvidence: Bool = true) throws -> SharedProfile {
        guard width == proposed.width, height == proposed.height, driveOnlyJoe == proposed.driveOnlyJoe, dubNativeMaster == proposed.dubNativeMaster else {
            throw JoeyError.invalid("Saved export profile requires \(width)×\(height) and its original delivery mode. Production Setup selects \(proposed.width)×\(proposed.height) or a different delivery mode. Restore the saved profile before Resume. Existing job and accepted clips are preserved.")
        }
        if isDriveOnly {
            guard identityContract == proposed.identityContract else {
                throw JoeyError.invalid("Saved Drive-only profile changed. Restore the original Joe Budden Drive-only profile in Production Setup before Resume.")
            }
            try validate(requireCurrentEvidence:requireCurrentEvidence)
            return self
        }
        guard let x, let instagram, let proposedX = proposed.x, let proposedInstagram = proposed.instagram else {
            throw JoeyError.dependency("Saved or configured X/Instagram capability is missing. Open Production Setup and supply current evidence for both saved accounts and upload surfaces.")
        }
        var renewed = self
        renewed.x = try x.renewingEvidence(from:proposedX,requireCurrentEvidence:requireCurrentEvidence)
        renewed.instagram = try instagram.renewingEvidence(from:proposedInstagram,requireCurrentEvidence:requireCurrentEvidence)
        try renewed.validate(requireCurrentEvidence:requireCurrentEvidence)
        return renewed
    }
    public static func select(x: SurfaceCapability, instagram: SurfaceCapability, now: Date = Date()) throws -> SharedProfile {
        for (w,h) in [(1080,1920),(720,1280)] {
            let profile = SharedProfile(x: x, instagram: instagram, width: w, height: h)
            if (try? profile.validate(now: now)) != nil { return profile }
        }
        try x.validate(now: now); try instagram.validate(now: now)
        throw JoeyError.dependency("X and Instagram have no verified common 1080x1920 or 720x1280 profile")
    }
}

public struct TranscriptSegment: Codable, Equatable, Sendable {
    public var start: Double
    public var end: Double
    public var text: String
}
public struct Transcript: Codable, Equatable, Sendable {
    public var sourceID: String
    public var sourceSHA256: String
    public var duration: Double
    public var engine: String
    public var segments: [TranscriptSegment]
    public func validate(sourceID: String, sha256: String, duration: Double) throws {
        guard self.sourceID == sourceID, sourceSHA256 == sha256, abs(self.duration-duration) < 0.1,
              !engine.isEmpty, !segments.isEmpty else { throw JoeyError.invalid("Transcript is not bound to this complete source") }
        var previous = 0.0
        for (index, s) in segments.enumerated() {
            let reason: String?
            if !s.start.isFinite || !s.end.isFinite { reason = "non-finite timestamp" }
            else if s.start < previous { reason = "start precedes the previous segment start" }
            else if s.end < s.start { reason = "end precedes start" }
            else if s.end > duration + 0.1 { reason = "end exceeds source duration" }
            else if s.text.isEmpty { reason = "empty text" }
            else { reason = nil }
            if let reason {
                throw JoeyError.invalid("Invalid timestamped transcript at segment \(index + 1) (\(s.start)–\(s.end)s; source \(duration)s): \(reason)")
            }
            previous = s.start
        }
    }
}
public struct AdExclusion: Codable, Equatable, Sendable {
    public var interval: Interval
    public var evidence: String
    public var confidence: Double
}
public struct Artwork: Codable, Equatable, Sendable {
    public var owner: Owner
    public var sourceID: String?
    public var driveID: String
    public var file: EvidenceFile
}

public struct JobRequest: Codable, Equatable, Sendable {
    public var owner: Owner
    public var sourceID: String
    public var title: String
    public var episodeDate: String?
    public var dateEvidence: String?
    public var originalURL: String?
    public var localPath: String?
    public var authorizationBasis: String = ""
    public var archiveReference: String?
    public var archiveRootID: String?
    public var expectedDuration: Double?
    public var expectedSourceSHA256: String?
    public var taxstoneReuse: [TaxstoneReuseInput]?
    public var mode: JobMode = .fullShow
    public var requestedCount: Int?
    public var fixedIntervals: [Interval]?
    public var transcriptPath: String?
    // Optional to preserve the serialized identity of existing requests.
    // nil retains the original transcript-assisted behavior.
    public var transcriptPolicy: TranscriptPolicy?
    // nil preserves serialized identities and the existing ten-minute default.
    public var preferredDuration: Double?
    public var adExclusions: [AdExclusion] = []
    public var artwork: Artwork?
    public var profile: SharedProfile
    public var fileToDrive: Bool = true
    public var productionWorkflow: ProductionWorkflow?
    /// Historical completed-job readback needs the contract, not a new upload
    /// authorization. Fresh evidence remains mandatory before new operations.
    public func validate(requireCurrentCapability: Bool = true) throws {
        guard !sourceID.isEmpty, sourceID.count <= 180, !title.isEmpty,
              localPath != nil || originalURL != nil else { throw JoeyError.invalid("Source identity and an original source are required") }
        if let productionWorkflow {
            guard localPath == nil, let originalURL, fileToDrive, transcriptPolicy != .modelIndependent else {
                throw JoeyError.invalid("Production workflows require a source link, verified clip delivery and transcript-assisted processing")
            }
            if productionWorkflow == .taxstoneLibrary {
                guard owner == .taxstone, mode == .fullShow, let archiveReference,
                      originalURL == archiveReference, originalURL.hasPrefix("https://drive.google.com/file/d/"),
                      sourceID.hasPrefix("soundcloud:"), expectedSourceSHA256?.count == 64,
                      profile.driveOnlyJoe != true else {
                    throw JoeyError.invalid("Taxstone Library requires an identified, hash-bound archived original and shared profile")
                }
            } else {_ = try Acquisition.validateOriginalURL(originalURL)}
            if productionWorkflow == .joeBudden {
                guard owner == .dub, mode == .fullShow, profile.driveOnlyJoe == true,
                      SourceIdentitySuggestion.from(originalURL)?.hasPrefix("youtube:") == true else {
                    throw JoeyError.invalid("Joe Budden requires a YouTube source and the full-show Drive-only clipping workflow")
                }
            } else if profile.driveOnlyJoe == true {throw JoeyError.invalid("The Drive-only Joe profile cannot be used for DUB or Taxstone")}
        } else if profile.driveOnlyJoe == true {throw JoeyError.invalid("Drive-only export requires the Joe Budden workflow")}
        if profile.dubNativeMaster == true || productionWorkflow == .dubBroadcast {
            guard productionWorkflow == .dubBroadcast, profile.dubNativeMaster == true,
                  profile.driveOnlyJoe != true, owner == .dub, mode == .fullShow,
                  let originalURL, SourceIdentitySuggestion.from(originalURL) == sourceID,
                  sourceID.hasPrefix("x:broadcast:") else {
                throw JoeyError.invalid("Dub native masters require the original Dub broadcast full-show Drive-only workflow")
            }
        }
        if taxstoneReuse != nil, productionWorkflow != .taxstoneLibrary {throw JoeyError.invalid("Legacy Taxstone reuse belongs only to the library workflow")}
        if episodeDate != nil, dateEvidence?.isEmpty != false { throw JoeyError.invalid("Episode date requires source evidence") }
        if let count = requestedCount, count <= 0 { throw JoeyError.invalid("Highlight count must be positive") }
        if mode == .fullShow, fixedIntervals != nil || requestedCount != nil { throw JoeyError.invalid("Fixed selections/count require explicit highlight mode") }
        if let seconds = preferredDuration, !seconds.isFinite || !(480...600).contains(seconds) || mode != .fullShow {
            throw JoeyError.invalid("Full-show preferred duration must be between 480 and 600 seconds")
        }
        if transcriptPolicy == .modelIndependent {
            guard localPath != nil, mode == .fullShow, adExclusions.isEmpty else {
                throw JoeyError.invalid("Model-independent processing requires a local full-show source with no requested exclusions")
            }
        }
        try profile.validate(requireCurrentEvidence:requireCurrentCapability)
    }
    func identityData(ignoringProfile: Bool = false) throws -> Data {
        var copy = self
        copy.profile = ignoringProfile ? .joeBuddenDrive : profile.identityContract
        // Changing Joe's archive must not create a second job for an existing
        // immutable source request. The saved job ID remains authoritative.
        if copy.productionWorkflow == .joeBudden {copy.archiveRootID = nil}
        return try Persistence.encoder.encode(copy)
    }
    func stableID() throws -> String {
        owner.rawValue + "-" + String(Integrity.textHash(String(decoding:try identityData(),as:UTF8.self)).prefix(24))
    }
}

public struct SourceClassificationProof: Codable, Equatable, Sendable {
    public var version: Int
    public var sourceSHA256: String
    public var decodedFrameCount: Int
    public var uniformFrameSHA256: String?

    func provesStaticVideo(sha256: String) -> Bool {
        version == 1 && sourceSHA256 == sha256 && decodedFrameCount > 0 &&
            uniformFrameSHA256?.count == 64 && uniformFrameSHA256!.allSatisfy {"0123456789abcdef".contains($0)}
    }
}

public struct SourceRecord: Codable, Equatable, Sendable {
    public var id: String
    public var owner: Owner
    public var title: String
    public var episodeDate: String?
    public var originalURL: String?
    public var path: String
    public var bytes: Int64
    public var sha256: String
    public var duration: Double
    public var width: Int
    public var height: Int
    public var fps: Double
    public var hasAudio: Bool
    public var kind: MediaKind
    public var streams: [StreamInfo]
    public var authorizationBasis: String
    public var archiveReference: String?
    public var classificationEvidence: String
    public var classificationProof: SourceClassificationProof? = nil
}

public struct ResolvedClipFailure: Codable, Equatable, Sendable {
    public var stage: String
    public var error: String
    public var resolvedAt: Date
}
public struct ClipRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var title: String
    public var intervals: [Interval]
    public var filename: String
    public var durationException: String?
    public var measuredDuration: Double?
    public var bytes: Int64?
    public var sha256: String?
    public var qa: QAReport?
    public var drive: DriveReceipt?
    public var failureStage: String?
    public var error: String?
    public var resolvedFailures: [ResolvedClipFailure]?
    public var expectedDuration: Double { intervals.reduce(0) { $0+$1.duration } }
}
public struct QAReport: Codable, Equatable, Sendable {
    public var checkedAt: Date
    public var checks: [String: String]
    public var outputSHA256: String
    public var passed: Bool
    public var limitations: [String]
}
public struct DriveReceipt: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var parent: String
    public var bytes: Int64
    public var md5: String?
    public var sha256: String
    public var url: String
    public var permissions: [String]
    public var verifiedAt: Date
    public var destination: FilingDestination?
    public var permissionFingerprint: String?
}
public struct JobRecord: Codable, Identifiable, Sendable {
    public var id: String
    public var request: JobRequest
    public var state: JobState = .planned
    public var stage = "intake"
    public var source: SourceRecord?
    public var transcript: Transcript?
    public var planningBasis: PlanningBasis?
    public var clips: [ClipRecord] = []
    public var exclusions: [AdExclusion] = []
    public var folderID: String?
    public var companions: [String: DriveReceipt] = [:]
    public var registerRows: [String] = []
    public var storageRequiredBytes: Int64?
    public var storageWarnings: [String]?
    public var error: String?
    public var updatedAt = Date()
    public var unavailableTranscriptFeatures: [String] {
        var missing: [String] = []
        if transcript == nil {missing.append("Complete source-bound transcript")}
        if transcript == nil || planningBasis == .deterministicTime {
            missing += ["Transcript-assisted sentence/topic boundaries", "Descriptive content titles", "Advertisement identification/removal"]
        }
        return missing
    }
    /// Saved delivery evidence must identify the accepted bytes in this job's
    /// episode folder. This does not perform a fresh provider readback.
    public var verifiedDriveClipCount: Int {
        guard let folderID, !folderID.isEmpty,let source,
              let destination = try? DestinationResolver.resolve(source:source,request:request,asset:.clip) else {return 0}
        return clips.filter {clip in
            guard let receipt = clip.drive, !receipt.id.isEmpty,
                  let hash = clip.sha256, !hash.isEmpty, let bytes = clip.bytes, bytes > 0 else {return false}
            return receipt.parent == folderID && receipt.destination == destination && receipt.name == clip.filename &&
                receipt.sha256 == hash && receipt.bytes == bytes &&
                clip.qa?.passed == true && clip.qa?.outputSHA256 == hash
        }.count
    }
    /// Shared completion evidence for recovery and presentation. The coordinator
    /// also checks current local bytes before reopening a completed checkpoint.
    public var hasRequiredCompletionEvidence: Bool {
        guard !clips.isEmpty, unavailableTranscriptFeatures.isEmpty,
              verifiedDriveClipCount == clips.count,let source,let folderID,
              let destination = try? DestinationResolver.resolve(source:source,request:request,asset:.clip),
              Set(clips.compactMap { $0.drive?.id }).count == clips.count,
              !DestinationResolver.requiresDUBRegister(request) ||
                (registerRows.count == clips.count && Set(registerRows).count == clips.count),
              Set(companions.keys) == Set(Records.companionNames(source:source)),
              let transcript,
              (try? transcript.validate(sourceID:source.id,sha256:source.sha256,duration:source.duration)) != nil else {return false}
        let receipts = clips.compactMap(\.drive) + Array(companions.values)
        return Set(receipts.map(\.id)).count == receipts.count && receipts.allSatisfy {
            !$0.id.isEmpty && $0.parent == folderID && $0.destination == destination &&
            $0.bytes > 0 && $0.sha256.count == 64 && $0.md5?.count == 32 &&
            !$0.permissions.isEmpty && $0.permissionFingerprint?.count == 64
        } && companions.allSatisfy {$0.key == $0.value.name}
    }
    public var resumesAutomatically: Bool {
        state == .processing || state == .planned || state == .filed ||
        (state == .qaPassed && request.fileToDrive && unavailableTranscriptFeatures.isEmpty)
    }
}
