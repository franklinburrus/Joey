import XCTest
@testable import JoeyCore

/// URLProtocol and rclone boundaries are simulated. Every routing, integrity,
/// recovery and completion decision below runs the production Swift code.
final class DriveFilingTests: XCTestCase {
    private func setup() throws -> (URL, SourceRecord, JobRequest, FilingDestination, FilingProvider, DriveDelivery) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("joey-filing-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        addTeardownBlock {try? FileManager.default.removeItem(at:dir)}
        let file = dir.appendingPathComponent("01_clip.mp4")
        try Data("Synthetic accepted artifact; not real media".utf8).write(to:file)
        var (source,request) = try DestinationRoutingTests().fixture(kind:.nativeVideo)
        source.path = file.path;source.bytes = Int64(try Data(contentsOf:file).count);source.sha256 = try Integrity.sha256(file)
        request.localPath = file.path
        let destination = try DestinationResolver.resolve(source:source,request:request,asset:.clip)
        let fixture = FilingProvider(destination:destination)
        FilingProtocol.fixture = fixture
        let configuration = URLSessionConfiguration.ephemeral;configuration.protocolClasses = [FilingProtocol.self]
        let session = URLSession(configuration:configuration);addTeardownBlock {session.invalidateAndCancel()}
        let delivery = try DriveDelivery(remote:"fixture",session:session,runHelper:{_,args,_ in try fixture.command(args)})
        return (dir,source,request,destination,fixture,delivery)
    }
    func testUploadReusesExactBytesWithoutDuplicatesAndPreservesPermissions() async throws {
        let (dir,_,_,route,provider,delivery) = try setup(), file = dir.appendingPathComponent("01_clip.mp4")
        let first = try await delivery.upload(file,parent:FilingProvider.folder,destination:route)
        let second = try await delivery.upload(file,parent:FilingProvider.folder,destination:route)
        XCTAssertEqual(first.id,second.id);XCTAssertEqual(provider.writes,1)
        XCTAssertEqual(second.parent,FilingProvider.folder);XCTAssertEqual(second.destination,route)
        XCTAssertEqual(second.permissionFingerprint,try DriveDelivery.permissionFingerprint(["permissions":FilingProvider.permissions]))
        XCTAssertEqual(provider.permissionMutations,0)
    }
    func testInterruptedCommittedUploadReconcilesWithoutSecondWrite() async throws {
        let (dir,_,_,route,provider,delivery) = try setup()
        provider.loseResponse = true
        let result = try await delivery.upload(dir.appendingPathComponent("01_clip.mp4"),parent:FilingProvider.folder,destination:route)
        XCTAssertFalse(result.id.isEmpty);XCTAssertEqual(provider.writes,1)
    }
    func testWrongActualParentAndAncestryPreventAnyWrite() async throws {
        for wrongAncestor in [false,true] {
            let (dir,_,_,route,provider,delivery) = try setup()
            provider.wrongAncestor = wrongAncestor;provider.wrongFolderParent = !wrongAncestor
            do {_ = try await delivery.upload(dir.appendingPathComponent("01_clip.mp4"),parent:FilingProvider.folder,destination:route);XCTFail("Wrong placement accepted")}
            catch {XCTAssertTrue(error.localizedDescription.contains("parent") || error.localizedDescription.contains("ancestry"))}
            XCTAssertEqual(provider.writes,0)
        }
    }
    func testPostUploadParentHashSharingAndDuplicateFailuresCannotReturnReceipt() async throws {
        for fault in ["parent","hash","sharing","duplicate"] {
            let (dir,_,_,route,provider,delivery) = try setup();provider.fault = fault
            do {_ = try await delivery.upload(dir.appendingPathComponent("01_clip.mp4"),parent:FilingProvider.folder,destination:route);XCTFail("Accepted fault: "+fault)}
            catch {XCTAssertTrue(error.localizedDescription.contains("readback") || error.localizedDescription.contains("Duplicate"),error.localizedDescription)}
            XCTAssertEqual(provider.writes,1)
        }
    }
    func testCompanionIsPlacedBesideClipsAndDownloadedForByteReadback() async throws {
        let (dir,_,_,route,provider,delivery) = try setup()
        let file = dir.appendingPathComponent("RECONCILE.md");try Data("# Synthetic reconciliation\n".utf8).write(to:file)
        let result = try await delivery.upload(file,parent:FilingProvider.folder,destination:route,replaceCompanion:true)
        XCTAssertEqual(result.parent,FilingProvider.folder);XCTAssertEqual(provider.downloads,1)
        provider.corruptDownload = true
        do {_ = try await delivery.upload(file,parent:FilingProvider.folder,destination:route,replaceCompanion:true);XCTFail("Corrupted companion accepted")}
        catch {XCTAssertTrue(error.localizedDescription.contains("Downloaded companion"))}
        XCTAssertEqual(provider.writes,1)
    }
    func testChangedExistingMediaIsPreservedWithoutOverwrite() async throws {
        let (dir,_,_,route,provider,delivery) = try setup(), file = dir.appendingPathComponent("01_clip.mp4")
        _ = try await delivery.upload(file,parent:FilingProvider.folder,destination:route)
        let before = provider.files
        try Data("Different local bytes".utf8).write(to:file)
        do {_ = try await delivery.upload(file,parent:FilingProvider.folder,destination:route);XCTFail("Existing media overwritten")}
        catch {XCTAssertTrue(error.localizedDescription.contains("different bytes"))}
        XCTAssertEqual(provider.writes,1);XCTAssertEqual(provider.files,before)
    }
    func testEquivalentMediaUnderAnotherNameIsNotDuplicated() async throws {
        let (dir,_,_,route,provider,delivery) = try setup(),file = dir.appendingPathComponent("01_clip.mp4")
        _ = try await delivery.upload(file,parent:FilingProvider.folder,destination:route)
        do {_ = try await delivery.upload(file,name:"renamed.mp4",parent:FilingProvider.folder,destination:route);XCTFail("Duplicate media uploaded under another name")}
        catch {XCTAssertTrue(error.localizedDescription.contains("Equivalent media"))}
        XCTAssertEqual(provider.writes,1)
    }

