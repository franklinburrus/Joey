import XCTest
@testable import JoeyCore

/// Opt-in local acceptance. Inputs/media and resulting evidence stay outside Git.
/// Fixture account limits exercise rendering, never establish account eligibility.
final class RealMediaTests: XCTestCase {
    func testAuthorizedRealMediaRenderers() async throws {
        guard let path = ProcessInfo.processInfo.environment["JOEY_REAL_MEDIA_INPUTS"] else {
            throw XCTSkip("Local real-media inputs not supplied; generated tests do not establish real acceptance")
        }
        let inputURL = URL(fileURLWithPath:path)
        let fixtures = try JSONSerialization.jsonObject(with:Data(contentsOf:inputURL)) as! [[String:Any]]
        for (index,fixture) in fixtures.enumerated() {
            let dir = inputURL.deletingLastPathComponent().appendingPathComponent("case-\(index+1)")
            try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
            let sourceURL = URL(fileURLWithPath:fixture["path"] as! String)
            if let hash = fixture["sha256"] as? String {XCTAssertEqual(try Integrity.sha256(sourceURL),hash)}
            let profile = try Fixtures.profile(dir:dir)
            let owner = Owner(rawValue:fixture["owner"] as! String)!
            var request = try Fixtures.request(dir:dir,path:sourceURL.path)
            request.owner = owner; request.sourceID = fixture["sourceID"] as! String
            request.title = fixture["title"] as! String; request.originalURL = fixture["originalURL"] as? String
            request.authorizationBasis = "Frank consolidated requirements section 18: use authorized existing media for real acceptance; historical source/art receipts checked"
            let sourceFile = dir.appendingPathComponent("source.json")
            let source: SourceRecord
            if let previous: SourceRecord = try? Persistence.load(sourceFile), previous.sha256 == (try Integrity.sha256(sourceURL)) {source = previous}
            else {source = try await Media.inspect(sourceURL,request:request);try Persistence.save(source,to:sourceFile)}
            XCTAssertEqual(source.kind.rawValue,fixture["kind"] as? String)
            var artwork: Artwork?
            if let art = fixture["artwork"] as? String {
                artwork = Artwork(owner:owner,sourceID:owner == .taxstone ? source.id:nil,driveID:fixture["artworkID"] as! String,
                    file:EvidenceFile(path:art,sha256:fixture["artworkSHA256"] as! String,basis:"Approved real source artwork; historical identity independently inspected"))
            }
            let clip = ClipRecord(id:1,title:request.title,intervals:[Interval(fixture["start"] as! Double,fixture["end"] as! Double)],filename:"real-\(owner.rawValue)-\(source.kind.rawValue).mp4")
            let output = dir.appendingPathComponent(clip.filename)
            let render: RenderReceipt
            let renderURL = dir.appendingPathComponent("render.json")
            if FileManager.default.fileExists(atPath:output.path), let saved: RenderReceipt = try? Persistence.load(renderURL) {
                // This opt-in run uses the same immutable external input list.
                // Reuse the known rendered bytes while repairing QA itself.
                render = saved
            } else {render = try await Media.render(source:source,clip:clip,profile:profile,artwork:artwork,work:dir,output:output)}
            let qa = try await Media.validate(output:output,source:source,clip:clip,profile:profile,render:render,work:dir)
            XCTAssertTrue(qa.passed)
            try Persistence.save(qa,to:dir.appendingPathComponent("qa.json"))
            try Persistence.save(["scope":"Real-media local renderer validation only","productionJobCompleted":"false",
                "platformAccountEligibility":"unverified; synthetic fixture limits used only for isolated renderer tests",
                "driveDelivery":"not attempted","output":output.path,"sourceSHA256":source.sha256,
                "outputSHA256":qa.outputSHA256],to:dir.appendingPathComponent("acceptance.json"))
        }
    }
}
