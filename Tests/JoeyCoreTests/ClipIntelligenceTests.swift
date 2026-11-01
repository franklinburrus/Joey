import XCTest
@testable import JoeyCore

final class ClipIntelligenceTests: XCTestCase {
    private func completedJob(_ segments: [TranscriptSegment]? = nil) -> JobRecord {
        let sourceHash = String(repeating: "a", count: 64)
        let outputHash = String(repeating: "b", count: 64)
        let request = JobRequest(owner: .taxstone, sourceID: "soundcloud:episode-1",
                                 title: "Episode One", localPath: "/unused/source.wav",
                                 profile: SharedProfile(x: nil, instagram: nil, width: 720, height: 1280))
        let source = SourceRecord(id: request.sourceID, owner: .taxstone, title: request.title,
                                  path: "/unused/source.wav", bytes: 1, sha256: sourceHash,
                                  duration: 60, width: 0, height: 0, fps: 0, hasAudio: true,
                                  kind: .audio, streams: [], authorizationBasis: "Authorized fixture",
                                  classificationEvidence: "Synthetic audio fixture")
        let transcript = Transcript(sourceID: source.id, sourceSHA256: sourceHash, duration: 60,
                                    engine: "fixture", segments: segments ?? [
            TranscriptSegment(start: 0, end: 20, text: "Why do music contracts matter to independent artists?"),
            TranscriptSegment(start: 20, end: 40, text: "I disagree because music contracts can protect ownership."),
            TranscriptSegment(start: 40, end: 60, text: "However, music contracts need clear terms about ownership.")
        ])
        let clip = ClipRecord(id: 1, title: "Old production title", intervals: [Interval(0, 60)],
                              filename: "accepted-original-name.mp4", measuredDuration: 60, bytes: 100,
                              sha256: outputHash,
                              qa: QAReport(checkedAt: Date(timeIntervalSince1970: 1), checks: ["decode": "passed"],
                                           outputSHA256: outputHash, passed: true, limitations: []))
        return JobRecord(id: "job-1", request: request, state: .completed, source: source,
                         transcript: transcript, planningBasis: .transcriptAssisted, clips: [clip])
    }

    func testDistributionTitleUsesSupportedTopicInsteadOfFirstFragment() throws {
        let job = completedJob()
        let recommendation = try ClipIntelligence.evaluate(job: job, clip: job.clips[0])
        XCTAssertTrue(recommendation.title.lowercased().contains("music contracts"))
        XCTAssertFalse(recommendation.title.hasPrefix("Why do"))
        XCTAssertFalse(recommendation.title.contains("Old production title"))
        XCTAssertTrue(recommendation.xCaption.contains("Episode One"))
        XCTAssertTrue(recommendation.instagramCaption.contains("Episode One"))
        XCTAssertNotEqual(recommendation.xCaption, recommendation.instagramCaption)
        XCTAssertEqual(recommendation.transcriptEvidence, job.transcript!.segments)
    }

    func testAllCriteriaExplainEvidenceAndUnknownsWithoutPerformanceClaims() throws {
        let job = completedJob()
        let recommendation = try ClipIntelligence.evaluate(job: job, clip: job.clips[0])
        for criterion in ["Opening hook", "Immediate comprehensibility", "Standalone context", "Topic relevance",
                          "Meaningful disagreement", "Emotional or narrative interest", "Shareability",
                          "Audience relevance", "Timeliness", "Sustained attention", "Natural boundaries", "Editorial accuracy"] {
            XCTAssertTrue(recommendation.rationale.contains { $0.hasPrefix(criterion + ":") }, criterion)
        }
        XCTAssertTrue(recommendation.confidence.lowercased().contains("low"))
        XCTAssertTrue(recommendation.restrictions.contains { $0.contains("deterministic") })
        XCTAssertTrue(recommendation.restrictions.contains { $0.contains("not") && $0.contains("virality") })
        XCTAssertTrue(recommendation.rationale.contains { $0.hasPrefix("Timeliness:") && $0.contains("unverified") })
        XCTAssertTrue((0...100).contains(recommendation.xScore))
        XCTAssertTrue((0...100).contains(recommendation.instagramScore))
    }

