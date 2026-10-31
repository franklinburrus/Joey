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
    public func validate(now: Date) throws {
        guard ["X", "Instagram"].contains(platform), !account.isEmpty, !surface.isEmpty,
              checkedAt <= now, validUntil > now, validUntil > checkedAt,
              maxDuration.isFinite, maxDuration > 0, maxBytes > 0,
              maxWidth > 0, maxHeight > 0, maxFPS >= 30, !officialURLs.isEmpty else {
            throw JoeyError.dependency("Missing or expired \(platform) account/upload-surface capability evidence")
        }
        for raw in officialURLs {
            guard let u = URL(string: raw), u.scheme == "https", let host = u.host,
                  (platform == "X" ? ["help.x.com", "docs.x.com", "developer.x.com"].contains(host)
                    : ["help.instagram.com", "developers.facebook.com", "www.facebook.com", "www.instagram.com"].contains(host)) else {
                throw JoeyError.invalid("Capability requires official platform sources")
            }
        }
        try accountEvidence.validate()
    }
}

public struct SharedProfile: Codable, Equatable, Sendable {
    public var x: SurfaceCapability
    public var instagram: SurfaceCapability
    public var width: Int
    public var height: Int
    public var maxDuration: Double { min(x.maxDuration, instagram.maxDuration) }
    public var maxBytes: Int64 { min(x.maxBytes, instagram.maxBytes) }
    public func validate(now: Date = Date()) throws {
        try x.validate(now: now); try instagram.validate(now: now)
        guard x.platform == "X", instagram.platform == "Instagram",
              [(1080,1920),(720,1280)].contains(where: { $0.0 == width && $0.1 == height }),
              width <= min(x.maxWidth,instagram.maxWidth), height <= min(x.maxHeight,instagram.maxHeight) else {
            throw JoeyError.dependency("No compliant selected shared portrait profile")
        }
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
        for s in segments {
            guard s.start.isFinite, s.end.isFinite, s.start >= previous, s.end >= s.start,
                  s.end <= duration + 0.1, !s.text.isEmpty else { throw JoeyError.invalid("Invalid timestamped transcript") }
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
    public var authorizationBasis: String
    public var archiveReference: String?
    public var archiveRootID: String?
    public var expectedDuration: Double?
    public var mode: JobMode = .fullShow
    public var requestedCount: Int?
    public var fixedIntervals: [Interval]?
    public var transcriptPath: String?
    public var adExclusions: [AdExclusion] = []
    public var artwork: Artwork?
    public var profile: SharedProfile
    public var fileToDrive: Bool = true
    public func validate() throws {
        guard !sourceID.isEmpty, sourceID.count <= 180, !title.isEmpty,
              !authorizationBasis.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              localPath != nil || originalURL != nil else { throw JoeyError.invalid("Source identity, authorization and local file or original URL are required") }
        if episodeDate != nil, dateEvidence?.isEmpty != false { throw JoeyError.invalid("Episode date requires source evidence") }
        if let count = requestedCount, count <= 0 { throw JoeyError.invalid("Highlight count must be positive") }
        if mode == .fullShow, fixedIntervals != nil || requestedCount != nil { throw JoeyError.invalid("Fixed selections/count require explicit highlight mode") }
        try profile.validate()
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
}
public struct JobRecord: Codable, Identifiable, Sendable {
    public var id: String
    public var request: JobRequest
    public var state: JobState = .planned
    public var stage = "intake"
    public var source: SourceRecord?
    public var transcript: Transcript?
    public var clips: [ClipRecord] = []
    public var exclusions: [AdExclusion] = []
    public var folderID: String?
    public var companions: [String: DriveReceipt] = [:]
    public var registerRows: [String] = []
    public var error: String?
    public var updatedAt = Date()
    public var resumesAutomatically: Bool {
        state == .processing || state == .planned || state == .filed ||
        (state == .qaPassed && request.fileToDrive)
    }
}
