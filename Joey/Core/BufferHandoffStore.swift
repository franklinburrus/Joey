import Foundation

/// A distribution extension of Joey's existing durable job records. It owns no
/// media and never writes to Buffer or replaces production checkpoints.
public struct BufferHandoffState: Codable, Sendable {
    public var version = 1
    public var selection = BufferSelection()
    public var prepared: [String:BufferPreparedClip] = [:]
    public var batches: [BufferManifest] = []
    public var receipts: [BufferReceipt] = []
}

public final class BufferHandoffStore: @unchecked Sendable {
    public let directory: URL
    private var stateURL: URL {directory.appendingPathComponent("handoff.json")}
    public init(root: URL) throws {
        let canonical = root.standardizedFileURL.resolvingSymlinksInPath()
        directory = canonical.appendingPathComponent("buffer",isDirectory:true)
        if FileManager.default.fileExists(atPath:directory.path) {
            guard directory.resolvingSymlinksInPath() == directory else {throw JoeyError.invalid("Handoff storage cannot traverse a symbolic link")}
        } else {try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])}
    }
    private func locked<T>(_ action: () throws -> T) throws -> T {
        guard directory.resolvingSymlinksInPath() == directory else {throw JoeyError.invalid("Handoff directory identity changed")}
        let lock = try ProcessingLock(directory:directory,name:"handoff.lock")
        return try withExtendedLifetime(lock) {try action()}
    }
    public func snapshot() throws -> BufferHandoffState {
        guard FileManager.default.fileExists(atPath:stateURL.path) else {return BufferHandoffState()}
        guard stateURL.resolvingSymlinksInPath() == stateURL else {throw JoeyError.invalid("Unsafe handoff checkpoint")}
        let state: BufferHandoffState = try Persistence.load(stateURL)
        guard state.version == 1 else {throw JoeyError.invalid("Unsupported handoff checkpoint version; preserve it")}
        for batch in state.batches {try batch.validate()}
        return state
    }
    public func saveSelection(_ selection: BufferSelection) throws {
        try locked {var state = try snapshot();state.selection = selection;try Persistence.save(state,to:stateURL)}
    }
    func savePreparation(_ prepared: BufferPreparedClip) throws {
        try locked {var state = try snapshot();state.prepared[prepared.key] = prepared;try Persistence.save(state,to:stateURL)}
    }
    public func prepare(job: JobRecord, clip: ClipRecord, root: URL, profile: SharedProfile?) async throws -> BufferPreparedClip {
        var prepared = BufferPreparedClip(jobID:job.id,clipID:clip.id,
            lane:job.request.productionWorkflow == .joeBudden ? "joeBudden":job.request.owner.rawValue,
            sourceID:job.request.sourceID,episode:job.request.title,intervals:clip.intervals,sha256:clip.sha256 ?? "",
            rightsBasis:job.source?.authorizationBasis ?? job.request.authorizationBasis,checkedAt:Date())
        do {
            guard job.request.productionWorkflow != .joeBudden else {throw JoeyError.dependency("Joe Budden is Drive-only; no authorized Buffer mapping or shared compliant export exists")}
            prepared.recommendation = try ClipIntelligence.evaluate(job:job,clip:clip)
            guard let profile else {throw JoeyError.dependency("Current owner-bound shared production profile is missing")}
            prepared.media = try await BufferPreflight.check(job:job,clip:clip,root:root,profile:profile)
        } catch {prepared.error = error.localizedDescription}
        try savePreparation(prepared)
        return prepared
    }
    public func channels() throws -> [BufferChannel] {
        let file = directory.appendingPathComponent("channels.json")
        guard FileManager.default.fileExists(atPath:file.path) else {return []}
        return try Persistence.load(file)
    }
    public func importChannels(_ data: Data) throws {
        guard data.count <= 1_000_000 else {throw JoeyError.invalid("Channel evidence exceeds 1 MB")}
        let channels = try Persistence.decoder.decode([BufferChannel].self,from:data)
        guard Set(channels.map(\.channelID)).count == channels.count else {throw JoeyError.invalid("Duplicate channel evidence")}
        for channel in channels {try channel.validate(lane:channel.lane,platform:channel.platform,mode:.draft,now:Date())}
        try locked {try Persistence.save(channels,to:directory.appendingPathComponent("channels.json"))}
    }
    public func generate(selection: BufferSelection, channels: [BufferChannel], now: Date = Date()) throws -> BufferManifest {
        try locked {
            guard !selection.clipKeys.isEmpty, !selection.platforms.isEmpty,
                  Set(selection.clipKeys).count == selection.clipKeys.count,
                  Set(selection.platforms).count == selection.platforms.count,
                  (1...20).contains(selection.maximumOperations) else {throw JoeyError.invalid("Select unique clips/destinations and 1–20 operations per sub-batch")}
            var state = try snapshot()
            var normalized = selection;normalized.clipKeys.sort();normalized.platforms.sort {$0.rawValue < $1.rawValue}
            // An exported handoff may already be in another GPT session. Reuse its
            // immutable identity even when receipts have not returned yet.
            let existing = state.batches.last(where:{$0.selection == normalized})
            // Rebuild eligibility from the latest preparation and channel evidence
            // before reusing an export. An unchanged output hash cannot override a
            // newer failed preflight or a disconnected/locked channel observation.
            let parentID = existing?.id ?? UUID().uuidString
            var operations: [BufferOperation] = []
            for key in normalized.clipKeys {
                guard let clip = state.prepared[key] else {throw JoeyError.dependency("Run preflight for \(key) before exporting")}
                for platform in normalized.platforms {
                    let matches = channels.filter {$0.lane == clip.lane && $0.platform == platform}
                    let channel = matches.count == 1 ? matches[0]:nil
                    var blockers = normalized.blockers(for:platform)
                    if let error = clip.error {blockers.append(error)}
                    if clip.recommendation == nil {blockers.append("Transcript-grounded editorial evidence is unavailable")}
                    if clip.rightsBasis.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {blockers.append("Source authorization evidence is missing")}
                    if let media = clip.media {
                        if media.sha256 != clip.sha256 || media.checkedAt > now || media.validUntil <= now || media.urlEvidence.validUntil <= now {
                            blockers.append("Media identity or distribution evidence has expired; rerun preflight")
                        }
                        do {try media.capabilityEvidence.validate(now:now)} catch {blockers.append(error.localizedDescription)}
                    } else {blockers.append("Actual-media and anonymous URL preflight has not passed")}
                    if let channel {
                        do {try channel.validate(lane:clip.lane,platform:platform,mode:normalized.mode,now:now)} catch {blockers.append(error.localizedDescription)}
                        if platform == .instagram && !channel.supportedInstagramPresentations.contains(normalized.instagramPresentation) {blockers.append("Selected Instagram presentation is unsupported by the verified channel")}
                        if let profile = clip.media?.capabilityEvidence {
                            let account = platform == .x ? profile.x?.account:profile.instagram?.account
                            if account?.lowercased().trimmingCharacters(in:CharacterSet(charactersIn:"@")) != channel.handle.lowercased() {blockers.append("Media capability evidence belongs to another account")}
                        }
                    } else {blockers.append("Exactly one current channel mapping is required for this content identity and platform")}
                    let id = try BufferOperation.identity(lane:clip.lane,sourceID:clip.sourceID,intervals:clip.intervals,sha256:clip.sha256,platform:platform,channelID:channel?.channelID ?? "UNRESOLVED")
                    let observed = state.receipts.contains {$0.operationID == id && ($0.postID != nil || [.submitted,.reconciled,.unconfirmed].contains($0.reconciliationState))}
                    let prior = Array(Set(state.batches.filter {batch in
                        (batch.id != parentID || observed) && batch.operations.contains(where:{$0.id == id && $0.state != .blocked})
                    }.map(\.id))).sorted()
                    if !prior.isEmpty {blockers.append("This operation is reserved in an earlier handoff. Reconcile its provider state and receipts before any retry; do not submit a second post.")}
                    operations.append(BufferOperation(id:id,clip:clip,platform:platform,channel:channel,requestedMode:normalized.mode,
                        instagramPresentation:platform == .instagram ? normalized.instagramPresentation:nil,
                        shareToFeed:platform == .instagram ? normalized.instagramPresentation == .reelSharedToFeed:nil,
                        scheduledAt:normalized.scheduledAt,state:blockers.isEmpty ? .prepared:.blocked,blockers:blockers,priorBatchIDs:prior))
                }
            }
            let id = parentID
            let priorReceipts = state.receipts.filter {r in operations.contains {$0.id == r.operationID}}
            if let existing, try Persistence.encoder.encode(existing.operations) == Persistence.encoder.encode(operations),
               try Persistence.encoder.encode(existing.priorReceipts) == Persistence.encoder.encode(priorReceipts) {return existing}
            let subBatches = stride(from:0,to:operations.count,by:normalized.maximumOperations).enumerated().map {index,start in
                BufferSubBatch(id:id+"-"+String(format:"%03d",index+1),operationIDs:Array(operations[start..<min(operations.count,start+normalized.maximumOperations)]).map(\.id))
            }
            let expiries = operations.flatMap {[$0.channel?.validUntil,$0.clip.media?.validUntil,$0.clip.media?.urlEvidence.validUntil].compactMap {$0}}
            var manifest = BufferManifest(id:id,createdAt:now,selection:normalized,selectedClipCount:normalized.clipKeys.count,
                expectedOperationCount:operations.count,evidenceValidUntil:expiries.min(),operations:operations,subBatches:subBatches)
            manifest.previousManifestSHA256 = existing?.manifestSHA256
            manifest.priorReceipts = priorReceipts
            manifest.manifestSHA256 = try manifest.digest();try manifest.validate()
            state.batches.append(manifest);state.selection = normalized
            try Persistence.save(state,to:stateURL)
            return manifest
        }
    }
    public func export(_ manifest: BufferManifest) throws -> URL {
        try locked {
            try manifest.validate()
            guard try snapshot().batches.contains(where:{$0.id == manifest.id && $0.manifestSHA256 == manifest.manifestSHA256}) else {throw JoeyError.invalid("Unknown handoff reservation")}
            let folder = directory.appendingPathComponent("exports/"+manifest.id+"/"+manifest.manifestSHA256,isDirectory:true)
            guard folder.resolvingSymlinksInPath().path == folder.path else {throw JoeyError.invalid("Unsafe handoff export path")}
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            var canonical = manifest;canonical.manifestSHA256 = ""
            let template = BufferReceiptPackage(batchID:manifest.id,manifestSHA256:manifest.manifestSHA256,results:manifest.operations.map {operation in
                BufferReceipt(batchID:manifest.id,manifestSHA256:manifest.manifestSHA256,operationID:operation.id,
                    jobID:operation.clip.jobID,clipID:operation.clip.clipID,sourceID:operation.clip.sourceID,lane:operation.clip.lane,
                    platform:operation.platform,organizationID:operation.channel?.organizationID ?? "UNRESOLVED",
                    channelID:operation.channel?.channelID ?? "UNRESOLVED",requestedMode:operation.requestedMode,
                    errors:["NOT EXECUTED — replace with actual results"],verificationMethod:"NONE — no provider operation performed",reconciliationState:.blocked)
            })
            let files: [(String,Data)] = [
                ("manifest.json",try Persistence.encoder.encode(manifest)),
                ("manifest-canonical.json",try Persistence.encoder.encode(canonical)),
                ("GPT-INSTRUCTIONS.txt",Data(manifest.executionInstructions.utf8)),
                ("receipt-template.json",try Persistence.encoder.encode(template))]
            for (name,data) in files {
                let path = folder.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath:path.path) {
                    guard path.resolvingSymlinksInPath() == path, try Data(contentsOf:path) == data else {throw JoeyError.invalid("Existing handoff file changed; preserve and reconcile \(name)")}
                } else {try data.write(to:path,options:.atomic);try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:path.path)}
                guard try Data(contentsOf:path) == data else {throw JoeyError.failed("Handoff readback mismatch")}
            }
            return folder
        }
    }
    public func importReceipts(data: Data) throws {
        guard data.count <= 16_000_000 else {throw JoeyError.invalid("Receipt file exceeds 16 MB")}
        try importReceipts(Persistence.decoder.decode(BufferReceiptPackage.self,from:data))
    }
    public func importReceipts(_ package: BufferReceiptPackage, now: Date = Date()) throws {
        try locked {
            var state = try snapshot()
            guard package.schemaVersion == "joey-buffer-receipts-v1",
                  let batch = state.batches.first(where:{$0.id == package.batchID && $0.manifestSHA256 == package.manifestSHA256}),
                  Set(package.results.map(\.operationID)).count == package.results.count else {throw JoeyError.invalid("Unknown, duplicate or mismatched receipt package")}
            for receipt in package.results {
                guard let operation = batch.operations.first(where:{$0.id == receipt.operationID}) else {throw JoeyError.invalid("Receipt operation is not in this manifest")}
                try validate(receipt,operation:operation,batch:batch,now:now)
                let history = state.receipts.filter {$0.operationID == receipt.operationID}
                let canonicalReceipt = try Persistence.encoder.encode(receipt)
                if try history.contains(where:{try Persistence.encoder.encode($0) == canonicalReceipt}) {continue}
                if let prior = history.last {
                    if let post = prior.postID, receipt.postID != post {throw JoeyError.invalid("Conflicting Buffer post identity; preserve prior receipt")}
                    if prior.reconciliationState == .reconciled && receipt.reconciliationState != .reconciled {throw JoeyError.invalid("An uncertain receipt cannot replace confirmed provider evidence")}
                    if let date = prior.readbackAt, receipt.readbackAt.map({$0 <= date}) != false {throw JoeyError.invalid("Conflicting or older readback; prior evidence preserved")}
                }
                state.receipts.append(receipt)
            }
            // One atomic checkpoint, after every submitted result passes validation.
            try Persistence.save(state,to:stateURL)
        }
    }
    private func validate(_ r: BufferReceipt,operation: BufferOperation,batch: BufferManifest,now: Date) throws {
        guard r.schemaVersion == "joey-buffer-receipts-v1", r.batchID == batch.id,r.manifestSHA256 == batch.manifestSHA256,
              r.jobID == operation.clip.jobID,r.clipID == operation.clip.clipID,r.sourceID == operation.clip.sourceID,
              r.lane == operation.clip.lane,r.platform == operation.platform,r.requestedMode == operation.requestedMode,
              r.organizationID == (operation.channel?.organizationID ?? "UNRESOLVED"),
              r.channelID == (operation.channel?.channelID ?? "UNRESOLVED"),
              r.provenance == "GPT-mediated provider evidence; not independently verified by Joey",
              !r.verificationMethod.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,
              ![.validated,.prepared].contains(r.reconciliationState) else {throw JoeyError.invalid("Receipt identity, provenance or workflow state does not match the saved manifest")}
        if let submitted = r.submittedAt {
            guard submitted <= now.addingTimeInterval(60),r.submissionOrigin == .existingPost || submitted >= batch.createdAt.addingTimeInterval(-60) else {throw JoeyError.invalid("Invalid provider submission timestamp")}
        }
        if let readback = r.readbackAt {
            guard readback <= now.addingTimeInterval(60),readback >= batch.createdAt.addingTimeInterval(-60) else {throw JoeyError.invalid("Invalid provider readback timestamp")}
        }
        if let submitted = r.submittedAt,let readback = r.readbackAt,readback < submitted {throw JoeyError.invalid("Readback precedes submission")}
        if let reference = r.mediaReference, reference != operation.clip.media?.directURL {throw JoeyError.invalid("Receipt media reference differs from accepted output")}
        if let post = r.postID,post.isEmpty || post.count > 256 {throw JoeyError.invalid("Invalid Buffer post ID")}
        if r.reconciliationState == .reconciled || r.reconciliationState == .submitted {
            guard (operation.state == .prepared || r.submissionOrigin == .existingPost),r.postID != nil,r.providerState != nil,r.mediaReference != nil,
                  r.submittedAt != nil else {throw JoeyError.invalid("Submission receipt lacks exact accepted operation and provider evidence")}
            if r.reconciliationState == .reconciled && r.readbackAt == nil {throw JoeyError.invalid("Reconciliation requires provider readback")}
            if r.submissionOrigin == .newSubmission && r.requestedMode == .draft && ![.draft,.error].contains(r.providerState) {throw JoeyError.invalid("Draft-only operation reports unauthorized mode escalation")}
        }
        if [.blocked,.failed,.unconfirmed].contains(r.reconciliationState) && r.errors.isEmpty {throw JoeyError.invalid("Unresolved receipt requires the actual reason")}
    }
    public func unresolved(_ batchID: String) throws -> Int {
        let state = try snapshot()
        guard let batch = state.batches.last(where:{$0.id == batchID}) else {throw JoeyError.invalid("Unknown batch")}
        return batch.operations.filter {op in
            guard let receipt = state.receipts.last(where:{$0.operationID == op.id && $0.batchID == batch.id && $0.manifestSHA256 == batch.manifestSHA256}) else {return true}
            return receipt.reconciliationState != .reconciled || receipt.providerState == .error ||
                (op.requestedMode == .draft ? receipt.providerState != .draft : receipt.providerState == .draft)
        }.count
    }
}
