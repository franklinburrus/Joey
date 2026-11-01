import XCTest
@testable import JoeyCore

final class DurationPolicyTests: XCTestCase {
    private func fixture(_ duration: Double) throws -> (JobRequest, SourceRecord, Transcript) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        addTeardownBlock {try? FileManager.default.removeItem(at:dir)}
        var request = try Fixtures.request(dir:dir,path:"unused")
        request.profile.x!.surface = "Buffer X video"
        request.profile.instagram!.surface = "Buffer Instagram Reel"
        request.profile.x!.maxDuration = 140
        request.profile.instagram!.maxDuration = 900
        let source = SourceRecord(id:request.sourceID,owner:request.owner,title:"Fixture",path:"unused",bytes:1,sha256:"fixture",duration:duration,width:320,height:180,fps:30,hasAudio:false,kind:.nativeVideo,streams:[],authorizationBasis:"fixture",classificationEvidence:"fixture")
        let transcript = Transcript(sourceID:source.id,sourceSHA256:source.sha256,duration:duration,engine:"fixture",segments:[TranscriptSegment(start:0,end:duration,text:"Complete fixture.")])
        return (request,source,transcript)
    }
    private func probe(_ duration: Double) -> MediaProbe {
        MediaProbe(streams:[StreamInfo(codec_type:"video",codec_name:"h264",width:720,height:1280,pix_fmt:"yuv420p",field_order:"progressive",sample_aspect_ratio:"1:1",avg_frame_rate:"30/1",duration:String(duration),start_time:"0",bit_rate:"2000000")],format:MediaProbe.Format(duration:String(duration),size:"1000000",format_name:"mov,mp4,m4a,3gp,3g2,mj2"))
    }
    func testPlannerOutputsPassPreflightIncludingWorstPositiveEncodingTolerance() throws {
        for duration in [5.0, 139.8, 140, 141, 279.65, 280, 281, 600.025] {
            let (request,source,transcript) = try fixture(duration)
            let clips = try Editorial.plan(request:request,source:source,transcript:transcript,exclusions:[])
            try Planning.validateCoverage(duration:duration,exclusions:[],clips:clips.map(\.intervals))
            for clip in clips {
                XCTAssertGreaterThanOrEqual(clip.expectedDuration,5)
                XCTAssertLessThanOrEqual(clip.expectedDuration,139.825 + 0.000001)
                for drift in [0.0, 0.074999] {
                    XCTAssertNoThrow(try BufferPreflight.validateTechnical(probe(clip.expectedDuration+drift),bytes:1_000_000,expectedDuration:clip.expectedDuration,hasAudio:false,profile:request.profile))
                }
            }
        }
    }
    func testShortSourcesAndExplicitSelectionsReportConflictWithoutChangingSelection() throws {
        for length in [0.01,1,4.999] {
            let (request,source,transcript) = try fixture(length)
            XCTAssertThrowsError(try Editorial.plan(request:request,source:source,transcript:transcript,exclusions:[]))
        }
        var (request,source,transcript) = try fixture(200)
        request.mode = .highlights
        for selection in [Interval(0,1),Interval(0,140)] {
            request.fixedIntervals = [selection]
            XCTAssertThrowsError(try Editorial.plan(request:request,source:source,transcript:transcript,exclusions:[]))
            XCTAssertEqual(request.fixedIntervals,[selection])
        }
        for length in [5.0,139.825] {
            request.fixedIntervals = [Interval(0,length)]
            XCTAssertEqual(try Editorial.plan(request:request,source:source,transcript:transcript,exclusions:[]).first?.intervals,request.fixedIntervals)
        }
    }
    func testAutomaticHighlightRemainderKeepsSourceEndingWithinCompliantSelection() throws {
        var (request,source,transcript) = try fixture(1801)
        request.mode = .highlights;request.productionWorkflow = .link
        let clips = try Editorial.plan(request:request,source:source,transcript:transcript,exclusions:[])
        XCTAssertEqual(clips.count,3)
        XCTAssertEqual(clips.last?.intervals,[Interval(1796,1801)])
        XCTAssertTrue(clips.allSatisfy{(5...139.8250001).contains($0.expectedDuration)})
        XCTAssertLessThan(clips[1].intervals.last!.end,clips[2].intervals.first!.start)
    }

    func testExclusionsAndModelIndependentPlanningRebalanceRemainder() throws {
        var (request,source,transcript) = try fixture(300)
        let exclusions = [AdExclusion(interval:Interval(80,99),evidence:"Synthetic bounded ad",confidence:1)]
        let clips = try Editorial.plan(request:request,source:source,transcript:transcript,exclusions:exclusions)
        try Planning.validateCoverage(duration:300,exclusions:exclusions.map(\.interval),clips:clips.map(\.intervals))
        XCTAssertTrue(clips.allSatisfy{(5...139.8250001).contains($0.expectedDuration)})
        request.transcriptPolicy = .modelIndependent
        source.duration = 141
        let local = try Editorial.planWithoutTranscript(request:request,source:source)
        XCTAssertTrue(local.allSatisfy{(5...139.8250001).contains($0.expectedDuration)})
        try Planning.validateCoverage(duration:141,exclusions:[],clips:local.map(\.intervals))
    }
}
