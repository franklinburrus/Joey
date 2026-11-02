import XCTest
@testable import JoeyCore

final class RecoveryRegressionTests: XCTestCase {
    private func workspace() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        return root
    }
    private func legacyID(_ request: JobRequest) throws -> String {
        request.owner.rawValue + "-" + String(Integrity.textHash(String(decoding:try Persistence.encoder.encode(request),as:UTF8.self)).prefix(24))
    }
    private func source(_ request: JobRequest) -> SourceRecord {
        SourceRecord(id:request.sourceID,owner:request.owner,title:request.title,path:"unused synthetic source",bytes:1,
            sha256:request.expectedSourceSHA256 ?? String(repeating:"a",count:64),duration:100,width:720,height:1280,fps:30,
            hasAudio:false,kind:.nativeVideo,streams:[],authorizationBasis:"Synthetic regression only",classificationEvidence:"Synthetic fixture")
    }
    private func renew(_ request: JobRequest, in root: URL) throws -> JobRequest {
        let proof = root.appendingPathComponent("renewed-proof.txt")
        try Data("New synthetic account observation; no provider access".utf8).write(to:proof)
        let evidence = EvidenceFile(path:proof.path,sha256:try Integrity.sha256(proof),basis:"Synthetic renewal")
        var renewed = request
        renewed.profile.x!.checkedAt = Date().addingTimeInterval(-5)
        renewed.profile.instagram!.checkedAt = Date().addingTimeInterval(-5)
        renewed.profile.x!.validUntil = Date().addingTimeInterval(7200)
        renewed.profile.instagram!.validUntil = Date().addingTimeInterval(7200)
        renewed.profile.x!.accountEvidence = evidence
        renewed.profile.instagram!.accountEvidence = evidence
        return renewed
    }
    private func completed(_ request: JobRequest, root: URL) throws -> (JobRecord, URL) {
        var job = JobRecord(id:try legacyID(request),request:request)
        let directory = root.appendingPathComponent("jobs/"+job.id)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let output = directory.appendingPathComponent("accepted.mp4")
        try Data("Synthetic accepted bytes; not playable media".utf8).write(to:output)
        let hash = try Integrity.sha256(output)
        let bytes = Int64(try Data(contentsOf:output).count)
        let receipt = DriveReceipt(id:"synthetic_clip_id_123456789",name:output.lastPathComponent,parent:"synthetic_folder_123456789",
            bytes:bytes,md5:try Integrity.md5(output),sha256:hash,url:"https://example.invalid/synthetic",permissions:["user:owner"],verifiedAt:Date())
        job.source = source(request)
        let original = directory.appendingPathComponent("original.synthetic")
        try Data("Synthetic original identity".utf8).write(to:original)
        job.source!.path = original.path;job.source!.sha256 = try Integrity.sha256(original)
        job.transcript = Transcript(sourceID:request.sourceID,sourceSHA256:job.source!.sha256,duration:100,engine:"Synthetic fixture",
            segments:[TranscriptSegment(start:0,end:100,text:"Synthetic complete source.")])
        job.planningBasis = .transcriptAssisted
        job.folderID = receipt.parent
        job.clips = [ClipRecord(id:1,title:"Synthetic",intervals:[Interval(0,100)],filename:output.lastPathComponent,
            measuredDuration:100,bytes:bytes,sha256:hash,qa:QAReport(checkedAt:Date(),checks:[:],outputSHA256:hash,passed:true,
                limitations:["Synthetic checkpoint fixture; no media or provider acceptance"]),drive:receipt)]
        let destination = try DestinationResolver.resolve(source:job.source!,request:request,asset:.clip)
        job.clips[0].drive!.destination = destination
        job.clips[0].drive!.permissionFingerprint = String(repeating:"a",count:64)
        for name in Records.companionNames(source:job.source!) {
            var companion = job.clips[0].drive!;companion.name = name;companion.id = "synthetic_"+name
            job.companions[name] = companion
        }
        job.registerRows = request.owner == .dub ? ["fixture-row"] : []
        job.state = .completed;job.stage = "complete"
        try Persistence.save(job.transcript,to:directory.appendingPathComponent("transcript.json"))
        try Persistence.save(job,to:directory.appendingPathComponent("job.json"))
        return (job,directory)
    }
    func testFilingCompletionRequiresParentsRegistersAndFinalReadback() async throws {
        for fault in ["none","parent","register","final-readback"] {
            let root = try workspace();defer {try? FileManager.default.removeItem(at:root)}
            var request = try Fixtures.request(dir:root,path:"unused");request.fileToDrive = true
            var (saved,directory) = try completed(request,root:root)
            saved.state = .qaPassed;saved.clips[0].drive = nil;saved.companions = [:];saved.registerRows = []
            try Persistence.save(saved,to:directory.appendingPathComponent("job.json"))
            let persisted: JobRecord = try Persistence.load(directory.appendingPathComponent("job.json"))
            let provider = RecoveryDelivery(filingFault:fault)
            let coordinator = try Coordinator(root:root)
            let first = try await Coordinator.$deliveryOverride.withValue(provider) {try await coordinator.run(request)}
            XCTAssertEqual(first.state,.qaPassed,"Lost upload response must retain accepted QA")
            let final = try await Coordinator.$deliveryOverride.withValue(provider) {try await coordinator.run(request)}
            XCTAssertEqual(final.state,fault == "none" ? .completed : .qaPassed,final.error ?? fault)
            XCTAssertEqual(final.hasRequiredCompletionEvidence,fault == "none" || fault == "final-readback")
            XCTAssertEqual(JobPresentation(job:final).completed,fault == "none")
            XCTAssertEqual(final.clips[0].qa,persisted.clips[0].qa,"Filing failure must not rerender or replace accepted QA")
            XCTAssertEqual(try Integrity.sha256(directory.appendingPathComponent(saved.clips[0].filename)),saved.clips[0].sha256)
            let creations = await provider.clipCreations
            XCTAssertEqual(creations,1,"Interrupted filing must not create a second media file")
        }
    }

    func testTaxstonePreplanningCheckpointsRetainOriginalJobIdentity() throws {
        let root = try workspace();defer {try? FileManager.default.removeItem(at:root)}
        var request = try Fixtures.request(dir:root,path:"unused")
        request.owner = .taxstone;request.sourceID = "soundcloud:123";request.localPath = nil
        request.originalURL = "https://drive.google.com/file/d/synthetic_archive_123456789/view"
        request.archiveReference = request.originalURL;request.productionWorkflow = .taxstoneLibrary;request.fileToDrive = true
        request.expectedSourceSHA256 = String(repeating:"a",count:64)
        for stage in ["source","original archive verification","transcription","planning"] {
            var job = JobRecord(id:"existing-taxstone-job",request:request)
            job.state = .processing;job.stage = stage
            if stage != "source" {job.source = source(request)}
            if stage == "planning" {
                job.transcript = Transcript(sourceID:request.sourceID,sourceSHA256:request.expectedSourceSHA256!,duration:100,
                    engine:"fixture",segments:[TranscriptSegment(start:0,end:100,text:"Synthetic complete transcript.")])
            }
            var episode = TaxstoneLibraryEpisode(id:request.sourceID,title:"Fixture",driveID:"synthetic_archive_123456789",sourceSHA256:request.expectedSourceSHA256!)
            XCTAssertNoThrow(try TaxstoneLibrary.reconcile(&episode,job:job,directory:root),stage)
            XCTAssertEqual(episode.jobID,job.id,stage)
            XCTAssertEqual(episode.status,"RESUMABLE",stage)
            XCTAssertEqual(episode.plannedClips,0)
        }
    }
    func testTaxstoneCoordinatorResumesEveryPreplanningStageInTheSameDirectory() async throws {
        let root = try workspace();defer {try? FileManager.default.removeItem(at:root)}
        let original = root.appendingPathComponent("source.mp4")
        _ = try await Processes.run("ffmpeg",["-v","error","-f","lavfi","-i","testsrc2=s=320x180:r=30:d=2",
            "-c:v","libx264","-pix_fmt","yuv420p",original.path])
        var request = try Fixtures.request(dir:root,path:"unused")
        request.owner = .taxstone;request.sourceID = "soundcloud:synthetic-123";request.localPath = nil
        request.originalURL = "https://drive.google.com/file/d/synthetic_archive_123456789/view"
        request.archiveReference = request.originalURL;request.productionWorkflow = .taxstoneLibrary;request.fileToDrive = true
        request.expectedSourceSHA256 = try Integrity.sha256(original)
        let inspected = try await Media.inspect(original,request:request)
        let transcript = Transcript(sourceID:request.sourceID,sourceSHA256:inspected.sha256,duration:inspected.duration,
            engine:"Synthetic cached transcript",segments:[TranscriptSegment(start:0,end:inspected.duration,text:"Complete synthetic source.")])
        for stage in ["source","original archive verification","transcription","planning"] {
            let runtime = root.appendingPathComponent(stage.replacingOccurrences(of:" ",with:"-"))
            var job = JobRecord(id:try legacyID(request),request:request)
            job.state = .processing;job.stage = stage
            if stage != "source" {job.source = inspected}
            if stage == "planning" {job.transcript = transcript}
            let directory = runtime.appendingPathComponent("jobs/"+job.id)
            try Persistence.save(job,to:directory.appendingPathComponent("job.json"))
            // A previously imported valid cache is independent of the durable
            // coordinator stage. No ASR helper or real historical data is read.
            try Persistence.save(transcript,to:directory.appendingPathComponent("transcript.json"))
            let provider = RecoveryDelivery(original:original)
            let coordinator = try Coordinator(root:runtime)
            let resumed = try await Coordinator.$deliveryOverride.withValue(provider) {
                try await coordinator.run(request) {progress in
                    if progress.state == .processing,progress.stage == "planning",!progress.clips.isEmpty {throw CancellationError()}
                }
            }
            XCTAssertEqual(resumed.id,job.id,stage);XCTAssertEqual(resumed.state,.cancelled,resumed.error ?? stage)
            XCTAssertEqual(resumed.planningBasis,.transcriptAssisted,stage)
            XCTAssertEqual(resumed.clips.count,1,stage)
            XCTAssertEqual(resumed.source?.sha256,inspected.sha256,stage)
            XCTAssertEqual(resumed.transcript,transcript,stage)
            let jobs = try await coordinator.jobs(),downloads = await provider.downloads
            XCTAssertEqual(jobs.count,1);XCTAssertEqual(downloads,stage == "source" ? 1 : 0)
            XCTAssertEqual(try Integrity.sha256(original),inspected.sha256)
        }
    }
    func testCompletedCheckpointReopensAfterCapabilityExpiryWithoutChangingAcceptedBytes() async throws {
        let root = try workspace();defer {try? FileManager.default.removeItem(at:root)}
        var request = try Fixtures.request(dir:root,path:"unused")
        request.fileToDrive = true
        request.profile.x!.checkedAt = Date().addingTimeInterval(-7200)
        request.profile.instagram!.checkedAt = Date().addingTimeInterval(-7200)
        request.profile.x!.validUntil = Date().addingTimeInterval(-3600)
        request.profile.instagram!.validUntil = Date().addingTimeInterval(-3600)
        let (saved,directory) = try completed(request,root:root)
        let checkpoint = directory.appendingPathComponent("job.json")
        let original = try Data(contentsOf:checkpoint)
        let result = try await Coordinator(root:root).run(request)
        XCTAssertEqual(result.id,saved.id)
        XCTAssertEqual(result.state,.completed)
        XCTAssertEqual(try Data(contentsOf:checkpoint),original)
        XCTAssertEqual(try Integrity.sha256(directory.appendingPathComponent(saved.clips[0].filename)),saved.clips[0].sha256)
    }
    func testCompletedCheckpointRejectsDriveReceiptForDifferentAcceptedBytes() async throws {
        let root = try workspace();defer {try? FileManager.default.removeItem(at:root)}
        var request = try Fixtures.request(dir:root,path:"unused");request.fileToDrive = true
        var (saved,directory) = try completed(request,root:root)
        saved.clips[0].drive!.sha256 = String(repeating:"b",count:64)
        try Persistence.save(saved,to:directory.appendingPathComponent("job.json"))
        let persisted: JobRecord = try Persistence.load(directory.appendingPathComponent("job.json"))
        let result = try await Coordinator(root:root).run(request)
        XCTAssertEqual(result.state,.qaPassed)
        XCTAssertTrue(result.error?.contains("Completed checkpoint lacks required delivery evidence") == true)
        XCTAssertFalse(JobPresentation(job:result).completed)
        XCTAssertEqual(result.clips[0].drive,persisted.clips[0].drive,"Preserve conflicting evidence for reconciliation")
        XCTAssertEqual(try Integrity.sha256(directory.appendingPathComponent(saved.clips[0].filename)),saved.clips[0].sha256)
    }
    func testRenewedRequestFindsLegacyCheckpointInsteadOfCreatingSecondJob() async throws {
        let root = try workspace();defer {try? FileManager.default.removeItem(at:root)}
        let request = try Fixtures.request(dir:root,path:"unused")
        let (saved,directory) = try completed(request,root:root)
        let renewed = try renew(request,in:root)
        XCTAssertEqual(try request.stableID(),try renewed.stableID())
        let coordinator = try Coordinator(root:root)
        let result = try await coordinator.run(renewed) {job in
            if job.stage == "source",job.state == .processing {throw CancellationError()}
        }
        XCTAssertEqual(result.id,saved.id)
        XCTAssertEqual(result.state,.completed)
        XCTAssertEqual(result.request.profile.x?.accountEvidence.sha256,renewed.profile.x?.accountEvidence.sha256)
        let jobs = try await coordinator.jobs()
        XCTAssertEqual(jobs.count,1)
        XCTAssertEqual(try Integrity.sha256(directory.appendingPathComponent(saved.clips[0].filename)),saved.clips[0].sha256)
    }
    func testRenewedOwnerSettingsReachPartialFiledAndCompletedJobs() async throws {
        for state in [JobState.processing,.filed,.completed] {
            let root = try workspace();defer {try? FileManager.default.removeItem(at:root)}
            var request = try Fixtures.request(dir:root,path:"unused")
            request.owner = .taxstone
            var (saved,directory) = try completed(request,root:root)
            saved.state = state
            try Persistence.save(saved,to:directory.appendingPathComponent("job.json"))
            var settings = Configuration();settings.taxstoneProfile = try renew(request,in:root).profile
            try Persistence.save(settings,to:root.appendingPathComponent("settings.json"))
            let result = try await Coordinator(root:root).run(request) {job in
                if job.stage == "source",job.state == .processing {throw CancellationError()}
            }
            XCTAssertEqual(result.id,saved.id)
            XCTAssertEqual(result.request.profile.x?.accountEvidence.sha256,settings.taxstoneProfile?.x?.accountEvidence.sha256)
            XCTAssertEqual(result.clips.map(\.sha256),saved.clips.map(\.sha256))
            XCTAssertEqual(try Integrity.sha256(directory.appendingPathComponent(saved.clips[0].filename)),saved.clips[0].sha256)
        }
    }
    func testCapabilityRenewalRejectsChangedAccountSurfaceAndTechnicalContract() async throws {
        let root = try workspace();defer {try? FileManager.default.removeItem(at:root)}
        let request = try Fixtures.request(dir:root,path:"unused")
        let (saved,directory) = try completed(request,root:root)
        let before = try Data(contentsOf:directory.appendingPathComponent("job.json"))
        let renewed = try renew(request,in:root)
        var changed: [JobRequest] = []
        var next = renewed;next.profile.x!.account = "different-account";changed.append(next)
        next = renewed;next.profile.instagram!.surface = "different-upload-destination";changed.append(next)
        next = renewed;next.profile.x!.maxDuration -= 10;changed.append(next)
        next = renewed;next.profile.instagram!.maxBytes -= 1;changed.append(next)
        next = renewed;next.profile.width = 1080;next.profile.height = 1920;changed.append(next)
        let coordinator = try Coordinator(root:root)
        for proposed in changed {
            do {_ = try await coordinator.run(proposed);XCTFail("Incompatible resume accepted")}
            catch {XCTAssertTrue(error.localizedDescription.contains("saved account") || error.localizedDescription.contains("profile"),error.localizedDescription)}
            XCTAssertEqual(try Data(contentsOf:directory.appendingPathComponent("job.json")),before)
        }
        var settings = Configuration();settings.profile = changed[0].profile
        try Persistence.save(settings,to:root.appendingPathComponent("settings.json"))
        do {_ = try await coordinator.run(request);XCTFail("Incompatible configured renewal accepted")}
        catch {XCTAssertTrue(error.localizedDescription.contains("saved account"),error.localizedDescription)}
        XCTAssertEqual(try Data(contentsOf:directory.appendingPathComponent("job.json")),before)
        let jobs = try await coordinator.jobs()
        XCTAssertEqual(jobs.count,1);XCTAssertEqual(jobs.first?.id,saved.id)
    }
    func testFreshEvidenceStillRequiredBeforeIncompleteJobCanReachProvider() async throws {
        let root = try workspace();defer {try? FileManager.default.removeItem(at:root)}
        var request = try Fixtures.request(dir:root,path:"unused");request.fileToDrive = true
        request.profile.x!.checkedAt = Date().addingTimeInterval(-7200)
        request.profile.instagram!.checkedAt = Date().addingTimeInterval(-7200)
        request.profile.x!.validUntil = Date().addingTimeInterval(-3600)
        request.profile.instagram!.validUntil = Date().addingTimeInterval(-3600)
        var (saved,directory) = try completed(request,root:root)
        saved.state = .filed
        try Persistence.save(saved,to:directory.appendingPathComponent("job.json"))
        let provider = RecoveryDelivery()
        let blocked = try await Coordinator.$deliveryOverride.withValue(provider) {
            try await Coordinator(root:root).run(request)
        }
        XCTAssertEqual(blocked.id,saved.id);XCTAssertNotEqual(blocked.state,.completed)
        XCTAssertTrue(blocked.error?.contains("expired") == true)
        let calls = await provider.calls
        XCTAssertEqual(calls,0)
        XCTAssertEqual(blocked.clips.map(\.sha256),saved.clips.map(\.sha256))
    }
    func testExpiredCompletedEvidenceCannotHideChangedAcceptedOutput() async throws {
        let root = try workspace();defer {try? FileManager.default.removeItem(at:root)}
        var request = try Fixtures.request(dir:root,path:"unused")
        request.profile.x!.checkedAt = Date().addingTimeInterval(-7200)
        request.profile.x!.validUntil = Date().addingTimeInterval(-3600)
        let (saved,directory) = try completed(request,root:root)
        try Data("corrupted synthetic accepted file".utf8).write(to:directory.appendingPathComponent(saved.clips[0].filename))
        let checked = try await Coordinator(root:root).run(request)
        XCTAssertNotEqual(checked.state,.completed)
        XCTAssertTrue(checked.error?.contains("Completed output changed") == true)
    }
    func testCapabilityExpiryAfterLocalQABlocksNewProviderOperations() async throws {
        let root = try workspace();defer {try? FileManager.default.removeItem(at:root)}
        var request = try Fixtures.request(dir:root,path:"unused");request.owner = .taxstone;request.fileToDrive = true
        request.profile.x!.validUntil = Date().addingTimeInterval(2)
        var (saved,directory) = try completed(request,root:root)
        saved.state = .qaPassed;saved.companions = [:];saved.clips[0].drive = nil
        try Persistence.save(saved,to:directory.appendingPathComponent("job.json"))
        let provider = RecoveryDelivery()
        let result = try await Coordinator.$deliveryOverride.withValue(provider) {
            try await Coordinator(root:root).run(request) {job in
                if job.stage == "local package",job.error == nil {
                    let remaining = job.request.profile.x!.validUntil.timeIntervalSinceNow + 0.05
                    if remaining > 0 {try await Task.sleep(nanoseconds:UInt64(remaining*1_000_000_000))}
                }
            }
        }
        XCTAssertEqual(result.state,.qaPassed)
        XCTAssertTrue(result.error?.contains("expired") == true,result.error ?? "")
        let calls = await provider.calls
        XCTAssertEqual(calls,0,"Freshness must be checked after long local work, before archive/folder/upload writes")
        XCTAssertEqual(result.clips[0].sha256,saved.clips[0].sha256)
    }
    func testCancellationInProgressCallbackPreventsFollowingProviderDispatch() async throws {
        let root = try workspace();defer {try? FileManager.default.removeItem(at:root)}
        var request = try Fixtures.request(dir:root,path:"unused");request.owner = .taxstone;request.fileToDrive = true
        var (saved,directory) = try completed(request,root:root)
        saved.state = .qaPassed;saved.companions = [:];saved.clips[0].drive = nil
        try Persistence.save(saved,to:directory.appendingPathComponent("job.json"))
        let provider = RecoveryDelivery()
        let task = Task {
            try await Coordinator.$deliveryOverride.withValue(provider) {
                try await Coordinator(root:root).run(request) {job in
                    if job.stage == "original archive verification",job.state != .cancelled {
                        withUnsafeCurrentTask {$0?.cancel()}
                    }
                }
            }
        }
        let result = try await task.value
        XCTAssertEqual(result.state,.cancelled)
        let calls = await provider.calls
        XCTAssertEqual(calls,0)
        XCTAssertEqual(result.clips[0].sha256,saved.clips[0].sha256)
    }
    func testUploadFailureResumesReconcilesAndClearsOnlyResolvedErrorWithoutRendering() async throws {
        let root = try workspace();defer {try? FileManager.default.removeItem(at:root)}
        var request = try Fixtures.request(dir:root,path:"unused");request.owner = .taxstone;request.fileToDrive = true
        var (saved,directory) = try completed(request,root:root)
        saved.state = .qaPassed;saved.stage = "local package";saved.companions = [:]
        saved.clips[0].drive = nil
        try Persistence.save(saved,to:directory.appendingPathComponent("job.json"))
        let persisted: JobRecord = try Persistence.load(directory.appendingPathComponent("job.json"))
        let output = directory.appendingPathComponent(saved.clips[0].filename)
        let identity = try FileManager.default.attributesOfItem(atPath:output.path)
        let provider = RecoveryDelivery()
        let first = try await Coordinator.$deliveryOverride.withValue(provider) {
            try await Coordinator(root:root).run(request) {job in
                if job.stage.hasPrefix("render clip") || job.stage.hasPrefix("QA clip") {throw JoeyError.failed("Accepted media must never be rendered in this test")}
            }
        }
        XCTAssertEqual(first.state,.qaPassed)
        XCTAssertEqual(first.clips[0].failureStage,"Drive clip 1")
        XCTAssertEqual(first.clips[0].error,"Synthetic uncertain upload response")
        XCTAssertNil(first.clips[0].drive)
        // A fresh coordinator must load the failed durable checkpoint. The
        // provider has committed the object; reconciliation returns that object.
        let recovered = try await Coordinator.$deliveryOverride.withValue(provider) {
            try await Coordinator(root:root).run(request) {job in
                if job.stage.hasPrefix("render clip") || job.stage.hasPrefix("QA clip") {throw JoeyError.failed("Accepted media must never be rendered in this test")}
            }
        }
        XCTAssertEqual(recovered.id,saved.id);XCTAssertEqual(recovered.state,.completed,recovered.error ?? "")
        XCTAssertNil(recovered.clips[0].failureStage);XCTAssertNil(recovered.clips[0].error)
        XCTAssertEqual(recovered.clips[0].resolvedFailures?.map(\.error),["Synthetic uncertain upload response"])
        XCTAssertEqual(recovered.clips[0].resolvedFailures?.map(\.stage),["Drive clip 1"])
        XCTAssertEqual(recovered.clips[0].qa,persisted.clips[0].qa)
        XCTAssertEqual(try Integrity.sha256(output),saved.clips[0].sha256)
        let after = try FileManager.default.attributesOfItem(atPath:output.path)
        XCTAssertEqual(after[.modificationDate] as? Date,identity[.modificationDate] as? Date)
        XCTAssertEqual(after[.systemFileNumber] as? NSNumber,identity[.systemFileNumber] as? NSNumber)
        XCTAssertNoThrow(try BufferPreflight.validateJob(recovered,clip:recovered.clips[0]))
        let creations = await provider.clipCreations, attempts = await provider.clipAttempts
        XCTAssertEqual(creations,1);XCTAssertEqual(attempts,2)
        var unrelated = recovered.clips[0]
        unrelated.failureStage = "QA clip 1";unrelated.error = "Unrelated current failure"
        try Coordinator.acceptDelivery(recovered.clips[0].drive!,for:&unrelated)
        XCTAssertEqual(unrelated.failureStage,"QA clip 1");XCTAssertEqual(unrelated.error,"Unrelated current failure")
        XCTAssertThrowsError(try BufferPreflight.validateJob(recovered,clip:unrelated))
    }
    func testCancellationAfterDispatchedUploadRetainsCheckpointAndReconcilesCommittedObject() async throws {
        let root = try workspace();defer {try? FileManager.default.removeItem(at:root)}
        var request = try Fixtures.request(dir:root,path:"unused");request.owner = .taxstone;request.fileToDrive = true
        var (saved,directory) = try completed(request,root:root)
        saved.state = .qaPassed;saved.companions = [:];saved.clips[0].drive = nil
        try Persistence.save(saved,to:directory.appendingPathComponent("job.json"))
        let provider = RecoveryDelivery(suspendAfterCommit:true)
        let task = Task {
            try await Coordinator.$deliveryOverride.withValue(provider) {
                try await Coordinator(root:root).run(request)
            }
        }
        defer {task.cancel()}
        for _ in 0..<100 {
            if await provider.clipCreations == 1 {break}
            try await Task.sleep(nanoseconds:10_000_000)
        }
        let dispatched = await provider.clipCreations
        XCTAssertEqual(dispatched,1,"Test must cancel after provider dispatch, not before upload")
        task.cancel()
        let cancelled = try await task.value
        XCTAssertEqual(cancelled.state,.cancelled)
        XCTAssertNil(cancelled.clips[0].drive)
        XCTAssertEqual(cancelled.clips[0].sha256,saved.clips[0].sha256)
        let checkpoint: JobRecord = try Persistence.load(directory.appendingPathComponent("job.json"))
        XCTAssertEqual(checkpoint.state,.cancelled);XCTAssertFalse(checkpoint.resumesAutomatically)
        let result = try await Coordinator.$deliveryOverride.withValue(provider) {
            try await Coordinator(root:root).run(request) {job in
                if job.stage.hasPrefix("render clip") {throw JoeyError.failed("Cancellation recovery must not rerender accepted media")}
            }
        }
        XCTAssertEqual(result.state,.completed,result.error ?? "")
        XCTAssertEqual(result.id,saved.id)
        let creations = await provider.clipCreations, attempts = await provider.clipAttempts
        XCTAssertEqual(creations,1);XCTAssertEqual(attempts,2)
        XCTAssertEqual(try Integrity.sha256(directory.appendingPathComponent(saved.clips[0].filename)),saved.clips[0].sha256)
    }
}

