import XCTest
import Darwin
@testable import JoeyCore

final class RecoveryRegressionTests: XCTestCase {
    func testHistoricalAcceptedDurationRetainsSavedHardLimitWithoutNewEncodingMargin() async throws {
        let root = try workspace()
        defer {try? FileManager.default.removeItem(at:root)}
        var request = try Fixtures.request(dir:root,path:"unused")
        request.profile.x!.surface = "Buffer X video"
        request.profile.instagram!.surface = "Buffer Instagram Reel"
        request.profile.x!.maxDuration = 140
        request.profile.instagram!.maxDuration = 140
        var (saved,directory) = try completed(request,root:root)
        saved.source!.duration = 140
        saved.transcript!.duration = 140
        saved.transcript!.segments[0].end = 140
        saved.clips[0].intervals = [Interval(0,140)]
        saved.clips[0].measuredDuration = 140
        try Persistence.save(saved,to:directory.appendingPathComponent("job.json"))
        XCTAssertThrowsError(try DurationPolicy(profile:request.profile).validateMeasured(140,expected:140),
            "New exports retain their measured ceiling margin")
        XCTAssertTrue(saved.hasRequiredCompletionEvidence)
        let result = try await Coordinator(root:root).run(request)
        XCTAssertEqual(result.state,.completed,result.error ?? "")
        XCTAssertEqual(result.clips[0].sha256,saved.clips[0].sha256)
        var outside = saved
        outside.clips[0].measuredDuration = 140.001
        XCTAssertFalse(outside.hasRequiredCompletionEvidence,"A historical receipt cannot exceed its saved hard ceiling")
    }

    func testNoncompletedAcceptedPlanRejectionPreservesCompanionsOnRepeatedResume() async throws {
        let root = try workspace()
        defer {try? FileManager.default.removeItem(at:root)}
        let request = try Fixtures.request(dir:root,path:"unused")
        var (saved,directory) = try completed(request,root:root)
        saved.state = .qaPassed
        saved.clips[0].intervals = [Interval(0,50)]
        let files = try Records.write(job:saved,directory:directory)
        let before = try files.map {($0,try Data(contentsOf:$0))}
        try Persistence.save(saved,to:directory.appendingPathComponent("job.json"))
        for _ in 0..<2 {
            let result = try await Coordinator(root:root).run(request)
            XCTAssertEqual(result.state,.qaPassed)
            XCTAssertEqual(result.stage,"accepted plan verification")
            for (file,data) in before {XCTAssertEqual(try Data(contentsOf:file),data,file.lastPathComponent)}
        }
    }

    func testCompletedReopenRejectsConflictingHighlightCounts() async throws {
        for fixed in [false,true] {
            let root = try workspace()
            defer {try? FileManager.default.removeItem(at:root)}
            var request = try joeRequest(root:root)
            request.productionWorkflow = .link
            request.profile = try Fixtures.landscapeProfile(dir:root)
            request.mode = .highlights
            request.requestedCount = 2
            request.fixedIntervals = fixed ? [Interval(0,100)] : nil
            let (saved,_) = try completed(request,root:root)
            XCTAssertFalse(saved.hasRequiredCompletionEvidence)
            let result = try await Coordinator(root:root).run(request)
            XCTAssertNotEqual(result.state,.completed)
        }
    }

    func testCompletedReopenEnforcesSavedByteCeilingIncludingEquality() async throws {
        for allowed in [Int64(1),Int64(44)] {
            let root = try workspace()
            defer {try? FileManager.default.removeItem(at:root)}
            var request = try Fixtures.request(dir:root,path:"unused")
            request.profile.x!.maxBytes = allowed
            request.profile.instagram!.maxBytes = allowed
            let (saved,_) = try completed(request,root:root)
            XCTAssertEqual(saved.clips[0].bytes,44)
            XCTAssertEqual(saved.hasRequiredCompletionEvidence,allowed == 44)
            let result = try await Coordinator(root:root).run(request)
            XCTAssertEqual(result.state == .completed,allowed == 44,result.error ?? "")
        }
    }

    func testValidHistoricalPortraitContractReopensWithoutApplyingNewRenderRecipe() async throws {
        let root = try workspace()
        defer {try? FileManager.default.removeItem(at:root)}
        var request = try Fixtures.request(dir:root,path:"unused")
        request.profile = try Fixtures.profile(dir:root)
        var (saved,directory) = try completed(request,root:root)
        saved.clips[0].qa!.checks["framing"] = "Source 720x1280; effective picture 720x1280 inside 720x1280, no quality-upscale claim"
        try Persistence.save(saved,to:directory.appendingPathComponent("job.json"))
        let result = try await Coordinator(root:root).run(request)
        XCTAssertEqual(result.state,.completed,result.error ?? "")
        XCTAssertEqual(result.clips[0].sha256,saved.clips[0].sha256)
    }

    func testAcceptedPlanBindingRejectsChangedSourceProfileQAAndIntervals() throws {
        let root = try workspace()
        defer {try? FileManager.default.removeItem(at:root)}
        let request = try Fixtures.request(dir:root,path:"unused")
        let (saved,_) = try completed(request,root:root)
        var bound = saved
        bound.acceptedPlanSHA256 = try bound.acceptancePlanHash()
        XCTAssertTrue(bound.hasRequiredCompletionEvidence)
        for fault in ["source", "profile", "qa", "interval", "title"] {
            var changed = bound
            switch fault {
            case "source": changed.source!.duration = 101
            case "profile": changed.request.profile.x!.maxFPS = 31
            case "qa": changed.clips[0].qa!.checks["changed"] = "Different QA input"
            case "interval": changed.clips[0].intervals = [Interval(0,50),Interval(50,100)]
            default: changed.clips[0].title = "Revised title requires reconciled evidence"
            }
            XCTAssertFalse(changed.hasRequiredCompletionEvidence,fault)
        }
        var wrongHash = saved
        wrongHash.request.expectedSourceSHA256 = String(repeating:"b",count:64)
        XCTAssertFalse(wrongHash.hasRequiredCompletionEvidence)
        var wrongDuration = saved
        wrongDuration.request.expectedDuration = 200
        XCTAssertFalse(wrongDuration.hasRequiredCompletionEvidence)
    }

