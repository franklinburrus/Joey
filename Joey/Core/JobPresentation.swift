import Foundation

/// Read-only presentation of the existing durable workflow. No stage weights
/// or elapsed-time estimates are invented, and no checkpoint is mutated.
struct JobPresentation {
    let job: JobRecord
    static func selectedJob(in jobs: [JobRecord], id: String?) -> JobRecord? {
        jobs.first {$0.id == id} ?? jobs.first
    }
    struct Stage: Identifiable {
        let id: String
        let title: String
        let detail: String
        let verified: Bool
    }
    /// Retained source metadata is historical evidence. A current source check
    /// can be running, paused or rejected without discarding that evidence.
    private var sourceStage: Stage {
        guard job.source != nil else {
            return Stage(id:"source",title:"Source",detail:"Pending",verified:false)
        }
        if job.stage == "source" {
            switch job.state {
            case .processing, .planned:
                return Stage(id:"source",title:"Source",detail:"Checking original · saved evidence retained",verified:false)
            case .cancelled:
                return Stage(id:"source",title:"Source",detail:"Verification paused · original evidence retained",verified:false)
            default:
                if job.state == .failed || job.error != nil {
                    return Stage(id:"source",title:"Source",detail:"Verification failed · original evidence retained. Resolve the reported source issue before Resume.",verified:false)
                }
            }
        }
        return Stage(id:"source",title:"Source",detail:"Verified original",verified:true)
    }
    /// Each stage reports its own saved evidence, not an inferred position in
    /// a linear timeline. Recovery can reuse later work while retrying a stage.
    var stages: [Stage] {
        [
            sourceStage,
            Stage(id:"transcript",title:"Transcript",detail:job.transcript != nil ? "Source-bound transcript" : job.planningBasis == .deterministicTime ? "Unavailable · time-based planning" : "Pending",verified:job.transcript != nil),
            Stage(id:"planning",title:"Clip plan",detail:total > 0 ? "\(total) clips" : "Pending",verified:total > 0),
            Stage(id:"qa",title:"Automatic QA",detail:"\(accepted)/\(total) passed",verified:total > 0 && accepted == total),
            Stage(id:"delivery",title:"Drive",detail:deliveryStatus,verified:total > 0 && filed == total),
            Stage(id:"records",title:"Records",detail:recordStatus,verified:completed)
        ]
    }
    var activeStageID: String? {
        switch job.stage {
        case "intake", "source", "original archive verification": return "source"
        case "transcription": return "transcript"
        case "planning", "artwork": return "planning"
        case "local package", "companion records", "register reconciliation", "final Drive package verification", "complete": return "records"
        case "Drive folder": return "delivery"
        default:
            if job.stage.hasPrefix("render clip ") {return "planning"}
            if job.stage.hasPrefix("QA clip ") {return "qa"}
            if job.stage.hasPrefix("Drive clip ") {return "delivery"}
            return nil
        }
    }
    var total: Int { job.clips.count }
    var accepted: Int { job.clips.filter { $0.qa?.passed == true }.count }
    var filed: Int { job.verifiedDriveClipCount }
    var completed: Bool { job.state == .completed && job.hasRequiredCompletionEvidence }
    var deliveryStatus: String {
        guard total > 0 else {return "Required for every clip"}
        return (filed == total ? "" : "Required · ")+"\(filed)/\(total) clips verified"
    }
    /// Durable checkpoint wording. Pass `isRunning` when the Process owner still
    /// holds this job so Cancel/Stopped controls stay truthful mid-transition.
    var status: String { status(isRunning:false) }
    func status(isRunning: Bool, isCancelling: Bool = false) -> String {
        if completed { return "Completed" }
        if isRunning && job.state == .cancelled {
            return isCancelling ? "Stopping — saving progress" : "Processing"
        }
        if let storage = storageBlockedStatus { return storage }
        if isRunning {
            if job.error == nil {
                switch job.state {
                case .processing, .planned: return "Processing"
                case .qaPassed, .filed, .failed, .cancelled, .completed: break
                }
            }
        }
        if job.error != nil && job.state != .cancelled { return "Needs attention" }
        switch job.state {
        case .cancelled: return "Stopped — progress saved"
        case .qaPassed: return job.request.fileToDrive ? "Delivery pending" : "Drive filing required"
        case .filed: return "Finishing records"
        case .failed: return "Needs attention"
        case .processing: return "Processing"
        case .planned: return "Ready to process"
        case .completed: return "Delivery incomplete"
        }
    }
    /// Active capacity wait keeps required bytes on the checkpoint; available
    /// bytes are retained in the storage-blocked error text when measured.
    var storageBlockedStatus: String? {
        guard let required = job.storageRequiredBytes else { return nil }
        if let available = Self.availableBytes(from:job.error) {
            return "Paused while storage blocked — need \(required) bytes; \(available) bytes available when paused"
        }
        return "Paused while storage blocked — need \(required) bytes"
    }
    /// Process chrome derived from durable state plus live ownership. Open Clips
    /// stays gated on accepted QA separately from Cancel/Resume.
    func processControls(isRunning: Bool, isCancelling: Bool = false) -> (status: String, showsCancel: Bool, showsResume: Bool) {
        (status(isRunning:isRunning,isCancelling:isCancelling), isRunning, !isRunning && !completed)
    }
    static func availableBytes(from error: String?) -> Int64? {
        guard let error else { return nil }
        guard let availableRange = error.range(of:"available ") else { return nil }
        let remainder = error[availableRange.upperBound...]
        let digits = remainder.prefix(while:{"0123456789".contains($0)})
        guard !digits.isEmpty, let value = Int64(digits) else { return nil }
        return value
    }
    var stage: String {
        switch job.stage {
        case "intake": return "Preparing your job"
        case "source": return "Checking the original"
        case "transcription": return "Preparing the transcript"
        case "planning": return "Planning clips"
        case "artwork": return "Finding approved episode artwork"
        case "local package": return "Preparing clip records"
        case "original archive verification": return "Verifying the full-length archive"
        case "Drive folder": return "Finding the episode folder"
        case "companion records": return "Filing the index and transcript"
        case "register reconciliation", "final Drive package verification": return "Verifying delivery records"
        case "complete": return completed ? "Delivery verified" : filed < total ? "Drive filing required" : "Verifying delivery records"
        default:
            if job.stage.hasPrefix("render clip ") { return job.stage.replacingOccurrences(of:"render clip ",with:"Creating clip ")+" of \(total)" }
            if job.stage.hasPrefix("QA clip ") { return job.stage.replacingOccurrences(of:"QA clip ",with:"Checking clip ")+" of \(total)" }
            if job.stage.hasPrefix("Drive clip ") { return job.stage.replacingOccurrences(of:"Drive clip ",with:"Filing clip ")+" of \(total)" }
            return job.stage
        }
    }
    // The bar is explicitly clip QA, never a percentage of complete delivery.
    var clipProgress: Double? { total > 0 ? Double(accepted)/Double(total) : nil }
    var recordStatus: String {
        if completed { return "Verified" }
        if DestinationResolver.requiresDUBRegister(job.request) { return "\(job.registerRows.count)/\(total) register rows verified" }
        return "\(job.companions.count)/4 companion records verified"
    }
    var recovery: String {
        if job.state == .cancelled { return "Resume reuses accepted clips and saved progress." }
        if !job.unavailableTranscriptFeatures.isEmpty && accepted == total && total > 0 {
            return "Local clips are retained. Production delivery still requires a complete source-bound transcript and transcript-assisted planning."
        }
        return "Check the details below, resolve the reported input or connection issue, then Resume. Accepted clips are retained."
    }
}

