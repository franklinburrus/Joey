import XCTest
@testable import JoeyCore

final class SourceIntegrityTests: XCTestCase {
    private func workspace() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("joey-source-integrity-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        addTeardownBlock {try? FileManager.default.removeItem(at:root)}
        return try StorageManager.canonicalRoot(root)
    }

    private func video(in root: URL, filter: String? = nil, audio: Bool = true, duration: Int = 2) async throws -> URL {
        let url = root.appendingPathComponent(UUID().uuidString+".nut")
        var args = ["-nostdin","-v","error","-f","lavfi","-i","testsrc2=s=160x90:r=30:d=\(duration)"]
        if audio {args += ["-f","lavfi","-i","sine=frequency=440:duration=\(duration)"]}
        if let filter {args += ["-vf",filter]}
        args += ["-c:v","ffv1","-c:a","pcm_s16le",url.path]
        _ = try await Processes.run("ffmpeg",args)
        return url
    }

    func testCachedAndResumedSourcesRejectNewDurationBeforeTranscriptAdoption() async throws {
        for resumed in [false,true] {
            let root = try workspace(), url = try await video(in:root,audio:false,duration:4)
            var request = try Fixtures.request(dir:root,path:url.path)
            request.localPath = nil;request.originalURL = "https://x.com/i/broadcasts/synthetic"
            request.expectedDuration = 4
            let source = try await Media.inspect(url,request:request)
            var saved = JobRecord(id:try request.stableID(),request:request)
            saved.source = source
            saved.transcript = Transcript(sourceID:source.id,sourceSHA256:source.sha256,duration:4,engine:"Synthetic",
                segments:[TranscriptSegment(start:0,end:4,text:"Complete four-second source.")])
            request.expectedDuration = 8
            if resumed {saved.request = request;saved.id = try request.stableID()}
            try Persistence.save(saved,to:root.appendingPathComponent("jobs/"+saved.id+"/job.json"))
            let provider = IntegrityDelivery()
            let result = try await Coordinator.$deliveryOverride.withValue(provider) {
                try await Coordinator(root:root).run(request) {job in
                    if job.stage == "transcription",job.error == nil {throw JoeyError.failed("Reached transcription before rejecting incomplete source")}
                }
            }
            XCTAssertEqual(result.state,.failed)
            XCTAssertTrue(result.error?.contains("Incomplete source") == true,result.error ?? "Missing duration rejection")
            XCTAssertTrue(result.clips.isEmpty)
            XCTAssertFalse(FileManager.default.fileExists(atPath:root.appendingPathComponent("jobs/"+result.id+"/transcript.json").path))
            XCTAssertEqual(try Integrity.sha256(url),source.sha256)
            let calls = await provider.calls;XCTAssertEqual(calls,0)
        }
    }

    func testChangedCachedBytesFailWithoutReplacementDownload() async throws {
        let root = try workspace(), url = try await video(in:root,audio:false)
        var priorRequest = try Fixtures.request(dir:root,path:url.path)
        priorRequest.localPath = nil;priorRequest.originalURL = "https://x.com/i/broadcasts/synthetic"
        let source = try await Media.inspect(url,request:priorRequest)
        var saved = JobRecord(id:try priorRequest.stableID(),request:priorRequest);saved.source = source
        try Persistence.save(saved,to:root.appendingPathComponent("jobs/"+saved.id+"/job.json"))
        var request = priorRequest;request.title = "New request for cached original"
        request.archiveReference = "https://drive.google.com/file/d/synthetic_archive_123456789/view"
        try Data("Changed source bytes".utf8).write(to:url)
        let provider = IntegrityDelivery()
        let result = try await Coordinator.$deliveryOverride.withValue(provider) {try await Coordinator(root:root).run(request)}
        XCTAssertEqual(result.state,.failed)
        XCTAssertTrue(result.error?.contains("Original source changed") == true,result.error ?? "Missing hash rejection")
        let calls = await provider.calls;XCTAssertEqual(calls,0,"Changed cached bytes cannot silently trigger replacement")
        XCTAssertEqual(try Data(contentsOf:url),Data("Changed source bytes".utf8))
    }

