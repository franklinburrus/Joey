import XCTest
@testable import JoeyCore

final class AcquisitionResumeTests: XCTestCase {
    private struct Fixture {
        var root: URL
        var original: URL
        var request: JobRequest
    }

    private func fixture(providerDuration: Double? = nil) async throws -> Fixture {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:temporary,withIntermediateDirectories:true)
        let root = try StorageManager.canonicalRoot(temporary)
        addTeardownBlock {try? FileManager.default.removeItem(at:root)}
        let original = root.appendingPathComponent("original.mp4")
        _ = try await Processes.run("ffmpeg",["-v","error","-f","lavfi","-i","testsrc2=s=128x72:r=30:d=4",
            "-c:v","libx264","-threads","1","-an",original.path])
        var request = try Fixtures.request(dir:root,path:original.path)
        request.localPath = nil
        request.originalURL = "https://x.com/i/broadcasts/syntheticResume123"
        request.sourceID = "x:broadcast:syntheticResume123"
        request.expectedDuration = 4
        let metadata: [String:Any] = ["id":"syntheticResume123","title":"Synthetic completed original",
            "original_url":request.originalURL!,"webpage_url":request.originalURL!,
            "duration":providerDuration.map {$0 as Any} ?? NSNull(),"is_live":false,"live_status":"was_live"]
        let data = try JSONSerialization.data(withJSONObject:metadata)
        try data.write(to:root.appendingPathComponent("acquisition.json"))
        try data.write(to:root.appendingPathComponent("original.info.json"))
        return Fixture(root:root,original:original,request:request)
    }

    private func changeMetadata(_ f: Fixture, name: String = "original.info.json", changes: [String:Any]) throws {
        let path = f.root.appendingPathComponent(name)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:path)) as? [String:Any])
        object.merge(changes) {_,new in new}
        try JSONSerialization.data(withJSONObject:object).write(to:path)
    }

    private func expectFailure(_ f: Fixture, containing text: String) async throws {
        let before = try Integrity.sha256(f.original)
        do {
            _ = try await Acquisition.acquire(f.request,directory:f.root)
            XCTFail("Conflicting completed original was reused")
        } catch {
            XCTAssertTrue(error.localizedDescription.localizedCaseInsensitiveContains(text),error.localizedDescription)
        }
        XCTAssertEqual(try Integrity.sha256(f.original),before,"Existing original must remain unchanged")
    }

    func testCompletedOriginalReusesBeforeDownloadCapacityOrNetwork() async throws {
        let f = try await fixture()
        let protected = [f.original,f.root.appendingPathComponent("acquisition.json"),f.root.appendingPathComponent("original.info.json")]
        let hashes = try protected.map {try Integrity.sha256($0)}
        let result = try await StorageManager.$capacityOverride.withValue({0}) {
            try await Acquisition.acquire(f.request,directory:f.root)
        }
        XCTAssertEqual(result,f.original)
        XCTAssertEqual(try protected.map {try Integrity.sha256($0)},hashes)
    }

    func testMissingExpectedDurationUsesConcreteRetainedProviderDuration() async throws {
        var f = try await fixture(providerDuration:4)
        f.request.expectedDuration = nil
        let result = try await StorageManager.$capacityOverride.withValue({0}) {
            try await Acquisition.acquire(f.request,directory:f.root)
        }
        XCTAssertEqual(result,f.original)
    }

    func testMissingAllExpectedDurationsDoesNotTrustMeasuredLength() async throws {
        var f = try await fixture()
        f.request.expectedDuration = nil
        try await expectFailure(f,containing:"duration")
    }

    func testConflictingProviderIdentityPreservesOriginal() async throws {
        let f = try await fixture()
        try changeMetadata(f,changes:["id":"differentSource"])
        try await expectFailure(f,containing:"identity")
    }

    func testConflictingRetainedURLPreservesOriginal() async throws {
        let f = try await fixture()
        try changeMetadata(f,name:"acquisition.json",changes:["webpage_url":"https://x.com/i/broadcasts/differentSource"])
        try await expectFailure(f,containing:"URL")
    }

    func testExpectedAndProviderDurationsRemainIndependentRequirements() async throws {
        var f = try await fixture(providerDuration:4)
        f.request.expectedDuration = 8
        try await expectFailure(f,containing:"Incomplete original")
        f.request.expectedDuration = 4
        try changeMetadata(f,changes:["duration":8])
        try await expectFailure(f,containing:"Incomplete original")
    }

    func testMissingOrMalformedProvenancePreservesOriginal() async throws {
        let f = try await fixture()
        let metadata = f.root.appendingPathComponent("original.info.json")
        try FileManager.default.removeItem(at:metadata)
        try await expectFailure(f,containing:"metadata")
        try Data("invalid JSON".utf8).write(to:metadata)
        try await expectFailure(f,containing:"metadata")
    }

    func testAmbiguousCanonicalOriginalsArePreserved() async throws {
        let f = try await fixture()
        let second = f.root.appendingPathComponent("original.mkv")
        try FileManager.default.copyItem(at:f.original,to:second)
        let hash = try Integrity.sha256(second)
        try await expectFailure(f,containing:"multiple")
        XCTAssertEqual(try Integrity.sha256(second),hash)
    }

    func testSymbolicLinkCannotQualifyAsOwnedCompletedOriginal() async throws {
        let f = try await fixture()
        let target = f.root.appendingPathComponent("preserved.mp4")
        try FileManager.default.moveItem(at:f.original,to:target)
        try FileManager.default.createSymbolicLink(at:f.original,withDestinationURL:target)
        try await expectFailure(f,containing:"symbolic link")
    }

    func testInvalidCompletedOriginalIsNotReplaced() async throws {
        let f = try await fixture()
        try Data("Invalid original; preserve these bytes".utf8).write(to:f.original)
        try await expectFailure(f,containing:"preserved")
    }

    func testInterruptedMPEGTSRemuxCannotQualifyAsCompletedMP4() async throws {
        let f = try await fixture()
        let interrupted = f.root.appendingPathComponent("interrupted.ts")
        _ = try await Processes.run("ffmpeg",["-v","error","-i",f.original.path,"-c","copy","-f","mpegts",interrupted.path])
        try FileManager.default.removeItem(at:f.original)
        try FileManager.default.moveItem(at:interrupted,to:f.original)
        try await expectFailure(f,containing:"unfinished MPEG-TS remux")
    }

    func testPartialOnlyOriginalRetainsDownloaderResumePath() async throws {
        let f = try await fixture()
        let partial = f.root.appendingPathComponent("original.mp4.part")
        try FileManager.default.moveItem(at:f.original,to:partial)
        let hash = try Integrity.sha256(partial)
        let completed = try await Acquisition.completedOriginal(f.request,directory:f.root)
        XCTAssertNil(completed)
        XCTAssertEqual(try Integrity.sha256(partial),hash)
        let arguments = Acquisition.downloadArguments(for:URL(string:f.request.originalURL!)!,directory:f.root)
        XCTAssertTrue(arguments.contains("--continue"))
        XCTAssertTrue(arguments.contains("--no-overwrites"))
    }
}
