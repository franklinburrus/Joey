import XCTest
@testable import JoeyCore

final class EditorialAuditRegressionTests: XCTestCase {
    private func fixture(duration: Double = 1800) throws -> (JobRequest, SourceRecord) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let request = try Fixtures.request(dir: root, path: "unused synthetic source")
        let source = SourceRecord(id: request.sourceID, owner: .dub, title: "Synthetic audit source",
            path: request.localPath!, bytes: 1, sha256: "synthetic", duration: duration,
            width: 320, height: 180, fps: 30, hasAudio: false, kind: .nativeVideo, streams: [],
            authorizationBasis: "Synthetic regression", classificationEvidence: "Synthetic regression")
        return (request, source)
    }

    private func transcript(_ source: SourceRecord, opening: String, ending: String,
                            middle: String = "A paid product offer.") -> Transcript {
        Transcript(sourceID: source.id, sourceSHA256: source.sha256, duration: source.duration,
            engine: "Synthetic regression", segments: [
                TranscriptSegment(start: 0, end: 10, text: "We have no sponsor today."),
                TranscriptSegment(start: 10, end: 20, text: opening),
                TranscriptSegment(start: 20, end: 30, text: middle),
                TranscriptSegment(start: 30, end: 40, text: ending),
                TranscriptSegment(start: 40, end: source.duration, text: "Retained discussion.")
            ])
    }

    func testExactNegatedAuditCaseRetainsAll1800Seconds() throws {
        let (request, source) = try fixture()
        let input = transcript(source,
            opening: "Do not say this episode is sponsored by Example, because it is not.",
            ending: "Back to the show we were discussing yesterday.",
            middle: "That sentence is misleading and we are discussing why.")
        let exclusions = Editorial.exclusions(request, transcript: input)
        let clips = try Editorial.plan(request: request, source: source, transcript: input, exclusions: exclusions)
        XCTAssertTrue(exclusions.isEmpty)
        XCTAssertEqual(clips.reduce(0) { $0 + $1.expectedDuration }, 1800)
        XCTAssertNoThrow(try Planning.validateCoverage(duration: 1800, exclusions: [], clips: clips.map(\.intervals)))
    }

    func testQuotedNegatedAndUnrelatedSponsorshipDiscussionStays() throws {
        let (request, source) = try fixture()
        for opening in [
            "She quoted the phrase \"this episode is sponsored by Example\" while discussing a lawsuit.",
            "This episode is sponsored by nobody. There is no paid read today.",
            "If this episode is sponsored by Example, we should disclose that.",
            "We are analyzing why the phrase this episode is sponsored by Example appears in podcasts.",
            "This episode is sponsored by Example is the phrase we are discussing.",
            "This episode is sponsored by Example. That was a quotation.",
            "This is a paid advertisement is what the fictional host says."
        ] {
            XCTAssertTrue(Editorial.exclusions(request, transcript: transcript(source,
                opening: opening, ending: "Back to the show.")).isEmpty, opening)
        }
        XCTAssertTrue(Editorial.exclusions(request, transcript: transcript(source,
            opening: "This episode is sponsored by Example.",
            ending: "Back to the show we were discussing yesterday.")).isEmpty)
    }

    func testGenuineBoundedAdsKeepExactIntervalsAndUnboundedReadsStay() throws {
        var (request, source) = try fixture()
        for opening in ["This episode is sponsored by Example.", "This is a paid advertisement."] {
            let input = transcript(source, opening: opening, ending: "Back to the show.")
            for ending in ["Back to the show.", "Now back to the show.", "Now, back to the episode!"] {
                let found = Editorial.exclusions(request, transcript: transcript(source, opening: opening, ending: ending))
                XCTAssertEqual(found.map(\.interval), [Interval(10, 30)])
                XCTAssertTrue(found.allSatisfy { $0.confidence >= 0.99 && !$0.evidence.isEmpty })
            }
            XCTAssertTrue(Editorial.exclusions(request, transcript: transcript(source,
                opening: opening, ending: "Continuing this conversation.")).isEmpty)
            request.mode = .highlights
            XCTAssertTrue(Editorial.exclusions(request, transcript: input).isEmpty)
            request.mode = .fullShow
        }
        request.adExclusions = [AdExclusion(interval: Interval(100, 110), evidence: "Explicit source-bound exclusion", confidence: 1)]
        XCTAssertEqual(Editorial.exclusions(request, transcript: transcript(source,
            opening: "Uncertain promotion.", ending: "Conversation.")).map(\.interval), [Interval(100, 110)])
    }

    func testLaterRetractionOrSplitQuotationCancelsInferredAdRemoval() throws {
        let (request, source) = try fixture()
        for middle in [
            "We have no sponsor today. That was a quotation.",
            "That phrase was quoted, without a paid read.",
            "We did not receive sponsorship.",
            "We were discussing the wording, not reading an advertisement."
        ] {
            let input = transcript(source, opening: "This episode is sponsored by Example.",
                ending: "Back to the show.", middle: middle)
            XCTAssertTrue(Editorial.exclusions(request, transcript: input).isEmpty, middle)
        }
    }

    private func crossingTranscript(_ source: SourceRecord) -> Transcript {
        Transcript(sourceID: source.id, sourceSHA256: source.sha256, duration: source.duration,
            engine: "Synthetic source-bound sentence evidence", segments: [
                TranscriptSegment(start: 0, end: 895, text: "Complete opening discussion."),
                TranscriptSegment(start: 895, end: 910, text: "If you remove the preceding condition, this conclusion makes no sense."),
                TranscriptSegment(start: 910, end: 1040, text: "A complete second-block selection."),
                TranscriptSegment(start: 1040, end: min(1796, source.duration), text: "Complete continuation."),
                TranscriptSegment(start: min(1796, source.duration), end: source.duration, text: "Complete ending.")
            ].filter { $0.end > $0.start })
    }

    func testLinkHighlightStartsAfterCrossingSentenceAtBothLimits() throws {
        var (request, source) = try fixture()
        request.mode = .highlights
        request.productionWorkflow = .link
        for limit in [600.0, 140] {
            request.profile.x!.maxDuration = limit
            let clips = try Editorial.plan(request: request, source: source,
                transcript: crossingTranscript(source), exclusions: [])
            XCTAssertEqual(clips.count, 2)
            XCTAssertEqual(clips[1].intervals.first?.start, 910)
            XCTAssertLessThanOrEqual(clips[1].expectedDuration, limit)
            XCTAssertLessThanOrEqual(clips[0].intervals.last!.end, clips[1].intervals.first!.start)
        }
    }

    func testPartialBlockKeepsCountAndCompliantEndingWithoutOverlap() throws {
        var (request, source) = try fixture(duration: 1801)
        request.mode = .highlights
        request.productionWorkflow = .link
        request.profile.x!.surface = "Buffer X video"
        request.profile.instagram!.surface = "Buffer Instagram Reel"
        request.profile.x!.maxDuration = 140
        let clips = try Editorial.plan(request: request, source: source,
            transcript: crossingTranscript(source), exclusions: [])
        XCTAssertEqual(clips.count, 3)
        XCTAssertEqual(clips.last?.intervals, [Interval(1796, 1801)])
        XCTAssertTrue(clips.allSatisfy { (5...139.8250001).contains($0.expectedDuration) })
        XCTAssertLessThanOrEqual(clips[1].intervals.last!.end, clips[2].intervals.first!.start)
    }

    func testKnownSentenceWithoutViableStartFailsInsteadOfCuttingItsInterior() throws {
        var (request, source) = try fixture()
        request.mode = .highlights
        request.productionWorkflow = .link
        let input = Transcript(sourceID: source.id, sourceSHA256: source.sha256, duration: source.duration,
            engine: "Synthetic", segments: [TranscriptSegment(start: 0, end: 1800, text: "One known sentence.")])
        XCTAssertThrowsError(try Editorial.plan(request: request, source: source, transcript: input, exclusions: []))
    }

    func testExplicitCountConflictsAndFixedIntervalsKeepPrecedence() throws {
        var (request, source) = try fixture()
        request.mode = .highlights
        request.productionWorkflow = .link
        request.requestedCount = 1
        XCTAssertThrowsError(try Editorial.plan(request: request, source: source,
            transcript: crossingTranscript(source), exclusions: []))
        request.fixedIntervals = [Interval(900, 1000)]
        XCTAssertEqual(try Editorial.plan(request: request, source: source,
            transcript: crossingTranscript(source), exclusions: []).map(\.intervals), [[Interval(900, 1000)]])
        request.fixedIntervals = [Interval(900, 1601)]
        XCTAssertThrowsError(try Editorial.plan(request: request, source: source,
            transcript: crossingTranscript(source), exclusions: []))
        XCTAssertEqual(request.fixedIntervals, [Interval(900, 1601)])
    }

    func testCoordinatorPersistsCorrectedExclusionsAndHighlightStartsBeforeRendering() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let media = root.appendingPathComponent("synthetic-original.nut")
        _ = try await Processes.run("ffmpeg", ["-nostdin", "-v", "error", "-f", "lavfi", "-i",
            "testsrc2=s=32x32:r=1:d=1800", "-c:v", "ffv1", media.path])
        for mode in [JobMode.fullShow, .highlights] {
            var profile = try Fixtures.landscapeProfile(dir: root)
            profile.x!.maxDuration = 140
            var request = try ProductionIntake.request(source: DiscoveredSource(id: "youtube:abcdefghijk",
                title: "Synthetic coordinator planning", url: "https://www.youtube.com/watch?v=abcdefghijk",
                duration: 1800), content: .dub, mode: mode, sharedProfile: profile)
            let source = try await Media.inspect(media, request: request)
            let input = mode == .fullShow ? transcript(source,
                opening: "Do not say this episode is sponsored by Example, because it is not.",
                ending: "Back to the show we were discussing yesterday.") : crossingTranscript(source)
            let inputURL = root.appendingPathComponent(mode.rawValue + "-transcript.json")
            try Persistence.save(input, to: inputURL)
            request.transcriptPath = inputURL.path
            let runtime = root.appendingPathComponent(mode.rawValue + "-runtime")
            let coordinator = try Coordinator(root: runtime)
            var saved = JobRecord(id: try request.stableID(), request: request)
            saved.source = source
            try Persistence.save(saved, to: runtime.appendingPathComponent("jobs/\(saved.id)/job.json"))
            let provider = EditorialPlanningDelivery()
            let operation = Task {
                try await Coordinator.$deliveryOverride.withValue(provider) {
                    try await coordinator.run(request) { job in
                        if job.stage == "planning", !job.clips.isEmpty {
                            withUnsafeCurrentTask { $0?.cancel() }
                        }
                    }
                }
            }
            let result = try await operation.value
            XCTAssertEqual(result.state, .cancelled, result.error ?? "")
            XCTAssertEqual(result.planningBasis, .transcriptAssisted)
            XCTAssertTrue(result.exclusions.isEmpty)
            XCTAssertFalse(result.clips.isEmpty)
            XCTAssertTrue(result.clips.allSatisfy { $0.qa == nil && $0.drive == nil })
            if mode == .fullShow {
                XCTAssertEqual(result.clips.reduce(0) { $0 + $1.expectedDuration }, 1800)
                XCTAssertNoThrow(try Planning.validateCoverage(duration: 1800, exclusions: [], clips: result.clips.map(\.intervals)))
            } else {
                XCTAssertEqual(result.clips.count, 2)
                XCTAssertEqual(result.clips[1].intervals.first?.start, 910)
            }
            let archives = await provider.archives
            let unexpected = await provider.unexpectedCalls
            XCTAssertEqual(archives, 1)
            XCTAssertEqual(unexpected, 0)
            XCTAssertEqual(try Integrity.sha256(media), source.sha256)
        }
    }
}

private actor EditorialPlanningDelivery: CoordinatorDelivery {
    var archives = 0
    var unexpectedCalls = 0
    private func unexpected() -> JoeyError {
        unexpectedCalls += 1
        return .failed("Unexpected provider operation after planning cancellation")
    }
    func archive(source: SourceRecord, request: JobRequest) async throws -> String {
        archives += 1
        return "https://example.invalid/synthetic-archive"
    }
    func metadata(_ id: String) async throws -> [String: Any] { throw unexpected() }
    func downloadOriginal(reference: String, directory: URL) async throws -> URL { throw unexpected() }
    func episodeFolder(source: SourceRecord, request: JobRequest, jobID: String, existingFolderID: String?, intentURL: URL) async throws -> String { throw unexpected() }
    func upload(_ local: URL, name: String?, parent: String, destination: FilingDestination, replaceCompanion: Bool) async throws -> DriveReceipt { throw unexpected() }
    func resolveArtwork(source: SourceRecord, configuration: Configuration, root: URL) async throws -> Artwork { throw unexpected() }
    func reconcileRegister(job: JobRecord, tab: String) async throws -> [String] { throw unexpected() }
    func verifyPackage(job: JobRecord, directory: URL) async throws { throw unexpected() }
}