    func testCachedTaxstoneQARequiresStaticProofBeforeReuse() async throws {
        let root = try workspace(), url = try await video(in:root)
        var request = try Fixtures.request(dir:root,path:url.path);request.owner = .taxstone
        var source = try await Media.inspect(url,request:request);source.kind = .audio;source.classificationProof = nil
        request.artwork = Artwork(owner:.taxstone,sourceID:source.id,driveID:"synthetic-art",
            file:EvidenceFile(path:url.path,sha256:source.sha256,basis:"Synthetic identity only"))
        let transcript = Transcript(sourceID:source.id,sourceSHA256:source.sha256,duration:source.duration,engine:"Synthetic",
            segments:[TranscriptSegment(start:0,end:source.duration,text:"Complete source.")])
        let provider = IntegrityDelivery()
        do {
            _ = try await TaxstoneReuse.plan(request:request,source:source,transcript:transcript,exclusions:[],provider:provider,directory:root)
            XCTFail("Reuse accepted an audio classification without complete static-video proof")
        } catch {XCTAssertTrue(error.localizedDescription.contains("classification"),error.localizedDescription)}
        let calls = await provider.calls;XCTAssertEqual(calls,0)
    }

    func testInspectionRetainsMotionBetweenFormerSamples() async throws {
        let root = try workspace()
        let url = try await video(in:root,filter:"drawbox=color=black:t=fill:enable='not(between(t,0.1,0.2))'")
        let source = try await Media.inspect(url,request:Fixtures.request(dir:root,path:url.path))
        XCTAssertEqual(source.kind,.nativeVideo)
    }

    func testInspectionRetainsSingleFrameAndLateMotion() async throws {
        for frame in [3,59] {
            let root = try workspace()
            let url = try await video(in:root,filter:"drawbox=color=black:t=fill:enable='not(eq(n,\(frame)))'")
            let source = try await Media.inspect(url,request:Fixtures.request(dir:root,path:url.path))
            XCTAssertEqual(source.kind,.nativeVideo,"Discarded changed frame \(frame)")
        }
    }

    func testInspectionRetainsChromaOnlyChanges() async throws {
        let root = try workspace()
        let url = try await video(in:root,filter:"format=yuv444p,geq=lum=64:cb='if(eq(N,3),200,128)':cr=128")
        let source = try await Media.inspect(url,request:Fixtures.request(dir:root,path:url.path))
        XCTAssertEqual(source.kind,.nativeVideo)
    }

    func testSilentStaticVideoRemainsNative() async throws {
        let root = try workspace()
        let url = try await video(in:root,filter:"drawbox=color=black:t=fill",audio:false)
        let source = try await Media.inspect(url,request:Fixtures.request(dir:root,path:url.path))
        XCTAssertEqual(source.kind,.nativeVideo)
        XCTAssertFalse(source.hasAudio)
    }

    func testSourceDurationContractHandlesToleranceAndInvalidValues() throws {
        // Use exactly representable differences at the existing tolerance;
        // 4 - 3.9 is slightly greater than 0.1 in binary floating point.
        for (actual,expected) in [(4.0,4.0),(0.2,0.1),(4.09,4),(999,1000),(1001,1000)] {
            XCTAssertNoThrow(try Media.validateSourceDuration(actual,expected:expected))
        }
        for (actual,expected) in [(3.89,4.0),(4.11,4),(998.9,1000),(1001.1,1000),(4,0),(4,-1),(4,.infinity),(4,.nan)] {
            XCTAssertThrowsError(try Media.validateSourceDuration(actual,expected:expected))
        }
        XCTAssertNoThrow(try Media.validateSourceDuration(4,expected:nil))
        for actual in [0.0,-1,.nan,.infinity] {XCTAssertThrowsError(try Media.validateSourceDuration(actual,expected:nil))}
    }