    func testPlatformEmphasisDistinguishesDiscussionFromPersonalNarrative() throws {
        let debate = completedJob()
        let narrative = completedJob([
            TranscriptSegment(start: 0, end: 20, text: "I remember how my family helped me find confidence."),
            TranscriptSegment(start: 20, end: 40, text: "When I felt afraid, my family stayed with me."),
            TranscriptSegment(start: 40, end: 60, text: "I learned to ask my family for support.")
        ])
        let discussion = try ClipIntelligence.evaluate(job: debate, clip: debate.clips[0])
        let story = try ClipIntelligence.evaluate(job: narrative, clip: narrative.clips[0])
        XCTAssertGreaterThan(story.instagramScore, story.xScore)
        XCTAssertGreaterThan(discussion.xScore - discussion.instagramScore, story.xScore - story.instagramScore)
    }

    func testRejectsIncompleteForeignOrChangedClipRecords() throws {
        var job = completedJob()
        let clip = job.clips[0]
        for state in [JobState.planned, .processing, .qaPassed, .filed, .cancelled, .failed] {
            job.state = state
            XCTAssertThrowsError(try ClipIntelligence.evaluate(job: job, clip: clip))
        }
        job.state = .completed
        var foreign = clip; foreign.intervals = [Interval(0, 59)]
        XCTAssertThrowsError(try ClipIntelligence.evaluate(job: job, clip: foreign))
        job.clips.append(clip)
        XCTAssertThrowsError(try ClipIntelligence.evaluate(job: job, clip: clip))
    }

    func testRejectsMismatchedSourceTranscriptAndUnacceptedMedia() throws {
        let good = completedJob()
        var bad = good; bad.source!.owner = .dub
        XCTAssertThrowsError(try ClipIntelligence.evaluate(job: bad, clip: bad.clips[0]))
        bad = good; bad.transcript!.sourceSHA256 = String(repeating: "c", count: 64)
        XCTAssertThrowsError(try ClipIntelligence.evaluate(job: bad, clip: bad.clips[0]))
        bad = good; bad.transcript!.duration = 30
        XCTAssertThrowsError(try ClipIntelligence.evaluate(job: bad, clip: bad.clips[0]))
        bad = good; bad.transcript = nil
        XCTAssertThrowsError(try ClipIntelligence.evaluate(job: bad, clip: bad.clips[0]))
        bad = good; bad.planningBasis = .deterministicTime
        XCTAssertThrowsError(try ClipIntelligence.evaluate(job: bad, clip: bad.clips[0]))
        bad = good; bad.clips[0].qa!.outputSHA256 = String(repeating: "d", count: 64)
        XCTAssertThrowsError(try ClipIntelligence.evaluate(job: bad, clip: bad.clips[0]))
        bad = good; bad.clips[0].qa!.passed = false
        XCTAssertThrowsError(try ClipIntelligence.evaluate(job: bad, clip: bad.clips[0]))
    }

    func testExcludedAndBoundaryCrossingTextCannotSupplyTitleOrCaption() throws {
        var job = completedJob([
            TranscriptSegment(start: 0, end: 20, text: "Family support helped us through a difficult personal experience."),
            TranscriptSegment(start: 20, end: 40, text: "Music contracts and music contracts: excluded promotional discussion."),
            TranscriptSegment(start: 40, end: 60, text: "Our family shared meals and offered support every day.")
        ])
        job.clips[0].intervals = [Interval(0, 20), Interval(40, 60)]
        job.clips[0].measuredDuration = 40
        let result = try ClipIntelligence.evaluate(job: job, clip: job.clips[0])
        XCTAssertEqual(result.transcriptEvidence.map(\.start), [0, 40])
        XCTAssertFalse(result.title.lowercased().contains("contracts"))
        XCTAssertFalse(result.xCaption.lowercased().contains("contracts"))
        XCTAssertTrue(result.title.lowercased().contains("family"))
        job.clips[0].intervals = [Interval(10.125, 60)]
        let crossing = try ClipIntelligence.evaluate(job: job, clip: job.clips[0])
        XCTAssertEqual(crossing.transcriptEvidence.map(\.start), [20, 40])
        XCTAssertTrue(crossing.boundaryNotes.contains { $0.contains("10.125") })
        XCTAssertTrue(crossing.boundaryNotes.contains { $0.lowercased().contains("future") })
    }