    func testLegitimateRevisedFractionalPlanReopensWithManifestAndWithoutCache() async throws {
        let root = try workspace()
        defer {try? FileManager.default.removeItem(at:root)}
        let request = try Fixtures.request(dir:root,path:"unused")
        var (saved,directory) = try completed(request,root:root)
        saved.clips[0].intervals = [Interval(0,37.125),Interval(37.125,100)]
        saved.acceptedPlanSHA256 = try saved.acceptancePlanHash()
        var manifestJob = saved
        manifestJob.state = .filed
        _ = try Records.write(job:manifestJob,directory:directory)
        let manifest = directory.appendingPathComponent("clip_manifest.json")
        saved.companions[manifest.lastPathComponent]!.sha256 = try Integrity.sha256(manifest)
        try Persistence.save(saved,to:directory.appendingPathComponent("job.json"))
        let first = try await Coordinator(root:root).run(request)
        XCTAssertEqual(first.state,.completed,first.error ?? "")
        let before = try Integrity.sha256(directory.appendingPathComponent(saved.clips[0].filename))
        try FileManager.default.removeItem(at:manifest)
        try FileManager.default.removeItem(at:URL(fileURLWithPath:saved.source!.path))
        let offline = try await Coordinator(root:root).run(request)
        XCTAssertEqual(offline.state,.completed,offline.error ?? "")
        XCTAssertEqual(try Integrity.sha256(directory.appendingPathComponent(saved.clips[0].filename)),before)
        try FileManager.default.removeItem(at:directory.appendingPathComponent(saved.clips[0].filename))
        let evicted = try await Coordinator(root:root).run(request)
        XCTAssertEqual(evicted.state,.completed,evicted.error ?? "")
        XCTAssertEqual(evicted.clips[0].drive,first.clips[0].drive)
    }

    func testCompletedReopenPreservesConflictingManifest() async throws {
        let root = try workspace()
        defer {try? FileManager.default.removeItem(at:root)}
        let request = try Fixtures.request(dir:root,path:"unused")
        var (saved,directory) = try completed(request,root:root)
        var stale = saved
        stale.clips[0].intervals = [Interval(0,50)]
        _ = try Records.write(job:stale,directory:directory)
        let manifest = directory.appendingPathComponent("clip_manifest.json")
        let bytes = try Data(contentsOf:manifest)
        saved.companions[manifest.lastPathComponent]!.sha256 = try Integrity.sha256(manifest)
        try Persistence.save(saved,to:directory.appendingPathComponent("job.json"))
        let result = try await Coordinator(root:root).run(request)
        XCTAssertNotEqual(result.state,.completed)
        XCTAssertEqual(try Data(contentsOf:manifest),bytes)
        XCTAssertFalse(result.resumesAutomatically)
        let retried = try await Coordinator(root:root).run(request)
        XCTAssertNotEqual(retried.state,.completed)
        XCTAssertEqual(try Data(contentsOf:manifest),bytes)
        XCTAssertFalse(retried.resumesAutomatically)
        // Restoring independently verified original evidence permits a local
        // reconciliation retry without a render, upload or approval gate.
        var corrected = saved
        corrected.state = .filed
        _ = try Records.write(job:corrected,directory:directory)
        saved.companions[manifest.lastPathComponent]!.sha256 = try Integrity.sha256(manifest)
        saved.state = .qaPassed
        saved.completionReconciliationRequired = true
        try Persistence.save(saved,to:directory.appendingPathComponent("job.json"))
        let reconciled = try await Coordinator(root:root).run(request)
        XCTAssertEqual(reconciled.state,.completed,reconciled.error ?? "")
        XCTAssertNil(reconciled.completionReconciliationRequired)
    }

    func testCompletedReopenRejectsReducedCoverageAndChangedNumbering() async throws {
        for fault in ["omitted-source-half", "clip-number-seven", "duplicate-name", "duplicate-number"] {
            let root = try workspace()
            defer {try? FileManager.default.removeItem(at:root)}
            let request = try Fixtures.request(dir:root,path:"unused")
            var (saved,directory) = try completed(request,root:root)
            if fault == "omitted-source-half" {saved.clips[0].intervals = [Interval(0,50)]}
            if fault == "clip-number-seven" {saved.clips[0].id = 7}
            if fault.hasPrefix("duplicate") {
                saved.clips[0].intervals = [Interval(0,50)]
                var second = saved.clips[0]
                second.id = fault == "duplicate-number" ? 1 : 2
                second.intervals = [Interval(50,100)]
                if fault == "duplicate-number" {second.filename = "second.mp4"}
                second.drive!.id = "second-synthetic-drive-id"
                second.drive!.name = second.filename
                saved.clips.append(second)
                saved.registerRows.append("second-fixture-row")
            }
            try Persistence.save(saved,to:directory.appendingPathComponent("job.json"))
            let persisted: JobRecord = try Persistence.load(directory.appendingPathComponent("job.json"))
            let before = try Data(contentsOf:directory.appendingPathComponent(saved.clips[0].filename))
            XCTAssertFalse(saved.hasRequiredCompletionEvidence,fault)
            let result = try await Coordinator(root:root).run(request)
            XCTAssertNotEqual(result.state,.completed,fault)
            XCTAssertEqual(result.clips,persisted.clips,fault)
            XCTAssertEqual(try Data(contentsOf:directory.appendingPathComponent(saved.clips[0].filename)),before,fault)
        }
    }

    func testIncompleteNativeJobWithUnsupportedDimensionsCannotResumeProviderWrites() async throws {
        let root = try workspace();defer {try? FileManager.default.removeItem(at:root)}
        var request = try Fixtures.request(dir:root,path:"unused")
        request.profile = try Fixtures.profile(dir:root) // X permits only 720 pixels wide.
        request.fileToDrive = true
        var (saved,directory) = try completed(request,root:root)
        saved.state = .qaPassed;saved.clips[0].drive = nil;saved.companions = [:];saved.registerRows = []
        try Persistence.save(saved,to:directory.appendingPathComponent("job.json"))
        let persisted: JobRecord = try Persistence.load(directory.appendingPathComponent("job.json"))
        let output = directory.appendingPathComponent(saved.clips[0].filename)
        let before = try Integrity.sha256(output)
        let provider = RecoveryDelivery()
        let coordinator = try Coordinator(root:root)
        let result = try await Coordinator.$deliveryOverride.withValue(provider) {try await coordinator.run(request)}
        XCTAssertTrue(result.error?.contains("1920×1080") == true,result.error ?? "Missing capability rejection")
        let calls = await provider.calls
        XCTAssertEqual(calls,0,"Accepted legacy QA cannot authorize an out-of-contract archive or upload")
        XCTAssertEqual(result.state,.qaPassed)
        XCTAssertEqual(result.clips[0].qa,persisted.clips[0].qa)
        XCTAssertEqual(try Integrity.sha256(output),before)
        XCTAssertTrue(result.companions.isEmpty)
    }

