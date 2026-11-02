import Foundation

/// Email carries source links only. All source identity and request validation
/// remain in the existing media intake, before any downloader is invoked.
public struct EmailSource: Codable, Equatable, Sendable {
    public let id: String
    public let url: String
    public init(_ raw: String) throws {
        let parsed = try Acquisition.validateOriginalURL(raw)
        guard raw.utf8.count <= 2048, let id = SourceIdentitySuggestion.from(raw),
              let components = URLComponents(url:parsed,resolvingAgainstBaseURL:false) else {
            throw JoeyError.invalid("Unsupported source identity")
        }
        let parts = parsed.path.split(separator:"/").map(String.init)
        if id.hasPrefix("youtube:") {
            guard (components.queryItems ?? []).filter({$0.name == "v"}).count <= 1 else {
                throw JoeyError.invalid("Ambiguous YouTube identity")
            }
            self.url = "https://www.youtube.com/watch?v=" + id.dropFirst(8)
        } else if id.hasPrefix("x:broadcast:") || id.hasPrefix("x:space:") {
            guard parts.count == 3, parts[0] == "i" else {throw JoeyError.invalid("Unsupported X source path")}
            self.url = "https://x.com/i/" + (id.hasPrefix("x:space:") ? "spaces/":"broadcasts/") + parts[2]
        } else {
            guard parts.count == 3, parts[1] == "status",
                  parts[0].range(of:"^[A-Za-z0-9_]+$",options:.regularExpression) != nil,
                  parts[2].allSatisfy(\.isNumber) else {throw JoeyError.invalid("Unsupported X post path")}
            self.url = "https://x.com/" + parts[0] + "/status/" + parts[2]
        }
        self.id = id
    }
}

public struct EmailWorkflow: Codable, Equatable, Sendable {
    public var content: LinkContent = .dub
    public var mode: JobMode = .fullShow
    public var archiveRoot: String = ""
    public init() {}
    public func validated() throws -> Self {
        var copy = self
        copy.archiveRoot = archiveRoot.trimmingCharacters(in:.whitespacesAndNewlines)
        guard copy.archiveRoot.isEmpty || copy.archiveRoot.range(of:"^[A-Za-z0-9_-]{10,200}$",options:.regularExpression) != nil else {
            throw JoeyError.invalid("Archive folder must be an existing Drive folder ID")
        }
        if copy.content == .joeBudden {copy.mode = .fullShow}
        return copy
    }
}

public struct EmailIntakeSettings: Codable, Equatable, Sendable {
    public static let alias = "uploadtojoey@icloud.com"
    public var account = ""
    public var allowedSenders: [String] = []
    public var workflow = EmailWorkflow()
    public init() {}
    public func validated() throws -> Self {
        var copy = self
        copy.account = account.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()
        copy.allowedSenders = Array(Set(allowedSenders.map {$0.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()})).sorted()
        let address = "^[a-z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?$"
        guard copy.account.count <= 254, copy.account.range(of:address,options:.regularExpression) != nil,
              ["icloud.com","me.com","mac.com"].contains(String(copy.account.split(separator:"@").last ?? "")),
              !copy.allowedSenders.isEmpty, copy.allowedSenders.count <= 20,
              copy.allowedSenders.allSatisfy({$0.count <= 254 && $0.range(of:address,options:.regularExpression) != nil}) else {
            throw JoeyError.invalid("Enter the primary iCloud Mail address and 1–20 complete allowed sender addresses")
        }
        return copy
    }
}