private actor RecoveryDelivery: CoordinatorDelivery {
    var calls = 0
    var downloads = 0
    var clipCreations = 0
    var clipAttempts = 0
    var committed: [String:DriveReceipt] = [:]
    let suspendAfterCommit: Bool
    let original: URL?
    let filingFault: String
    init(suspendAfterCommit: Bool = false, original: URL? = nil, filingFault: String = "none") {self.suspendAfterCommit = suspendAfterCommit;self.original = original;self.filingFault = filingFault}
    func metadata(_ id: String) async throws -> [String:Any] {throw JoeyError.failed("Unexpected metadata lookup in synthetic recovery")}
    func downloadOriginal(reference: String, directory: URL) async throws -> URL {
        downloads += 1
        guard let original else {throw JoeyError.failed("Saved original must be reused")}
        return original
    }
    func archive(source: SourceRecord, request: JobRequest) async throws -> String {
        calls += 1;return "https://drive.google.com/file/d/synthetic_archive_123456789/view"
    }
    func episodeFolder(source: SourceRecord, request: JobRequest, jobID: String, existingFolderID: String?, intentURL: URL) async throws -> String {
        calls += 1;return "synthetic_folder_123456789"
    }
    func resolveArtwork(source: SourceRecord, configuration: Configuration, root: URL) async throws -> Artwork {
        throw JoeyError.failed("Native synthetic checkpoint must not resolve artwork")
    }
    func verifyPackage(job: JobRecord, directory: URL) async throws {
        guard job.hasRequiredCompletionEvidence else {throw JoeyError.failed("Synthetic package incomplete")}
        if filingFault == "final-readback" {throw JoeyError.failed("Synthetic final parent readback failure")}
    }
    func reconcileRegister(job: JobRecord, tab: String) async throws -> [String] {
        calls += 1;return DestinationResolver.requiresDUBRegister(job.request) && filingFault != "register" ? ["fixture-row"] : []
    }
    func upload(_ local: URL, name: String?, parent: String, destination: FilingDestination, replaceCompanion: Bool) async throws -> DriveReceipt {
        calls += 1
        let filename = name ?? local.lastPathComponent
        let bytes = Int64(try Data(contentsOf:local).count), hash = try Integrity.sha256(local)
        if local.pathExtension == "mp4" {
            clipAttempts += 1
            if let existing = committed[filename] {
                guard existing.sha256 == hash,existing.bytes == bytes,existing.parent == parent else {throw JoeyError.failed("Synthetic reconciliation identity changed")}
                if filingFault == "parent" {var wrong = existing;wrong.parent = "incorrect-actual-parent";return wrong}
                return existing
            }
            clipCreations += 1
        }
        let receipt = DriveReceipt(id:"synthetic_"+Integrity.textHash(filename),name:filename,parent:parent,bytes:bytes,
            md5:try Integrity.md5(local),sha256:hash,url:"https://example.invalid/synthetic",permissions:["user:owner"],verifiedAt:Date(),destination:destination,permissionFingerprint:String(repeating:"a",count:64))
        committed[filename] = receipt
        if local.pathExtension == "mp4",suspendAfterCommit {try await Task.sleep(nanoseconds:60_000_000_000)}
        if local.pathExtension == "mp4" {throw JoeyError.failed("Synthetic uncertain upload response")}
        return receipt
    }
}