    func testStaticProofSupportsAudioRenderAndQAWhileLegacyOrChangedProofCannot() async throws {
        let root = try workspace(), url = try await video(in:root,filter:"drawbox=color=blue:t=fill")
        var request = try Fixtures.request(dir:root,path:url.path);request.owner = .taxstone
        let source = try await Media.inspect(url,request:request)
        XCTAssertEqual(source.kind,.audio)
        XCTAssertEqual(source.classificationProof?.decodedFrameCount,60)
        XCTAssertEqual(source.classificationProof?.sourceSHA256,source.sha256)
        XCTAssertNotNil(source.classificationProof?.uniformFrameSHA256)
        let art = root.appendingPathComponent("art.png")
        _ = try await Processes.run("ffmpeg",["-nostdin","-v","error","-f","lavfi","-i","color=blue:s=300x300","-frames:v","1",art.path])
        let artwork = Artwork(owner:.taxstone,sourceID:source.id,driveID:"synthetic-art",
            file:EvidenceFile(path:art.path,sha256:try Integrity.sha256(art),basis:"Generated artwork"))
        let clip = ClipRecord(id:1,title:"Static artwork",intervals:[Interval(0,2)],filename:"clip.mp4")
        let output = root.appendingPathComponent(clip.filename)
        let receipt = try await Media.render(source:source,clip:clip,profile:request.profile,artwork:artwork,work:root,output:output)
        let qa = try await Media.validate(output:output,source:source,clip:clip,profile:request.profile,render:receipt,work:root)
        XCTAssertTrue(qa.passed)
        let before = try Integrity.sha256(output)
        for fault in ["legacy","wrong-source","incomplete","unsupported-version","non-static"] {
            var invalid = source
            switch fault {
            case "legacy": invalid.classificationProof = nil
            case "wrong-source": invalid.classificationProof!.sourceSHA256 = String(repeating:"0",count:64)
            case "incomplete": invalid.classificationProof!.decodedFrameCount = 0
            case "unsupported-version": invalid.classificationProof!.version = 99
            default: invalid.classificationProof!.uniformFrameSHA256 = nil
            }
            for operation in ["render","reference","QA"] {
                do {
                    switch operation {
                    case "render": _ = try await Media.render(source:invalid,clip:clip,profile:request.profile,artwork:artwork,work:root,output:output)
                    case "reference": _ = try await Media.audioReference(source:invalid,clip:clip,profile:request.profile,artwork:artwork,output:output,work:root)
                    default: _ = try await Media.validate(output:output,source:invalid,clip:clip,profile:request.profile,render:receipt,work:root)
                    }
                    XCTFail("\(operation) accepted \(fault) classification proof")
                } catch {XCTAssertTrue(error.localizedDescription.contains("classification"),error.localizedDescription)}
            }
            XCTAssertEqual(try Integrity.sha256(output),before)
        }
        try Data("Source replaced after inspection".utf8).write(to:url)
        XCTAssertThrowsError(try Media.validateAudioClassification(source))
        XCTAssertEqual(try Integrity.sha256(output),before)
    }

    func testLegacyUnacceptedSourcesUpgradeBeforeTranscriptionAndReuseStaticProof() async throws {
        for moving in [false,true] {
            let root = try workspace()
            let url = try await video(in:root,filter:moving ? "drawbox=color=black:t=fill:enable='not(eq(n,3))'" : "drawbox=color=blue:t=fill")
            let request = try Fixtures.request(dir:root,path:url.path)
            var source = try await Media.inspect(url,request:request)
            source.kind = .audio;source.classificationEvidence = "Legacy sparse samples";source.classificationProof = nil
            var job = JobRecord(id:try request.stableID(),request:request);job.source = source
            let checkpoint = root.appendingPathComponent("jobs/"+job.id+"/job.json")
            try Persistence.save(job,to:checkpoint)
            let provider = IntegrityDelivery()
            var result = try await Coordinator.$deliveryOverride.withValue(provider) {
                try await Coordinator(root:root).run(request) {job in
                    if job.stage == "transcription",job.error == nil {throw CancellationError()}
                }
            }
            XCTAssertEqual(result.state,.cancelled)
            XCTAssertEqual(result.source?.kind,moving ? .nativeVideo : .audio)
            XCTAssertEqual(result.id,job.id)
            XCTAssertEqual(try request.stableID(),job.id)
            XCTAssertNotNil(result.source?.classificationProof)
            XCTAssertEqual(result.source?.sha256,source.sha256)
            result.source!.classificationEvidence = "Retained complete proof; no second decode required"
            try Persistence.save(result,to:checkpoint)
            let reused = try await Coordinator.$deliveryOverride.withValue(provider) {
                try await Coordinator(root:root).run(request) {job in
                    if job.stage == "transcription",job.error == nil {throw CancellationError()}
                }
            }
            XCTAssertEqual(reused.source,result.source)
            let calls = await provider.calls;XCTAssertEqual(calls,0)
        }
    }

    func testAudioOnlyInspectionAndLegacyRecordDecodingPreserveIdentity() async throws {
        let root = try workspace(), url = root.appendingPathComponent("audio.wav")
        _ = try await Processes.run("ffmpeg",["-nostdin","-v","error","-f","lavfi","-i","sine=frequency=440:duration=1",url.path])
        let request = try Fixtures.request(dir:root,path:url.path)
        let id = try request.stableID()
        let source = try await Media.inspect(url,request:request)
        XCTAssertEqual(source.kind,.audio);XCTAssertNil(source.classificationProof)
        var json = try JSONSerialization.jsonObject(with:Persistence.encoder.encode(source)) as! [String:Any]
        json.removeValue(forKey:"classificationProof")
        let legacy = try Persistence.decoder.decode(SourceRecord.self,from:JSONSerialization.data(withJSONObject:json))
        XCTAssertEqual(legacy,source)
        XCTAssertEqual(try request.stableID(),id)
        XCTAssertNoThrow(try Media.validateAudioClassification(legacy))
    }

