import XCTest
@testable import JoeyCore
@testable import JoeyInterface

final class JoeDiscoveryFailureTests: XCTestCase {
    private let dnsFailure = "yt-dlp exit 1: Failed to resolve 'www.youtube.com'\n[Errno 8] nodename nor servname provided, or not known"

    @MainActor
    private func waitForScan(_ model: JobModel) async throws {
        for _ in 0..<500 {
            if !model.scanningJoe { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Joe discovery did not finish")
    }

    @MainActor
    private func root() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("joey-joe-discovery-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    @MainActor
    private func queuedSource() -> DiscoveredSource {
        DiscoveredSource(id: "youtube:queued-fixture", title: "Queued fixture", url: "https://www.youtube.com/watch?v=queued-fixture", duration: 600,
                         channelID: SourceDiscovery.joeChannelID, episodeNumber: 977)
    }

    @MainActor
    func testDeniedPreviewKeepsCatalogAndQueueAcrossFailureAndRestart() async throws {
        let root = try root()
        var saved = JoeAutomationState()
        saved.queue = [queuedSource()]
        try Persistence.save(saved, to: root.appendingPathComponent("joe-automation.json"))
        let prior = DiscoveredSource(id: "youtube:prior-fixture", title: "Last successful episode", url: "https://www.youtube.com/watch?v=prior-fixture", duration: 600,
                                     channelID: SourceDiscovery.joeChannelID, episodeNumber: 976)
        let model = JobModel(root: root, startsAutomatically: false, networkDeniedPreview: true,
                             recentJoeEpisodes: { throw JoeyError.failed(self.dnsFailure) })
        model.joeAutomation = saved
        model.latestJoe = prior

        model.scanJoe()
        try await waitForScan(model)

        let message = "Episode check unavailable in this isolated preview; network access is intentionally denied."
        XCTAssertEqual(model.joeStatus, message)
        XCTAssertEqual(model.joeAutomation.lastCheckError, message)
        XCTAssertEqual(model.joeAutomation.lastCheckDiagnostic, dnsFailure)
        XCTAssertEqual(model.joeAutomation.lastError, nil)
        XCTAssertEqual(model.latestJoe, prior)
        XCTAssertEqual(model.joeAutomation.queue, saved.queue)
        XCTAssertFalse(model.joeStatus.contains("Failed to resolve"))
        XCTAssertFalse(model.joeStatus.contains("Episode check failed:"))

        let persisted: JoeAutomationState = try Persistence.load(root.appendingPathComponent("joe-automation.json"))
        XCTAssertEqual(persisted.queue, saved.queue)
        XCTAssertEqual(persisted.lastCheckError, message)
        XCTAssertEqual(persisted.lastCheckDiagnostic, dnsFailure)

        let reopened = JobModel(root: root, startsAutomatically: true, networkDeniedPreview: true,
                                recentJoeEpisodes: { throw JoeyError.failed(self.dnsFailure) })
        await reopened.startupTask?.value
        try await waitForScan(reopened)
        XCTAssertEqual(reopened.joeStatus, message)
        XCTAssertEqual(reopened.joeAutomation.queue, saved.queue)
        XCTAssertEqual(reopened.joeAutomation.lastCheckDiagnostic, dnsFailure)
        XCTAssertEqual(reopened.joeAutomation.lastError, nil)
        reopened.startupTask?.cancel()
    }

    @MainActor
    func testOrdinaryDiscoveryFailureUsesActionableMessageAndRetainsDiagnostic() async throws {
        let root = try root()
        var saved = JoeAutomationState()
        saved.queue = [queuedSource()]
        try Persistence.save(saved, to: root.appendingPathComponent("joe-automation.json"))
        let model = JobModel(root: root, startsAutomatically: false, networkDeniedPreview: false,
                             recentJoeEpisodes: { throw JoeyError.failed(self.dnsFailure) })
        model.joeAutomation = saved

        model.scanJoe()
        try await waitForScan(model)

        let message = "Episode check unavailable. Check network connection and retry."
        XCTAssertEqual(model.joeStatus, message)
        XCTAssertEqual(model.joeAutomation.lastCheckError, message)
        XCTAssertEqual(model.joeAutomation.lastCheckDiagnostic, dnsFailure)
        XCTAssertEqual(model.joeAutomation.queue, saved.queue)
        XCTAssertFalse(model.joeStatus.contains("Failed to resolve"))
        XCTAssertFalse(model.joeStatus.contains("Episode check failed:"))
    }
}
