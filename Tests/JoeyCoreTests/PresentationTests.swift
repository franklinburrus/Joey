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
        XCTAssertEqual(view.stages.first {$0.id == "delivery"}!.detail,"Not requested")
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
        XCTAssertEqual(JobPresentation(job:job).status,"Local clips ready")
        XCTAssertFalse(JobPresentation(job:job).completed)
        job.state = .completed
        XCTAssertTrue(JobPresentation(job:job).completed)
        XCTAssertEqual(JobPresentation(job:job).status,"Completed")
    }
}
