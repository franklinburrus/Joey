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
    func testAllEightDestinationsUseOwnershipFormatAndAsset() throws {
        let combinations: [(Owner,MediaKind,Bool,DriveAsset,String)] = [
            (.dub,.audio,false,.clip,"1FRi-yy2D9yenjQRailTA2iAbPaqAEPXm"),
            (.dub,.nativeVideo,false,.clip,"1380CHJ3a3kl7fXNIKWqUM7_DeTZUwxsy"),
            (.taxstone,.audio,false,.clip,"1kxv3bbnPPRt914npHFUI51jrbCY0atyU"),
            (.dub,.nativeVideo,true,.clip,"1X5VNP6fo3VpZPu4ZW4p7Ggk2o_IAVGSI"),
            (.dub,.audio,false,.fullEpisode,"109_QzHpF0Bi-OG6-AxuTDw1uHG4zeop3"),
            (.dub,.nativeVideo,false,.fullEpisode,"1GpuGWGIbSt3afwsi9L782soT9WJKOHS9"),
            (.taxstone,.nativeVideo,false,.fullEpisode,"12g_etkCruq4tjG07t9hAqQffc4NqbSQK"),
            (.dub,.nativeVideo,true,.fullEpisode,"1IIYLVDhCvwf5ZoMb0aM5vpSCe-eMCmyK")]
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
            XCTAssertEqual(try DestinationResolver.resolve(source:source,request:request,asset:.clip).rootID,"1kxv3bbnPPRt914npHFUI51jrbCY0atyU")
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
}
