import Foundation

public enum BufferPlatform: String, Codable, CaseIterable, Sendable {case x = "X", instagram = "Instagram"}
public enum BufferMode: String, Codable, CaseIterable, Sendable {case draft = "Save as Draft", queue = "Add to Queue", scheduled = "Schedule"}
public enum InstagramPresentation: String, Codable, CaseIterable, Sendable {
    case traditionalFeed = "Traditional feed post", reel = "Reel", reelSharedToFeed = "Reel shared to feed"
}
public enum BufferWorkflowState: String, Codable, Sendable {
    case validated = "VALIDATED", prepared = "PREPARED", submitted = "SUBMITTED", reconciled = "RECONCILED"
    case blocked = "BLOCKED", failed = "FAILED", unconfirmed = "UNCONFIRMED"
}
public enum BufferProviderState: String, Codable, Sendable {case draft, scheduled, sending, sent, error}

public struct BufferSelection: Codable, Equatable, Sendable {
    public var clipKeys: [String] = []
    public var platforms: [BufferPlatform] = [.x]
    public var mode: BufferMode = .draft
    public var instagramPresentation: InstagramPresentation = .traditionalFeed
    public var instagramAcknowledged = false
    public var scheduledAt: Date?
    public var maximumOperations = 5
    public init() {}
    public func blockers(for platform: BufferPlatform) -> [String] {
        var result: [String] = []
        if platform == .instagram && (!instagramAcknowledged || instagramPresentation == .traditionalFeed) {
            result.append("Traditional single-video feed placement is not verified. Explicitly choose Reel or Reel shared to feed; these are different presentations.")
        }
        if mode != .draft {
            result.append("Media retrieval longevity through the queue/publication time is unverified. Choose Draft or supply a separately authorized supported delivery method; Joey will not change sharing.")
        }
        if mode == .scheduled && scheduledAt == nil {result.append("An explicit schedule with timezone is required.")}
        return result
    }
}

/// Observations from the existing Buffer connector, never permanent account authority.
public struct BufferChannel: Codable, Equatable, Sendable {
    public var lane: String
    public var platform: BufferPlatform
    public var organizationID: String
    public var channelID: String
    public var handle: String
    public var connected: Bool
    public var locked: Bool
    public var checkedAt: Date
    public var validUntil: Date
    public var supportedModes: [BufferMode]
    public var supportedInstagramPresentations: [InstagramPresentation]
    public var evidenceSource: String
    public var remainingAllowances: [Int]
    public func validate(lane expectedLane: String, platform expectedPlatform: BufferPlatform, mode: BufferMode, now: Date) throws {
        let expectedHandles = ["dub": ["X":"dubwiththefiles","Instagram":"dubwiththefiles"],
                               "taxstone": ["X":"JailCallwithTax","Instagram":"thejailcallwithtaxstone"]]
        guard lane == expectedLane, platform == expectedPlatform,
              expectedHandles[lane]?[platform.rawValue]?.lowercased() == handle.lowercased(),
              !organizationID.isEmpty, !channelID.isEmpty, connected, !locked,
              checkedAt <= now, validUntil > now, validUntil.timeIntervalSince(checkedAt) <= 86_400,
              !evidenceSource.isEmpty, supportedModes.contains(mode) else {
            throw JoeyError.dependency("Missing, expired or mismatched Buffer channel evidence for \(expectedLane) \(expectedPlatform.rawValue)")
        }
    }
}

public struct BufferPreparedClip: Codable, Sendable {
    public var jobID: String
    public var clipID: Int
    public var lane: String
    public var sourceID: String
    public var episode: String
    public var intervals: [Interval]
    public var sha256: String
    public var rightsBasis: String
    public var recommendation: ClipRecommendation?
    public var media: BufferMediaPreflight?
    public var checkedAt: Date
    public var error: String?
    public var observedPerformance: [BufferPerformanceObservation]?
    public var key: String {Self.key(jobID:jobID,clipID:clipID)}
    public static func key(jobID: String, clipID: Int) -> String {jobID+":"+String(clipID)}
}
/// Reserved for actual provider observations. No metrics are fabricated or
/// inferred from recommendation scores, and no analytics collection runs here.
public struct BufferPerformanceObservation: Codable, Sendable {
    public var platform: BufferPlatform
    public var metric: String
    public var value: Double
    public var observedAt: Date
    public var evidenceReference: String
}

