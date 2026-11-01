import XCTest
@testable import JoeyCore

final class ModelIndependentTests: XCTestCase {
    // Decode the new opt-in at the wire boundary so this regression also runs
    // against the old implementation, which ignored the unknown policy field.
    private func independent(_ request: JobRequest) throws -> JobRequest {
        var object = try JSONSerialization.jsonObject(with:Persistence.encoder.encode(request)) as! [String:Any]
        object["transcriptPolicy"] = "modelIndependent"
        return try Persistence.decoder.decode(JobRequest.self,from:JSONSerialization.data(withJSONObject:object))
    }

    func testLocalExportWithoutTranscriptModelOrHelper() async throws {
        let evidence = ProcessInfo.processInfo.environment["JOEY_MODEL_INDEPENDENT_EVIDENCE"]
        let dir = evidence.map {URL(fileURLWithPath:$0)} ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        defer {if evidence == nil {try? FileManager.default.removeItem(at:dir)}}
        let media = dir.appendingPathComponent("source.mp4")
        _ = try await Processes.run("ffmpeg",["-v","error","-f","lavfi","-i","testsrc2=s=320x180:r=30:d=3.4","-f","lavfi","-i","sine=frequency=440:duration=3.4","-c:v","libx264","-pix_fmt","yuv420p","-c:a","aac","-shortest",media.path])
        var request = try Fixtures.request(dir:dir,path:media.path)
        request.profile.x!.maxDuration = 1.2 // Diagnostic fixture limit, not account evidence.
        request = try independent(request)
        let root = dir.appendingPathComponent("runtime")
        var config = Configuration()
        config.pythonPath = dir.appendingPathComponent("absent-python").path
        config.transcriptionScript = dir.appendingPathComponent("absent-helper.py").path
        config.modelPath = dir.appendingPathComponent("absent-model").path
        try Persistence.save(config,to:root.appendingPathComponent("settings.json"))
        XCTAssertNil(request.transcriptPath)
        for path in [config.pythonPath!,config.transcriptionScript!,config.modelPath!] {
            XCTAssertFalse(FileManager.default.fileExists(atPath:path))
        }
        let coordinator = try Coordinator(root:root)
        let job = try await coordinator.run(request)
        XCTAssertEqual(job.state,.qaPassed,job.error ?? "")
        guard job.state == .qaPassed else {return}
        XCTAssertNil(job.error)
        XCTAssertNil(job.transcript)
        XCTAssertTrue(job.exclusions.isEmpty)
        XCTAssertEqual(job.clips.map(\.intervals),[[Interval(0,1.2)],[Interval(1.2,2.4)],[Interval(2.4,3.4)]])
        XCTAssertTrue(job.clips.allSatisfy {$0.qa?.passed == true})
        try Planning.validateCoverage(duration:job.source!.duration,exclusions:[],clips:job.clips.map(\.intervals))
        let jobDir = await coordinator.directory(for:job.id)
        let files = try FileManager.default.contentsOfDirectory(atPath:jobDir.path)
        XCTAssertFalse(files.contains("transcript.json"))
        XCTAssertFalse(files.contains("asr-source.json"))
        XCTAssertFalse(files.contains {$0.hasSuffix("Full Transcript.txt")})
        XCTAssertEqual(files.filter {$0.hasSuffix(".mp4")}.count,3)
        XCTAssertTrue(files.contains("clip_manifest.json"))
        let summary = try String(contentsOf:jobDir.appendingPathComponent("RECONCILE.md"),encoding:.utf8)
        XCTAssertTrue(summary.contains("UNAVAILABLE"))
        XCTAssertTrue(summary.contains("transcript"))
        XCTAssertNotEqual(job.state,.completed)
        let persisted: JobRecord = try Persistence.load(jobDir.appendingPathComponent("job.json"))
        let dates = try job.clips.map {try FileManager.default.attributesOfItem(atPath:jobDir.appendingPathComponent($0.filename).path)[.modificationDate] as? Date}
        let second = try await coordinator.run(request)
        XCTAssertEqual(second.clips.map(\.intervals),job.clips.map(\.intervals))
        // Compare persisted receipt precision, not unsaved subsecond Date values.
        XCTAssertEqual(second.clips.map(\.qa),persisted.clips.map(\.qa))
        XCTAssertEqual(second.clips.map(\.sha256),job.clips.map(\.sha256))
        XCTAssertEqual(try second.clips.map {try FileManager.default.attributesOfItem(atPath:jobDir.appendingPathComponent($0.filename).path)[.modificationDate] as? Date},dates)
        XCTAssertEqual(job.planningBasis,.deterministicTime)
        XCTAssertEqual(job.unavailableTranscriptFeatures.count,4)
        XCTAssertTrue(job.clips.allSatisfy {$0.qa!.limitations.contains("UNAVAILABLE: Advertisement identification/removal")})
        XCTAssertEqual(job.clips.map(\.title),["Part 01","Part 02","Part 03"])
        XCTAssertFalse(FileManager.default.fileExists(atPath:root.appendingPathComponent("helpers").path))

        // Supplying a transcript after deterministic acceptance cannot silently
        // reclassify the existing plan or replace accepted media/QA.
        let later = Transcript(sourceID:job.source!.id,sourceSHA256:job.source!.sha256,duration:3.4,engine:"fixture",segments:[TranscriptSegment(start:0,end:3.4,text:"This episode is sponsored by Example.")])
        try Persistence.save(later,to:jobDir.appendingPathComponent("transcript.json"))
        let reopened = try await coordinator.run(request)
        XCTAssertNil(reopened.transcript)
        XCTAssertEqual(reopened.planningBasis,.deterministicTime)
        XCTAssertEqual(reopened.clips.map(\.qa),persisted.clips.map(\.qa))
        // Remove only this test-created later transcript; retain no fake
        // transcript in the offline acceptance package.
        try FileManager.default.removeItem(at:jobDir.appendingPathComponent("transcript.json"))
    }

