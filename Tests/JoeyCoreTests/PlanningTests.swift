import XCTest
@testable import JoeyCore

final class PlanningTests: XCTestCase {
    func testHourProducesSixCompleteTenMinuteClips() throws {
        let clips = try Planning.fullShow(duration: 3600)
        XCTAssertEqual(clips, [[Interval(0,600)], [Interval(600,1200)], [Interval(1200,1800)],
                               [Interval(1800,2400)], [Interval(2400,3000)], [Interval(3000,3600)]])
        try Planning.validateCoverage(duration: 3600, exclusions: [], clips: clips)
    }
    func testShortAndFractionalRemainderAreNotDropped() throws {
        XCTAssertEqual(try Planning.fullShow(duration: 12.345), [[Interval(0,12.345)]])
        XCTAssertEqual(try Planning.fullShow(duration: 600.025), [[Interval(0,600)], [Interval(600,600.025)]])
    }
    func testExclusionInsideClipRetainsExactMapping() throws {
        let clips = try Planning.fullShow(duration: 720, exclusions: [Interval(240,300)])
        XCTAssertEqual(clips, [[Interval(0,240),Interval(300,660)], [Interval(660,720)]])
        try Planning.validateCoverage(duration: 720, exclusions: [Interval(240,300)], clips: clips)
    }
    func testPlatformLimitWinsWithoutLostRemainder() throws {
        XCTAssertEqual(try Planning.fullShow(duration: 300.1, limit: 140),
                       [[Interval(0,140)], [Interval(140,280)], [Interval(280,300.1)]])
    }
    func testNaturalBoundaryKeepsFollowingContent() throws {
        XCTAssertEqual(try Planning.fullShow(duration: 1000, boundaries: [550]),
                       [[Interval(0,550)], [Interval(550,1000)]])
    }
    func testAdjacentExclusionsDoNotCreateZeroLengthContent() throws {
        XCTAssertEqual(try Planning.fullShow(duration: 100, exclusions: [Interval(0,10),Interval(10,20),Interval(90,100)]),
                       [[Interval(20,90)]])
    }
    func testInvalidAndOverlappingIntervalsFail() {
        for duration in [0.0, -1, Double.nan, Double.infinity] {
            XCTAssertThrowsError(try Planning.fullShow(duration: duration))
        }
        XCTAssertThrowsError(try Planning.fullShow(duration: 100, exclusions: [Interval(20,40),Interval(30,50)]))
        XCTAssertThrowsError(try Planning.fullShow(duration: 100, limit: 0))
        XCTAssertThrowsError(try Planning.fullShow(duration: 100, exclusions: [Interval(0,101)]))
    }
    func testCoverageRejectsGapDuplicateAndReordering() {
        XCTAssertThrowsError(try Planning.validateCoverage(duration: 100, exclusions: [], clips: [[Interval(0,49)],[Interval(50,100)]]))
        XCTAssertThrowsError(try Planning.validateCoverage(duration: 100, exclusions: [], clips: [[Interval(0,60)],[Interval(50,100)]]))
        XCTAssertThrowsError(try Planning.validateCoverage(duration: 100, exclusions: [], clips: [[Interval(50,100)],[Interval(0,50)]]))
    }
}
