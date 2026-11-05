import Foundation

public struct DubBroadcast: Codable, Equatable, Sendable {
    public var source: DiscoveredSource
    public var broadcasterID: String
    public var startedAt: Double?
    public var verifiedAt: Date
}

public enum DubBroadcastDiscovery {
    public static let accountURL = "https://x.com/TheFilesWithDUB"
    // Verified against the original reference broadcast's linked original post,
    // whose User.rest_id and legacy.screen_name agree. Handles can change.
    public static let broadcasterID = "1633447924565680129"

    public static func originalURL(_ raw: String) throws -> String {
        let url = try Acquisition.validateOriginalURL(raw.trimmingCharacters(in:.whitespacesAndNewlines))
        guard let id = SourceIdentitySuggestion.from(url.absoluteString),id.hasPrefix("x:broadcast:"),
              let component = id.split(separator:":").last,
              component.range(of:"^[A-Za-z0-9]+$",options:.regularExpression) != nil,
              url.path == "/i/broadcasts/"+component else {
            throw JoeyError.invalid("Supply an original https://x.com/i/broadcasts/BROADCAST_ID URL")
        }
        return "https://x.com/i/broadcasts/"+component
    }

    public static func lookup(_ raw: String) async throws -> DubBroadcast {
        let url = try originalURL(raw)
        let id = String(url.split(separator:"/").last!)
        // yt-dlp's supported extractor omits twitter_user_id from normalized
        // metadata. Its raw broadcast response supplies that required identity.
        // All response dumps, including ephemeral guest/session data, remain in
        // this private temporary directory and are removed before returning.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("joey-dub-lookup-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        defer {try? FileManager.default.removeItem(at:directory)}
        let result = try await Processes.retry {
            try await Processes.run("yt-dlp",["--ignore-config","--no-playlist","--skip-download","--dump-single-json","--write-pages",
                "--socket-timeout","15","--retries","0","--extractor-retries","0",url],directory:directory,maxOutput:4*1024*1024,timeout:90)
        }
        guard let metadata = try JSONSerialization.jsonObject(with:result.stdout) as? [String:Any] else {
            throw JoeyError.failed("Original broadcast metadata is malformed")
        }
        let source = try await SourceDiscovery.parseSource(result.stdout,url:url)
        let dumps = try FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:[.fileSizeKey])
            .filter {$0.lastPathComponent.contains("broadcasts_show.json") && $0.pathExtension == "dump"}
        guard dumps.count == 1,let file = dumps.first,
              (try file.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? Int.max) <= 4*1024*1024,
              let object = try JSONSerialization.jsonObject(with:Data(contentsOf:file)) as? [String:Any],
              let broadcasts = object["broadcasts"] as? [String:Any],let broadcast = broadcasts[id] as? [String:Any] else {
            throw JoeyError.dependency("Supported extractor supplied no unique original broadcaster evidence; source not admitted")
        }
        return try verify(source:source,metadata:metadata,broadcast:broadcast)
    }

    static func verify(source: DiscoveredSource, metadata: [String:Any], broadcast: [String:Any]) throws -> DubBroadcast {
        let url = try originalURL(source.url)
        let id = String(url.split(separator:"/").last!)
        guard source.id == "x:broadcast:"+id,metadata["id"] as? String == id,
              broadcast["id"] as? String == id,
              broadcast["twitter_user_id"] as? String == broadcasterID,
              broadcast["state"] as? String == "ENDED",broadcast["available_for_replay"] as? Bool == true,
              broadcast["is_locked"] as? Bool != true,
              metadata["is_live"] as? Bool == false,metadata["live_status"] as? String == "was_live",
              source.duration.isFinite,source.duration > 0 else {
            throw JoeyError.dependency("Original Dub broadcaster, completed broadcast identity or accessible full replay could not be verified")
        }
        let start = (broadcast["start_ms"] as? String).flatMap(Double.init).map {$0/1000}
        let timestamp = start.flatMap {$0.isFinite && $0 > 0 ? $0:nil}
        var verified = source
        verified.url = url
        verified.channelID = broadcasterID
        if let timestamp {
            let formatter = DateFormatter();formatter.locale = Locale(identifier:"en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT:0);formatter.dateFormat = "yyyy-MM-dd"
            verified.episodeDate = formatter.string(from:Date(timeIntervalSince1970:timestamp))
        }
        return DubBroadcast(source:verified,broadcasterID:broadcasterID,startedAt:timestamp,verifiedAt:Date())
    }

    public static func request(_ broadcast: DubBroadcast) throws -> JobRequest {
        guard broadcast.broadcasterID == broadcasterID else {throw JoeyError.invalid("Wrong broadcast owner")}
        let source = broadcast.source
        let request = JobRequest(owner:.dub,sourceID:source.id,title:source.title,episodeDate:source.episodeDate,
            dateEvidence:source.episodeDate == nil ? nil:"Original X broadcast metadata for "+source.url,
            originalURL:try originalURL(source.url),
            authorizationBasis:"Frank authorized manual Check Now ingestion of original TheFilesWithDUB broadcasts; verified X broadcaster "+broadcasterID,
            expectedDuration:source.duration,profile:.dubBroadcastMaster,productionWorkflow:.dubBroadcast)
        try request.validate()
        return request
    }
}

