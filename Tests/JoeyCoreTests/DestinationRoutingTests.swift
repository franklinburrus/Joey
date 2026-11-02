import XCTest
@testable import JoeyCore

final class DestinationRoutingTests: XCTestCase {
    func fixture(owner: Owner = .dub, kind: MediaKind = .audio, joe: Bool = false) throws -> (SourceRecord, JobRequest) {
        var request = try Fixtures.request(dir:FileManager.default.temporaryDirectory,path:"source.mp4")
        request.owner = owner;request.sourceID = joe ? "youtube:abcdefghijk" : "identified-source"
        if joe {request.productionWorkflow = .joeBudden;request.originalURL = "https://www.youtube.com/watch?v=abcdefghijk"}
        let source = SourceRecord(id:request.sourceID,owner:owner,title:request.title,originalURL:request.originalURL,
            path:"source.mp4",bytes:100,sha256:String(repeating:"a",count:64),duration:10,width:1920,height:1080,fps:30,
            hasAudio:true,kind:kind,streams:[],authorizationBasis:"Synthetic",classificationEvidence:"Inspected synthetic source")
        return (source,request)
    }
    func testActiveDestinationsUseOwnershipFormatAndAsset() throws {
        let combinations: [(Owner,MediaKind,Bool,DriveAsset,String)] = [
            (.dub,.audio,false,.clip,"1FRi-yy2D9yenjQRailTA2iAbPaqAEPXm"),
            (.dub,.nativeVideo,false,.clip,"1380CHJ3a3kl7fXNIKWqUM7_DeTZUwxsy"),
            (.taxstone,.audio,false,.clip,"1bpHEdKPXQjjtoKp-L13KdITOT8Ep7JH8"),
            (.dub,.nativeVideo,true,.clip,"1X5VNP6fo3VpZPu4ZW4p7Ggk2o_IAVGSI"),
            (.dub,.audio,false,.fullEpisode,"109_QzHpF0Bi-OG6-AxuTDw1uHG4zeop3"),
            (.dub,.nativeVideo,false,.fullEpisode,"1GpuGWGIbSt3afwsi9L782soT9WJKOHS9"),
            (.taxstone,.nativeVideo,false,.fullEpisode,"1wQMwzUconRC3UCvH2jpL1kD__ctBv29p"),
            (.dub,.nativeVideo,true,.fullEpisode,"1KJ0-sjGWNxwIuis_faA5z_FbPUcbjEDD")]
        for (owner,kind,joe,asset,expected) in combinations {
            let (source,request) = try fixture(owner:owner,kind:kind,joe:joe)
            let route = try DestinationResolver.resolve(source:source,request:request,asset:asset)
            XCTAssertEqual(route.rootID,expected)
            XCTAssertEqual(route.sourceID,source.id)
            XCTAssertEqual(route.sourceSHA256,source.sha256)
            XCTAssertEqual(route.destination.ancestorIDs.last,DestinationResolver.dubRoot)
        }
    }
    func testMissingConflictingOrUnverifiedIdentityStopsRouting() throws {
        let (source,request) = try fixture()
        var variants: [SourceRecord] = []
        var bad = source;bad.id = " ";variants.append(bad)
        bad = source;bad.id = "another-source";variants.append(bad)
        bad = source;bad.owner = .taxstone;variants.append(bad)
        bad = source;bad.sha256 = "unknown";variants.append(bad)
        bad = source;bad.classificationEvidence = "";variants.append(bad)
        for bad in variants {XCTAssertThrowsError(try DestinationResolver.resolve(source:bad,request:request,asset:.clip))}
        var wrong = request;wrong.productionWorkflow = .joeBudden
        XCTAssertThrowsError(try DestinationResolver.resolve(source:source,request:wrong,asset:.clip))
        wrong = request;wrong.archiveRootID = "1GpuGWGIbSt3afwsi9L782soT9WJKOHS9"
        XCTAssertThrowsError(try DestinationResolver.resolve(source:source,request:wrong,asset:.fullEpisode))
    }
    func testSourceKindOverridesMP4ExtensionAndTaxstoneKeepsOwnership() throws {
        for kind in [MediaKind.audio,.nativeVideo] {
            let (source,request) = try fixture(owner:.taxstone,kind:kind)
            XCTAssertEqual(try DestinationResolver.resolve(source:source,request:request,asset:.clip).rootID,"1bpHEdKPXQjjtoKp-L13KdITOT8Ep7JH8")
        }
        let (source,request) = try fixture()
        XCTAssertEqual(URL(fileURLWithPath:source.path).pathExtension,"mp4")
        XCTAssertEqual(try DestinationResolver.resolve(source:source,request:request,asset:.clip).rootID,"1FRi-yy2D9yenjQRailTA2iAbPaqAEPXm")
    }
    func testJoeDoesNotReconcileDUBRegister() throws {
        let (_,request) = try fixture(joe:true)
        XCTAssertFalse(DestinationResolver.requiresDUBRegister(request))
        var dub = request;dub.productionWorkflow = .link
        XCTAssertTrue(DestinationResolver.requiresDUBRegister(dub))
        dub.owner = .taxstone
        XCTAssertFalse(DestinationResolver.requiresDUBRegister(dub))
    }
    func testJoeArchiveRestorationPreservesSavedIdentityAndRejectsUnknownSelections() throws {
        let content = "18Ix3mVu8gCFSa-EGGpzQsh03SajrZvKm"
        XCTAssertEqual(DriveDestination.active.count,8)
        for destination in DriveDestination.active {
            XCTAssertEqual(destination.ancestorIDs.count,3)
            XCTAssertEqual(destination.ancestorIDs[1],content)
        }
        XCTAssertEqual(DriveDestination.taxstoneClips.ancestorIDs.first,"1kxv3bbnPPRt914npHFUI51jrbCY0atyU")
        XCTAssertEqual(DriveDestination.taxstoneEpisodes.name,"Taxstone Full Episodes")
        XCTAssertEqual(DriveDestination.joeBuddenClips.name,"Joe Budden Clips")
        let (source,request) = try fixture(joe:true)
        XCTAssertEqual(try DestinationResolver.resolve(source:source,request:request,asset:.fullEpisode).rootID,"1KJ0-sjGWNxwIuis_faA5z_FbPUcbjEDD")
        XCTAssertEqual(DriveDestination.joeBuddenEpisodes.name,"Joe Budden Full Episodes")
        XCTAssertEqual(DriveDestination.joeBuddenEpisodes.ancestorIDs.first,"1-HjL5kpENfWQm5jwshAhU3QM-THI6u53")
        var legacy = request;legacy.archiveRootID = "1IIYLVDhCvwf5ZoMb0aM5vpSCe-eMCmyK"
        XCTAssertEqual(try DestinationResolver.resolve(source:source,request:legacy,asset:.fullEpisode).rootID,"1KJ0-sjGWNxwIuis_faA5z_FbPUcbjEDD")
        XCTAssertEqual(try legacy.identityData(),try request.identityData())
        var current = request;current.archiveRootID = "1KJ0-sjGWNxwIuis_faA5z_FbPUcbjEDD"
        XCTAssertEqual(try current.identityData(),try request.identityData())
        var conflict = request;conflict.archiveRootID = "unapproved-destination"
        XCTAssertThrowsError(try DestinationResolver.resolve(source:source,request:conflict,asset:.fullEpisode))
        XCTAssertEqual(try JSONDecoder().decode(DriveDestination.self,from:Data("\"joeBuddenEpisodes\"".utf8)),.joeBuddenEpisodes)
    }
}