    func testUnsupportedTextFallsBackWithoutInventingTopicOrSpeaker() throws {
        let job = completedJob([
            TranscriptSegment(start: 0, end: 60, text: "Well, that is what they said and it was like that before.")
        ])
        let result = try ClipIntelligence.evaluate(job: job, clip: job.clips[0])
        XCTAssertTrue(result.title.contains("Episode One"))
        XCTAssertFalse(result.title.contains("Well"))
        XCTAssertTrue(result.topic.lowercased().contains("unresolved"))
        XCTAssertTrue(result.confidence.lowercased().contains("low"))
        let empty = completedJob([TranscriptSegment(start: 0, end: 60, text: "…")])
        XCTAssertThrowsError(try ClipIntelligence.evaluate(job: empty, clip: empty.clips[0]))
    }

    func testInvalidIntervalsAndAmbiguousTranscriptAreRejected() throws {
        var job = completedJob()
        for intervals in [[Interval(0, 61)], [Interval(20, 10)], [Interval(0, 30), Interval(20, 60)], []] {
            job.clips[0].intervals = intervals
            XCTAssertThrowsError(try ClipIntelligence.evaluate(job: job, clip: job.clips[0]))
        }
        job = completedJob()
        job.transcript!.segments[1].start = 19
        XCTAssertThrowsError(try ClipIntelligence.evaluate(job: job, clip: job.clips[0]))
    }

    func testEvaluationIsDeterministicAndPreservesAcceptedJobBytes() throws {
        let job = completedJob()
        let original = try Persistence.encoder.encode(job)
        let first = try ClipIntelligence.evaluate(job: job, clip: job.clips[0])
        XCTAssertEqual(first, try ClipIntelligence.evaluate(job: job, clip: job.clips[0]))
        XCTAssertEqual(try Persistence.decoder.decode(ClipRecommendation.self, from: Persistence.encoder.encode(first)), first)
        XCTAssertEqual(try Persistence.encoder.encode(job), original)
        XCTAssertEqual(job.clips[0].filename, "accepted-original-name.mp4")
        XCTAssertEqual(job.clips[0].intervals, [Interval(0, 60)])
    }

    func testProvocationAndUnverifiedCurrentnessDoNotIncreaseScores() throws {
        let plain = completedJob([
            TranscriptSegment(start: 0, end: 60, text: "Music contracts involve ownership and different terms for artists.")
        ])
        let provocative = completedJob([
            TranscriptSegment(start: 0, end: 60, text: "Today shocking outrageous music contracts involve ownership and different terms for artists.")
        ])
        let baseline = try ClipIntelligence.evaluate(job: plain, clip: plain.clips[0])
        let changed = try ClipIntelligence.evaluate(job: provocative, clip: provocative.clips[0])
        XCTAssertEqual(changed.xScore, baseline.xScore)
        XCTAssertEqual(changed.instagramScore, baseline.instagramScore)
        XCTAssertFalse(changed.title.lowercased().contains("shocking"))
        XCTAssertFalse(changed.title.lowercased().contains("today"))
    }

    func testFallbackCaptionsRemainBoundedForLongSourceMetadata() throws {
        var job = completedJob([
            TranscriptSegment(start: 0, end: 60, text: "Well, that is what they said and it was like that before.")
        ])
        job.source!.title = String(repeating: "Long episode title ", count: 100)
        job.clips[0].id = Int.max
        let recommendation = try ClipIntelligence.evaluate(job: job, clip: job.clips[0])
        XCTAssertLessThanOrEqual(recommendation.xCaption.count, 280)
        XCTAssertLessThanOrEqual(recommendation.instagramCaption.count, 2200)
    }
}