    func testTimePlanRepeatabilityAndUnsupportedSelections() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:dir)}
        let request = try independent(Fixtures.request(dir:dir,path:"local-fixture"))
        let source = SourceRecord(id:request.sourceID,owner:.dub,title:"Verified fixture metadata",path:"local-fixture",bytes:1,sha256:"fixture",duration:1250,width:320,height:180,fps:30,hasAudio:true,kind:.nativeVideo,streams:[],authorizationBasis:"fixture",classificationEvidence:"fixture")
        let first = try Editorial.planWithoutTranscript(request:request,source:source)
        let second = try Editorial.planWithoutTranscript(request:request,source:source)
        XCTAssertEqual(first,second)
        XCTAssertEqual(first.map(\.intervals),[[Interval(0,600)],[Interval(600,1200)],[Interval(1200,1250)]])
        try Planning.validateCoverage(duration:1250,exclusions:[],clips:first.map(\.intervals))
        var invalid = request; invalid.mode = .highlights
        XCTAssertThrowsError(try invalid.validate())
        invalid = request; invalid.adExclusions = [AdExclusion(interval:Interval(1,2),evidence:"requested",confidence:1)]
        XCTAssertThrowsError(try invalid.validate())
        invalid = request; invalid.localPath = nil; invalid.originalURL = "https://x.com/i/broadcasts/fixture"
        XCTAssertThrowsError(try invalid.validate())
        var legacy = request; legacy.transcriptPolicy = nil
        let encoded = try JSONSerialization.jsonObject(with:Persistence.encoder.encode(legacy)) as! [String:Any]
        XCTAssertNil(encoded["transcriptPolicy"])
    }

    func testIndependentPolicyReusesValidTranscriptButRejectsMismatch() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:dir)}
        var request = try independent(Fixtures.request(dir:dir,path:"local-fixture"))
        let source = SourceRecord(id:request.sourceID,owner:.dub,title:"Fixture",path:"local-fixture",bytes:1,sha256:"fixture",duration:1200,width:320,height:180,fps:30,hasAudio:true,kind:.nativeVideo,streams:[],authorizationBasis:"fixture",classificationEvidence:"fixture")
        let input = dir.appendingPathComponent("supplied.json")
        request.transcriptPath = input.path
        var transcript = Transcript(sourceID:source.id,sourceSHA256:source.sha256,duration:1200,engine:"fixture",segments:[TranscriptSegment(start:0,end:530,text:"Source-grounded sentence.")])
        try Persistence.save(transcript,to:input)
        let work = dir.appendingPathComponent("job")
        let reused = try await Acquisition.transcript(source:source,request:request,configuration:Configuration(),directory:work)
        XCTAssertEqual(reused,transcript)
        let clips = try Editorial.plan(request:request,source:source,transcript:reused!,exclusions:[])
        XCTAssertEqual(clips[0].intervals,[Interval(0,530)])
        XCTAssertEqual(clips[0].title,"Source-grounded sentence.")
        transcript.sourceSHA256 = "different"
        try Persistence.save(transcript,to:work.appendingPathComponent("transcript.json"))
        do {_ = try await Acquisition.transcript(source:source,request:request,configuration:Configuration(),directory:work);XCTFail("Mismatched cached transcript accepted")}
        catch {XCTAssertTrue(error.localizedDescription.contains("not bound"))}
    }

    func testMissingEditorialRequirementsBlockProductionBeforeProviders() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:dir)}
        let source = dir.appendingPathComponent("source.mp4")
        _ = try await Processes.run("ffmpeg",["-v","error","-f","lavfi","-i","testsrc2=s=320x180:r=30:d=1","-c:v","libx264","-pix_fmt","yuv420p",source.path])
        var request = try independent(Fixtures.request(dir:dir,path:source.path));request.fileToDrive = true
        let coordinator = try Coordinator(root:dir.appendingPathComponent("runtime"))
        let job = try await coordinator.run(request)
        XCTAssertEqual(job.state,.qaPassed,job.error ?? "")
        XCTAssertTrue(job.error?.contains("Production requirements incomplete") == true,job.error ?? "Missing production guard")
        XCTAssertNil(job.folderID);XCTAssertTrue(job.companions.isEmpty);XCTAssertTrue(job.registerRows.isEmpty)
        XCTAssertFalse(job.resumesAutomatically)
        XCTAssertNil(job.transcript)
        // Even a falsely promoted checkpoint must not pass the COMPLETED fast path.
        var forged = job;forged.state = .completed
        let work = await coordinator.directory(for:job.id)
        try Persistence.save(forged,to:work.appendingPathComponent("job.json"))
        let checked = try await coordinator.run(request)
        XCTAssertNotEqual(checked.state,.completed)
        XCTAssertTrue(checked.error?.contains("Completed checkpoint lacks") == true)
    }
}