    func testCompatibleCachedDurationReusesSourceAndTranscript() async throws {
        for expected in [Double?(4),Double?(4.09),nil] {
            let root = try workspace(), url = try await video(in:root,audio:false,duration:4)
            var request = try Fixtures.request(dir:root,path:url.path)
            request.localPath = nil;request.originalURL = "https://x.com/i/broadcasts/synthetic";request.expectedDuration = 4
            let source = try await Media.inspect(url,request:request)
            let transcript = Transcript(sourceID:source.id,sourceSHA256:source.sha256,duration:4,engine:"Synthetic",
                segments:[TranscriptSegment(start:0,end:4,text:"Complete source.")])
            var saved = JobRecord(id:try request.stableID(),request:request);saved.source = source;saved.transcript = transcript
            try Persistence.save(saved,to:root.appendingPathComponent("jobs/"+saved.id+"/job.json"))
            request.title = "Reuse compatible source";request.expectedDuration = expected
            let provider = IntegrityDelivery()
            let result = try await Coordinator.$deliveryOverride.withValue(provider) {
                try await Coordinator(root:root).run(request) {job in
                    if job.stage == "transcription",job.error == nil {throw CancellationError()}
                }
            }
            XCTAssertEqual(result.state,.cancelled)
            XCTAssertEqual(result.source?.path,url.path)
            XCTAssertEqual(result.source?.sha256,source.sha256)
            let adopted: Transcript = try Persistence.load(root.appendingPathComponent("jobs/"+result.id+"/transcript.json"))
            XCTAssertEqual(adopted,transcript)
            let calls = await provider.calls;XCTAssertEqual(calls,0)
        }
    }

    func testChangingDecodedDimensionsCannotBecomeStaticArtwork() async throws {
        let root = try workspace()
        var encoded = Data()
        for geometry in ["160x96","96x160"] {
            let part = root.appendingPathComponent(geometry+".h264")
            _ = try await Processes.run("ffmpeg",["-nostdin","-v","error","-f","lavfi","-i","color=blue:s=\(geometry):r=30:d=1",
                "-c:v","libx264","-qp","0",part.path])
            encoded.append(try Data(contentsOf:part))
        }
        let elementary = root.appendingPathComponent("changing.h264"), url = root.appendingPathComponent("changing.nut")
        try encoded.write(to:elementary)
        _ = try await Processes.run("ffmpeg",["-nostdin","-v","error","-fflags","+genpts","-r","30","-i",elementary.path,
            "-f","lavfi","-i","sine=frequency=440:duration=2","-c:v","copy","-c:a","pcm_s16le",url.path])
        let source = try await Media.inspect(url,request:Fixtures.request(dir:root,path:url.path))
        XCTAssertEqual(source.kind,.nativeVideo,"Equal pixel counts and colors cannot hide different frame geometry")
        XCTAssertEqual(source.classificationProof?.decodedFrameCount,60)
        XCTAssertNil(source.classificationProof?.uniformFrameSHA256)
    }

    func testCancellationRemovesInProgressFrameEvidence() async throws {
        let root = try workspace(), url = try await video(in:root,duration:20)
        let request = try Fixtures.request(dir:root,path:url.path)
        let temp = FileManager.default.temporaryDirectory
        let before = Set(try FileManager.default.contentsOfDirectory(atPath:temp.path))
        let task = Task {try await Media.inspect(url,request:request)}
        var created: Set<String> = []
        for _ in 0..<1000 {
            created = Set(try FileManager.default.contentsOfDirectory(atPath:temp.path)).subtracting(before).filter {$0.hasPrefix("joey-classification-")}
            if !created.isEmpty {break}
            try await Task.sleep(nanoseconds:2_000_000)
        }
        task.cancel()
        do {_ = try await task.value;XCTFail("Cancelled inspection produced acceptance proof")}
        catch is CancellationError {} catch {XCTFail("Unexpected cancellation error: \(error)")}
        XCTAssertFalse(created.isEmpty,"Cancellation must interrupt active frame inspection")
        for name in created {XCTAssertFalse(FileManager.default.fileExists(atPath:temp.appendingPathComponent(name).path))}
    }

    func testDisprovenLegacyAcceptedAudioPreservesEvidenceAndStopsBeforeProvider() async throws {
        for evidence in ["all-accepted","partial","receipt-only","duration"] {
            try await assertLegacyEvidencePreserved(evidence)
        }
    }

