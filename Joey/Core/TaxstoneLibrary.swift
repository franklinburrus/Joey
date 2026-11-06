import Foundation
import AppKit

public struct TaxstoneLibraryEpisode: Codable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var driveID: String
    public var sourceSHA256: String
    public var episodeDate: String?
    public var duration: Double?
    public var artworkURL: String?
    public var status = "READY"
    public var error: String?
    public var notes: [String] = []
    public var legacyClipCount = 0
    public var duplicateCount = 0
    public var acceptedClips = 0
    public var plannedClips = 0
    public var missingSeconds: Double?
    public var request: JobRequest?
    public var jobID: String?
    public var reuseCandidates: [TaxstoneReuseInput]?
}

/// Library ordering and operational intent only; jobs remain the sole media/delivery checkpoints.
public struct TaxstoneLibraryState: Codable, Sendable {
    public var enabled = false
    public var status = "Inventory not loaded"
    public var episodes: [TaxstoneLibraryEpisode] = []
    public var currentSourceID: String?
    public var error: String?
    public var inventoriedAt: Date?
    public var remoteOutputCount = 0
    public var uncertainOutputCount = 0
    public var discoveredCount: Int {episodes.count}
    public var completedCount: Int {episodes.filter {$0.status == "COMPLETED"}.count}
    public var remainingCount: Int {discoveredCount-completedCount}
    public var duplicateCount: Int {episodes.reduce(0) {$0+$1.duplicateCount}}
    public init() {}
}

private struct LegacyTechnicalReceipt: Codable {
    var id: String
    var md5: String
    var width: Int?
    var height: Int?
    var duration: Double?
    var checkedAt: Date
    var error: String?
    func incompatible(limit: Double) -> Bool {
        if let width,let height,width > height {return true}
        if let duration,duration > limit+0.075 {return true}
        return false
    }
}

