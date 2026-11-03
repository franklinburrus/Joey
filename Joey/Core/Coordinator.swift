import Foundation

/// The coordinator owns recovery and sequencing; provider adapters own current
/// readback. Tests can replace this boundary without reaching live accounts.
protocol CoordinatorDelivery: TaxstoneReuseProvider, Sendable {
    func archive(source: SourceRecord, request: JobRequest) async throws -> String
    func episodeFolder(source: SourceRecord, request: JobRequest, jobID: String, existingFolderID: String?, intentURL: URL) async throws -> String
    func upload(_ local: URL, name: String?, parent: String, destination: FilingDestination, replaceCompanion: Bool) async throws -> DriveReceipt
    func resolveArtwork(source: SourceRecord, configuration: Configuration, root: URL) async throws -> Artwork
    func reconcileRegister(job: JobRecord, tab: String) async throws -> [String]
    func verifyPackage(job: JobRecord, directory: URL) async throws
}
extension DriveDelivery: CoordinatorDelivery {}

public actor Coordinator {
    @TaskLocal static var deliveryOverride: (any CoordinatorDelivery)?
    public let root: URL
    public init(root: URL = Persistence.defaultRoot) throws {
        let path = root.standardizedFileURL.resolvingSymlinksInPath().path
        guard !path.contains("/CloudStorage/"), !path.contains("/Mobile Documents/") else {
            throw JoeyError.invalid("Working data must be outside synchronized Drive/iCloud storage")
        }
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        self.root = try StorageManager.canonicalRoot(root)
    }
    public func jobs() throws -> [JobRecord] {
        let dir = root.appendingPathComponent("jobs")
        guard FileManager.default.fileExists(atPath:dir.path) else {return []}
        return try FileManager.default.contentsOfDirectory(at:dir,includingPropertiesForKeys:nil).compactMap {
            try? Persistence.load($0.appendingPathComponent("job.json")) as JobRecord
        }.sorted {$0.updatedAt > $1.updatedAt}
    }
    public func directory(for id: String) -> URL {root.appendingPathComponent("jobs").appendingPathComponent(id)}
    public func run(_ request: JobRequest, estimatedDuration: Double? = nil, progress: @escaping @Sendable (JobRecord) async throws -> Void = {_ in}) async throws -> JobRecord {
        try await StorageManager.$processingRoot.withValue(root) {
            while true {
                let job = try await execute(request,estimatedDuration:estimatedDuration,progress:progress)
                guard let needed = job.storageRequiredBytes else {return job}
                // Capacity polling does not retry rendering, provider writes or
                // profile validation. Those resume only after capacity permits.
                do {
                    while true {
                        try await Task.sleep(nanoseconds:StorageManager.capacityRetryNanoseconds)
                        if StorageManager.automaticCleanupEnabled(root:root) {
                            _ = try? StorageManager.clean(root:root)
                        }
                        if try StorageManager.capacity(at:root).free >= needed {break}
                    }
                } catch {
                    // Another coordinator may have progressed while this one
                    // waited. Never overwrite its checkpoint with a stale copy.
                    if let lock = try? ProcessingLock(directory:root) {
                        defer {withExtendedLifetime(lock) {}}
                        let checkpoint = directory(for:job.id).appendingPathComponent("job.json")
                        var current: JobRecord = try Persistence.load(checkpoint)
                        if current.storageRequiredBytes != nil,try Persistence.encoder.encode(current) == Persistence.encoder.encode(job) {
                            current.state = .cancelled;current.storageRequiredBytes = nil
                            current.error = "Paused while storage blocked; progress preserved"
                            try Persistence.save(current,to:checkpoint)
                            try await progress(current)
                        }
                    }
                    throw error
                }
            }
        }
    }
    private func execute(_ request: JobRequest, estimatedDuration: Double?, progress: @escaping @Sendable (JobRecord) async throws -> Void) async throws -> JobRecord {
        let supplied = try Persistence.decoder.decode(JobRequest.self,from:Persistence.encoder.encode(request))
        try supplied.validate(requireCurrentCapability:false)
        let lock = try ProcessingLock(directory:root)
        defer {withExtendedLifetime(lock) {}}
        // New IDs omit renewable observations. Older IDs remain authoritative:
        // locate their immutable contract and retain their directory/receipts.
        let identity = try supplied.identityData()
        let checkpoints = try jobs()
        let matches = try checkpoints.filter {try $0.request.identityData() == identity}
        guard matches.count <= 1 else {throw JoeyError.invalid("Multiple checkpoints match this job; reconcile existing identities before resume")}
        if matches.isEmpty,try checkpoints.contains(where:{try $0.request.identityData(ignoringProfile:true) == supplied.identityData(ignoringProfile:true)}) {
            throw JoeyError.invalid("Resume changes the saved account, upload surface or technical constraints; existing job preserved")
        }
        let id = try matches.first?.id ?? supplied.stableID()
        let dir = directory(for:id), checkpoint = dir.appendingPathComponent("job.json")
        if matches.isEmpty,FileManager.default.fileExists(atPath:checkpoint.path) {
            throw JoeyError.invalid("Existing checkpoint at stable job identity cannot be reconciled; preserve it for recovery")
        }
        var job = matches.first ?? JobRecord(id:id,request:supplied)
        var request = job.request
        let config = try Configuration.load(root:root,discoverTranscription:job.state != .completed && request.transcriptPolicy != .modelIndependent)
        let storage = try StorageManager(root:root,lock:lock)
        if job.state != .completed,StorageManager.automaticCleanupEnabled(root:root) {_ = try? storage.clean()}
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        func save() async throws {
            job.updatedAt = Date(); try Persistence.save(job,to:checkpoint); try await progress(job)
        }
        func renewCapabilityEvidence(requireCurrent: Bool) throws {
            request.profile = try request.profile.renewingEvidence(from:supplied.profile,requireCurrentEvidence:false)
            request = try config.renewingCapabilities(in:request,requireCurrentEvidence:requireCurrent)
            job.request = request
        }
        func authorizeNewOperation() throws {
            try Task.checkCancellation()
            try request.profile.validate()
        }
        var completedReadbackPassed = false
        do {
            if job.state == .completed {
                guard job.hasRequiredCompletionEvidence else {throw JoeyError.failed("Completed checkpoint lacks required delivery evidence")}
                for clip in job.clips {
                    guard try Integrity.sha256(dir.appendingPathComponent(clip.filename)) == clip.sha256 else {throw JoeyError.failed("Completed output changed: \(clip.filename)")}
                }
                // Current local bytes match accepted receipts. Reopening does
                // not claim a new provider readback or require network access.
                completedReadbackPassed = true
                let previous = job.request
                try renewCapabilityEvidence(requireCurrent:false)
                if job.request != previous {try await save()}
                try await progress(job); return job
            }
            try renewCapabilityEvidence(requireCurrent:true)
            let delivery: any CoordinatorDelivery = try Self.deliveryOverride ?? DriveDelivery(remote:config.rcloneRemote)
            job.error = nil; job.storageRequiredBytes = nil;job.state = .processing; job.stage = "source"; try await save()
            try authorizeNewOperation()
            if job.source == nil, let duration = estimatedDuration ?? request.expectedDuration {
                let audio = request.productionWorkflow == .taxstoneLibrary
                guard duration.isFinite,duration > 0,duration < 1_000_000 else {throw JoeyError.invalid("Invalid episode duration for storage admission")}
                let estimate = try StorageManager.peakBytes(duration:duration,sourceBytes:Int64(duration * (audio ? 192_000 : 1_500_000)),clipDuration:min(duration,request.profile.maxDuration),audio:audio)
                try Persistence.checkDisk(at:root,requiredBytes:estimate)
            } else if job.clips.isEmpty || job.clips.contains(where:{$0.qa?.passed != true}) {
                try Persistence.checkDisk(at:root,requiredBytes:128*1024*1024)
            }
            if request.productionWorkflow == .joeBudden, job.source == nil {
                let metadata = try await SourceDiscovery.lookup(request.originalURL!)
                guard metadata.channelID == SourceDiscovery.joeChannelID, metadata.episodeNumber != nil else {
                    throw JoeyError.invalid("Joe Budden requires a numbered full episode from Joe Budden TV on YouTube")
                }
            }
            let reusable = try jobs().first {candidate in
                candidate.source?.id == request.sourceID && candidate.source?.owner == request.owner &&
                candidate.source?.originalURL == request.originalURL && candidate.source != nil
            }
            let sourceURL: URL
            if let prior = job.source {sourceURL = URL(fileURLWithPath:prior.path)}
            else if request.localPath == nil, let prior = reusable?.source,
                    (try? Integrity.sha256(URL(fileURLWithPath:prior.path))) == prior.sha256 {
                sourceURL = URL(fileURLWithPath:prior.path)
                var copy = prior; copy.title = request.title; copy.episodeDate = request.episodeDate
                copy.authorizationBasis = request.authorizationBasis; job.source = copy
                if let transcript = reusable?.transcript {
                    try transcript.validate(sourceID:prior.id,sha256:prior.sha256,duration:prior.duration)
                    try Persistence.save(transcript,to:dir.appendingPathComponent("transcript.json"))
                }
            } else if request.localPath == nil, let archive = request.archiveReference {
                sourceURL = try await delivery.downloadOriginal(reference:archive,directory:dir)
            } else {
                sourceURL = try await Acquisition.acquire(request,directory:dir)
            }
            if let source = job.source {
                guard source.path == sourceURL.path, try Integrity.sha256(sourceURL) == source.sha256 else {throw JoeyError.failed("Original source changed; preserved job cannot silently switch inputs")}
            } else {
                job.source = try await Media.inspect(sourceURL,request:request)
                try await save()
            }
            guard var source = job.source else {throw JoeyError.failed("Missing inspected source")}
            // Accepted local QA from an older build does not authorize a new
            // provider operation outside the actual source-kind export limits.
            _ = try request.profile.outputProfile(for:source.kind)
            let remaining = job.clips.isEmpty ? source.duration : job.clips.filter {$0.qa?.passed != true}.reduce(0) {$0+$1.expectedDuration}
            if remaining > 0 {
                try Persistence.checkDisk(at:root,requiredBytes:StorageManager.peakBytes(duration:remaining,sourceBytes:0,clipDuration:min(remaining,request.profile.maxDuration),audio:source.kind == .audio))
            }
            if let expected = request.expectedSourceSHA256, source.sha256 != expected {
                throw JoeyError.failed("Archived original differs from inventory source SHA-256")
            }
            if request.productionWorkflow != nil {
                job.stage = "original archive verification";try await save()
                try authorizeNewOperation()
                source.archiveReference = try await delivery.archive(source:source,request:request)
                job.source = source;try await save()
            }
            if request.productionWorkflow == .taxstoneLibrary,
               !FileManager.default.fileExists(atPath:dir.appendingPathComponent("transcript.json").path),
               let entry = try TaxstoneEvidence.load().first(where:{"soundcloud:"+$0.trackID == source.id}),
               entry.transcript != nil {
                _ = try TaxstoneEvidence.convertTranscript(entry,source:source,to:dir.appendingPathComponent("transcript.json"))
            }
            // Persisted deterministic plans never silently acquire editorial
            // approval merely because a transcript later appears on disk.
            if job.planningBasis != .deterministicTime {
                job.stage = "transcription"; try await save()
                try Task.checkCancellation()
                job.transcript = try await Acquisition.transcript(source:source,request:request,configuration:config,directory:dir)
                try await save()
            }
            if job.clips.isEmpty {
                job.stage = "planning"
                try authorizeNewOperation()
                if let transcript = job.transcript {
                    job.exclusions = Editorial.exclusions(request,transcript:transcript)
                    if request.productionWorkflow == .taxstoneLibrary,request.taxstoneReuse?.isEmpty == false {
                        job.clips = try await TaxstoneReuse.plan(request:request,source:source,transcript:transcript,exclusions:job.exclusions,provider:delivery,directory:dir)
                    } else {job.clips = try Editorial.plan(request:request,source:source,transcript:transcript,exclusions:job.exclusions)}
                    job.planningBasis = .transcriptAssisted
                } else {
                    job.exclusions = []
                    job.clips = try Editorial.planWithoutTranscript(request:request,source:source)
                    job.planningBasis = .deterministicTime
                }
                try await save()
            }
            var branding: JoeBranding?
            var artwork = request.artwork
            if source.kind == .audio, artwork == nil {
                guard request.transcriptPolicy != .modelIndependent else {throw JoeyError.dependency("Model-independent local audio requires supplied approved artwork")}
                job.stage = "artwork"; try await save()
                try authorizeNewOperation()
                artwork = try await delivery.resolveArtwork(source:source,configuration:config,root:dir)
                try Persistence.save(artwork,to:dir.appendingPathComponent("artwork.json"))
            }
            var failures: [String] = []
            for index in job.clips.indices {
                try Task.checkCancellation()
                let clip = job.clips[index], output = dir.appendingPathComponent(clip.filename)
                if clip.qa?.passed == true, let sha = clip.sha256, (try? Integrity.sha256(output)) == sha {continue}
                // Attempt directories fence writers left by abrupt termination;
                // the native supervisor also terminates orphan process groups.
                try Persistence.checkDisk(at:root,requiredBytes:StorageManager.peakBytes(duration:clip.expectedDuration,sourceBytes:0,clipDuration:clip.expectedDuration, audio:source.kind == .audio))
                let work = try storage.begin(jobID:job.id,clipID:clip.id)
                let partial = work.appendingPathComponent("render.partial.mp4")
                do {
                    job.stage = "render clip \(clip.id)"; try await save()
                    try authorizeNewOperation()
                    if request.productionWorkflow == .joeBudden,branding == nil {branding = try JoeBranding.load(root:root)}
                    let render: RenderReceipt
                    if FileManager.default.fileExists(atPath:partial.path), FileManager.default.fileExists(atPath:work.appendingPathComponent("render.json").path),
                       let existing: RenderReceipt = try? Persistence.load(work.appendingPathComponent("render.json")),
                       (try? await Media.validate(output:partial,source:source,clip:clip,profile:request.profile,render:existing,work:work)) != nil {
                        render = existing
                    } else {render = try await Media.render(source:source,clip:clip,profile:request.profile,artwork:artwork,work:work,output:partial,branding:branding)}
                    job.stage = "QA clip \(clip.id)"; try await save()
                    var qa: QAReport
                    do {qa = try await Media.validate(output:partial,source:source,clip:clip,profile:request.profile,render:render,work:work)}
                    catch {
                        if error is CancellationError || error is StorageBlocked {throw error}
                        // One supported clean re-encode repairs partial/corrupt
                        // local writes. Deterministic failure stays an error.
                        try authorizeNewOperation()
                        let repaired = try await Media.render(source:source,clip:clip,profile:request.profile,artwork:artwork,work:work,output:partial,branding:branding)
                        qa = try await Media.validate(output:partial,source:source,clip:clip,profile:request.profile,render:repaired,work:work)
                    }
                    if !job.unavailableTranscriptFeatures.isEmpty {
                        qa.limitations += job.unavailableTranscriptFeatures.map {"UNAVAILABLE: "+$0}
                    }
                    if FileManager.default.fileExists(atPath:output.path) {
                        if try Integrity.sha256(output) != qa.outputSHA256 {
                            let preserved = dir.appendingPathComponent("preserved-"+UUID().uuidString+"-"+clip.filename)
                            try FileManager.default.moveItem(at:output,to:preserved)
                        } else {try FileManager.default.removeItem(at:partial)}
                    }
                    if FileManager.default.fileExists(atPath:partial.path) {try FileManager.default.moveItem(at:partial,to:output)}
                    let probe = try await Media.probe(output)
                    job.clips[index].qa = qa; job.clips[index].sha256 = qa.outputSHA256
                    job.clips[index].failureStage = nil; job.clips[index].error = nil
                    job.clips[index].measuredDuration = probe.duration
                    job.clips[index].bytes = ((try FileManager.default.attributesOfItem(atPath:output.path))[.size] as? NSNumber)?.int64Value
                    try await save()
                    let evidence = dir.appendingPathComponent("evidence/\(clip.id)")
                    var retainedReceipt = render
                    retainedReceipt.selectedAudio = nil; retainedReceipt.background = nil; retainedReceipt.waveformPCM = nil
                    try Persistence.save(retainedReceipt,to:evidence.appendingPathComponent("render.json"))
                    try Persistence.save(qa,to:evidence.appendingPathComponent("qa.json"))
                    // Only disposable data created for this accepted attempt is
                    // removed. Original, verified output and evidence remain.
                    do {try storage.closeAttempt(work,jobID:job.id)}
                    catch {
                        job.storageWarnings = (job.storageWarnings ?? []) + ["Scratch preserved: "+error.localizedDescription]
                        try await save()
                    }
                    if StorageManager.automaticCleanupEnabled(root:root) {_ = try? storage.clean()}
                } catch {
                    // Processes.run drains its supervisor before throwing. A
                    // sealed failed attempt remains protected until this clip
                    // has a durable accepted replacement and retained QA.
                    try? storage.closeAttempt(work,jobID:job.id)
                    if error is CancellationError || error is StorageBlocked {throw error}
                    failures.append("Clip \(clip.id): \(error.localizedDescription)")
                    job.clips[index].failureStage = job.stage; job.clips[index].error = error.localizedDescription
                    try await save()
                }
            }
            guard failures.isEmpty, job.clips.allSatisfy({$0.qa?.passed == true}) else {throw JoeyError.failed(failures.joined(separator:"\n"))}
            if request.mode == .fullShow {try Planning.validateCoverage(duration:source.duration,exclusions:job.exclusions.map(\.interval),clips:job.clips.map(\.intervals))}
            job.state = .qaPassed; job.stage = "local package"; try await save()
            _ = try Records.write(job:job,directory:dir)
            if !request.fileToDrive {return job}
            guard job.unavailableTranscriptFeatures.isEmpty else {
                throw JoeyError.dependency("Production requirements incomplete: "+job.unavailableTranscriptFeatures.joined(separator:"; ")+". Local media QA passed; no filing or register write attempted.")
            }
            if request.productionWorkflow == nil {
                job.stage = "original archive verification"; try await save()
                try authorizeNewOperation()
                job.source?.archiveReference = try await delivery.archive(source:source,request:request); try await save()
            }
            job.stage = "Drive folder"; try await save()
            try authorizeNewOperation()
            let destination = try DestinationResolver.resolve(source:source,request:request,asset:.clip)
            job.folderID = try await delivery.episodeFolder(source:source,request:request,jobID:job.id,existingFolderID:job.folderID,intentURL:dir.appendingPathComponent("folder-intent.json")); try await save()
            let folder = job.folderID!
            var filingErrors: [String] = []
            for index in job.clips.indices {
                do {
                    job.stage = "Drive clip \(job.clips[index].id)"; try await save()
                    try authorizeNewOperation()
                    let receipt = try await delivery.upload(dir.appendingPathComponent(job.clips[index].filename),name:nil,parent:folder,destination:destination,replaceCompanion:false)
                    guard receipt.parent == folder, receipt.destination == destination else {throw JoeyError.failed("Clip receipt has the wrong episode parent or destination")}
                    try Self.acceptDelivery(receipt,for:&job.clips[index])
                    try await save()
                } catch {
                    if error is CancellationError || error is StorageBlocked {throw error}
                    filingErrors.append("Clip \(job.clips[index].id): \(error.localizedDescription)")
                    job.clips[index].failureStage = job.stage; job.clips[index].error = error.localizedDescription
                    try await save()
                }
            }
            guard filingErrors.isEmpty else {throw JoeyError.failed(filingErrors.joined(separator:"\n"))}
            job.state = .filed; job.stage = "companion records"; try await save()
            let files = try Records.write(job:job,directory:dir)
            for file in files where !["clip_manifest.json","RECONCILE.md"].contains(file.lastPathComponent) {
                try authorizeNewOperation()
                job.companions[file.lastPathComponent] = try await delivery.upload(file,name:nil,parent:folder,destination:destination,replaceCompanion:true); try await save()
            }
            job.stage = "register reconciliation"; try await save()
            try authorizeNewOperation()
            job.registerRows = try await delivery.reconcileRegister(job:job,tab:config.registerTab); try await save()
            // Stage final records with all clip/index/transcript/register proofs.
            // Completion is committed locally only after their own readback.
            var final = job; final.state = .filed; final.stage = "Final companion readback; completion authority is the durable app checkpoint"; final.error = nil
            let finalFiles = try Records.write(job:final,directory:dir)
            for file in finalFiles where ["clip_manifest.json","RECONCILE.md"].contains(file.lastPathComponent) {
                try authorizeNewOperation()
                job.companions[file.lastPathComponent] = try await delivery.upload(file,name:nil,parent:folder,destination:destination,replaceCompanion:true); try await save()
            }
            job.stage = "final Drive package verification"; try await save()
            guard job.hasRequiredCompletionEvidence else {throw JoeyError.failed("Required completion evidence is missing or incorrectly routed")}
            try await delivery.verifyPackage(job:job,directory:dir)
            job.state = .completed; job.stage = "complete"; job.error = nil; try await save()
            completedReadbackPassed = true
            return job
        } catch {
            // A rejected renewal must not downgrade a verified completed job or
            // replace its evidence. Only new operations require fresh authority.
            if completedReadbackPassed {throw error}
            let hasAccepted = !job.clips.isEmpty && job.clips.allSatisfy {$0.qa?.passed == true}
            job.state = error is CancellationError ? .cancelled : (hasAccepted ? .qaPassed : .failed)
            if let blocked = error as? StorageBlocked {
                job.state = .processing;job.stage = "Storage blocked — capacity recheck in 60 seconds"
                job.storageRequiredBytes = blocked.required
            }
            job.error = error is CancellationError ? "Cancelled; progress preserved for resume" : error.localizedDescription
            try await save()
            if job.source != nil {_ = try? Records.write(job:job,directory:dir)}
            return job
        }
    }
    static func acceptDelivery(_ receipt: DriveReceipt, for clip: inout ClipRecord) throws {
        guard receipt.name == clip.filename,receipt.sha256 == clip.sha256,
              receipt.bytes == clip.bytes,clip.qa?.passed == true,
              clip.qa?.outputSHA256 == receipt.sha256 else {
            throw JoeyError.failed("Verified delivery does not match the accepted clip identity")
        }
        clip.drive = receipt
        if clip.failureStage == "Drive clip \(clip.id)" {
            if let error = clip.error {
                clip.resolvedFailures = (clip.resolvedFailures ?? []) + [ResolvedClipFailure(stage:clip.failureStage!,error:error,resolvedAt:receipt.verifiedAt)]
            }
            clip.failureStage = nil;clip.error = nil
        }
    }
}