public struct DubBroadcastEntry: Codable, Equatable, Identifiable, Sendable {
    public var broadcast: DubBroadcast
    public var request: JobRequest
    public var jobID: String?
    public var state: JobState = .planned
    public var error: String?
    public var recoveryIssue: String?
    public var heldByUser: Bool?
    public var id: String {broadcast.source.id}
}

public struct DubBroadcastState: Codable, Sendable {
    public var urls: [String] = []
    public var entries: [DubBroadcastEntry] = []
    public var lastCheckedAt: Date?
    public var lastError: String?
    public var discoveryStartDate: String?
    public var discoveryStatus: String?
    public var newCount = 0
    public var paused = false
    public var currentID: String?
    public var hasRunnableWork: Bool { !paused && entries.contains {$0.heldByUser != true && ($0.state == .planned || $0.state == .processing || $0.state == .filed || ($0.state == .qaPassed && $0.error == nil))} }
    public init() {}
}

/// Discovery intent and ordering only. Coordinator job.json remains the sole
/// authority for originals, transcripts, accepted media and provider receipts.
public actor DubBroadcastQueue {
    private let root: URL
    private let ownership: ProcessingLock
    private var state: DubBroadcastState
    private var checking = false
    private var running = false
    public init(root: URL) throws {
        self.root = root
        ownership = try ProcessingLock(directory:root,name:"dub-broadcasts.lock")
        let file = root.appendingPathComponent("dub-broadcasts.json")
        state = FileManager.default.fileExists(atPath:file.path) ? try Persistence.load(file):DubBroadcastState()
        state.currentID = nil
    }
    public func snapshot() -> DubBroadcastState {state}
    public func recover(jobs: [JobRecord]) throws {
        reconcile(jobs)
        try save()
    }
    private func save() throws {
        do {try Persistence.save(state,to:root.appendingPathComponent("dub-broadcasts.json"))}
        catch {state.paused = true;throw error}
    }
    public func pause() throws {state.paused = true;try save()}
    public func resume() throws {
        state.paused = false
        for index in state.entries.indices where state.entries[index].state != .completed {
            if state.entries[index].recoveryIssue == nil,state.entries[index].heldByUser != true {state.entries[index].state = .planned}
        }
        try save()
    }
    public func checkNow(urls: [String], jobs: [JobRecord], discoveredURLs: [String] = [], discoveryStatus: String? = nil,
                         lookup: @Sendable (String) async throws -> DubBroadcast = {try await DubBroadcastDiscovery.lookup($0)}) async throws {
        guard !checking else {return}
        try Task.checkCancellation()
        checking = true;defer {checking = false}
        reconcile(jobs)
        state.lastCheckedAt = Date();state.newCount = 0;state.lastError = nil
        state.discoveryStatus = discoveryStatus ?? state.discoveryStatus
        var errors: [String] = []
        var supplied = Set(state.urls)
        for raw in urls where !raw.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {
            do {supplied.insert(try DubBroadcastDiscovery.originalURL(raw))}
            catch {errors.append(error.localizedDescription)}
        }
        state.urls = supplied.sorted()
        state.paused = false
        try save()
        var verified: [DubBroadcast] = []
        let candidates = Array(Set(state.urls + discoveredURLs.compactMap {try? DubBroadcastDiscovery.originalURL($0)})).sorted()
        for url in candidates {
            try Task.checkCancellation()
            do {
                let broadcast = try await lookup(url)
                guard broadcast.source.url == url else {throw JoeyError.invalid("Discovered original URL changed")}
                _ = try DubBroadcastDiscovery.request(broadcast)
                verified.append(broadcast)
            } catch {
                if error is CancellationError {throw error}
                errors.append(url+" — "+error.localizedDescription)
            }
        }
        if state.discoveryStartDate == nil,!discoveredURLs.isEmpty {
            state.discoveryStartDate = (verified.compactMap { $0.source.episodeDate } + state.entries.compactMap {$0.broadcast.source.episodeDate}).max()
        }
        for broadcast in verified {
            let explicit = state.urls.contains(broadcast.source.url)
            if !explicit,let date = broadcast.source.episodeDate,let start = state.discoveryStartDate,date < start {continue}
            do {
                let request = try DubBroadcastDiscovery.request(broadcast)
                if let index = state.entries.firstIndex(where:{$0.id == broadcast.source.id}) {
                    // Discovery cannot replace the immutable production request.
                    // Retry failed work only through this explicit Check Now intent.
                    if state.entries[index].recoveryIssue == nil,state.entries[index].heldByUser != true, state.entries[index].state == .failed || state.entries[index].state == .cancelled || state.entries[index].state == .qaPassed {
                        state.entries[index].state = .planned
                    }
                } else {
                    var entry = DubBroadcastEntry(broadcast:broadcast,request:request)
                    let prior = jobs.filter {$0.request.owner == .dub && $0.request.sourceID == broadcast.source.id && $0.request.mode == .fullShow}
                    let completed = prior.filter {$0.state == .completed && $0.hasRequiredCompletionEvidence}
                    if let done = completed.first {
                        entry.request = done.request;entry.jobID = done.id;entry.state = .completed
                    } else if prior.count == 1,let saved = prior.first {
                        guard saved.request.productionWorkflow == .dubBroadcast else {
                            throw JoeyError.dependency("Existing incomplete broadcast uses a different export contract. Resume its saved job before admitting a native-master replacement: "+saved.id)
                        }
                        entry.request = saved.request;entry.jobID = saved.id
                    } else if !prior.isEmpty {throw JoeyError.dependency("Multiple saved broadcast jobs require identity reconciliation")}
                    state.entries.append(entry);state.newCount += entry.state == .completed ? 0:1
                }
            } catch {
                errors.append(broadcast.source.url+" — "+error.localizedDescription)
            }
        }
        state.entries.sort {
            // Known dates precede unknown dates. Never manufacture a timestamp.
            let a = ($0.broadcast.source.episodeDate ?? "9999",$0.broadcast.startedAt ?? .greatestFiniteMagnitude,$0.id)
            let b = ($1.broadcast.source.episodeDate ?? "9999",$1.broadcast.startedAt ?? .greatestFiniteMagnitude,$1.id)
            return a < b
        }
        state.lastError = errors.isEmpty ? nil:errors.joined(separator:"\n")
        try save()
    }

    private func reconcile(_ jobs: [JobRecord]) {
        for index in state.entries.indices {
            let entry = state.entries[index]
            let matches = jobs.filter {job in
                if let id = entry.jobID {return job.id == id}
                return job.request.owner == .dub && job.request.sourceID == entry.id && job.request.mode == .fullShow
            }
            var issue: String?
            if matches.count > 1 {issue = "Multiple broadcast checkpoints require identity reconciliation"}
            else if let job = matches.first {
                if (try? job.request.identityData()) != (try? entry.request.identityData()) {
                    issue = "Saved queue request conflicts with its broadcast checkpoint"
                } else if job.state == .completed {
                    if job.hasRequiredCompletionEvidence {
                        state.entries[index].state = .completed;state.entries[index].error = nil
                    } else {issue = "Completed broadcast checkpoint lacks required completion evidence"}
                } else if entry.state == .completed {
                    issue = "Completed queue entry disagrees with its broadcast checkpoint"
                }
                state.entries[index].jobID = job.id
            } else if entry.jobID != nil || entry.state == .completed {
                issue = "Saved broadcast checkpoint is missing; restore it before resuming. No replacement job created."
            }
            state.entries[index].recoveryIssue = issue
            if let issue {state.entries[index].state = .failed;state.entries[index].error = issue}
        }
    }

    public func run(jobs: [JobRecord],
                    process: @Sendable (JobRequest) async throws -> JobRecord,
                    progress: @Sendable (DubBroadcastState) async -> Void = {_ in}) async throws {
        guard !running,!checking,!state.paused else {return}
        reconcile(jobs)
        try save()
        running = true;defer {running = false}
        // Check Now may append work during an await. Include those entries on
        // this pass, but attempt each identity at most once per explicit turn.
        var attempted = Set<String>()
        while !state.paused,!checking,!Task.isCancelled,
              let index = state.entries.indices.first(where:{ state.entries[$0].heldByUser != true && !attempted.contains(state.entries[$0].id) && state.entries[$0].state != .completed && state.entries[$0].state != .failed && state.entries[$0].state != .cancelled }) {
            let id = state.entries[index].id
            let request = state.entries[index].request
            attempted.insert(id)
            state.currentID = id;state.entries[index].state = .processing
            try save();await progress(state)
            do {
                let result = try await process(request)
                guard result.request.sourceID == id else {throw JoeyError.failed("Processing returned a different broadcast identity")}
                let current = state.entries.firstIndex {$0.id == id}!
                state.entries[current].jobID = result.id
                state.entries[current].state = result.state == .completed && !result.hasRequiredCompletionEvidence ? .failed:result.state
                state.entries[current].error = result.error ?? (result.state == .completed && result.hasRequiredCompletionEvidence ? nil:"Broadcast remains incomplete; saved stages retained")
            } catch {
                let current = state.entries.firstIndex {$0.id == id}!
                state.entries[current].state = error is CancellationError ? .cancelled:.failed
                state.entries[current].error = error is CancellationError ? "Cancelled; accepted work retained":error.localizedDescription
                if error is CancellationError {state.paused = true}
            }
            state.currentID = nil
            try save();await progress(state)
        }
    }
}