    func testAcceptedHistoricalCanvasRecoveryUsesActualBytesAndSavedLimits() async throws {
        for width in [720,1920] {
            let root = try workspace();defer {try? FileManager.default.removeItem(at:root)}
            var request = try Fixtures.request(dir:root,path:"unused")
            request.profile = try Fixtures.profile(dir:root);request.fileToDrive = true
            var (saved,directory) = try completed(request,root:root)
            let original = URL(fileURLWithPath:saved.source!.path)
            _ = try await Processes.run("ffmpeg",["-nostdin","-v","error","-y","-f","lavfi","-i","testsrc2=s=320x180:r=30:d=2","-an","-c:v","libx264","-pix_fmt","yuv420p",original.path])
            saved.source = try await Media.inspect(original,request:request)
            let output = directory.appendingPathComponent(saved.clips[0].filename)
            let height = width == 720 ? 1280 : 1080
            _ = try await Processes.run("ffmpeg",["-nostdin","-v","error","-y","-i",original.path,"-vf","scale=320:180,pad=\(width):\(height):(ow-iw)/2:(oh-ih)/2","-an","-c:v","libx264","-preset","ultrafast","-pix_fmt","yuv420p",output.path])
            let hash = try Integrity.sha256(output), probe = try await Media.probe(output)
            saved.clips[0].sha256 = hash;saved.clips[0].qa!.outputSHA256 = hash
            saved.clips[0].qa!.checks = ["historical_fixture":"Generated pre-landscape acceptance; dimensions must be measured"]
            saved.clips[0].bytes = Int64(try Data(contentsOf:output).count)
            saved.clips[0].intervals = [Interval(0,2)];saved.clips[0].measuredDuration = probe.duration
            saved.clips[0].drive = nil;saved.companions = [:];saved.registerRows = []
            saved.transcript = Transcript(sourceID:request.sourceID,sourceSHA256:saved.source!.sha256,duration:2,engine:"Synthetic regression",segments:[TranscriptSegment(start:0,end:2,text:"Generated color bars.")])
            saved.state = .qaPassed;saved.acceptedPlanSHA256 = try saved.acceptancePlanHash()
            try Persistence.save(saved.transcript,to:directory.appendingPathComponent("transcript.json"))
            try Persistence.save(saved,to:directory.appendingPathComponent("job.json"))
            let before: JobRecord = try Persistence.load(directory.appendingPathComponent("job.json"))
            let provider = RecoveryDelivery()
            let result = try await Coordinator.$deliveryOverride.withValue(provider) {
                try await Coordinator(root:root).run(request) {job in
                    XCTAssertFalse(job.stage.hasPrefix("render clip") || job.stage.hasPrefix("QA clip"))
                    if job.stage == "Drive folder",job.error == nil {throw JoeyError.failed("Synthetic filing unavailable")}
                }
            }
            XCTAssertEqual(result.state,.qaPassed,result.error ?? "")
            XCTAssertEqual(result.stage,width == 720 ? "Drive folder" : "accepted export verification",result.error ?? "")
            if width == 720 {XCTAssertEqual(result.error,"Synthetic filing unavailable")}
            else {XCTAssertTrue(result.error?.contains("1920×1080") == true,result.error ?? "")}
            XCTAssertEqual(try result.request.identityData(),try request.identityData())
            XCTAssertEqual(result.clips,before.clips)
            XCTAssertEqual(try Integrity.sha256(output),hash)
            let calls = await provider.calls;XCTAssertEqual(calls,width == 720 ? 1 : 0,"Only the supported output may reach mocked archive/delivery")
            if width == 720 {
                XCTAssertNil(Configuration().resumeIssue(for:before))
                let interrupted = try await Coordinator.$deliveryOverride.withValue(provider) {
                    try await Coordinator(root:root).run(request) {job in
                        XCTAssertFalse(job.stage.hasPrefix("render clip") || job.stage.hasPrefix("QA clip"))
                    }
                }
                XCTAssertEqual(interrupted.state,.qaPassed)
                XCTAssertEqual(interrupted.clips[0].qa,before.clips[0].qa)
                // The existing delivery fixture loses its first upload reply.
                // Retry must reconcile that committed identity, never rerender.
                let recovered = try await Coordinator.$deliveryOverride.withValue(provider) {
                    try await Coordinator(root:root).run(request) {job in
                        XCTAssertFalse(job.stage.hasPrefix("render clip") || job.stage.hasPrefix("QA clip"))
                    }
                }
                XCTAssertEqual(recovered.state,.completed,recovered.error ?? "")
                XCTAssertEqual(recovered.id,saved.id)
                XCTAssertEqual(recovered.clips[0].qa,before.clips[0].qa)
                XCTAssertEqual(try Integrity.sha256(output),hash)
                XCTAssertTrue(recovered.hasRequiredCompletionEvidence)
            }
        }
    }