public struct EmailMessage: Codable, Sendable {
    public var uid: UInt64
    public var status: String
    public var reason: String
    public var links: [String]
    public init(uid: UInt64, status: String, reason: String, links: [String]) {
        self.uid = uid; self.status = status; self.reason = reason; self.links = links
    }
}
public struct EmailScan: Codable, Sendable {
    public var uidValidity: UInt64
    public var uidNext: UInt64
    public var frontier: UInt64
    public var messages: [EmailMessage]
    public init(uidValidity: UInt64, uidNext: UInt64, frontier: UInt64, messages: [EmailMessage]) {
        self.uidValidity = uidValidity; self.uidNext = uidNext; self.frontier = frontier; self.messages = messages
    }
    func validate() throws {
        guard uidValidity > 0, uidValidity <= UInt32.max, uidNext > 0, uidNext <= UInt32.max,
              frontier <= UInt32.max, messages.count <= 50,
              Set(messages.map(\.uid)).count == messages.count,
              messages.allSatisfy({$0.uid > 0 && $0.uid <= frontier && $0.uid < uidNext && $0.links.count <= 100}) else {
            throw JoeyError.failed("Invalid bounded mailbox result")
        }
    }
}
public struct EmailBaseline: Codable, Sendable {
    public var account: String
    public var mailbox = "INBOX"
    public var uidValidity: UInt64
    public var frontier: UInt64
    public var activatedAt: Date
}
public struct EmailReceipt: Codable, Identifiable, Sendable {
    public var id: String
    public var account: String
    public var receivedAt: Date
    public var status: String
    public var reason: String
    public var sources: [EmailSource]
    public var workIDs: [String]
}
public enum EmailWorkStatus: String, Codable, Sendable {
    case queued, running, retryable, cancelled, completed
}
public struct EmailWork: Codable, Identifiable, Sendable {
    public var id: String
    public var account: String
    public var source: EmailSource
    public var workflow: EmailWorkflow
    public var request: JobRequest?
    public var jobID: String?
    public var status: EmailWorkStatus = .queued
    public var reason: String?
    public var attempts = 0
    public var retryAt: Date?
    public var retryRequested: Bool?
    /// Only a local Process action creates this intent. Old ledgers omit it.
    public var processingRequested: Bool?
}
public struct EmailIntakeState: Codable, Sendable {
    public var version = 2
    public var settings = EmailIntakeSettings()
    public var enabled = false
    public var baselines: [EmailBaseline] = []
    public var receipts: [EmailReceipt] = []
    public var work: [EmailWork] = []
    public var lastCheckedAt: Date?
    public var lastError: String?
    public var failures = 0
    public var nextCheckAt: Date?
    public var requiresAuthentication = false
    public var requiresResynchronization = false
    public init() {}
    public var currentBaseline: EmailBaseline? {baselines.first {$0.account == settings.account && $0.mailbox == "INBOX"}}
    public var pendingCount: Int {
        work.filter {$0.status != .completed && $0.status != .cancelled}.count + receipts.filter {$0.status == "pendingAuthorization"}.count
    }
    public var capacity: Int {max(0,100-pendingCount)}
    public func nextRequestedWork(now: Date = Date()) -> EmailWork? {
        work.first {$0.processingRequested == true && ($0.status == .queued || $0.status == .retryable) && ($0.retryAt ?? .distantPast) <= now}
    }
}