public actor TaxstoneLibrary {
    public static let archiveRoot = DriveDestination.taxstoneEpisodes.id
    /// Existing originals remain discoverable here without relocation.
    public static let legacyArchiveRoot = "1wQMwzUconRC3UCvH2jpL1kD__ctBv29p"
    private let root: URL
    private var state: TaxstoneLibraryState
    private var running = false
    private let session: URLSession
    private let helperRunner: @Sendable (String, [String], Int) async throws -> ProcessResult
    private let loadEvidence: @Sendable () throws -> [TaxstoneEvidenceEntry]
    public init(root: URL) throws {
        try self.init(root:root,session:.shared,
            runHelper:{try await Processes.run($0,$1,maxOutput:$2)},loadEvidence:{try TaxstoneEvidence.load()})
    }
    /// Use the same read-only provider boundaries as DriveDelivery for isolated inventory checks.
    init(root: URL, session: URLSession,
         runHelper: @escaping @Sendable (String, [String], Int) async throws -> ProcessResult,
         loadEvidence: @escaping @Sendable () throws -> [TaxstoneEvidenceEntry]) throws {
        self.root = root
        self.session = session; self.helperRunner = runHelper; self.loadEvidence = loadEvidence
        let url = root.appendingPathComponent("taxstone-library.json")
        state = FileManager.default.fileExists(atPath:url.path) ? try Persistence.load(url) : TaxstoneLibraryState()
    }
    public func snapshot() -> TaxstoneLibraryState {state}
    private func save() throws {try Persistence.save(state,to:root.appendingPathComponent("taxstone-library.json"))}
    public func pause() throws {
        state.enabled = false; state.status = "PAUSED — progress retained"; try save()
    }
    public static func ordered(_ episodes: [TaxstoneLibraryEpisode]) -> [TaxstoneLibraryEpisode] {
        // Existing partial work first, then shortest known episode for bounded first acceptance,
        // followed by date and stable identity. The ordering is persisted and deterministic.
        episodes.sorted {
            let a = ($0.jobID == nil ? 1:0, $0.duration ?? Double.greatestFiniteMagnitude, $0.episodeDate ?? "", $0.id)
            let b = ($1.jobID == nil ? 1:0, $1.duration ?? Double.greatestFiniteMagnitude, $1.episodeDate ?? "", $1.id)
            return a < b
        }
    }
    public static func missing(duration: Double, exclusions: [Interval], accepted: [[Interval]]) throws -> Double {
        let retained = try Planning.retained(duration:duration,exclusions:exclusions)
        let ranges = accepted.flatMap {$0}.sorted {$0.start < $1.start}
        var end = -Double.infinity
        var covered = 0.0
        for range in ranges {
            guard range.start.isFinite,range.end.isFinite,range.duration > 0,range.start >= end,
                  retained.contains(where:{$0.start <= range.start && range.end <= $0.end}) else {
                throw JoeyError.invalid("Accepted coverage overlaps, lies outside retained source, or has invalid intervals")
            }
            covered += range.duration; end = range.end
        }
        return max(0,retained.reduce(0){$0+$1.duration}-covered)
    }
    public static func reconcile(_ episode: inout TaxstoneLibraryEpisode, job: JobRecord, directory: URL) throws {
        guard job.request.owner == .taxstone, job.request.mode == .fullShow,
              job.request.sourceID == episode.id, job.request.fileToDrive,
              job.planningBasis == .transcriptAssisted || (job.planningBasis == nil && job.clips.isEmpty) else {
            throw JoeyError.invalid("Existing Taxstone job does not match source identity and production contract")
        }
        if let source = job.source {
            guard source.id == episode.id,source.owner == .taxstone,source.sha256 == episode.sourceSHA256 else {
                throw JoeyError.invalid("Existing Taxstone inspected source differs from inventory identity")
            }
        } else {
            guard job.request.expectedSourceSHA256 == episode.sourceSHA256,
                  job.request.productionWorkflow == .taxstoneLibrary,job.clips.isEmpty,job.transcript == nil else {
                throw JoeyError.invalid("Uninspected Taxstone checkpoint is not bound to the inventoried original")
            }
        }
        try job.request.validate(requireCurrentCapability:false)
        episode.request = job.request; episode.jobID = job.id
        episode.plannedClips = job.clips.count
        let accepted = try job.clips.filter {clip in
            guard clip.qa?.passed == true, let hash = clip.sha256 else {return false}
            guard try Integrity.sha256(directory.appendingPathComponent(clip.filename)) == hash else {
                throw JoeyError.failed("Previously accepted output changed; preserve and reconcile: "+clip.filename)
            }
            return true
        }
        episode.acceptedClips = accepted.count
        if let source = job.source {
            episode.duration = source.duration
            episode.missingSeconds = try missing(duration:source.duration,exclusions:job.exclusions.map(\.interval),accepted:accepted.map(\.intervals))
        }
        episode.status = job.state == .completed ? "VERIFYING DELIVERY" : "RESUMABLE"
        episode.error = job.error
    }
    private func libraryLock() throws -> ProcessingLock {
        let directory = root.appendingPathComponent("taxstone-assets")
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        return try ProcessingLock(directory:directory)
    }
    public func inventory(progress: @escaping @Sendable (TaxstoneLibraryState) async -> Void = {_ in}) async throws -> TaxstoneLibraryState {
        guard !running else {throw JoeyError.dependency("Library is processing; pause before refreshing inventory")}
        let lock = try libraryLock();defer {withExtendedLifetime(lock) {}}
        return try await refreshInventory(progress:progress)
    }
    private func refreshInventory(progress: @escaping @Sendable (TaxstoneLibraryState) async -> Void) async throws -> TaxstoneLibraryState {
        state.status = "Reconciling archive and existing outputs";state.error = nil
        try save();await progress(state)
        let config = try Configuration.load(root:root)
        let provider = try DriveDelivery(remote:config.rcloneRemote,session:session,runHelper:helperRunner)
        let currentOriginals = try await provider.children(Self.archiveRoot)
        let legacyOriginals = try await provider.children(Self.legacyArchiveRoot)
        var seenOriginals = Set<String>()
        let original = (currentOriginals + legacyOriginals).filter {
            guard let id = $0["id"] as? String,$0["mimeType"] as? String != "application/vnd.google-apps.folder" else {return false}
            return seenOriginals.insert(id).inserted
        }
        let evidence = try loadEvidence()
        let byDrive = Dictionary(grouping:evidence,by:\.driveID)
        let outputListing = try await Processes.retry {
            try await self.helperRunner("rclone",["lsjson",config.rcloneRemote+":","--drive-root-folder-id",DriveDestination.taxstoneClips.id,"--recursive","--hash","--retries","1","--low-level-retries","1"],16*1024*1024)
        }
        let remoteObjects = try JSONSerialization.jsonObject(with:outputListing.stdout) as? [[String:Any]] ?? []
        let mediaObjects = remoteObjects.filter {($0["Name"] as? String ?? "").lowercased().hasSuffix(".mp4")}
        let knownIDs = Set(evidence.flatMap { $0.legacyClips.map(\.driveID) })
        state.remoteOutputCount = mediaObjects.count
        state.uncertainOutputCount = mediaObjects.filter {!knownIDs.contains($0["ID"] as? String ?? "")}.count
        try outputListing.stdout.write(to:root.appendingPathComponent("taxstone-legacy-drive-inventory.json"),options:.atomic)
        let appleURL = URL(string:"https://itunes.apple.com/lookup?id=978037629&entity=podcastEpisode&limit=200")!
        let (data,response) = try await session.data(from:appleURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with:data) as? [String:Any],
              let rows = json["results"] as? [[String:Any]] else {throw JoeyError.dependency("Tax Season episode identity/artwork feed unavailable")}
        let feed = Dictionary(grouping:rows.compactMap {row -> (String,[String:Any])? in
            guard row["collectionId"] as? Int == 978037629, let guid = row["episodeGuid"] as? String,
                  guid.hasPrefix("tag:soundcloud,2010:tracks/") else {return nil}
            return (String(guid.split(separator:"/").last!),row)
        },by:{$0.0})
        try data.write(to:root.appendingPathComponent("taxstone-provider-inventory.json"),options:.atomic)
        let jobs = try await Coordinator(root:root).jobs()
        let technicalURL = root.appendingPathComponent("taxstone-legacy-technical.json")
        var technical: [String:LegacyTechnicalReceipt] = (try? Persistence.load(technicalURL)) ?? [:]
        let legacyLimit = config.taxstoneProfile?.maxDuration ?? 140
        let listedPending = mediaObjects.compactMap {file -> String? in
            guard let id = file["ID"] as? String else {return nil}
            let md5 = (file["Hashes"] as? [String:String])?["md5"] ?? ""
            if let cached = technical[id],!md5.isEmpty,cached.md5 == md5 {return nil}
            return id
        }
        let otherIDs = knownIDs.filter {technical[$0]?.md5.isEmpty != false}
        let pending = Array(Set(listedPending).union(otherIDs)).sorted()
        for start in stride(from:0,to:pending.count,by:4) {
            try Task.checkCancellation()
            let batch = Array(pending[start..<min(start+4,pending.count)])
            let receipts = try await withThrowingTaskGroup(of:LegacyTechnicalReceipt.self) {group in
                for id in batch {group.addTask {
                    do {
                        let meta = try await provider.metadata(id)
                        let video = meta["videoMediaMetadata"] as? [String:Any] ?? [:]
                        return LegacyTechnicalReceipt(id:id,md5:meta["md5Checksum"] as? String ?? "",
                            width:video["width"] as? Int,height:video["height"] as? Int,
                            duration:(video["durationMillis"] as? String).flatMap(Double.init).map {$0/1000},checkedAt:Date())
                    } catch {
                        if error is CancellationError {throw error}
                        return LegacyTechnicalReceipt(id:id,md5:"",checkedAt:Date(),error:error.localizedDescription)
                    }
                }}
                var results: [LegacyTechnicalReceipt] = []
                for try await result in group {results.append(result)}
                return results
            }
            for receipt in receipts {technical[receipt.id] = receipt}
            try Persistence.save(technical,to:technicalURL)
            state.status = "Reconciling legacy media metadata: \(min(start+4,pending.count)) / \(pending.count) pending objects"
            try save();await progress(state)
        }
        try Persistence.save(technical,to:technicalURL)
        var episodes: [TaxstoneLibraryEpisode] = []
        var currentOutputIDs = Set<String>()
        for file in original where (file["mimeType"] as? String ?? "").hasPrefix("audio/") {
            try Task.checkCancellation()
            guard let driveID = file["id"] as? String else {continue}
            let mappings = byDrive[driveID] ?? []
            let metadata = try await provider.metadata(driveID)
            let hash = metadata["sha256Checksum"] as? String ?? ""
            guard mappings.count == 1, let entry = mappings.first else {
                episodes.append(TaxstoneLibraryEpisode(id:"drive:"+driveID,title:file["name"] as? String ?? driveID,
                    driveID:driveID,sourceSHA256:hash,status:"BLOCKED",error:"Archive has no unambiguous stable source mapping; filename alone is insufficient"))
                continue
            }
            let id = "soundcloud:"+entry.trackID
            let matches = feed[entry.trackID] ?? []
            let row = matches.count == 1 ? matches[0].1 : [:]
            var episode = state.episodes.first {$0.id == id} ?? TaxstoneLibraryEpisode(id:id,title:entry.title,driveID:driveID,sourceSHA256:hash)
            episode.status = "READY";episode.error = nil;episode.notes = entry.notes
            episode.episodeDate = (row["releaseDate"] as? String).map {String($0.prefix(10))} ?? entry.episodeDate
            episode.duration = entry.duration ?? (row["trackTimeMillis"] as? Double).map {$0/1000}
            episode.artworkURL = row["artworkUrl600"] as? String
            episode.legacyClipCount = Set(entry.legacyClips.map(\.driveID)).count
            episode.duplicateCount = Self.duplicateClips(entry.legacyClips)
            episode.missingSeconds = episode.duration
            if hash.count != 64 || (!episode.sourceSHA256.isEmpty && episode.sourceSHA256 != hash) ||
                (entry.sourceSHA256 != nil && entry.sourceSHA256 != hash) {
                episode.status = "BLOCKED";episode.error = "Archive source hash missing or differs from accepted identity"
            } else {episode.sourceSHA256 = hash}
            if matches.count != 1 || episode.artworkURL == nil {
                episode.status = "BLOCKED";episode.error = "Exact episode GUID and episode-specific artwork unresolved"
            }
            // Current checkpoint ownership precedes legacy classification. A
            // canonical Joey filename is not a legacy interval hint, and must
            // not hide an otherwise resumable or complete accepted package.
            let inventoryError = episode.status == "BLOCKED" ? episode.error : nil
            let matching = jobs.filter {$0.request.owner == .taxstone && $0.request.sourceID == id && $0.request.mode == .fullShow && $0.request.fileToDrive}
            var currentJob: JobRecord?
            var recognizedIDs = Set<String>()
            if matching.count > 1 {episode.status = "BLOCKED";episode.error = "Multiple production job identities require reconciliation; no new job created"}
            else if let job = matching.first {
                // Remote receipt ownership is independent of local cache
                // availability. A missing/changed cache can block recovery,
                // but cannot turn this verified provider identity into legacy.
                recognizedIDs = Self.currentOutputIDs(job:job,sourceID:id,sourceSHA256:hash,mediaObjects:mediaObjects)
                currentOutputIDs.formUnion(recognizedIDs)
                do {
                    try Self.reconcile(&episode,job:job,directory:root.appendingPathComponent("jobs/"+job.id))
                    currentJob = job
                } catch {episode.status = "BLOCKED";episode.error = error.localizedDescription}
            }
            if let inventoryError {episode.status = "BLOCKED";episode.error = inventoryError}
            // Metadata rules out known incompatible files. Other objects are
            // candidates only: actual source-audio and presentation QA is required.
            var candidates: [TaxstoneReuseInput] = []
            for clip in entry.legacyClips where !Self.knownIncompatible(clip) && technical[clip.driveID]?.incompatible(limit:legacyLimit) != true {
                guard let receipt = technical[clip.driveID],!receipt.md5.isEmpty else {
                    episode.status = "BLOCKED";episode.error = "Legacy object requires reconciliation: "+clip.driveID+"; "+(technical[clip.driveID]?.error ?? "current provider checksum missing");continue
                }
                candidates.append(TaxstoneReuseInput(driveID:clip.driveID,intervals:clip.intervals,
                    sourceSHA256:hash,md5:receipt.md5,evidence:clip.evidencePath))
            }
            let unknownRelated = mediaObjects.filter {file in
                !knownIDs.contains(file["ID"] as? String ?? "") && !recognizedIDs.contains(file["ID"] as? String ?? "") && technical[file["ID"] as? String ?? ""]?.incompatible(limit:legacyLimit) != true && (file["Path"] as? String ?? "").contains(entry.trackID)
            }
            var unresolved = 0
            for file in unknownRelated {
                let name = file["Name"] as? String ?? ""
                let prefix = "taxstone-"+entry.trackID+"-C"
                let sequence = name.hasPrefix(prefix) ? Int(name.dropFirst(prefix.count).prefix(2)) : nil
                let ledger = entry.legacyClips.filter {$0.sequence == sequence && sequence != nil}
                let unique = Set(ledger.map {$0.intervals.map {"\($0.start):\($0.end)"}.joined(separator:",")})
                if let id = file["ID"] as? String,let receipt = technical[id],!receipt.md5.isEmpty,
                   unique.count == 1,let reference = ledger.first {
                    candidates.append(TaxstoneReuseInput(driveID:id,intervals:reference.intervals,sourceSHA256:hash,md5:receipt.md5,
                        evidence:"CANDIDATE ONLY: filename selects sequence \(sequence!) in "+reference.evidencePath+"; source signal, episode artwork, waveform and current profile must independently pass QA before adoption"))
                } else {unresolved += 1}
            }
            if unresolved > 0 {
                episode.status = "BLOCKED";episode.error = "\(unresolved) legacy outputs have no resolvable candidate source intervals. Preserved; no duplicate rendering."
            }
            episode.reuseCandidates = candidates
            if !candidates.isEmpty {episode.notes.append("\(candidates.count) legacy candidates require full source/presentation QA before adoption; candidate filenames are not acceptance evidence.")}
            let blockingError = episode.status == "BLOCKED" ? episode.error : nil
            if let job = currentJob,job.state == .completed {
                do {
                    try await verifyDelivery(job,provider:provider);episode.status = "COMPLETED";episode.error = nil
                } catch {episode.status = "BLOCKED";episode.error = error.localizedDescription}
            }
            if let blockingError {episode.status = "BLOCKED";episode.error = blockingError}
            episodes.append(episode)
        }
        guard !episodes.isEmpty,Set(episodes.map(\.id)).count == episodes.count else {throw JoeyError.failed("Empty or duplicate Taxstone archive inventory")}
        // Reconcile current Joey packages: never recreate a source whose remote
        // package exists without its local job checkpoint.
        var folders = try await provider.children(DriveDestination.taxstoneClips.id)
        for retired in DestinationResolver.retiredClipRoots {folders += try await provider.children(retired)}
        for folder in folders {
            let props = folder["appProperties"] as? [String:String] ?? [:]
            guard props["joeyOwner"] == "taxstone",let source = props["joeySourceID"],let i = episodes.firstIndex(where:{$0.id == source}) else {continue}
            if episodes[i].jobID == nil {episodes[i].status = "BLOCKED";episodes[i].error = "Existing Joey Drive package requires checkpoint recovery; no duplicate production"}
        }
        state.uncertainOutputCount = mediaObjects.filter {
            let id = $0["ID"] as? String ?? ""
            return !knownIDs.contains(id) && !currentOutputIDs.contains(id)
        }.count
        state.episodes = Self.ordered(episodes); state.inventoriedAt = Date()
        state.status = "Inventory reconciled — \(state.remainingCount) episodes remaining"
        try save();await progress(state);return state
    }
    /// This recognizes ownership only. Historical receipts can omit the later
    /// destination field, but an explicit conflicting destination is rejected.
    /// Completion still requires the full independent package readback, and
    /// partial jobs still resume delivery.
    static func currentOutputIDs(job: JobRecord, sourceID: String, sourceSHA256: String,
                                 mediaObjects: [[String:Any]]) -> Set<String> {
        guard job.request.owner == .taxstone,job.request.sourceID == sourceID,
              job.request.mode == .fullShow,job.request.fileToDrive,
              let source = job.source,source.owner == .taxstone,source.id == sourceID,
              source.sha256 == sourceSHA256,sourceSHA256.count == 64,
              let folder = job.folderID,!folder.isEmpty,
              let route = try? DestinationResolver.resolve(source:source,request:job.request,asset:.clip) else {return []}
        let listing = Dictionary(grouping:mediaObjects,by:{$0["ID"] as? String ?? ""})
        let receipts = Dictionary(grouping:job.clips.compactMap(\.drive),by:\.id)
        return Set(job.clips.compactMap {clip in
            guard let receipt = clip.drive,!receipt.id.isEmpty,receipts[receipt.id]?.count == 1,
                  clip.qa?.passed == true,let hash = clip.sha256,hash.count == 64,
                  clip.qa?.outputSHA256 == hash,receipt.sha256 == hash,
                  let bytes = clip.bytes,bytes > 0,receipt.bytes == bytes,
                  receipt.name == clip.filename,receipt.parent == folder,
                  receipt.destination == nil || receipt.destination == route,
                  let md5 = receipt.md5,md5.count == 32,
                  let objects = listing[receipt.id],objects.count == 1,let file = objects.first,
                  file["Name"] as? String == clip.filename,
                  (file["Size"] as? NSNumber)?.int64Value == bytes,
                  (file["Hashes"] as? [String:String])?["md5"] == md5 else {return nil}
            return receipt.id
        })
    }
    public static func knownIncompatible(_ clip: TaxstoneLegacyClip) -> Bool {
        if let fps = clip.fps, fps < 30 {return true}
        if let width = clip.width,let height = clip.height,width > height {return true}
        return false
    }
    public static func duplicateClips(_ clips: [TaxstoneLegacyClip]) -> Int {
        let groups = Dictionary(grouping:clips,by:{$0.intervals.map {"\($0.start):\($0.end)"}.joined(separator:",")})
        return groups.values.reduce(0) {$0+max(0,Set($1.map(\.driveID)).count-1)}
    }
    private func verifyDelivery(_ job: JobRecord, provider: DriveDelivery) async throws {
        guard let source = job.source,let folder = job.folderID,job.unavailableTranscriptFeatures.isEmpty,
              !job.clips.isEmpty,job.companions.count >= 4 else {throw JoeyError.failed("Completed episode lacks delivery evidence")}
        try Planning.validateCoverage(duration:source.duration,exclusions:job.exclusions.map(\.interval),clips:job.clips.map(\.intervals))
        _ = folder
        try await provider.verifyPackage(job:job,directory:root.appendingPathComponent("jobs/"+job.id))
    }
    private func prepare(_ episode: TaxstoneLibraryEpisode, config: Configuration) async throws -> JobRequest {
        if let request = episode.request {return try config.renewingCapabilities(in:request)}
        guard let profile = config.taxstoneProfile else {throw JoeyError.dependency("Taxstone X/Instagram account evidence is missing; DUB's profile cannot authorize Taxstone")}
        try profile.validate()
        guard let raw = episode.artworkURL, let url = URL(string:raw),url.scheme == "https",
              url.host?.hasSuffix("mzstatic.com") == true else {throw JoeyError.dependency("Verified episode artwork URL missing")}
        let directory = root.appendingPathComponent("taxstone-assets/"+episode.id.replacingOccurrences(of:":",with:"-"))
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let receiptURL = directory.appendingPathComponent("artwork-receipt.json")
        let receipt: Artwork? = try? Persistence.load(receiptURL)
        let art: Artwork
        if let receipt,receipt.sourceID == episode.id,receipt.driveID == raw,receipt.owner == .taxstone,
           (try? receipt.file.validate()) != nil {
            art = receipt
        } else {
            let (data,response) = try await URLSession.shared.data(from:url)
            guard (response as? HTTPURLResponse)?.statusCode == 200,data.count < 20_000_000,NSImage(data:data) != nil else {
                throw JoeyError.dependency("Episode artwork download is not a supported image")
            }
            // New versioned file: never relabel or overwrite accepted artwork.
            let target = directory.appendingPathComponent("episode-art-"+UUID().uuidString+".jpg")
            try data.write(to:target,options:.atomic)
            art = Artwork(owner:.taxstone,sourceID:episode.id,driveID:raw,
                file:EvidenceFile(path:target.path,sha256:try Integrity.sha256(target),basis:"Tax Season collection 978037629 exact episode GUID "+episode.id+"; provider artwork "+raw))
            try Persistence.save(art,to:receiptURL)
        }
        let archive = "https://drive.google.com/file/d/"+episode.driveID+"/view"
        let request = JobRequest(owner:.taxstone,sourceID:episode.id,title:episode.title,episodeDate:episode.episodeDate,
            dateEvidence:"Tax Season episode GUID and historical source ledger",originalURL:archive,
            authorizationBasis:"Frank authorized Taxstone Library production and Drive delivery",archiveReference:archive,
            expectedSourceSHA256:episode.sourceSHA256,taxstoneReuse:episode.reuseCandidates,artwork:art,profile:profile,fileToDrive:true,productionWorkflow:.taxstoneLibrary)
        try request.validate();return request
    }
    public func run(limit: Int? = nil, progress: @escaping @Sendable (TaxstoneLibraryState) async -> Void = {_ in},
                    jobProgress: @escaping @Sendable (JobRecord) async -> Void = {_ in},
                    betweenEpisodes: @escaping @Sendable () async -> Void = {}) async throws -> TaxstoneLibraryState {
        guard !running else {throw JoeyError.dependency("Taxstone Library already running")}
        // Refresh before every activation; no completed flag is trusted without readback.
        let lock = try libraryLock();defer {withExtendedLifetime(lock) {}}
        running = true;defer {running = false}
        _ = try await refreshInventory(progress:progress)
        try Task.checkCancellation()
        state.enabled = true;state.status = "PROCESSING";try save();await progress(state)
        let config = try Configuration.load(root:root)
        let coordinator = try Coordinator(root:root)
        var attempts = 0
        do {
            for index in state.episodes.indices {
                try Task.checkCancellation()
                guard state.enabled else {break}
                if let limit,attempts >= limit {break}
                if ["COMPLETED","BLOCKED"].contains(state.episodes[index].status) {continue}
                attempts += 1;state.currentSourceID = state.episodes[index].id
                do {
                    let request = try await prepare(state.episodes[index],config:config)
                    try Task.checkCancellation();guard state.enabled else {break}
                    state.episodes[index].request = request;state.episodes[index].status = "PROCESSING";try save();await progress(state)
                    let job = try await coordinator.run(request,estimatedDuration:state.episodes[index].duration) {job in
                        try await self.update(job)
                        await progress(await self.snapshot());await jobProgress(job)
                    }
                    try update(job)
                    if job.state == .completed {
                        try await verifyDelivery(job,provider:DriveDelivery(remote:config.rcloneRemote))
                        state.episodes[index].status = "COMPLETED"
                    } else {state.episodes[index].status = "INCOMPLETE"}
                } catch {
                    if error is CancellationError {throw error}
                    state.episodes[index].status = "BLOCKED";state.episodes[index].error = error.localizedDescription
                }
                try save();await progress(state)
                // Let the existing Joe queue use the same serial processor
                // between episodes; a long library must not starve monitoring work.
                await betweenEpisodes()
            }
            state.enabled = false;state.currentSourceID = nil
            state.status = state.remainingCount == 0 ? "COMPLETED — all episode deliveries verified" : "PAUSED — \(state.remainingCount) episodes remain; inspect details or Resume"
            try save();await progress(state);return state
        } catch {
            state.enabled = false;state.status = "PAUSED — progress retained";state.error = error is CancellationError ? nil:error.localizedDescription
            try save();await progress(state);throw error
        }
    }
    private func update(_ job: JobRecord) throws {
        guard let i = state.episodes.firstIndex(where:{$0.id == job.request.sourceID}) else {return}
        state.episodes[i].jobID = job.id;state.episodes[i].request = job.request
        state.episodes[i].plannedClips = job.clips.count
        state.episodes[i].acceptedClips = job.clips.filter {$0.qa?.passed == true}.count
        state.episodes[i].status = job.state == .completed ? "VERIFYING DELIVERY" : job.stage
        state.episodes[i].error = job.error
        if let source = job.source {state.episodes[i].duration = source.duration
            state.episodes[i].missingSeconds = try Self.missing(duration:source.duration,exclusions:job.exclusions.map(\.interval),accepted:job.clips.filter {$0.qa?.passed == true}.map(\.intervals))}
        try save()
    }
}