    func testNewArchiveUsesResolverAndExistingOriginalStaysInLegacyParent() async throws {
        let (_,source,request,_,provider,delivery) = try setup()
        let route = try DestinationResolver.resolve(source:source,request:request,asset:.fullEpisode)
        provider.destination = route
        _ = try await delivery.archive(source:source,request:request)
        XCTAssertEqual(provider.writtenParents,[route.rootID])
        let archive = try XCTUnwrap(provider.files.keys.first)
        var existing = source;existing.archiveReference = "https://drive.google.com/file/d/"+archive+"/view"
        provider.parents[archive] = "legacy_archive_parent"
        var oldRequest = request;oldRequest.archiveRootID = "obsolete-selection"
        let before = try Integrity.sha256(URL(fileURLWithPath:source.path))
        _ = try await delivery.archive(source:existing,request:oldRequest)
        XCTAssertEqual(provider.writes,1);XCTAssertEqual(provider.parents[archive],"legacy_archive_parent")
        XCTAssertEqual(try Integrity.sha256(URL(fileURLWithPath:source.path)),before)
    }
    func testExistingWronglyRoutedEpisodeStopsBeforeCreatingOrUploading() async throws {
        let (dir,source,request,_,provider,delivery) = try setup();provider.wrongFolderParent = true
        do {_ = try await delivery.episodeFolder(source:source,request:request,jobID:"job",existingFolderID:FilingProvider.folder,intentURL:dir.appendingPathComponent("intent.json"));XCTFail("Wrong legacy folder accepted")}
        catch {XCTAssertTrue(error.localizedDescription.contains("incorrectly routed"))}
        XCTAssertEqual(provider.writes,0)
    }
    func testJoeRegisterReconciliationDoesNotCallSheets() async throws {
        let (_,_,_,_,provider,delivery) = try setup()
        let (_,request) = try DestinationRoutingTests().fixture(joe:true)
        let rows = try await delivery.reconcileRegister(job:JobRecord(id:"joe",request:request),tab:"DUB")
        XCTAssertEqual(rows,[]);XCTAssertEqual(provider.requests,0)
    }
}