    func testAcceptedAudioRecoveryDoesNotResolveArtworkOrRerender() async throws {
        let root = try workspace();defer {try? FileManager.default.removeItem(at:root)}
        var request = try Fixtures.request(dir:root,path:"unused")
        request.owner = .taxstone;request.fileToDrive = true
        var (saved,directory) = try completed(request,root:root)
        saved.source!.kind = .audio;saved.state = .qaPassed;saved.companions = [:]
        try Persistence.save(saved,to:directory.appendingPathComponent("job.json"))
        let persisted: JobRecord = try Persistence.load(directory.appendingPathComponent("job.json"))
        let provider = RecoveryDelivery()
        let result = try await Coordinator.$deliveryOverride.withValue(provider) {
            try await Coordinator(root:root).run(request) {job in
                if job.stage.hasPrefix("render clip") || job.stage.hasPrefix("QA clip") {
                    XCTFail("Accepted audio must not render or repeat QA")
                }
                if job.stage == "Drive folder",job.error == nil {throw CancellationError()}
            }
        }
        XCTAssertEqual(result.stage,"Drive folder",result.error ?? "")
        XCTAssertEqual(result.state,.cancelled)
        let artworkCalls = await provider.artworkCalls
        XCTAssertEqual(artworkCalls,0)
        XCTAssertEqual(result.clips,persisted.clips)
        XCTAssertEqual(try Integrity.sha256(directory.appendingPathComponent(saved.clips[0].filename)),saved.clips[0].sha256)
    }

    func testRequiredAudioRenderValidatesSavedArtworkAndPreservesAcceptedClips() async throws {
        for fault in ["none","owner","episode","changed","malformed","missing"] {
            let root = try workspace();defer {try? FileManager.default.removeItem(at:root)}
            var request = try Fixtures.request(dir:root,path:"unused")
            request.owner = .taxstone;request.fileToDrive = true
            var (saved,directory) = try completed(request,root:root)
            saved.source!.kind = .audio;saved.state = .qaPassed;saved.companions = [:]
            saved.clips.append(ClipRecord(id:2,title:"Pending synthetic",intervals:[Interval(50,100)],filename:"pending.mp4"))
            let artFile = directory.appendingPathComponent("approved-art.fixture")
            try Data("Synthetic artwork identity, never decoded by this admission test".utf8).write(to:artFile)
            var art = Artwork(owner:.taxstone,sourceID:saved.source!.id,driveID:"synthetic-art",file:EvidenceFile(path:artFile.path,sha256:try Integrity.sha256(artFile),basis:"Synthetic admission fixture"))
            if fault == "owner" {art.owner = .dub}
            if fault == "episode" {art.sourceID = "other-episode"}
            let receipt = directory.appendingPathComponent("artwork.json")
            if fault != "missing" {try Persistence.save(art,to:receipt)}
            if fault == "malformed" {try Data("{malformed".utf8).write(to:receipt)}
            if fault == "changed" {try Data("Changed synthetic bytes".utf8).write(to:artFile)}
            let priorReceipt = try? Data(contentsOf:receipt)
            try Persistence.save(saved,to:directory.appendingPathComponent("job.json"))
            let persisted: JobRecord = try Persistence.load(directory.appendingPathComponent("job.json"))
            let provider = RecoveryDelivery()
            let result = try await Coordinator.$deliveryOverride.withValue(provider) {
                try await Coordinator(root:root).run(request) {job in
                    if job.stage == "render clip 2",job.error == nil {throw CancellationError()}
                }
            }
            let artworkCalls = await provider.artworkCalls
            XCTAssertEqual(artworkCalls,fault == "missing" ? 1:0,fault)
            XCTAssertEqual(result.stage,fault == "none" ? "render clip 2":"artwork",fault)
            XCTAssertEqual(result.state,fault == "none" ? .cancelled:.failed,fault)
            XCTAssertEqual(result.clips[0],persisted.clips[0],fault)
            XCTAssertEqual(try? Data(contentsOf:receipt),priorReceipt,fault)
            XCTAssertEqual(try Integrity.sha256(directory.appendingPathComponent(saved.clips[0].filename)),saved.clips[0].sha256)
        }
    }

    func testSavedRegisterReceiptsRequireExactAcceptedDriveIdentities() async throws {
        let root = try workspace();defer {try? FileManager.default.removeItem(at:root)}
        let request = try Fixtures.request(dir:root,path:"unused")
        let (saved,directory) = try completed(request,root:root)
        let id = try XCTUnwrap(saved.clips[0].drive?.id)
        XCTAssertTrue(saved.hasRequiredCompletionEvidence)
        for invalid in ["unrelated", "Master Library!2:other-id", "Master Library!0:\(id)",
                        "Master Library!1:\(id)", "!2:\(id)", "Master Library!A2:\(id)",
                        "Master Library!2:", "Master Library!2:\(id):extra"] {
            var changed = saved;changed.registerRows = [invalid]
            XCTAssertFalse(changed.hasRequiredCompletionEvidence,invalid)
        }
        var duplicate = saved
        duplicate.clips[0].intervals = [Interval(0,50)];duplicate.clips[0].measuredDuration = 50
        var second = duplicate.clips[0]
        second.id = 2;second.filename = "second.mp4";second.intervals = [Interval(50,100)]
        second.drive!.id = "second-drive-id";second.drive!.name = second.filename
        duplicate.clips.append(second)
        duplicate.registerRows = ["Master Library!2:\(id)","Master Library!3:\(id)"]
        XCTAssertFalse(duplicate.hasRequiredCompletionEvidence,"Distinct row strings cannot repeat a clip identity")
        duplicate.registerRows = ["Master Library!2:\(id)","Master Library!2:second-drive-id"]
        XCTAssertFalse(duplicate.hasRequiredCompletionEvidence,"One row cannot identify two clips")
        duplicate.registerRows = ["Master Library!2:\(id)","Master Library!3:second-drive-id"]
        XCTAssertTrue(duplicate.hasRequiredCompletionEvidence)
        let provider = RecoveryDelivery()
        let before = try Data(contentsOf:directory.appendingPathComponent(saved.clips[0].filename))
        let result = try await Coordinator.$deliveryOverride.withValue(provider) {try await Coordinator(root:root).run(request)}
        XCTAssertEqual(result.state,.completed,result.error ?? "")
        XCTAssertEqual(result.registerRows,saved.registerRows)
        let calls = await provider.calls;XCTAssertEqual(calls,0)
        XCTAssertEqual(try Data(contentsOf:directory.appendingPathComponent(saved.clips[0].filename)),before)
    }

