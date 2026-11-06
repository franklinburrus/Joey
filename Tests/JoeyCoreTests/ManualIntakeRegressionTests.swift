import XCTest
@testable import JoeyCore
@testable import JoeyInterface

final class ManualIntakeRegressionTests: XCTestCase {
    @MainActor private func fixture() throws -> (JobModel, DiscoveredSource, JobRequest) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let model = JobModel(root: root, startsAutomatically: false)
        model.configuration?.profile = try Fixtures.landscapeProfile(dir: root)
        let source = DiscoveredSource(id: "youtube:abcdefghijk", title: "Original source title",
            url: "https://www.youtube.com/watch?v=abcdefghijk", duration: 1800, episodeDate: "2026-11-04")
        let request = try ProductionIntake.request(source: source, content: .dub, mode: .fullShow,
            sharedProfile: model.configuration?.profile)
        return (model, source, request)
    }

    @MainActor private func save(_ request: JobRequest, in model: JobModel) throws -> JobRecord {
        var job = JobRecord(id: try request.stableID(), request: request)
        job.state = .failed
        job.source = SourceRecord(id: request.sourceID, owner: request.owner, title: request.title,
            originalURL: request.originalURL, path: model.root.appendingPathComponent("unavailable-synthetic-original.mp4").path,
            bytes: 1, sha256: String(repeating: "a", count: 64), duration: request.expectedDuration ?? 1800,
            width: 320, height: 180, fps: 30, hasAudio: false, kind: .nativeVideo, streams: [],
            authorizationBasis: "Synthetic", classificationEvidence: "Synthetic")
        try Persistence.save(job, to: model.root.appendingPathComponent("jobs/\(job.id)/job.json"))
        model.jobs.append(job)
        return job
    }

    @MainActor private func waitForIntake(_ model: JobModel) async throws {
        for _ in 0..<500 where model.preparingSource { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertFalse(model.preparingSource)
        await model.task?.value
    }

    @MainActor func testChangedProviderMetadataReusesSavedManualContractBeforeDiscovery() async throws {
        let (model, source, request) = try fixture()
        let prior = try save(request, in: model)
        var changed = source
        changed.title = "Changed provider title"
        changed.episodeDate = "2026-11-05"
        changed.duration = 1799
        var lookups = 0
        model.startLink("https://youtu.be/abcdefghijk", content: .dub, mode: .fullShow,
            archive: "", archiveRoot: "", transcript: "", lookup: { _ in lookups += 1; return changed })
        try await waitForIntake(model)
        XCTAssertEqual(lookups, 0)
        XCTAssertEqual(model.jobs.count, 1)
        XCTAssertEqual(model.selected, prior.id)
        XCTAssertEqual(try model.jobs.first?.request.identityData(), try request.identityData())
        XCTAssertFalse(model.jobs.contains { $0.clips.contains { $0.qa?.passed == true || $0.drive != nil } })
    }

    @MainActor func testAmbiguousSavedContractsStopBeforeLookupOrProcessing() async throws {
        let (model, _, request) = try fixture()
        _ = try save(request, in: model)
        var other = request
        other.title = "A second immutable title"
        _ = try save(other, in: model)
        var lookups = 0
        model.startLink("https://youtu.be/abcdefghijk", content: .dub, mode: .fullShow,
            archive: "", archiveRoot: "", transcript: "", lookup: { _ in
                lookups += 1
                throw JoeyError.dependency("Discovery must not start for ambiguity")
            })
        try await waitForIntake(model)
        XCTAssertEqual(lookups, 0)
        XCTAssertNil(model.task)
        XCTAssertNil(model.selected)
        XCTAssertTrue(model.error?.contains("Multiple existing source contracts") == true)
        XCTAssertEqual(model.jobs.count, 2)
    }

    @MainActor func testSavedContractIsFoundBeforeHistoryHasRefreshed() async throws {
        let (model, _, request) = try fixture()
        let prior = try save(request, in: model)
        model.jobs.removeAll()
        var lookups = 0
        model.startLink("https://youtu.be/abcdefghijk", content: .dub, mode: .fullShow,
            archive: "", archiveRoot: "", transcript: "", lookup: { _ in
                lookups += 1
                throw JoeyError.dependency("Saved inventory must be checked first")
            })
        try await waitForIntake(model)
        XCTAssertEqual(lookups, 0)
        XCTAssertEqual(model.selected, prior.id)
        XCTAssertEqual(model.jobs.map(\.id), [prior.id])
    }

    @MainActor func testDistinctSelectionsAndExplicitInputsDoNotAdoptAnotherContract() async throws {
        let (model, _, request) = try fixture()
        var selected = request
        selected.mode = .highlights
        selected.fixedIntervals = [Interval(0, 30)]
        selected.requestedCount = 1
        let prior = try save(selected, in: model)
        var lookups = 0
        model.startLink("https://youtu.be/abcdefghijk", content: .dub, mode: .highlights,
            archive: "", archiveRoot: "", transcript: "", lookup: { _ in
                lookups += 1
                throw JoeyError.dependency("Synthetic discovery boundary")
            })
        try await waitForIntake(model)
        XCTAssertEqual(lookups, 1)
        XCTAssertNil(model.task)
        XCTAssertEqual(model.jobs.map(\.id), [prior.id])

        model.jobs.removeAll()
        _ = try save(request, in: model)
        for (archive, root, transcript) in [("existing-source", "", ""), ("", "different-archive-root", ""), ("", "", "/explicit/transcript.json")] {
            model.startLink("https://youtu.be/abcdefghijk", content: .dub, mode: .fullShow,
                archive: archive, archiveRoot: root, transcript: transcript, lookup: { _ in
                    lookups += 1
                    throw JoeyError.dependency("Synthetic explicit-input boundary")
                })
            try await waitForIntake(model)
            XCTAssertNil(model.task)
        }
        XCTAssertEqual(lookups, 4)
    }

    @MainActor func testOmittedOptionalInputsPreserveSavedContractAndOwnerModeSeparation() throws {
        let (_, source, request) = try fixture()
        var prior = request
        prior.archiveReference = "https://drive.google.com/file/d/synthetic-original/view"
        prior.transcriptPath = "/synthetic/complete-transcript.json"
        let reused = try ProductionIntake.existingRequest(for: source.url, content: .dub, mode: .fullShow, requests: [prior])
        XCTAssertEqual(reused, prior)
        XCTAssertNil(try ProductionIntake.existingRequest(for: source.url, content: .taxstone, mode: .fullShow, requests: [prior]))
        XCTAssertNil(try ProductionIntake.existingRequest(for: source.url, content: .dub, mode: .highlights, requests: [prior]))
        XCTAssertNil(try ProductionIntake.existingRequest(for: source.url, content: .dub, mode: .fullShow,
            requests: [prior], transcript: "/different/transcript.json"))
    }

    @MainActor func testAutomaticallyRecognizedJoeReusesItsSeparateFullShowContract() throws {
        let (_, source, _) = try fixture()
        var official = source
        official.channelID = SourceDiscovery.joeChannelID
        official.episodeNumber = 976
        official.title = "Joe Budden Podcast Episode 976 | Synthetic"
        let prior = try ProductionIntake.request(source: official, content: .joeBudden, mode: .fullShow, sharedProfile: nil)
        let reused = try ProductionIntake.existingRequest(for: source.url, content: .dub,
            mode: .highlights, requests: [prior])
        XCTAssertEqual(reused, prior)
        XCTAssertEqual(reused?.productionWorkflow, .joeBudden)
        XCTAssertEqual(reused?.mode, .fullShow)
        XCTAssertNil(try ProductionIntake.existingRequest(for: source.url, content: .taxstone,
            mode: .fullShow, requests: [prior]))
    }
}
