import Foundation

public enum LinkContent: String, Codable, CaseIterable, Sendable {case dub, taxstone, joeBudden}

public enum ProductionIntake {
    public static func request(source: DiscoveredSource, content: LinkContent, mode: JobMode,
                               sharedProfile: SharedProfile?, archive: String? = nil,
                               archiveRoot: String? = nil, transcript: String? = nil, preferredDuration: Double? = nil) throws -> JobRequest {
        if content == .dub,source.id.hasPrefix("x:broadcast:") {
            guard source.channelID == DubBroadcastDiscovery.broadcasterID,mode == .fullShow else {
                throw JoeyError.invalid("Dub broadcasts require verified original ownership and Clip Entire Show native masters")
            }
            var request = try DubBroadcastDiscovery.request(DubBroadcast(source:source,broadcasterID:DubBroadcastDiscovery.broadcasterID,startedAt:nil,verifiedAt:Date()))
            request.archiveReference = archive;request.archiveRootID = archiveRoot;request.transcriptPath = transcript
            request.preferredDuration = preferredDuration
            try request.validate()
            return request
        }
        guard preferredDuration == nil else {throw JoeyError.invalid("Core clip length selection requires a verified DUB X broadcast and Clip Entire Show")}
        let joe = content == .joeBudden || source.channelID == SourceDiscovery.joeChannelID
        if joe {
            guard content != .taxstone, source.channelID == SourceDiscovery.joeChannelID,
                  source.episodeNumber != nil, source.id.hasPrefix("youtube:") else {
                throw JoeyError.invalid("Select a numbered full episode from Joe Budden TV on YouTube")
            }
        }
        guard let profile = joe ? SharedProfile.joeBuddenDrive : sharedProfile else {
            throw JoeyError.dependency("Set up the shared X/Instagram export limits in Settings")
        }
        let request = JobRequest(owner:content == .taxstone ? .taxstone:.dub,sourceID:source.id,title:source.title,
            episodeDate:source.episodeDate,dateEvidence:source.episodeDate == nil ? nil:"Original provider upload_date for "+source.url,
            originalURL:source.url,authorizationBasis:"User-initiated Joey link workflow; no separate authorization form",
            archiveReference:archive,archiveRootID:joe ? nil:archiveRoot,
            expectedDuration:source.duration,mode:joe ? .fullShow:mode,transcriptPath:transcript,
            profile:profile,fileToDrive:true,productionWorkflow:joe ? .joeBudden:.link)
        try request.validate();return request
    }
}

/// A small checkpoint for opt-in, app-session automation. Media job state
/// remains solely in the existing coordinator and job checkpoints.
public struct JoeAutomationState: Codable, Sendable {
    public var enabled = false
    public var afterEpisode: Int?
    public var lastCheckedAt: Date?
    public var queue: [DiscoveredSource] = []
    /// A bounded library turn resumes here even after a failed episode or feed sort.
    public var nextInterleavedEpisodeID: String?
    public var lastError: String?
    public init() {}

    public mutating func enable(after latest: DiscoveredSource?) throws {
        // This is the activation baseline, never a completion watermark:
        // a later completed episode must not hide an earlier missing episode.
        if afterEpisode == nil {
            guard let latest, latest.channelID == SourceDiscovery.joeChannelID,
                  let number = latest.episodeNumber else {
                throw JoeyError.invalid("Check the official numbered episodes before enabling automation")
            }
            afterEpisode = number
        }
        enabled = true
        lastError = nil
    }

    public mutating func reconcile(_ episodes: [DiscoveredSource], completed: Set<String>, now: Date = Date()) {
        lastCheckedAt = now
        guard enabled, let baseline = afterEpisode else {return}
        queue.removeAll {completed.contains($0.id)}
        var known = Set(queue.map(\.id))
        for episode in episodes where episode.channelID == SourceDiscovery.joeChannelID && (episode.episodeNumber ?? 0) > baseline {
            if !completed.contains(episode.id), known.insert(episode.id).inserted {queue.append(episode)}
        }
        queue.sort {($0.episodeNumber ?? 0, $0.id) < ($1.episodeNumber ?? 0, $1.id)}
    }
}