    private func workspace() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        return try StorageManager.canonicalRoot(root)
    }
    private func legacyID(_ request: JobRequest) throws -> String {
        request.owner.rawValue + "-" + String(Integrity.textHash(String(decoding:try Persistence.encoder.encode(request),as:UTF8.self)).prefix(24))
    }
    private func source(_ request: JobRequest) -> SourceRecord {
        SourceRecord(id:request.sourceID,owner:request.owner,title:request.title,originalURL:request.originalURL,path:"unused synthetic source",bytes:1,
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
        let original = directory.appendingPathComponent("original.mp4")
        try Data("Synthetic original identity".utf8).write(to:original)
        job.source!.path = original.path;job.source!.sha256 = try Integrity.sha256(original)
        job.source!.bytes = Int64(try Data(contentsOf:original).count)
        job.transcript = Transcript(sourceID:request.sourceID,sourceSHA256:job.source!.sha256,duration:100,engine:"Synthetic fixture",
            segments:[TranscriptSegment(start:0,end:100,text:"Synthetic complete source.")])
        job.planningBasis = .transcriptAssisted
        job.folderID = receipt.parent
        job.clips = [ClipRecord(id:1,title:"Synthetic",intervals:[Interval(0,100)],filename:output.lastPathComponent,
            measuredDuration:request.productionWorkflow == .joeBudden ? 107.3 : 100,bytes:bytes,sha256:hash,qa:QAReport(checkedAt:Date(),checks:["framing":"Source 720x1280; effective picture 608x1080 inside 1920x1080, no quality-upscale claim"],outputSHA256:hash,passed:true,
                limitations:["Synthetic checkpoint fixture; no media or provider acceptance"]),drive:receipt)]
        let destination = try DestinationResolver.resolve(source:job.source!,request:request,asset:.clip)
        job.clips[0].drive!.destination = destination
        job.clips[0].drive!.permissionFingerprint = String(repeating:"a",count:64)
        for name in Records.companionNames(source:job.source!) {
            var companion = job.clips[0].drive!;companion.name = name;companion.id = "synthetic_"+name
            job.companions[name] = companion
        }
        job.registerRows = request.owner == .dub ? ["Master Library!2:\(receipt.id)"] : []
        job.state = .completed;job.stage = "complete"
        try Persistence.save(job.transcript,to:directory.appendingPathComponent("transcript.json"))
        try Persistence.save(job,to:directory.appendingPathComponent("job.json"))
        return (job,directory)
    }
    private func joeRequest(root: URL) throws -> JobRequest {
        var request = try Fixtures.request(dir:root,path:"unused")
        request.localPath = nil;request.sourceID = "youtube:abcdefghijk"
        request.originalURL = "https://www.youtube.com/watch?v=abcdefghijk"
        request.productionWorkflow = .joeBudden;request.profile = .joeBuddenDrive;request.fileToDrive = true
        return request
    }
    private func writeLegacyRetentionReceipt(_ job: JobRecord, directory: URL, removalStarted: Bool) throws -> Data {
        var ds = stat(),fs = stat()
        guard lstat(directory.path,&ds) == 0,lstat(job.source!.path,&fs) == 0 else {throw JoeyError.failed("Fixture source missing")}
        let receipt: [String:Any] = [
            "version":1,"jobID":job.id,"sourceID":job.source!.id,
            "directoryInode":UInt64(ds.st_ino),"directoryDevice":ds.st_dev,
            "file":["name":"original.mp4","bytes":job.source!.bytes,"inode":UInt64(fs.st_ino),
                    "device":fs.st_dev,"sha256":job.source!.sha256],
            "removalStarted":removalStarted]
        let data = try JSONSerialization.data(withJSONObject:receipt,options:[.sortedKeys])
        try data.write(to:directory.appendingPathComponent("source-retention.json"))
        return data
    }
    func testJoeArchivesOriginalBeforeTranscriptionWithoutRequiringClipBranding() async throws {
        let root = try workspace();defer {try? FileManager.default.removeItem(at:root)}
        let request = try joeRequest(root:root)
        var (saved,directory) = try completed(request,root:root)
        saved.state = .processing;saved.source!.archiveReference = nil
        try Persistence.save(saved,to:directory.appendingPathComponent("job.json"))
        let provider = RecoveryDelivery()
        let persisted: JobRecord = try Persistence.load(directory.appendingPathComponent("job.json"))
        let result = try await Coordinator.$deliveryOverride.withValue(provider) {
            try await Coordinator(root:root).run(request) {job in
                if job.stage == "transcription",job.error == nil {
                    XCTAssertEqual(job.source?.archiveReference,"https://drive.google.com/file/d/synthetic_archive_123456789/view")
                    throw JoeyError.failed("Intentional test stop before transcription or rendering")
                }
            }
        }
        XCTAssertEqual(result.source?.archiveReference,"https://drive.google.com/file/d/synthetic_archive_123456789/view")
        XCTAssertEqual(result.error,"Intentional test stop before transcription or rendering")
        XCTAssertEqual(result.clips,persisted.clips)
        XCTAssertEqual(try Integrity.sha256(URL(fileURLWithPath:saved.source!.path)),saved.source!.sha256)
    }
    func testJoeArchiveRestorationReopensLegacyJobAndPreservesRegisteredSource() async throws {
        for removalStarted in [false,true] {
            let root = try workspace();defer {try? FileManager.default.removeItem(at:root)}
            var legacy = try joeRequest(root:root);legacy.archiveRootID = "1IIYLVDhCvwf5ZoMb0aM5vpSCe-eMCmyK"
            let (saved,directory) = try completed(legacy,root:root)
            let receipt = try writeLegacyRetentionReceipt(saved,directory:directory,removalStarted:removalStarted)
            var current = legacy;current.archiveRootID = nil
            let coordinator = try Coordinator(root:root)
            for _ in 0..<2 {
                let opened = try await coordinator.run(current)
                XCTAssertEqual(opened.id,saved.id);XCTAssertEqual(opened.state,.completed)
                XCTAssertEqual(try Integrity.sha256(URL(fileURLWithPath:saved.source!.path)),saved.source!.sha256)
                XCTAssertEqual(try Integrity.sha256(directory.appendingPathComponent(saved.clips[0].filename)),saved.clips[0].sha256)
                XCTAssertTrue(FileManager.default.fileExists(atPath:directory.appendingPathComponent("transcript.json").path))
                XCTAssertEqual(try Data(contentsOf:directory.appendingPathComponent("source-retention.json")),receipt)
            }
            let jobs = try await coordinator.jobs();XCTAssertEqual(jobs.count,1)
        }
    }
    func testScratchCleanupPreservesJoeOriginalsAndHistoricalRetentionReceipts() throws {
        for removalStarted in [false,true] {
            let root = try workspace();defer {try? FileManager.default.removeItem(at:root)}
            let (saved,directory) = try completed(joeRequest(root:root),root:root)
            let receipt = try writeLegacyRetentionReceipt(saved,directory:directory,removalStarted:removalStarted)
            let result = try StorageManager.clean(root:root)
            XCTAssertEqual(result.removedFiles,0)
            XCTAssertEqual(try Integrity.sha256(URL(fileURLWithPath:saved.source!.path)),saved.source!.sha256)
            XCTAssertEqual(try Data(contentsOf:directory.appendingPathComponent("source-retention.json")),receipt)
        }
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

    func testAcceptedClipsWithoutCompanionReceiptsRecoverInterruptedCompanionsAndReopenSafely() async throws {
        for companionIndex in 0..<4 {
            for afterCommit in [false,true] {
                let root = try workspace();defer {try? FileManager.default.removeItem(at:root)}
                var request = try Fixtures.request(dir:root,path:"unused");request.owner = .taxstone;request.fileToDrive = true
                var (saved,directory) = try completed(request,root:root)
                saved.state = .qaPassed;saved.stage = "companion records";saved.companions = [:]
                try Persistence.save(saved,to:directory.appendingPathComponent("job.json"))
                let persisted: JobRecord = try Persistence.load(directory.appendingPathComponent("job.json"))
                let acceptedReceipt = try XCTUnwrap(persisted.clips[0].drive)
                let output = directory.appendingPathComponent(saved.clips[0].filename)
                let original = URL(fileURLWithPath:saved.source!.path)
                let identity = try FileManager.default.attributesOfItem(atPath:output.path)
                let names = Records.companionNames(source:saved.source!)
                let failedName = names[companionIndex]
                let provider = RecoveryDelivery(companionFailureName:failedName,companionFailureAfterCommit:afterCommit)
                await provider.seed(acceptedReceipt)
                let checkStages: @Sendable (JobRecord) async throws -> Void = {job in
                    if job.stage.hasPrefix("render clip") || job.stage.hasPrefix("QA clip") {
                        throw JoeyError.failed("Companion recovery must preserve accepted clips without rendering or QA")
                    }
                    if job.stage == "companion records",job.error == nil {XCTAssertEqual(job.state,.filed)}
                }
                let interrupted = try await Coordinator.$deliveryOverride.withValue(provider) {
                    try await Coordinator(root:root).run(request,progress:checkStages)
                }
                XCTAssertEqual(interrupted.state,.qaPassed)
                XCTAssertEqual(interrupted.error,"Synthetic interrupted companion: "+failedName)
                XCTAssertNil(interrupted.companions[failedName],"A lost response cannot fabricate a saved receipt")
                XCTAssertFalse(interrupted.hasRequiredCompletionEvidence)
                XCTAssertEqual(interrupted.clips,persisted.clips)
                let firstCommitted = await provider.committed
                XCTAssertEqual(firstCommitted[failedName] != nil,afterCommit)

                let recovered = try await Coordinator.$deliveryOverride.withValue(provider) {
                    try await Coordinator(root:root).run(request,progress:checkStages)
                }
                XCTAssertEqual(recovered.state,.completed,recovered.error ?? failedName)
                XCTAssertTrue(recovered.hasRequiredCompletionEvidence)
                XCTAssertEqual(recovered.id,persisted.id);XCTAssertEqual(recovered.folderID,persisted.folderID)
                XCTAssertEqual(recovered.clips,persisted.clips)
                XCTAssertEqual(Set(recovered.companions.keys),Set(names))
                let committed = await provider.committed
                for name in names {
                    let receipt = try XCTUnwrap(recovered.companions[name])
                    XCTAssertEqual(receipt,committed[name])
                    XCTAssertEqual(receipt.sha256,try Integrity.sha256(directory.appendingPathComponent(name)))
                    XCTAssertEqual(receipt.parent,recovered.folderID)
                }
                if afterCommit {XCTAssertEqual(recovered.companions[failedName]?.id,firstCommitted[failedName]?.id)}
                let creations = await provider.clipCreations, attempts = await provider.clipAttempts
                let companionCreations = await provider.companionCreations
                XCTAssertEqual(creations,0,"Existing accepted media cannot be uploaded again to recover companions")
                XCTAssertEqual(attempts,2,"Each retry reconciles the accepted provider object")
                XCTAssertEqual(companionCreations,Dictionary(uniqueKeysWithValues:names.map {($0,1)}))
                XCTAssertEqual(Set(committed.values.map(\.id)).count,5,"Exactly one clip and four canonical companions")
                let calls = await provider.calls
                let finalCheckpoint: JobRecord = try Persistence.load(directory.appendingPathComponent("job.json"))
                let recordBytes = try Dictionary(uniqueKeysWithValues:names.map {($0,try Data(contentsOf:directory.appendingPathComponent($0)))})
                for _ in 0..<2 {
                    let reopened = try await Coordinator.$deliveryOverride.withValue(provider) {
                        try await Coordinator(root:root).run(request,progress:checkStages)
                    }
                    XCTAssertEqual(reopened.state,.completed);XCTAssertEqual(reopened.companions,finalCheckpoint.companions)
                    XCTAssertEqual(reopened.clips,persisted.clips)
                    for (name,bytes) in recordBytes {XCTAssertEqual(try Data(contentsOf:directory.appendingPathComponent(name)),bytes)}
                }
                let finalCalls = await provider.calls;XCTAssertEqual(finalCalls,calls,"Completed reopen cannot repeat provider work")
                XCTAssertEqual(try Integrity.sha256(output),persisted.clips[0].sha256)
                XCTAssertEqual(try Integrity.sha256(original),persisted.source?.sha256)
                let after = try FileManager.default.attributesOfItem(atPath:output.path)
                XCTAssertEqual(after[.modificationDate] as? Date,identity[.modificationDate] as? Date)
                XCTAssertEqual(after[.systemFileNumber] as? NSNumber,identity[.systemFileNumber] as? NSNumber)
            }
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
    func testCapabilityWideningRenewsObservationsWithoutChangingSavedContract() throws {
        let root = try workspace();defer {try? FileManager.default.removeItem(at:root)}
        var request = try Fixtures.request(dir:root,path:"unused")
        request.owner = .taxstone
        request.profile.x!.maxWidth = 1080;request.profile.instagram!.maxWidth = 1080
        let identity = try request.identityData(), stableID = try request.stableID()
        var proposed = try renew(request,in:root).profile
        proposed.x!.maxWidth = 1920;proposed.instagram!.maxWidth = 1920
        proposed.x!.maxDuration += 10;proposed.instagram!.maxBytes += 1
        var settings = Configuration();settings.taxstoneProfile = proposed
        let renewed = try settings.renewingCapabilities(in:request)
        XCTAssertEqual(try renewed.identityData(),identity)
        XCTAssertEqual(try renewed.stableID(),stableID)
        XCTAssertEqual(renewed.profile.x!.maxWidth,request.profile.x!.maxWidth)
        XCTAssertEqual(renewed.profile.instagram!.maxBytes,request.profile.instagram!.maxBytes)
        XCTAssertEqual(renewed.profile.x!.accountEvidence,proposed.x!.accountEvidence)
        XCTAssertEqual(renewed.profile.instagram!.validUntil,proposed.instagram!.validUntil)
    }
    func testCapabilityRestrictionReportsExactRequirementWithoutDisclosingAccountOrSurface() throws {
        let root = try workspace();defer {try? FileManager.default.removeItem(at:root)}
        let request = try Fixtures.request(dir:root,path:"unused")
        let renewed = try renew(request,in:root)
        var proposed = renewed.profile
        proposed.x!.maxWidth -= 1
        XCTAssertThrowsError(try request.profile.renewingEvidence(from:proposed)) {error in
            XCTAssertTrue(error.localizedDescription.contains("maxWidth"),error.localizedDescription)
            XCTAssertTrue(error.localizedDescription.contains(String(request.profile.x!.maxWidth)),error.localizedDescription)
            XCTAssertTrue(error.localizedDescription.contains("Production Setup"),error.localizedDescription)
        }
        for field in ["platform","account","surface"] {
            proposed = renewed.profile
            if field == "platform" {proposed.x!.platform = "DUMMY_SECRET_PLATFORM"}
            if field == "account" {proposed.x!.account = "DUMMY_SECRET_ACCOUNT"}
            if field == "surface" {proposed.x!.surface = "DUMMY_SECRET_SURFACE"}
            XCTAssertThrowsError(try request.profile.renewingEvidence(from:proposed)) {error in
                XCTAssertTrue(error.localizedDescription.contains(field),error.localizedDescription)
                XCTAssertFalse(error.localizedDescription.contains("DUMMY_SECRET"),error.localizedDescription)
            }
        }
    }
    func testWiderConfiguredCapabilityResumesLegacyPartialCheckpointWithoutProviderWork() async throws {
        let root = try workspace();defer {try? FileManager.default.removeItem(at:root)}
        var request = try Fixtures.request(dir:root,path:"unused");request.owner = .taxstone
        request.profile.x!.maxWidth = 1080;request.profile.instagram!.maxWidth = 1080
        var (saved,directory) = try completed(request,root:root)
        saved.state = .failed;saved.error = "Previous capability verification failure"
        saved.clips[0].drive = nil;saved.companions = [:];saved.registerRows = []
        try Persistence.save(saved,to:directory.appendingPathComponent("job.json"))
        var proposed = try renew(request,in:root).profile
        proposed.x!.maxWidth = 1920;proposed.instagram!.maxWidth = 1920
        var settings = Configuration();settings.taxstoneProfile = proposed
        try Persistence.save(settings,to:root.appendingPathComponent("settings.json"))
        let provider = RecoveryDelivery(), coordinator = try Coordinator(root:root)
        let result = try await Coordinator.$deliveryOverride.withValue(provider) {
            try await coordinator.run(request) {job in
                if job.stage == "source",job.state == .processing {throw CancellationError()}
            }
        }
        XCTAssertEqual(result.id,saved.id)
        XCTAssertEqual(result.state,.cancelled)
        XCTAssertEqual(try result.request.identityData(),try request.identityData())
        XCTAssertEqual(result.clips.map(\.sha256),saved.clips.map(\.sha256))
        XCTAssertEqual(try Persistence.encoder.encode(result.clips.map(\.qa)),try Persistence.encoder.encode(saved.clips.map(\.qa)))
        XCTAssertEqual(try Integrity.sha256(directory.appendingPathComponent(saved.clips[0].filename)),saved.clips[0].sha256)
        let calls = await provider.calls, jobs = try await coordinator.jobs()
        XCTAssertEqual(calls,0);XCTAssertEqual(jobs.map(\.id),[saved.id])
    }
    func testResumeAssessmentRejectsEveryLowerLimitAndCanvasChange() throws {
        let root = try workspace();defer {try? FileManager.default.removeItem(at:root)}
        let request = try Fixtures.request(dir:root,path:"unused")
        let proposed = try renew(request,in:root).profile
        var variants: [(String,SharedProfile)] = []
        var next = proposed;next.x!.maxDuration -= 1;variants.append(("maxDuration",next))
        next = proposed;next.x!.maxBytes -= 1;variants.append(("maxBytes",next))
        next = proposed;next.x!.maxWidth -= 1;variants.append(("maxWidth",next))
        next = proposed;next.x!.maxHeight -= 1;variants.append(("maxHeight",next))
        next = proposed;next.instagram!.maxFPS -= 1;variants.append(("maxFPS",next))
        next = proposed;next.width = 1080;next.height = 1920;variants.append(("profile",next))
        for (field,profile) in variants {
            var settings = Configuration();settings.profile = profile
            let issue = try XCTUnwrap(settings.resumeIssue(for:request))
            XCTAssertTrue(issue.contains(field),issue)
            XCTAssertTrue(issue.contains("Production Setup"),issue)
        }
    }
    func testResumeAssessmentExplainsExpiredMissingAndChangedEvidenceWithoutFilePaths() throws {
        let root = try workspace();defer {try? FileManager.default.removeItem(at:root)}
        let request = try Fixtures.request(dir:root,path:"unused")
        let proposed = try renew(request,in:root).profile
        var settings = Configuration();settings.profile = proposed
        XCTAssertNil(settings.resumeIssue(for:request,sourceKind:.nativeVideo))
        for platform in ["X","Instagram"] {
            var expired = proposed
            if platform == "X" {
                expired.x!.checkedAt = Date().addingTimeInterval(-7200)
                expired.x!.validUntil = Date().addingTimeInterval(-3600)
            } else {
                expired.instagram!.checkedAt = Date().addingTimeInterval(-7200)
                expired.instagram!.validUntil = Date().addingTimeInterval(-3600)
            }
            // The configured observation must be at least as recent as the saved
            // one, so an expired saved contract cannot fall back to fresh data.
            var saved = request
            saved.profile = expired
            settings.profile = expired
            let issue = try XCTUnwrap(settings.resumeIssue(for:saved))
            XCTAssertTrue(issue.contains(platform),issue)
            XCTAssertTrue(issue.contains("expired at"),issue)
            XCTAssertTrue(issue.contains("Production Setup"),issue)
        }
        var missing = proposed
        missing.x!.accountEvidence.path = root.appendingPathComponent("DUMMY_SECRET_MISSING_PROOF").path
        settings.profile = missing
        var issue = try XCTUnwrap(settings.resumeIssue(for:request))
        XCTAssertTrue(issue.contains("X account evidence file is missing"),issue)
        XCTAssertFalse(issue.contains("DUMMY_SECRET"),issue)
        var changed = proposed
        changed.x!.accountEvidence.sha256 = String(repeating:"0",count:64)
        settings.profile = changed
        issue = try XCTUnwrap(settings.resumeIssue(for:request))
        XCTAssertTrue(issue.contains("X account evidence SHA-256 changed"),issue)
        XCTAssertFalse(issue.contains(root.path),issue)
        let before = try Persistence.encoder.encode(settings)
        _ = settings.resumeIssue(for:request)
        XCTAssertEqual(try Persistence.encoder.encode(settings),before)
        XCTAssertNil(Configuration().resumeIssue(for:request),"Valid saved evidence can be used when no replacement profile is configured")
        var unsupported = request
        unsupported.profile.x!.maxWidth = 1080;unsupported.profile.instagram!.maxWidth = 1080
        XCTAssertTrue(Configuration().resumeIssue(for:unsupported,sourceKind:.nativeVideo)?.contains("1920×1080") == true)
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
    var artworkCalls = 0
    var clipCreations = 0
    var clipAttempts = 0
    var committed: [String:DriveReceipt] = [:]
    var companionCreations: [String:Int] = [:]
    private var companionFailureTriggered = false
    let suspendAfterCommit: Bool
    let original: URL?
    let filingFault: String
    let companionFailureName: String?
    let companionFailureAfterCommit: Bool
    init(suspendAfterCommit: Bool = false, original: URL? = nil, filingFault: String = "none",
         companionFailureName: String? = nil, companionFailureAfterCommit: Bool = true) {
        self.suspendAfterCommit = suspendAfterCommit;self.original = original;self.filingFault = filingFault
        self.companionFailureName = companionFailureName;self.companionFailureAfterCommit = companionFailureAfterCommit
    }
    func seed(_ receipt: DriveReceipt) {committed[receipt.name] = receipt}
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
        artworkCalls += 1
        throw JoeyError.failed("Native synthetic checkpoint must not resolve artwork")
    }
    func verifyPackage(job: JobRecord, directory: URL) async throws {
        guard job.hasRequiredCompletionEvidence else {throw JoeyError.failed("Synthetic package incomplete")}
        if filingFault == "final-readback" {throw JoeyError.failed("Synthetic final parent readback failure")}
        if companionFailureName != nil {
            for receipt in job.clips.compactMap(\.drive) + Array(job.companions.values) {
                guard committed[receipt.name] == receipt,
                      try Integrity.sha256(directory.appendingPathComponent(receipt.name)) == receipt.sha256 else {
                    throw JoeyError.failed("Synthetic provider bytes differ from current package")
                }
            }
        }
    }
    func reconcileRegister(job: JobRecord, tab: String) async throws -> [String] {
        calls += 1;return DestinationResolver.requiresDUBRegister(job.request) && filingFault != "register" ? job.clips.enumerated().map {"\(tab)!\($0.offset+2):\($0.element.drive!.id)"} : []
    }
    func upload(_ local: URL, name: String?, parent: String, destination: FilingDestination, replaceCompanion: Bool) async throws -> DriveReceipt {
        calls += 1
        let filename = name ?? local.lastPathComponent
        let bytes = Int64(try Data(contentsOf:local).count), hash = try Integrity.sha256(local)
        let interruptCompanion = filename == companionFailureName && !companionFailureTriggered
        if interruptCompanion {
            companionFailureTriggered = true
            if !companionFailureAfterCommit {throw JoeyError.failed("Synthetic interrupted companion: "+filename)}
        }
        if local.pathExtension == "mp4" {
            clipAttempts += 1
            if let existing = committed[filename] {
                guard existing.sha256 == hash,existing.bytes == bytes,existing.parent == parent else {throw JoeyError.failed("Synthetic reconciliation identity changed")}
                if filingFault == "parent" {var wrong = existing;wrong.parent = "incorrect-actual-parent";return wrong}
                return existing
            }
            clipCreations += 1
        } else if committed[filename] == nil {
            companionCreations[filename,default:0] += 1
        }
        let receipt = DriveReceipt(id:"synthetic_"+Integrity.textHash(filename),name:filename,parent:parent,bytes:bytes,
            md5:try Integrity.md5(local),sha256:hash,url:"https://example.invalid/synthetic",permissions:["user:owner"],verifiedAt:Date(),destination:destination,permissionFingerprint:String(repeating:"a",count:64))
        committed[filename] = receipt
        if interruptCompanion {throw JoeyError.failed("Synthetic interrupted companion: "+filename)}
        if local.pathExtension == "mp4",suspendAfterCommit {try await Task.sleep(nanoseconds:60_000_000_000)}
        if local.pathExtension == "mp4" {throw JoeyError.failed("Synthetic uncertain upload response")}
        return receipt
    }
}
