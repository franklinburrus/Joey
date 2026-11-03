import Foundation

public enum DriveAsset: String, Codable, Sendable { case clip, fullEpisode }
public enum FilingOwner: String, Codable, Sendable { case dub, taxstone, joeBudden }

/// The only production destination catalog. Ancestors are ordered from the
/// immediate parent through the authoritative Dub root, verified in Drive.
public enum DriveDestination: String, Codable, CaseIterable, Sendable {
    case dubAudioClips, dubVideoClips, taxstoneClips, joeBuddenClips
    case dubAudioEpisodes, dubVideoEpisodes, taxstoneEpisodes, joeBuddenEpisodes

    public static var active: [DriveDestination] { allCases }

    public var id: String {
        switch self {
        case .dubAudioClips: return "1FRi-yy2D9yenjQRailTA2iAbPaqAEPXm"
        case .dubVideoClips: return "1380CHJ3a3kl7fXNIKWqUM7_DeTZUwxsy"
        case .taxstoneClips: return "1bpHEdKPXQjjtoKp-L13KdITOT8Ep7JH8"
        case .joeBuddenClips: return "1X5VNP6fo3VpZPu4ZW4p7Ggk2o_IAVGSI"
        case .dubAudioEpisodes: return "109_QzHpF0Bi-OG6-AxuTDw1uHG4zeop3"
        case .dubVideoEpisodes: return "1GpuGWGIbSt3afwsi9L782soT9WJKOHS9"
        case .taxstoneEpisodes: return "1wQMwzUconRC3UCvH2jpL1kD__ctBv29p"
        case .joeBuddenEpisodes: return "1KJ0-sjGWNxwIuis_faA5z_FbPUcbjEDD"
        }
    }
    public var name: String {
        switch self {
        case .dubAudioClips: return "X Audio Clips"
        case .dubVideoClips: return "X Video Clips"
        case .taxstoneClips: return "Taxstone Clips"
        case .taxstoneEpisodes: return "Taxstone Full Episodes"
        case .joeBuddenClips: return "Joe Budden Clips"
        case .dubAudioEpisodes: return "Full X Audio Spaces"
        case .dubVideoEpisodes: return "Full X Broadcasts"
        case .joeBuddenEpisodes: return "Joe Budden Full Episodes"
        }
    }
    public var ancestorIDs: [String] {
        let content = ["18Ix3mVu8gCFSa-EGGpzQsh03SajrZvKm",DestinationResolver.dubRoot]
        switch self {
        case .dubAudioClips, .dubVideoClips, .dubAudioEpisodes, .dubVideoEpisodes:
            return ["1JQH012UFDeHukvigMf4dGxCoUgWvMc4U"] + content
        case .joeBuddenClips, .joeBuddenEpisodes:
            return ["1-HjL5kpENfWQm5jwshAhU3QM-THI6u53"] + content
        case .taxstoneClips, .taxstoneEpisodes:
            return ["1kxv3bbnPPRt914npHFUI51jrbCY0atyU"] + content
        }
    }
}

public struct FilingDestination: Codable, Equatable, Sendable {
    public let destination: DriveDestination
    public let asset: DriveAsset
    public let owner: FilingOwner
    public let sourceID: String
    public let sourceSHA256: String
    public var rootID: String { destination.id }
    var storedOwner: String { owner == .taxstone ? "taxstone" : "dub" }
}

public enum DestinationResolver {
    public static let dubRoot = "1owpGIsjztPdlIIVb7DaszgtlbgEwrJ0Q"
    /// Read-only conflict discovery. These are never new delivery destinations.
    public static let retiredClipRoots = ["1fgABGYTtNC_h2u-v6fwTcPkVKjFd7GQx","1_s2K9Pw2Je93IwazQ6QgLjz_SimVYuPz"]
    public static func requiresDUBRegister(_ request: JobRequest) -> Bool {
        request.owner == .dub && request.productionWorkflow != .joeBudden
    }
    public static func resolve(source: SourceRecord, request: JobRequest, asset: DriveAsset) throws -> FilingDestination {
        guard !source.id.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,
              source.id == request.sourceID, source.owner == request.owner,
              source.title == request.title, !source.title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,
              source.episodeDate == request.episodeDate,
              source.episodeDate == nil || request.dateEvidence?.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty == false,
              source.sha256.range(of:"^[a-f0-9]{64}$",options:.regularExpression) != nil,
              source.bytes > 0, source.duration.isFinite, source.duration > 0,
              !source.classificationEvidence.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else {
            throw JoeyError.invalid("Filing source identity, ownership, verified date, hash or inspected format is missing or conflicts with the saved request: \(source.id)")
        }
        if let expected = request.expectedSourceSHA256, expected != source.sha256 {
            throw JoeyError.invalid("Filing source hash differs from the authorized source identity")
        }
        if let url = source.originalURL, let suggested = SourceIdentitySuggestion.from(url), suggested != source.id {
            throw JoeyError.invalid("Filing source URL and source ID disagree")
        }
        let owner: FilingOwner
        // Preserve existing immutable request/source serialization. Joe's
        // verified workflow is the discriminator for historical DUB-owned jobs.
        if request.productionWorkflow == .joeBudden {
            guard source.owner == .dub, source.id.hasPrefix("youtube:"),
                  let url = request.originalURL, SourceIdentitySuggestion.from(url) == source.id,
                  source.originalURL == url else {
                throw JoeyError.invalid("Ambiguous Joe Budden filing identity; numbered official source verification is required")
            }
            owner = .joeBudden
        } else {owner = source.owner == .taxstone ? .taxstone : .dub}
        let destination: DriveDestination
        switch (owner,source.kind,asset) {
        case (.dub,.audio,.clip): destination = .dubAudioClips
        case (.dub,.nativeVideo,.clip): destination = .dubVideoClips
        case (.dub,.audio,.fullEpisode): destination = .dubAudioEpisodes
        case (.dub,.nativeVideo,.fullEpisode): destination = .dubVideoEpisodes
        case (.taxstone,_,.clip): destination = .taxstoneClips
        case (.taxstone,_,.fullEpisode): destination = .taxstoneEpisodes
        case (.joeBudden,_,.clip): destination = .joeBuddenClips
        case (.joeBudden,_,.fullEpisode): destination = .joeBuddenEpisodes
        }
        if asset == .fullEpisode, source.archiveReference == nil, let oldSelection = request.archiveRootID,
           oldSelection != destination.id,
           !(owner == .joeBudden && oldSelection == "1IIYLVDhCvwf5ZoMb0aM5vpSCe-eMCmyK") {
            throw JoeyError.invalid("Saved archive destination \(oldSelection) conflicts with authoritative \(destination.id); no file moved or uploaded")
        }
        return FilingDestination(destination:destination,asset:asset,owner:owner,sourceID:source.id,sourceSHA256:source.sha256)
    }
}
