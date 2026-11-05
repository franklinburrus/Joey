import XCTest
@testable import JoeyCore

/// Explicit local acceptance. No live writes are performed by this readback.
final class DubLiveAcceptanceTests: XCTestCase {
    func testAuthorizedReferenceAndDestinationReadback() async throws {
        guard let input = ProcessInfo.processInfo.environment["JOEY_REAL_MEDIA_INPUTS"],
              let object = try? JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:input))) as? [String:String],
              object["purpose"] == "dub-readback",let runtime = object["runtime"],let output = object["output"] else {
            throw XCTSkip("Requires explicit local dub-readback input")
        }
        let source = try await DubBroadcastDiscovery.lookup("https://x.com/i/broadcasts/2onbAgvyKWBPYg")
        let config: Configuration = try Persistence.load(URL(fileURLWithPath:runtime).appendingPathComponent("settings.json"))
        let provider = try DriveDelivery(remote:config.rcloneRemote)
        var results: [[String:Any]] = []
        for root in [DriveDestination.dubAudioClips,.dubVideoClips,.dubVideoEpisodes] {
            do {
                let value = try await provider.verifyRoot(root)
                results.append(["id":root.id,"name":value["name"] ?? "","parents":value["parents"] ?? [],"trashed":value["trashed"] ?? true])
            } catch {results.append(["id":root.id,"error":error.localizedDescription])}
        }
        let dir = URL(fileURLWithPath:output)
        try Persistence.save(source,to:dir.appendingPathComponent("reference.json"))
        try JSONSerialization.data(withJSONObject:results,options:[.prettyPrinted,.sortedKeys]).write(to:dir.appendingPathComponent("roots.json"))
        if let package = try await provider.dubPackage(sourceID:source.source.id) {
            let values = try await provider.children(package)
            let clipIDs = values.filter {($0["name"] as? String)?.hasSuffix(".mp4") == true}.compactMap {$0["id"] as? String}
            var verified: [[String:Any]] = []
            for id in clipIDs {
                let metadata = try await provider.metadata(id)
                XCTAssertEqual(metadata["parents"] as? [String],[package])
                verified.append(["id":id,"name":metadata["name"] ?? "","size":metadata["size"] ?? "",
                    "md5":metadata["md5Checksum"] ?? "","sha256":metadata["sha256Checksum"] ?? "",
                    "permissionFingerprint":try DriveDelivery.permissionFingerprint(metadata)])
            }
            let range = "'Master Library'!A1:AZ10000".addingPercentEncoding(withAllowedCharacters:.urlPathAllowed)!
            let register = try await provider.request("spreadsheets/"+DriveDelivery.masterSheet+"/values/"+range,sheets:true)
            let rows = register["values"] as? [[String]] ?? []
            let matching = rows.dropFirst().filter {$0.contains(source.source.id) || $0.contains(source.source.url)}
            try JSONSerialization.data(withJSONObject:["folderID":package,"clips":verified,"matchingRegisterRows":matching.count,
                "scope":"Existing external delivery metadata readback only; no new production or register write"],options:[.prettyPrinted,.sortedKeys])
                .write(to:dir.appendingPathComponent("existing-package-readback.json"))
        }
        XCTAssertEqual(source.broadcasterID,DubBroadcastDiscovery.broadcasterID)
        XCTAssertGreaterThan(source.source.duration,600)
    }
    @MainActor func testAuthorizedNativeWebsiteDiscovery() async throws {
        guard let input = ProcessInfo.processInfo.environment["JOEY_REAL_MEDIA_INPUTS"],
              let object = try? JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:input))) as? [String:String],
              object["purpose"] == "dub-discovery",let output = object["output"] else {
            throw XCTSkip("Requires explicit local dub-discovery input")
        }
        let scan = try await DubWebsiteDiscovery.scan()
        try Persistence.save(["urls":scan.urls,"status":[scan.status]],to:URL(fileURLWithPath:output).appendingPathComponent("native-discovery.json"))
        XCTAssertFalse(scan.urls.isEmpty)
        XCTAssertTrue(scan.urls.allSatisfy {$0.hasPrefix("https://x.com/i/broadcasts/")})
    }

    func testAuthorizedNativeMasterAudioRenderer() async throws {
        guard let input = ProcessInfo.processInfo.environment["JOEY_REAL_MEDIA_INPUTS"],
              let object = try? JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:input))) as? [String:String],
              object["purpose"] == "dub-native-audio-renderer",let previous = object["previous"],let output = object["output"] else {
            throw XCTSkip("Requires explicit existing real-DUB-audio readback input")
        }
        let directory = URL(fileURLWithPath:previous)
        let inputs = try JSONSerialization.jsonObject(with:Data(contentsOf:directory.appendingPathComponent("inputs.json"))) as! [[String:Any]]
        let fixture = inputs[0],existing = directory.appendingPathComponent("case-1")
        let source: SourceRecord = try Persistence.load(existing.appendingPathComponent("source.json"))
        XCTAssertEqual(source.owner,.dub);XCTAssertEqual(source.kind,.audio)
        XCTAssertEqual(try Integrity.sha256(URL(fileURLWithPath:source.path)),source.sha256)
        let clip = ClipRecord(id:1,title:fixture["title"] as! String,
            intervals:[Interval(fixture["start"] as! Double,fixture["end"] as! Double)],filename:"native-dub-audio.mp4")
        let work = URL(fileURLWithPath:output).appendingPathComponent("native-audio-qa")
        try FileManager.default.createDirectory(at:work,withIntermediateDirectories:true)
        let media = work.appendingPathComponent(clip.filename),receipt = work.appendingPathComponent("render.json")
        let artwork = Artwork(owner:.dub,driveID:fixture["artworkID"] as! String,
            file:EvidenceFile(path:fixture["artwork"] as! String,sha256:fixture["artworkSHA256"] as! String,basis:"Existing approved DUB artwork"))
        let render: RenderReceipt
        if FileManager.default.fileExists(atPath:media.path) {render = try Persistence.load(receipt)}
        else {
            render = try await Media.render(source:source,clip:clip,profile:.dubBroadcastMaster,artwork:artwork,work:work,output:media)
            try Persistence.save(render,to:receipt)
        }
        let qa = try await Media.validate(output:media,source:source,clip:clip,profile:.dubBroadcastMaster,render:render,work:work)
        XCTAssertTrue(qa.passed)
        try Persistence.save(qa,to:work.appendingPathComponent("qa.json"))
    }

}