private final class FilingProvider: @unchecked Sendable {
    static let folder = "synthetic_episode_folder"
    static let permissions: [[String:Any]] = [["id":"owner","type":"user","role":"owner"],["id":"anyone","type":"anyone","role":"reader","allowFileDiscovery":false]]
    let lock = NSRecursiveLock()
    var destination: FilingDestination
    var files: [String:Data] = [:], names: [String:String] = [:], parents: [String:String] = [:]
    var writes = 0,downloads = 0,requests = 0,permissionMutations = 0
    var writtenParents: [String] = []
    var fault = "",loseResponse = false,wrongAncestor = false,wrongFolderParent = false,corruptDownload = false
    init(destination: FilingDestination) {self.destination = destination}
    func command(_ args: [String]) throws -> ProcessResult {
        lock.lock();defer {lock.unlock()}
        if args.first == "config" {
            return ProcessResult(stdout:try JSONSerialization.data(withJSONObject:["fixture":["type":"drive","token":"{\"access_token\":\"dummy-only\"}"]]),stderr:"",status:0)
        }
        if args.first == "lsjson" {return ProcessResult(stdout:Data("[]".utf8),stderr:"",status:0)}
        guard args.first == "copyto",let parentIndex = args.firstIndex(of:"--drive-root-folder-id") else {throw JoeyError.failed("Unexpected test mutation")}
        let parent = args[parentIndex+1]
        if args[1].hasPrefix("fixture:") {
            downloads += 1;let name = String(args[1].dropFirst(8))
            guard let id = names.first(where:{$0.value == name && parents[$0.key] == parent})?.key else {throw JoeyError.failed("Fixture download absent")}
            try (corruptDownload ? Data("corrupted".utf8) : files[id]!).write(to:URL(fileURLWithPath:args[2]))
        } else {
            writes += 1;writtenParents.append(parent)
            let name = String(args[2].dropFirst(8)),id = "synthetic_file_"+Integrity.textHash(name)
            files[id] = try Data(contentsOf:URL(fileURLWithPath:args[1]));names[id] = name;parents[id] = parent
            if loseResponse {throw JoeyError.failed("Synthetic connection lost after provider committed")}
        }
        return ProcessResult(stdout:Data(),stderr:"",status:0)
    }
    func file(_ id: String) throws -> [String:Any] {
        let data = files[id]!, temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try data.write(to:temporary);defer {try? FileManager.default.removeItem(at:temporary)}
        return ["id":id,"name":names[id]!,"parents":[fault == "parent" ? "wrong-parent":parents[id]!],"trashed":false,
            "mimeType":"application/octet-stream","size":String(data.count),"md5Checksum":fault == "hash" ? "bad":try Integrity.md5(temporary),
            "sha256Checksum":try Integrity.sha256(temporary),"webViewLink":"https://drive.google.com/file/d/"+id+"/view",
            "permissions":fault == "sharing" ? [["id":"anyone","type":"anyone","role":"writer"]] : Self.permissions]
    }
    func response(_ request: URLRequest) throws -> Data {
        lock.lock();defer {lock.unlock()};requests += 1
        guard request.httpMethod == "GET" else {permissionMutations += 1;throw JoeyError.failed("Unexpected provider mutation")}
        let url = request.url!,id = url.lastPathComponent
        let chain = [destination.rootID]+destination.destination.ancestorIDs
        var object: [String:Any]
        if id == "files" {
            let q = URLComponents(url:url,resolvingAgainstBaseURL:false)!.queryItems!.first(where:{$0.name == "q"})!.value!
            let parent = q.split(separator:"'").first.map(String.init) ?? ""
            var matches = try files.keys.filter {parents[$0] == parent}.map {try file($0)}
            // Listings remain correct for hash/parent/sharing faults; independent
            // metadata readback must detect those after the committed mutation.
            for i in matches.indices {
                let fileID = matches[i]["id"] as! String
                let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try files[fileID]!.write(to:temporary);defer {try? FileManager.default.removeItem(at:temporary)}
                matches[i]["md5Checksum"] = try Integrity.md5(temporary)
            }
            if fault == "duplicate",let first = matches.first {var extra = first;extra["id"] = "duplicate-provider-id";matches.append(extra)}
            object = ["files":matches]
        } else if chain.contains(id) {
            let index = chain.firstIndex(of:id)!
            object = ["id":id,"name":destination.destination.name,"mimeType":"application/vnd.google-apps.folder","trashed":false,
                "parents":index+1 < chain.count ? [wrongAncestor ? "unexpected-ancestor":chain[index+1]] : [],"permissions":Self.permissions,
                "capabilities":["canAddChildren":true]]
        } else if id == Self.folder {
            object = ["id":id,"name":"Episode","mimeType":"application/vnd.google-apps.folder","trashed":false,
                "parents":[wrongFolderParent ? "retired-root":destination.rootID],"permissions":Self.permissions,
                "appProperties":["joeySourceID":destination.sourceID,"joeyOwner":destination.storedOwner]]
        } else if files[id] != nil {object = try file(id)}
        else {throw JoeyError.failed("Unexpected provider identity: "+id)}
        return try JSONSerialization.data(withJSONObject:object)
    }
}
private final class FilingProtocol: URLProtocol {
    static var fixture: FilingProvider!
    override class func canInit(with request: URLRequest) -> Bool {true}
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {request}
    override func startLoading() {
        do {
            let data = try Self.fixture.response(request)
            client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!,cacheStoragePolicy:.notAllowed)
            client?.urlProtocol(self,didLoad:data);client?.urlProtocolDidFinishLoading(self)
        } catch {client?.urlProtocol(self,didFailWithError:error)}
    }
    override func stopLoading() {}
}