/// The application owns an email-only lock for this store's lifetime. It never
/// holds the media-processing lock during IMAP. Every mutation saves one full
/// snapshot before exposing the new cursor/queue in memory.
public final class EmailIntakeStore {
    public let url: URL
    public private(set) var state: EmailIntakeState
    public init(root: URL) throws {
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        url = root.appendingPathComponent("email-intake.json")
        state = FileManager.default.fileExists(atPath:url.path) ? try Persistence.load(url):EmailIntakeState()
        guard [1,2].contains(state.version), Set(state.work.map(\.id)).count == state.work.count else {
            throw JoeyError.failed("Saved email state is incompatible; preserve email-intake.json for recovery")
        }
        if state.version == 1 {
            // Upgrade in memory; the next atomic mutation writes version 2.
            // Initialization precedes the caller's lease, so never write here.
            // Version 1 binaries reject version 2 instead of auto-running it.
            state.version = 2
            for index in state.work.indices {
                state.work[index].processingRequested = nil
                state.work[index].retryRequested = nil
            }
        }
    }
    public func lock() throws -> ProcessingLock {try ProcessingLock(directory:url.deletingLastPathComponent(),name:"email-intake.lock")}
    private func commit(_ next: EmailIntakeState) throws {
        try Persistence.save(next,to:url)
        state = next
    }
    public func configure(_ settings: EmailIntakeSettings) throws {
        let settings = try settings.validated()
        var next = state
        if settings != next.settings {next.enabled = false; next.lastCheckedAt = nil}
        if settings.account != next.settings.account {next.requiresResynchronization = false}
        next.settings = settings; next.requiresAuthentication = false; next.lastError = nil
        next.failures = 0; next.nextCheckAt = nil
        try commit(next)
    }
    public func activate(_ scan: EmailScan, replaceBaseline: Bool = false) throws {
        try scan.validate()
        var next = state
        if next.currentBaseline == nil || replaceBaseline {
            next.baselines.removeAll {$0.account == next.settings.account}
            next.baselines.append(EmailBaseline(account:next.settings.account,uidValidity:scan.uidValidity,frontier:scan.uidNext-1,activatedAt:Date()))
        } else if next.currentBaseline?.uidValidity != scan.uidValidity {
            throw MailCheckFailure("uidValidityChanged")
        }
        next.enabled = true;next.requiresResynchronization = false;next.requiresAuthentication = false
        next.lastError = nil;next.failures = 0;next.nextCheckAt = nil
        try commit(next)
    }
    public func pause() throws {var next = state;next.enabled = false;try commit(next)}
    public func connected() throws {
        var next = state
        next.requiresAuthentication = false;next.failures = 0;next.lastError = nil;next.nextCheckAt = nil
        try commit(next)
    }
    public func recordFailure(_ code: String, now: Date = Date()) throws {
        var next = state
        next.lastError = code;next.failures += 1
        next.requiresAuthentication = code == "authenticationFailed" || code == "credentialUnavailable"
        next.requiresResynchronization = code == "uidValidityChanged"
        let delays: [TimeInterval] = [60,120,300,900]
        next.nextCheckAt = now.addingTimeInterval(delays[min(next.failures-1,3)])
        try commit(next)
    }
    public func ingest(_ scan: EmailScan, now: Date = Date()) throws {
        try scan.validate()
        guard let baseline = state.currentBaseline, baseline.uidValidity == scan.uidValidity,
              scan.frontier >= baseline.frontier else {throw JoeyError.dependency("Mailbox identity changed; saved receipts retained")}
        var next = state
        var frontier = scan.frontier
        for message in scan.messages.sorted(by:{$0.uid < $1.uid}) where message.uid > baseline.frontier {
            let beforeMessage = next
            let receiptID = Integrity.textHash("\(state.settings.account)|INBOX|\(scan.uidValidity)|\(message.uid)")
            if next.receipts.contains(where:{$0.id == receiptID}) {continue}
            var sources: [EmailSource] = []
            for raw in message.links {
                if let source = try? EmailSource(raw), !sources.contains(where:{$0.id == source.id}) {sources.append(source)}
            }
            var status = message.status, reason = message.reason
            if sources.count > 10 {status = "rejected";reason = "tooManyLinks";sources = []}
            else if sources.isEmpty && status != "rejected" {status = "rejected";reason = "noSupportedLinks"}
            guard ["authorized","pendingAuthorization","rejected"].contains(status) else {throw JoeyError.failed("Unknown email authorization result")}
            var ids: [String] = []
            if status == "authorized" {
                guard reason == "templateToken" else {throw JoeyError.failed("Email authorization proof unavailable")}
                for source in sources {
                    // Receipt timestamps and UIDs are deliberately absent from
                    // media identity. Frozen requests survive title changes.
                    // Intake identity is the source, independent of settings
                    // chosen later. Preserve legacy keys and frozen mappings.
                    let existing = next.work.first {$0.source.id == source.id}
                    let key = existing?.id ?? Integrity.textHash(source.id)
                    ids.append(key)
                    if !next.work.contains(where:{$0.id == key}) {
                        next.work.append(EmailWork(id:key,account:next.settings.account,source:source,workflow:EmailWorkflow()))
                    } else if let index = next.work.firstIndex(where:{$0.id == key}) {
                        // A newly authorized receipt in another configured
                        // account can continue the same frozen media contract.
                        next.work[index].account = next.settings.account
                    }
                }
                status = "queued"
            }
            next.receipts.append(EmailReceipt(id:receiptID,account:next.settings.account,receivedAt:now,status:status,reason:reason,sources:sources,workIDs:ids))
            if next.pendingCount > 100 {
                next = beforeMessage;frontier = message.uid-1
                break
            }
        }
        // Only display history is bounded. Work/request mappings remain intact
        // so pruning an old receipt never recreates an accepted media request.
        while next.receipts.count > 500, let index = next.receipts.firstIndex(where:{$0.status != "pendingAuthorization"}) {
            next.receipts.remove(at:index)
        }
        let index = next.baselines.firstIndex {$0.account == next.settings.account}!
        next.baselines[index].frontier = frontier
        next.lastCheckedAt = now;next.lastError = nil;next.failures = 0;next.nextCheckAt = now.addingTimeInterval(60)
        next.requiresAuthentication = false
        try commit(next)
    }
    public func freeze(_ id: String, request: JobRequest) throws {
        try request.validate()
        var next = state
        guard let index = next.work.firstIndex(where:{$0.id == id}), next.work[index].source.id == request.sourceID else {throw JoeyError.invalid("Email source identity changed")}
        if let prior = next.work[index].request {
            guard try prior.identityData() == request.identityData() else {throw JoeyError.invalid("Frozen email request cannot change")}
            return
        }
        next.work[index].request = request;next.work[index].jobID = try request.stableID()
        try commit(next)
    }
    public func updateWork(_ id: String, status: EmailWorkStatus, reason: String? = nil, jobID: String? = nil, now: Date = Date()) throws {
        var next = state
        guard let index = next.work.firstIndex(where:{$0.id == id}) else {return}
        next.work[index].status = status;next.work[index].reason = reason
        if status != .queued {next.work[index].processingRequested = nil}
        if status == .running {next.work[index].retryRequested = nil}
        if let jobID {next.work[index].jobID = jobID}
        if status == .retryable {
            next.work[index].attempts += 1
            next.work[index].retryAt = now.addingTimeInterval([60.0,120,300,900][min(next.work[index].attempts-1,3)])
        } else {next.work[index].retryAt = nil}
        try commit(next)
    }
    public func reconcile(_ jobs: [JobRecord]) throws {
        var next = state
        for index in next.work.indices {
            guard let request = next.work[index].request else {
                if next.work[index].status == .running {
                    next.work[index].status = .queued
                    next.work[index].processingRequested = nil
                }
                continue
            }
            let identity = try request.identityData()
            let matches = try jobs.filter {try $0.request.identityData() == identity}
            guard matches.count <= 1 else {throw JoeyError.failed("Multiple jobs match an email request; preserve and reconcile their checkpoints")}
            if let job = matches.first {
                next.work[index].jobID = job.id
                if job.state == .completed && job.hasRequiredCompletionEvidence {
                    next.work[index].status = .completed;next.work[index].processingRequested = nil
                }
                else if job.state == .cancelled && next.work[index].retryRequested != true {
                    next.work[index].status = .cancelled;next.work[index].processingRequested = nil
                }
                else if next.work[index].status == .completed {
                    next.work[index].status = .retryable
                    next.work[index].reason = job.error ?? "Coordinator completion evidence is no longer complete"
                }
                else if next.work[index].status == .running {next.work[index].status = .queued}
            } else if next.work[index].status == .running {next.work[index].status = .queued}
        }
        if try Persistence.encoder.encode(next) != Persistence.encoder.encode(state) {try commit(next)}
    }
    public func requestProcessing(_ id: String, workflow: EmailWorkflow) throws {
        var next = state
        guard let index = next.work.firstIndex(where:{$0.id == id}),
              next.work[index].status != .running, next.work[index].status != .completed else {
            throw JoeyError.invalid("This saved link is already processing or completed")
        }
        let workflow = try workflow.validated()
        if next.work[index].request != nil || next.work[index].processingRequested == true {
            guard workflow == (try next.work[index].workflow.validated()) else {throw JoeyError.invalid("A requested workflow cannot change; reuse its saved job")}
        }
        next.work[index].workflow = workflow
        next.work[index].status = .queued;next.work[index].retryRequested = true
        next.work[index].processingRequested = true
        next.work[index].retryAt = nil;next.work[index].reason = nil
        try commit(next)
    }
    public func dismiss(_ receiptID: String) throws {
        var next = state
        guard let index = next.receipts.firstIndex(where:{$0.id == receiptID && $0.status == "pendingAuthorization"}) else {return}
        next.receipts[index].status = "rejected";next.receipts[index].reason = "dismissed"
        try commit(next)
    }
}
