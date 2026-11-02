import XCTest
@testable import JoeyCore

/// Explicit, read-only local acceptance. Never enabled in cloud/normal tests.
final class LiveDriveRoutingTests: XCTestCase {
    func testAuthorizedLiveRootsAndExistingPackagePlacement() async throws {
        guard let input = ProcessInfo.processInfo.environment["JOEY_REAL_MEDIA_INPUTS"],
              let object = try? JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:input))) as? [String:String],
              object["purpose"] == "routing-readback",let runtime = object["runtime"],let output = object["output"] else {
            throw XCTSkip("Requires explicit local routing-readback input; no production delivery is simulated")
        }
        let config: Configuration = try Persistence.load(URL(fileURLWithPath:runtime).appendingPathComponent("settings.json"))
        let provider = try DriveDelivery(remote:config.rcloneRemote,runHelper:{executable,args,limit in
            // Only rclone OAuth refresh/list and in-memory config access are
            // permitted. No copy, mkdir, removal, relocation or sharing writes.
            guard executable == "rclone",["lsjson","config"].contains(args.first ?? "") else {throw JoeyError.failed("Read-only acceptance blocked a mutation")}
            return try await Processes.run(executable,args,maxOutput:limit)
        })
        var roots: [[String:Any]] = []
        var rootChildren: [String:[[String:Any]]] = [:]
        for destination in DriveDestination.active {
            let metadata = try await provider.verifyRoot(destination)
            rootChildren[destination.id] = try await provider.children(destination.id)
            roots.append(["id":destination.id,"name":destination.name,"ancestors":destination.ancestorIDs,
                "permissionFingerprint":try DriveDelivery.permissionFingerprint(metadata),
                "canAddChildren":(metadata["capabilities"] as? [String:Any])?["canAddChildren"] ?? false])
        }
        let runtimeURL = URL(fileURLWithPath:runtime)
        let checkpoints = try FileManager.default.contentsOfDirectory(at:runtimeURL.appendingPathComponent("jobs"),includingPropertiesForKeys:nil)
        var packages: [[String:Any]] = []
        for directory in checkpoints.sorted(by:{$0.path < $1.path}) {
            guard let job = try? Persistence.load(directory.appendingPathComponent("job.json")) as JobRecord,
                  let folder = job.folderID,let source = job.source else {continue}
            let route = try DestinationResolver.resolve(source:source,request:job.request,asset:.clip)
            let metadata = try await provider.metadata(folder)
            let actualParents = metadata["parents"] as? [String] ?? []
            let contents = try await provider.children(folder)
            let duplicateNames = Dictionary(grouping:contents,by:{$0["name"] as? String ?? ""})
                .filter {$0.value.count > 1}.map(\.key).sorted()
            let duplicateBytes = Dictionary(grouping:contents.filter {$0["md5Checksum"] != nil},by:{$0["md5Checksum"] as? String ?? ""})
                .filter {$0.value.count > 1}.map { $0.value.compactMap {$0["id"] as? String} }
            let destinationMatches = (rootChildren[route.rootID] ?? []).filter {
                let tags = $0["appProperties"] as? [String:String] ?? [:]
                return tags["joeySourceID"] == source.id || $0["name"] as? String == metadata["name"] as? String
            }.compactMap {$0["id"] as? String}
            var failure: String?
            do {_ = try await provider.verifyLocation(parent:folder,destination:route)}
            catch {failure = error.localizedDescription}
            if actualParents != [route.rootID] {XCTAssertNotNil(failure,"Incorrect actual placement must be rejected")}
            var receipts: [[String:Any]] = []
            // Inspect every saved output/companion's provider identity and bytes.
            for receipt in job.clips.compactMap(\.drive)+Array(job.companions.values) {
                let current = try await provider.metadata(receipt.id)
                let same = current["id"] as? String == receipt.id && current["name"] as? String == receipt.name &&
                    current["parents"] as? [String] == [folder] && current["trashed"] as? Bool == false &&
                    current["md5Checksum"] as? String == receipt.md5 && Int64(current["size"] as? String ?? "") == receipt.bytes
                receipts.append(["id":receipt.id,"matchesSavedFileReceipt":same])
                XCTAssertTrue(same,"Historical file changed: \(receipt.id)")
            }
            packages.append(["jobID":job.id,"sourceID":source.id,"owner":route.owner.rawValue,"folderID":folder,
                "expectedRoot":route.rootID,"actualParents":actualParents,"clips":job.clips.count,
                "permissionFingerprint":try DriveDelivery.permissionFingerprint(metadata),
                "duplicateNames":duplicateNames,"duplicateBytes":duplicateBytes,"destinationMatches":destinationMatches,
                "filingRejection":failure ?? "none","receipts":receipts])
        }
        let result: [String:Any] = ["scope":"LIVE READ-ONLY; no production upload or relocation","checkedAt":ISO8601DateFormatter().string(from:Date()),
            "roots":roots,"packages":packages]
        try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:output),options:.atomic)
        XCTAssertEqual(roots.count,8)
    }
}
