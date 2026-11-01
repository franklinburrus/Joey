import XCTest
@testable import JoeyCore

final class TaxstoneLibraryTests: XCTestCase {
    func testExactCoverageRejectsDuplicatesAndCountsOnlyMissingIntervals() throws {
        XCTAssertEqual(try TaxstoneLibrary.missing(duration:100,exclusions:[Interval(40,50)],accepted:[[Interval(0,40)],[Interval(50,70)]]),30)
        XCTAssertThrowsError(try TaxstoneLibrary.missing(duration:100,exclusions:[],accepted:[[Interval(0,50)],[Interval(40,70)]]))
        XCTAssertThrowsError(try TaxstoneLibrary.missing(duration:100,exclusions:[Interval(40,50)],accepted:[[Interval(30,60)]]))
    }
    func testLibraryStatePreservesPauseAndDeterministicQueueAfterRestart() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        var state = TaxstoneLibraryState();state.enabled = true
        let a = TaxstoneLibraryEpisode(id:"soundcloud:1",title:"Long",driveID:"drive1",sourceSHA256:"hash",duration:1000)
        let b = TaxstoneLibraryEpisode(id:"soundcloud:2",title:"Short",driveID:"drive2",sourceSHA256:"hash",duration:100)
        state.episodes = TaxstoneLibrary.ordered([a,b]);state.currentSourceID = b.id
        try Persistence.save(state,to:root.appendingPathComponent("taxstone-library.json"))
        let library = try TaxstoneLibrary(root:root)
        let initial = await library.snapshot()
        XCTAssertTrue(initial.enabled);XCTAssertEqual(initial.episodes.map(\.id),[b.id,a.id])
        try await library.pause()
        let restarted = try TaxstoneLibrary(root:root)
        let saved = await restarted.snapshot()
        XCTAssertFalse(saved.enabled);XCTAssertEqual(saved.currentSourceID,b.id)
        XCTAssertEqual(saved.remainingCount,2);XCTAssertEqual(saved.completedCount,0)
    }
    func testKnownIncompatibleLegacyIsNotConfusedWithUnknownMetadata() {
        var clip = TaxstoneLegacyClip(driveID:"legacy",intervals:[Interval(0,75)],fps:2,evidencePath:"qa")
        XCTAssertTrue(TaxstoneLibrary.knownIncompatible(clip))
        clip.fps = nil
        XCTAssertFalse(TaxstoneLibrary.knownIncompatible(clip))
        clip.width = 1920;clip.height = 1080
        XCTAssertTrue(TaxstoneLibrary.knownIncompatible(clip))
    }
    func testLegacyDuplicatesUseExactIntervalsAndProviderObjects() {
        let a = TaxstoneLegacyClip(driveID:"one",intervals:[Interval(1,2)],evidencePath:"receipt")
        var b = a;b.driveID = "two"
        XCTAssertEqual(TaxstoneLibrary.duplicateClips([a,a]),0)
        XCTAssertEqual(TaxstoneLibrary.duplicateClips([a,b]),1)
        b.intervals = [Interval(2,3)]
        XCTAssertEqual(TaxstoneLibrary.duplicateClips([a,b]),0)
    }
    func testOwnerProfilesRemainIndependentAndOldConfigurationDecodes() throws {
        let old = Data("{\"rcloneRemote\":\"dubdrive\",\"taxstoneArtwork\":{},\"registerTab\":\"Master Library\"}".utf8)
        let configuration = try Persistence.decoder.decode(Configuration.self,from:old)
        XCTAssertNil(configuration.taxstoneProfile)
    }
    func testPartialCheckpointReusesOnlyUnchangedAcceptedBytesAndNeverTrustsCompletedFlag() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        var request = try Fixtures.request(dir:root,path:"source")
        request.owner = .taxstone;request.fileToDrive = true
        let output = root.appendingPathComponent("accepted.mp4")
        try Data("synthetic accepted identity".utf8).write(to:output)
        let hash = try Integrity.sha256(output)
        var job = JobRecord(id:"partial",request:request)
        job.source = SourceRecord(id:request.sourceID,owner:.taxstone,title:"Fixture",path:"source",bytes:1,sha256:"source-hash",duration:100,width:0,height:0,fps:0,hasAudio:true,kind:.audio,streams:[],authorizationBasis:"fixture",classificationEvidence:"fixture")
        job.planningBasis = .transcriptAssisted
        job.clips = [ClipRecord(id:1,title:"First",intervals:[Interval(0,40)],filename:"accepted.mp4",sha256:hash,
            qa:QAReport(checkedAt:Date(),checks:[:],outputSHA256:hash,passed:true,limitations:["synthetic identity fixture"])),
            ClipRecord(id:2,title:"Remainder",intervals:[Interval(40,100)],filename:"missing.mp4")]
        var episode = TaxstoneLibraryEpisode(id:request.sourceID,title:"Fixture",driveID:"archive",sourceSHA256:"source-hash")
        try TaxstoneLibrary.reconcile(&episode,job:job,directory:root)
        XCTAssertEqual(episode.acceptedClips,1);XCTAssertEqual(episode.missingSeconds,60)
        job.state = .completed
        try TaxstoneLibrary.reconcile(&episode,job:job,directory:root)
        XCTAssertEqual(episode.status,"VERIFYING DELIVERY")
        try Data("changed".utf8).write(to:output)
        XCTAssertThrowsError(try TaxstoneLibrary.reconcile(&episode,job:job,directory:root))
    }
    func testLibraryContractRejectsUnboundOriginalAndWrongOwner() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        var request = try Fixtures.request(dir:root,path:"unused")
        request.owner = .taxstone;request.sourceID = "soundcloud:1";request.localPath = nil
        request.originalURL = "https://drive.google.com/file/d/123456789012345678901/view"
        request.archiveReference = request.originalURL;request.productionWorkflow = .taxstoneLibrary;request.fileToDrive = true
        XCTAssertThrowsError(try request.validate())
        request.expectedSourceSHA256 = String(repeating:"a",count:64)
        XCTAssertNoThrow(try request.validate())
        request.owner = .dub;XCTAssertThrowsError(try request.validate())
    }
}
