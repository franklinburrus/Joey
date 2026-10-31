import Foundation

public actor Coordinator {
    public let root: URL
    public init(root: URL = Persistence.defaultRoot) throws {
        let path = root.standardizedFileURL.resolvingSymlinksInPath().path
        guard !path.contains("/CloudStorage/"), !path.contains("/Mobile Documents/") else {
            throw JoeyError.invalid("Working data must be outside synchronized Drive/iCloud storage")
        }
        self.root = root
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
    }
    public func jobs() throws -> [JobRecord] {
        let dir = root.appendingPathComponent("jobs")
        guard FileManager.default.fileExists(atPath:dir.path) else {return []}
        return try FileManager.default.contentsOfDirectory(at:dir,includingPropertiesForKeys:nil).compactMap {
            try? Persistence.load($0.appendingPathComponent("job.json")) as JobRecord
        }.sorted {$0.updatedAt > $1.updatedAt}
    }
    public func directory(for id: String) -> URL {root.appendingPathComponent("jobs").appendingPathComponent(id)}
    public func run(_ request: JobRequest, progress: @escaping @Sendable (JobRecord) async -> Void = {_ in}) async throws -> JobRecord {
        let request = try Persistence.decoder.decode(JobRequest.self,from:Persistence.encoder.encode(request))
        try request.validate()
        let lock = try ProcessingLock(directory:root)
        defer {withExtendedLifetime(lock) {}}
        let config = try Configuration.load(root:root)
        let requestHash = Integrity.textHash(String(decoding:try Persistence.encoder.encode(request),as:UTF8.self))
        let id = request.owner.rawValue+"-"+String(requestHash.prefix(24))
        let dir = directory(for:id), checkpoint = dir.appendingPathComponent("job.json")
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        var job: JobRecord = FileManager.default.fileExists(atPath:checkpoint.path) ? try Persistence.load(checkpoint) : JobRecord(id:id,request:request)
        guard job.request == request else {throw JoeyError.invalid("Job identity collision or changed immutable request")}
        func save() async throws {
            job.updatedAt = Date(); try Persistence.save(job,to:checkpoint); await progress(job)
        }
        do {
            if job.state == .completed {
                guard !job.clips.isEmpty, job.companions["clip_manifest.json"] != nil,
                      job.request.owner != .dub || job.registerRows.count == job.clips.count else {throw JoeyError.failed("Completed checkpoint lacks required delivery evidence")}
                for clip in job.clips {
                    guard clip.qa?.passed == true, clip.drive != nil,
                          try Integrity.sha256(dir.appendingPathComponent(clip.filename)) == clip.sha256 else {throw JoeyError.failed("Completed output changed: \(clip.filename)")}
                }
                // Current local bytes match accepted receipts. Reopening does
                // not claim a new provider readback or require network access.
                await progress(job); return job
            }
            job.error = nil; job.state = .processing; job.stage = "source"; try await save()
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
                let provider = try DriveDelivery(remote:config.rcloneRemote)
                sourceURL = try await provider.downloadOriginal(reference:archive,directory:dir)
            } else {sourceURL = try await Acquisition.acquire(request,directory:dir)}
            if let source = job.source {
                guard source.path == sourceURL.path, try Integrity.sha256(sourceURL) == source.sha256 else {throw JoeyError.failed("Original source changed; preserved job cannot silently switch inputs")}
            } else {job.source = try await Media.inspect(sourceURL,request:request); try await save()}
            guard let source = job.source else {throw JoeyError.failed("Missing inspected source")}
            job.stage = "transcription"; try await save()
            job.transcript = try await Acquisition.transcript(source:source,request:request,configuration:config,directory:dir)
            try await save()
            if job.clips.isEmpty {
                job.stage = "planning"
                job.exclusions = Editorial.exclusions(request,transcript:job.transcript!)
                job.clips = try Editorial.plan(request:request,source:source,transcript:job.transcript!,exclusions:job.exclusions)
                try await save()
            }
            let delivery = try DriveDelivery(remote:config.rcloneRemote)
            var artwork = request.artwork
            if source.kind == .audio, artwork == nil {
                job.stage = "artwork"; try await save()
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
                let attempts = dir.appendingPathComponent("scratch/\(clip.id)")
                let work = attempts.appendingPathComponent(UUID().uuidString)
                try FileManager.default.createDirectory(at:work,withIntermediateDirectories:true)
                let partial = work.appendingPathComponent("render.partial.mp4")
                do {
                    job.stage = "render clip \(clip.id)"; try await save()
                    let render: RenderReceipt
                    if FileManager.default.fileExists(atPath:partial.path), FileManager.default.fileExists(atPath:work.appendingPathComponent("render.json").path),
                       let existing: RenderReceipt = try? Persistence.load(work.appendingPathComponent("render.json")),
                       (try? await Media.validate(output:partial,source:source,clip:clip,profile:request.profile,render:existing,work:work)) != nil {
                        render = existing
                    } else {render = try await Media.render(source:source,clip:clip,profile:request.profile,artwork:artwork,work:work,output:partial)}
                    job.stage = "QA clip \(clip.id)"; try await save()
                    var qa: QAReport
                    do {qa = try await Media.validate(output:partial,source:source,clip:clip,profile:request.profile,render:render,work:work)}
                    catch {
                        if error is CancellationError {throw error}
                        // One supported clean re-encode repairs partial/corrupt
                        // local writes. Deterministic failure stays an error.
                        let repaired = try await Media.render(source:source,clip:clip,profile:request.profile,artwork:artwork,work:work,output:partial)
                        qa = try await Media.validate(output:partial,source:source,clip:clip,profile:request.profile,render:repaired,work:work)
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
                    if try Integrity.sha256(output) == qa.outputSHA256 {try FileManager.default.removeItem(at:work)}
                } catch {
                    if error is CancellationError {throw error}
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
            job.stage = "original archive verification"; try await save()
            job.source?.archiveReference = try await delivery.archive(source:source,request:request); try await save()
            job.stage = "Drive folder"; try await save()
            job.folderID = try await delivery.episodeFolder(source:source,jobID:job.id,intentURL:dir.appendingPathComponent("folder-intent.json")); try await save()
            let folder = job.folderID!
            var filingErrors: [String] = []
            for index in job.clips.indices {
                do {
                    job.stage = "Drive clip \(job.clips[index].id)"; try await save()
                    job.clips[index].drive = try await delivery.upload(dir.appendingPathComponent(job.clips[index].filename),parent:folder)
                    try await save()
                } catch {
                    if error is CancellationError {throw error}
                    filingErrors.append("Clip \(job.clips[index].id): \(error.localizedDescription)")
                    job.clips[index].failureStage = job.stage; job.clips[index].error = error.localizedDescription
                    try await save()
                }
            }
            guard filingErrors.isEmpty else {throw JoeyError.failed(filingErrors.joined(separator:"\n"))}
            job.state = .filed; job.stage = "companion records"; try await save()
            let files = try Records.write(job:job,directory:dir)
            for file in files where !["clip_manifest.json","RECONCILE.md"].contains(file.lastPathComponent) {
                job.companions[file.lastPathComponent] = try await delivery.upload(file,parent:folder,replaceCompanion:true); try await save()
            }
            job.stage = "register reconciliation"; try await save()
            job.registerRows = try await delivery.reconcileRegister(job:job,tab:config.registerTab); try await save()
            // Stage final records with all clip/index/transcript/register proofs.
            // Completion is committed locally only after their own readback.
            var final = job; final.state = .filed; final.stage = "Final companion readback; completion authority is the durable app checkpoint"; final.error = nil
            let finalFiles = try Records.write(job:final,directory:dir)
            for file in finalFiles where ["clip_manifest.json","RECONCILE.md"].contains(file.lastPathComponent) {
                job.companions[file.lastPathComponent] = try await delivery.upload(file,parent:folder,replaceCompanion:true); try await save()
            }
            job.state = .completed; job.stage = "complete"; job.error = nil; try await save()
            return job
        } catch {
            let hasAccepted = !job.clips.isEmpty && job.clips.allSatisfy {$0.qa?.passed == true}
            job.state = error is CancellationError ? .cancelled : (hasAccepted ? .qaPassed : .failed)
            job.error = error is CancellationError ? "Cancelled; progress preserved for resume" : error.localizedDescription
            try await save()
            if job.source != nil, job.transcript != nil {_ = try? Records.write(job:job,directory:dir)}
            return job
        }
    }
}