public struct BufferOperation: Codable, Sendable, Identifiable {
    public var id: String
    public var clip: BufferPreparedClip
    public var platform: BufferPlatform
    public var channel: BufferChannel?
    public var requestedMode: BufferMode
    public var instagramPresentation: InstagramPresentation?
    public var shareToFeed: Bool?
    public var scheduledAt: Date?
    public var state: BufferWorkflowState
    public var blockers: [String]
    public var priorBatchIDs: [String]
    public var caption: String {platform == .x ? clip.recommendation?.xCaption ?? "" : clip.recommendation?.instagramCaption ?? ""}
    public static func identity(lane: String, sourceID: String, intervals: [Interval], sha256: String, platform: BufferPlatform, channelID: String) throws -> String {
        struct Identity: Encodable {var lane: String;var sourceID: String;var intervals: [Interval];var sha256: String;var platform: BufferPlatform;var channelID: String}
        let data = try Persistence.encoder.encode(Identity(lane:lane,sourceID:sourceID,intervals:intervals,sha256:sha256,platform:platform,channelID:channelID))
        return Integrity.textHash(String(decoding:data,as:UTF8.self))
    }
}

public struct BufferSubBatch: Codable, Sendable {public var id: String;public var operationIDs: [String]}
public struct BufferManifest: Codable, Sendable, Identifiable {
    public var schemaVersion = "joey-buffer-v1"
    public var id: String
    public var createdAt: Date
    public var manifestSHA256: String = ""
    public var previousManifestSHA256: String?
    public var selection: BufferSelection
    public var selectedClipCount: Int
    public var expectedOperationCount: Int
    public var executionAuthorization = "REQUIRED_SEPARATE_USER_REQUEST"
    public var evidenceValidUntil: Date?
    public var operations: [BufferOperation]
    public var priorReceipts: [BufferReceipt] = []
    public var subBatches: [BufferSubBatch]
    public var executionInstructions: String = BufferExecutionContract.instructions
    /// SHA-256 of canonical JSON using Persistence.encoder, with this field empty.
    public func digest() throws -> String {
        var copy = self;copy.manifestSHA256 = ""
        return Integrity.textHash(String(decoding:try Persistence.encoder.encode(copy),as:UTF8.self))
    }
    public func validate() throws {
        guard schemaVersion == "joey-buffer-v1", UUID(uuidString:id) != nil,
              executionAuthorization == "REQUIRED_SEPARATE_USER_REQUEST",
              manifestSHA256 == (try digest()), expectedOperationCount == operations.count,
              selectedClipCount == Set(operations.map { $0.clip.key }).count,
              Set(selection.clipKeys) == Set(operations.map {$0.clip.key}),
              (1...20).contains(selection.maximumOperations),
              Set(operations.map(\.id)).count == operations.count,
              subBatches.flatMap(\.operationIDs) == operations.map(\.id),
              subBatches.allSatisfy({!$0.operationIDs.isEmpty && $0.operationIDs.count <= selection.maximumOperations}) else {
            throw JoeyError.invalid("Invalid Buffer manifest identity, hash or operation counts")
        }
        for operation in operations {
            guard operation.id == (try BufferOperation.identity(lane:operation.clip.lane,sourceID:operation.clip.sourceID,
                intervals:operation.clip.intervals,sha256:operation.clip.sha256,platform:operation.platform,
                channelID:operation.channel?.channelID ?? "UNRESOLVED")),
                selection.platforms.contains(operation.platform),operation.requestedMode == selection.mode,
                operation.scheduledAt == selection.scheduledAt,
                [.prepared,.blocked].contains(operation.state),
                (operation.state == .prepared) == operation.blockers.isEmpty,
                operation.state != .prepared || (operation.clip.media != nil && operation.clip.recommendation != nil && operation.channel != nil),
                operation.channel == nil || (operation.channel?.lane == operation.clip.lane && operation.channel?.platform == operation.platform) else {
                throw JoeyError.invalid("Manifest operation does not match its exact selection and media identity")
            }
        }
        for key in selection.clipKeys {
            guard Set(operations.filter {$0.clip.key == key}.map(\.platform)) == Set(selection.platforms) else {
                throw JoeyError.invalid("Manifest is missing a selected clip/destination operation")
            }
        }
    }
}