    private func assertLegacyEvidencePreserved(_ evidence: String) async throws {
        let root = try workspace()
        let url = try await video(in:root,filter:"drawbox=color=black:t=fill:enable='not(eq(n,3))'")
        var request = try Fixtures.request(dir:root,path:url.path);request.fileToDrive = true
        var source = try await Media.inspect(url,request:request)
        source.kind = .audio;source.classificationEvidence = "Legacy sparse samples";source.classificationProof = nil
        if evidence == "duration" {request.expectedDuration = 8}
        var job = JobRecord(id:try request.stableID(),request:request)
        let dir = root.appendingPathComponent("jobs/"+job.id)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        let accepted = dir.appendingPathComponent("accepted.mp4")
        try Data("Synthetic accepted artifact; not production acceptance".utf8).write(to:accepted)
        let hash = try Integrity.sha256(accepted)
        job.source = source;job.state = .qaPassed
        job.transcript = Transcript(sourceID:source.id,sourceSHA256:source.sha256,duration:source.duration,engine:"Synthetic",
            segments:[TranscriptSegment(start:0,end:source.duration,text:"Full synthetic source.")])
        job.clips = [ClipRecord(id:1,title:"Accepted audio",intervals:[Interval(0,source.duration)],filename:accepted.lastPathComponent,
            bytes:Int64(try Data(contentsOf:accepted).count),sha256:hash,
            qa:QAReport(checkedAt:Date(),checks:[:],outputSHA256:hash,passed:true,limitations:["Synthetic checkpoint"]))]
        if evidence == "partial" {job.clips.append(ClipRecord(id:2,title:"Unaccepted",intervals:[Interval(0,1)],filename:"unaccepted.mp4"))}
        if evidence == "receipt-only" {job.clips[0].qa = nil}
        let receipt = DriveReceipt(id:"fixture-receipt",name:"clip_manifest.json",parent:"fixture-folder",bytes:1,sha256:hash,
            url:"https://example.invalid/fixture",permissions:["owner"],verifiedAt:Date())
        job.companions[receipt.name] = receipt
        let files = try Records.write(job:job,directory:dir)
        let before = try Dictionary(uniqueKeysWithValues:files.map {($0,try Data(contentsOf:$0))})
        try Persistence.save(job,to:dir.appendingPathComponent("job.json"))
        let saved: JobRecord = try Persistence.load(dir.appendingPathComponent("job.json"))
        let provider = IntegrityDelivery()
        for _ in 0..<2 {
            let result = try await Coordinator.$deliveryOverride.withValue(provider) {
                try await Coordinator(root:root).run(request) {job in
                    if job.stage == "transcription",job.error == nil {throw JoeyError.failed("Legacy classification reached transcription")}
                }
            }
            XCTAssertEqual(result.state,.failed,"Disproven accepted QA must not remain QA_PASSED")
            XCTAssertTrue(result.error?.contains(evidence == "duration" ? "Incomplete source" : "classification") == true,result.error ?? "Missing source rejection")
            XCTAssertEqual(result.source,saved.source)
            XCTAssertEqual(result.clips,saved.clips)
            XCTAssertEqual(result.companions,saved.companions)
            XCTAssertEqual(try Integrity.sha256(url),source.sha256)
            XCTAssertEqual(try Integrity.sha256(accepted),hash)
            for (file,bytes) in before {XCTAssertEqual(try Data(contentsOf:file),bytes,file.lastPathComponent)}
        }
        let calls = await provider.calls;XCTAssertEqual(calls,0)
    }
}

private actor IntegrityDelivery: CoordinatorDelivery {
    var calls = 0
    private func unexpected() -> JoeyError {calls += 1;return .failed("Unexpected provider operation in source-integrity test")}
    func metadata(_ id: String) async throws -> [String:Any] {throw unexpected()}
    func downloadOriginal(reference: String, directory: URL) async throws -> URL {throw unexpected()}
    func archive(source: SourceRecord, request: JobRequest) async throws -> String {throw unexpected()}
    func episodeFolder(source: SourceRecord, request: JobRequest, jobID: String, existingFolderID: String?, intentURL: URL) async throws -> String {throw unexpected()}
    func upload(_ local: URL, name: String?, parent: String, destination: FilingDestination, replaceCompanion: Bool) async throws -> DriveReceipt {throw unexpected()}
    func resolveArtwork(source: SourceRecord, configuration: Configuration, root: URL) async throws -> Artwork {throw unexpected()}
    func reconcileRegister(job: JobRecord, tab: String) async throws -> [String] {throw unexpected()}
    func verifyPackage(job: JobRecord, directory: URL) async throws {throw unexpected()}
}
