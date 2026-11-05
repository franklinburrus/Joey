import XCTest
@testable import JoeyCore

final class DubExistingDeliveryTests: XCTestCase {
    func testExistingExternalPackageAlsoStopsAResumedSourceBeforeRendering() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let request = try DubBroadcastDiscovery.request(DubBroadcastTests().broadcast())
        var saved = JobRecord(id:try request.stableID(),request:request)
        saved.source = SourceRecord(id:request.sourceID,owner:.dub,title:request.title,episodeDate:request.episodeDate,
            originalURL:request.originalURL,path:"unavailable-original",bytes:1,sha256:String(repeating:"a",count:64),duration:3600,
            width:128,height:72,fps:30,hasAudio:true,kind:.nativeVideo,streams:[],authorizationBasis:"Synthetic",classificationEvidence:"Synthetic")
        try Persistence.save(saved,to:root.appendingPathComponent("jobs/\(saved.id)/job.json"))
        let result = try await Coordinator.$deliveryOverride.withValue(DubExistingPackageProvider()) {
            try await Coordinator(root:root).run(request)
        }
        XCTAssertTrue(result.error?.contains("existing-package") == true)
        XCTAssertTrue(result.clips.isEmpty)
        XCTAssertEqual(result.source,saved.source)
    }
    func testMutableProviderTitleCannotCreateSecondNativeSourceJob() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        var request = try DubBroadcastDiscovery.request(DubBroadcastTests().broadcast())
        var job = JobRecord(id:try request.stableID(),request:request);job.state = .cancelled
        try Persistence.save(job,to:root.appendingPathComponent("jobs/\(job.id)/job.json"))
        request.title = "Changed provider title"
        let coordinator = try Coordinator(root:root)
        do {
            _ = try await Coordinator.$deliveryOverride.withValue(DubExistingPackageProvider()) {try await coordinator.run(request)}
            XCTFail("A changed provider title admitted a second native source job")
        } catch {XCTAssertTrue(error.localizedDescription.contains(job.id))}
        let jobs = try await coordinator.jobs()
        XCTAssertEqual(jobs.count,1)
    }
    func testExistingExternalPackageStopsBeforeSourceAcquisitionOrRendering() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let request = try DubBroadcastDiscovery.request(DubBroadcastTests().broadcast())
        let result = try await Coordinator.$deliveryOverride.withValue(DubExistingPackageProvider()) {
            try await Coordinator(root:root).run(request)
        }
        XCTAssertEqual(result.state,.failed)
        XCTAssertTrue(result.error?.contains("existing-package") == true)
        XCTAssertNil(result.source)
        XCTAssertTrue(result.clips.isEmpty)
    }
}

private actor DubExistingPackageProvider: CoordinatorDelivery {
    func dubPackage(sourceID: String) async throws -> String? {"existing-package"}
    func metadata(_ id: String) async throws -> [String:Any] {throw JoeyError.failed("Unexpected metadata")}
    func downloadOriginal(reference: String, directory: URL) async throws -> URL {throw JoeyError.failed("Unexpected acquisition")}
    func archive(source: SourceRecord, request: JobRequest) async throws -> String {throw JoeyError.failed("Unexpected archive")}
    func episodeFolder(source: SourceRecord, request: JobRequest, jobID: String, existingFolderID: String?, intentURL: URL) async throws -> String {throw JoeyError.failed("Unexpected folder")}
    func upload(_ local: URL, name: String?, parent: String, destination: FilingDestination, replaceCompanion: Bool) async throws -> DriveReceipt {throw JoeyError.failed("Unexpected upload")}
    func resolveArtwork(source: SourceRecord, configuration: Configuration, root: URL) async throws -> Artwork {throw JoeyError.failed("Unexpected artwork")}
    func reconcileRegister(job: JobRecord, tab: String) async throws -> [String] {throw JoeyError.failed("Unexpected register")}
    func verifyPackage(job: JobRecord, directory: URL) async throws {throw JoeyError.failed("Unexpected verification")}
}
