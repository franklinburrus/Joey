import XCTest
@testable import JoeyCore

final class PresentationTests: XCTestCase {
    func testStagesDoNotInferDeliveryFromAcceptedClips() throws {
        let dir = FileManager.default.temporaryDirectory
        var request = try Fixtures.request(dir:dir,path:"fixture")
        request.fileToDrive = true
        var job = JobRecord(id:"fixture",request:request)
        job.clips = [ClipRecord(id:1,title:"One",intervals:[Interval(0,5)],filename:"one.mp4",
            qa:QAReport(checkedAt:Date(),checks:[:],outputSHA256:"fixture",passed:true,limitations:[]))]
        job.state = .qaPassed; job.stage = "Drive folder"; job.error = "Provider unavailable"
        let view = JobPresentation(job:job)
        XCTAssertEqual(view.clipProgress,1)
        XCTAssertTrue(view.stages.first {$0.id == "qa"}!.verified)
        XCTAssertFalse(view.stages.first {$0.id == "delivery"}!.verified)
        XCTAssertFalse(view.stages.first {$0.id == "records"}!.verified)
        XCTAssertFalse(view.stages.first {$0.id == "transcript"}!.verified)
        XCTAssertEqual(view.activeStageID,"delivery")
        XCTAssertFalse(view.completed)
    }
    func testUnknownProgressAndCancelledStagesRemainUnverified() throws {
        var job = JobRecord(id:"fixture",request:try Fixtures.request(dir:FileManager.default.temporaryDirectory,path:"fixture"))
        job.state = .cancelled; job.stage = "transcription"
        let view = JobPresentation(job:job)
        XCTAssertNil(view.clipProgress)
        XCTAssertTrue(view.stages.allSatisfy {!$0.verified})
        XCTAssertEqual(view.activeStageID,"transcript")
        XCTAssertEqual(view.stages.first {$0.id == "delivery"}!.detail,"Required for every clip")
    }
    func testJobSelectionSurvivesBackgroundUpdatesAndFallsBackWhenRemoved() throws {
        let request = try Fixtures.request(dir:FileManager.default.temporaryDirectory,path:"fixture")
        let jobs = [JobRecord(id:"active",request:request),JobRecord(id:"selected",request:request)]
        XCTAssertEqual(JobPresentation.selectedJob(in:jobs,id:"selected")?.id,"selected")
        XCTAssertEqual(JobPresentation.selectedJob(in:jobs,id:"removed")?.id,"active")
        XCTAssertNil(JobPresentation.selectedJob(in:[],id:"selected"))
    }
    func testSourceSuggestionsPreserveIdentityAndRejectAmbiguousLinks() {
        XCTAssertEqual(SourceIdentitySuggestion.from("https://x.com/i/broadcasts/1oKMvNPnEzDGQ"),"x:broadcast:1oKMvNPnEzDGQ")
        XCTAssertEqual(SourceIdentitySuggestion.from("https://x.com/i/spaces/123abc"),"x:space:123abc")
        XCTAssertEqual(SourceIdentitySuggestion.from("https://x.com/example/status/123456"),"x:status:123456")
        XCTAssertEqual(SourceIdentitySuggestion.from("https://youtu.be/abcdefghijk?t=12"),"youtube:abcdefghijk")
        XCTAssertEqual(SourceIdentitySuggestion.from("https://www.youtube.com/watch?v=abcdefghijk"),"youtube:abcdefghijk")
        XCTAssertEqual(SourceIdentitySuggestion.from("https://youtube.com/shorts/abcdefghijk"),"youtube:abcdefghijk")
        for invalid in ["https://youtube.com/playlist?list=abcdef","https://x.com/example","https://x.com.evil.test/i/broadcasts/123","http://x.com/i/spaces/123","https://user:secret@x.com/i/spaces/123"] {
            XCTAssertNil(SourceIdentitySuggestion.from(invalid),invalid)
        }
    }
    func testProgressAndCompletionReflectPersistedStateWithoutChangingIt() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:dir)}
        var request = try Fixtures.request(dir:dir,path:"fixture");request.fileToDrive = true
        var job = JobRecord(id:"fixture",request:request)
        XCTAssertNil(JobPresentation(job:job).clipProgress)
        job.state = .processing;job.stage = "render clip 2"
        let qa = QAReport(checkedAt:Date(),checks:[:],outputSHA256:"fixture",passed:true,limitations:[])
        job.clips = [ClipRecord(id:1,title:"One",intervals:[Interval(0,5)],filename:"one.mp4",qa:qa),ClipRecord(id:2,title:"Two",intervals:[Interval(5,10)],filename:"two.mp4")]
        let before = try Persistence.encoder.encode(job)
        XCTAssertEqual(JobPresentation(job:job).clipProgress,0.5)
        XCTAssertEqual(JobPresentation(job:job).stage,"Creating clip 2 of 2")
        XCTAssertEqual(try Persistence.encoder.encode(job),before)
        job.clips[1].qa = qa;job.state = .filed;job.stage = "register reconciliation"
        XCTAssertEqual(JobPresentation(job:job).clipProgress,1)
        XCTAssertFalse(JobPresentation(job:job).completed)
        XCTAssertEqual(JobPresentation(job:job).status,"Finishing records")
        job.state = .qaPassed;job.error = "Provider HTTP 429"
        XCTAssertEqual(JobPresentation(job:job).status,"Needs attention")
        XCTAssertFalse(JobPresentation(job:job).completed)
        job.state = .cancelled
        XCTAssertEqual(JobPresentation(job:job).status,"Stopped — progress saved")
        job.error = nil;job.state = .qaPassed;job.request.fileToDrive = false
        XCTAssertEqual(JobPresentation(job:job).status,"Drive filing required")
        XCTAssertFalse(JobPresentation(job:job).completed)
        job.state = .completed
        XCTAssertFalse(JobPresentation(job:job).completed)
        XCTAssertEqual(JobPresentation(job:job).status,"Delivery incomplete")
    }

    func testRejectedSourceMarkersPreserveAcceptedEvidenceAndExactFailure() throws {
        let cases: [(JobState, String)] = [
            (.failed, "Synthetic source hash rejection"),
            (.qaPassed, "Synthetic source duration rejection"),
            (.filed, "Synthetic source classification rejection")
        ]
        for (state, error) in cases {
            var job = try deliveredJob()
            job.state = state
            job.stage = "source"
            job.error = error
            let before = try Persistence.encoder.encode(job)
            let presentation = JobPresentation(job:job)
            let source = try XCTUnwrap(presentation.stages.first {$0.id == "source"})

            XCTAssertFalse(source.verified)
            XCTAssertEqual(source.detail,"Verification failed · original evidence retained. Resolve the reported source issue before Resume.")
            XCTAssertEqual(job.error,error)
            XCTAssertTrue(presentation.stages.first {$0.id == "qa"}!.verified)
            XCTAssertEqual(presentation.accepted,job.clips.count)
            XCTAssertEqual(try Persistence.encoder.encode(job),before,"Presentation must preserve the rejected source, accepted clips, receipts and exact failure")
        }
    }

    func testSourceVerificationCheckingAndPauseRemainUnverified() throws {
        for state in [JobState.processing, .planned, .cancelled] {
            var job = try deliveredJob()
            job.state = state
            job.stage = "source"
            job.error = "Retained previous-attempt diagnostic"
            let before = try Persistence.encoder.encode(job)
            let source = try XCTUnwrap(JobPresentation(job:job).stages.first {$0.id == "source"})

            XCTAssertFalse(source.verified)
            XCTAssertEqual(source.detail,state == .cancelled ? "Verification paused · original evidence retained" : "Checking original · saved evidence retained")
            XCTAssertEqual(try Persistence.encoder.encode(job),before)
        }
    }

    func testLegacySourceFailureWithoutErrorRemainsUnverified() throws {
        var job = try deliveredJob()
        job.state = .failed
        job.stage = "source"
        job.error = nil
        let before = try Persistence.encoder.encode(job)
        let source = try XCTUnwrap(JobPresentation(job:job).stages.first {$0.id == "source"})

        XCTAssertFalse(source.verified)
        XCTAssertTrue(source.detail.contains("Verification failed"))
        XCTAssertEqual(try Persistence.encoder.encode(job),before)
    }

    func testSavedSourceMarkersRemainVerifiedOutsideCurrentSourceChecks() throws {
        var job = try deliveredJob()
        let completedBefore = try Persistence.encoder.encode(job)
        let completed = JobPresentation(job:job)
        XCTAssertTrue(completed.completed)
        XCTAssertTrue(completed.stages.first {$0.id == "source"}!.verified)
        XCTAssertEqual(completed.stages.first {$0.id == "source"}!.detail,"Verified original")
        XCTAssertEqual(try Persistence.encoder.encode(job),completedBefore)

        job.state = .failed
        job.stage = "capability verification"
        job.error = "Synthetic later-stage failure"
        let laterFailureBefore = try Persistence.encoder.encode(job)
        let laterFailure = JobPresentation(job:job)
        XCTAssertTrue(laterFailure.stages.first {$0.id == "source"}!.verified)
        XCTAssertEqual(laterFailure.stages.first {$0.id == "source"}!.detail,"Verified original")
        XCTAssertEqual(try Persistence.encoder.encode(job),laterFailureBefore)

        job.source = nil
        job.stage = "source"
        let absentBefore = try Persistence.encoder.encode(job)
        let absent = try XCTUnwrap(JobPresentation(job:job).stages.first {$0.id == "source"})
        XCTAssertFalse(absent.verified)
        XCTAssertEqual(absent.detail,"Pending")
        XCTAssertEqual(try Persistence.encoder.encode(job),absentBefore)
    }

    private func deliveredJob() throws -> JobRecord {
        var request = try Fixtures.request(dir:FileManager.default.temporaryDirectory,path:"fixture")
        request.owner = .taxstone;request.fileToDrive = true
        var job = JobRecord(id:"fixture",request:request)
        job.state = .completed;job.stage = "complete";job.folderID = "fixture-folder"
        job.transcript = Transcript(sourceID:request.sourceID,sourceSHA256:String(repeating:"a",count:64),duration:10,
            engine:"Synthetic UI regression",segments:[TranscriptSegment(start:0,end:10,text:"Synthetic complete transcript.")])
        job.source = SourceRecord(id:request.sourceID,owner:.taxstone,title:request.title,path:"fixture",bytes:100,
            sha256:String(repeating:"a",count:64),duration:10,width:0,height:0,fps:0,hasAudio:true,kind:.audio,
            streams:[],authorizationBasis:"Synthetic",classificationEvidence:"Synthetic")
        let destination = try DestinationResolver.resolve(source:job.source!,request:request,asset:.clip)
        job.clips = (1...2).map {number in
            let hash = Integrity.textHash("fixture-hash-\(number)"), name = "\(number).mp4"
            let receipt = DriveReceipt(id:"fixture-file-\(number)",name:name,parent:job.folderID!,bytes:100,md5:String(repeating:"a",count:32),
                sha256:hash,url:"https://example.invalid/fixture-\(number)",permissions:["user:owner"],verifiedAt:Date(),destination:destination,permissionFingerprint:String(repeating:"a",count:64))
            return ClipRecord(id:number,title:"Fixture \(number)",intervals:[Interval(Double(number-1)*5,Double(number)*5)],
                filename:name,measuredDuration:5,bytes:100,sha256:hash,
                qa:QAReport(checkedAt:Date(),checks:[:],outputSHA256:hash,passed:true,limitations:["Synthetic only"]),drive:receipt)
        }
        for name in Records.companionNames(source:job.source!) {
            var receipt = job.clips[0].drive!;receipt.id = "companion_"+name;receipt.name = name
            job.companions[name] = receipt
        }
        return job
    }

    func testCompletedBadgeRequiresDriveForEveryClipEvenForLegacyLocalJobs() throws {
        let delivered = try deliveredJob()
        XCTAssertTrue(JobPresentation(job:delivered).completed)
        for requested in [true,false] {
            var job = delivered;job.request.fileToDrive = requested;job.clips[1].drive = nil
            let original = try Persistence.encoder.encode(job)
            let view = JobPresentation(job:job)
            XCTAssertFalse(view.completed)
            XCTAssertEqual(view.status,"Delivery incomplete")
            XCTAssertEqual(view.stage,"Drive filing required")
            XCTAssertEqual(view.stages.first {$0.id == "delivery"}!.detail,"Required · 1/2 clips verified")
            XCTAssertFalse(view.stages.first {$0.id == "delivery"}!.verified)
            XCTAssertFalse(view.stages.first {$0.id == "records"}!.verified)
            XCTAssertEqual(try Persistence.encoder.encode(job),original,"Presentation must preserve checkpoints")
        }
    }

    func testCompletionRejectsWrongRouteMissingCompanionsAndDuplicateIDs() throws {
        let accepted = try deliveredJob()
        var variants: [JobRecord] = []
        var job = accepted;job.clips[0].drive!.destination = nil;variants.append(job)
        job = accepted;job.clips[0].drive!.permissionFingerprint = nil;variants.append(job)
        job = accepted;job.companions.removeValue(forKey:"RECONCILE.md");variants.append(job)
        job = accepted;job.companions["RECONCILE.md"]!.parent = "wrong-parent";variants.append(job)
        job = accepted;job.companions["RECONCILE.md"]!.id = job.clips[0].drive!.id;variants.append(job)
        job = accepted;job.transcript!.sourceSHA256 = "wrong-source";variants.append(job)
        for invalid in variants {XCTAssertFalse(invalid.hasRequiredCompletionEvidence)}
        let legacy = variants[0]
        XCTAssertEqual(JobPresentation(job:legacy).filed,1,"Legacy receipts without authoritative route evidence cannot make Drive fully verified")
    }

    func testMismatchedDriveReceiptsCannotMakeDeliveryGreen() throws {
        let delivered = try deliveredJob()
        var variants: [JobRecord] = []
        var job = delivered;job.clips[1].drive!.sha256 = "other";variants.append(job)
        job = delivered;job.clips[1].drive!.name = "other.mp4";variants.append(job)
        job = delivered;job.clips[1].drive!.parent = "other-folder";variants.append(job)
        job = delivered;job.clips[1].drive!.bytes = 101;variants.append(job)
        job = delivered;job.clips[1].qa!.outputSHA256 = "other";variants.append(job)
        for invalid in variants {
            let view = JobPresentation(job:invalid)
            XCTAssertEqual(view.filed,1)
            XCTAssertFalse(view.completed)
            XCTAssertFalse(view.stages.first {$0.id == "delivery"}!.verified)
        }
    }
}