/// Only unambiguous identifiers are suggested; authority and titles are never
/// inferred from the fact that a URL can be opened.
enum SourceIdentitySuggestion {
    static func from(_ raw: String) -> String? {
        guard let url = try? Acquisition.validateOriginalURL(raw) else { return nil }
        let parts = url.path.split(separator:"/").map(String.init)
        let host = url.host!.lowercased()
        if ["x.com","www.x.com","twitter.com"].contains(host) {
            for (component,prefix) in [("broadcasts","x:broadcast:"),("spaces","x:space:"),("status","x:status:")] {
                if let i = parts.firstIndex(of:component), i+2 == parts.count,
                   parts[i+1].range(of:"^[A-Za-z0-9_-]+$",options:.regularExpression) != nil { return prefix+parts[i+1] }
            }
        } else {
            let id: String?
            if host == "youtu.be", parts.count == 1 { id = parts.first }
            else if parts == ["watch"] { id = URLComponents(url:url,resolvingAgainstBaseURL:false)?.queryItems?.first(where:{$0.name == "v"})?.value }
            else if parts.count == 2, ["shorts","live","embed"].contains(parts[0]) { id = parts[1] }
            else { id = nil }
            if let id, id.range(of:"^[A-Za-z0-9_-]{11}$",options:.regularExpression) != nil { return "youtube:"+id }
        }
        return nil
    }
}