/// Used by the portable execution contract; Joey itself never accepts this as a
/// grant to write to Buffer. The human request must be verified outside the file.
public struct BufferExecutionAuthorization: Codable, Sendable {
    public var batchID: String
    public var operationIDs: [String]
    public var channelIDs: [String]
    public var mode: BufferMode
    public var expiresAt: Date
    public var actualUserRequest: String
    public func validate(batchID: String, operationID: String, channelID: String, mode: BufferMode, now: Date) throws {
        guard self.batchID == batchID, operationIDs.contains(operationID), channelIDs.contains(channelID),
              self.mode == mode, expiresAt > now, !actualUserRequest.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else {
            throw JoeyError.invalid("Separate exact user execution authorization is missing, mismatched or expired")
        }
    }
}

public enum BufferRetryDecision: Equatable, Sendable {case proceed, reconcile, waitUntil(Date), stop(String)}
public enum BufferRateGate {
    /// A decision helper for imported execution evidence and portable instructions;
    /// it does not execute requests or schedule background retries.
    public static func decide(remainingAllowances: [Int], observedAt: Date, now: Date, attempts: Int,
                              retryAfter: Date?, authorizationExpiresAt: Date, uncertainWrite: Bool) -> BufferRetryDecision {
        if uncertainWrite {return .reconcile}
        guard !remainingAllowances.isEmpty, observedAt <= now, now.timeIntervalSince(observedAt) <= 60 else {return .stop("Current rate-limit evidence required")}
        guard remainingAllowances.allSatisfy({$0 > 0}) else {return .stop("Request allowance exhausted")}
        guard attempts >= 0, attempts < 3 else {return .stop("Three transient attempts exhausted")}
        guard authorizationExpiresAt > now else {return .stop("Execution authorization expired")}
        if let retryAfter, retryAfter > now {
            guard retryAfter < authorizationExpiresAt else {return .stop("Authorization expires before retry")}
            return .waitUntil(retryAfter)
        }
        return .proceed
    }
}

public struct BufferReceipt: Codable, Equatable, Sendable {
    public var schemaVersion = "joey-buffer-receipts-v1"
    public var batchID: String
    public var manifestSHA256: String
    public var operationID: String
    public var jobID: String
    public var clipID: Int
    public var sourceID: String
    public var lane: String
    public var platform: BufferPlatform
    public var organizationID: String
    public var channelID: String
    public var postID: String?
    public var submissionOrigin: BufferSubmissionOrigin = .newSubmission
    public var requestedMode: BufferMode
    public var providerState: BufferProviderState?
    public var mediaReference: String?
    public var submittedAt: Date?
    public var readbackAt: Date?
    public var errors: [String]
    public var verificationMethod: String
    public var reconciliationState: BufferWorkflowState
    public var provenance = "GPT-mediated provider evidence; not independently verified by Joey"
}
public enum BufferSubmissionOrigin: String, Codable, Sendable {case newSubmission, existingPost}
public struct BufferReceiptPackage: Codable, Sendable {
    public var schemaVersion = "joey-buffer-receipts-v1"
    public var batchID: String
    public var manifestSHA256: String
    public var results: [BufferReceipt]
}
