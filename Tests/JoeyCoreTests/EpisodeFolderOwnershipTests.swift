import XCTest
@testable import JoeyCore

final class EpisodeFolderOwnershipTests: XCTestCase {
    private func workspace() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("joey-folder-owner-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        addTeardownBlock {try? FileManager.default.removeItem(at:directory)}
        return directory
    }
    private func source() -> SourceRecord {
        SourceRecord(id:"fixture-source",owner:.taxstone,title:"Fixture",path:"unused",bytes:1,sha256:String(repeating:"a",count:64),
            duration:10,width:160,height:90,fps:30,hasAudio:false,kind:.nativeVideo,streams:[],
            authorizationBasis:"Generated fixture",classificationEvidence:"Synthetic checkpoint")
    }
    private func request() throws -> JobRequest {
        var request = try Fixtures.request(dir:FileManager.default.temporaryDirectory,path:"unused")
        request.owner = .taxstone;request.sourceID = source().id;request.title = source().title
        return request
    }
    private func adapter(_ fixture: FolderProvider) throws -> DriveDelivery {
        FolderProtocol.fixture = fixture
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FolderProtocol.self]
        let session = URLSession(configuration:configuration)
        addTeardownBlock {session.invalidateAndCancel()}
        return try DriveDelivery(remote:"fixture",session:session,runHelper:{executable,arguments,_ in try fixture.command(executable,arguments)})
    }
    private func intent(in directory: URL, jobID: String) throws -> URL {
        let url = directory.appendingPathComponent("folder-intent.json")
        try Persistence.save(["root":DriveDestination.taxstoneClips.id,"name":FolderProvider.name,"jobID":jobID,
            "started":"2026-01-01T00:00:00Z"],to:url)
        return url
    }
    private func assertRejected(_ delivery: DriveDelivery, jobID: String, intent: URL) async {
        do {
            _ = try await delivery.episodeFolder(source:source(),request:request(),jobID:jobID,existingFolderID:nil,intentURL:intent)
            XCTFail("A folder without this job's verified ownership was accepted")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("job") || error.localizedDescription.contains("identity"),error.localizedDescription)
        }
    }

    func testSameJobRetriesReuseFolderWithoutMutation() async throws {
        let directory = try workspace(), fixture = FolderProvider(jobID:"same-job")
        fixture.properties["joeySourceSHA256"] = source().sha256
        let delivery = try adapter(fixture)
        for _ in 0..<2 {
            let id = try await delivery.episodeFolder(source:source(),request:request(),jobID:"same-job",existingFolderID:nil,intentURL:directory.appendingPathComponent("absent-intent.json"))
            XCTAssertEqual(id,FolderProvider.id)
        }
        XCTAssertEqual(fixture.mutations,0)
        XCTAssertEqual(fixture.mkdirCount,0)
    }

    func testDifferentPlanAndMissingJobOwnershipCannotReuseSourceFolder() async throws {
        let directory = try workspace()
        var full = try Fixtures.request(dir:directory,path:"unused");full.owner = .taxstone
        var highlights = full;highlights.mode = .highlights;highlights.fixedIntervals = [Interval(0,6)]
        let fullID = try full.stableID(), highlightsID = try highlights.stableID()
        XCTAssertNotEqual(fullID,highlightsID)
        for existingJob in [fullID,nil] as [String?] {
            let fixture = FolderProvider(jobID:existingJob), delivery = try adapter(fixture)
            await assertRejected(delivery,jobID:highlightsID,intent:directory.appendingPathComponent("absent-intent.json"))
            XCTAssertEqual(fixture.mutations,0)
            XCTAssertEqual(fixture.mkdirCount,0)
        }
    }

    func testMatchingCreationIntentRecoversEmptyUntaggedFolderAndRetry() async throws {
        let directory = try workspace(), fixture = FolderProvider(jobID:nil,untagged:true)
        let delivery = try adapter(fixture), savedIntent = try intent(in:directory,jobID:"recover-job")
        for _ in 0..<2 {
            let id = try await delivery.episodeFolder(source:source(),request:request(),jobID:"recover-job",existingFolderID:nil,intentURL:savedIntent)
            XCTAssertEqual(id,FolderProvider.id)
        }
        XCTAssertEqual(fixture.properties["joeyJobID"],"recover-job")
        XCTAssertEqual(fixture.properties["joeySourceID"],"fixture-source")
        XCTAssertEqual(fixture.mutations,1)
        XCTAssertEqual(fixture.mkdirCount,0)
    }

    func testCompatibleExistingManifestReusesFolderWithoutAnotherDirectory() async throws {
        let directory = try workspace(),fixture = FolderProvider(jobID:nil,untagged:true)
        let request = try request()
        var prior = JobRecord(id:"compatible-job",request:request);prior.source = source()
        fixture.manifest = try Persistence.encoder.encode(prior)
        let delivery = try adapter(fixture)
        let id = try await delivery.episodeFolder(source:source(),request:request,jobID:prior.id,existingFolderID:FolderProvider.id,
            intentURL:directory.appendingPathComponent("no-intent.json"))
        XCTAssertEqual(id,FolderProvider.id);XCTAssertEqual(fixture.mkdirCount,0)
        XCTAssertEqual(fixture.properties["joeySourceSHA256"],source().sha256)
        XCTAssertEqual(fixture.properties["joeyJobID"],prior.id)
    }

    func testExistingManifestWithDifferentSourceHashIsPreserved() async throws {
        let directory = try workspace(),fixture = FolderProvider(jobID:nil,untagged:true)
        var prior = JobRecord(id:"compatible-job",request:try request());prior.source = source()
        prior.source!.sha256 = String(repeating:"b",count:64)
        fixture.manifest = try Persistence.encoder.encode(prior)
        await assertRejected(try adapter(fixture),jobID:prior.id,intent:directory.appendingPathComponent("no-intent.json"))
        XCTAssertEqual(fixture.mutations,0);XCTAssertEqual(fixture.mkdirCount,0)
    }

    func testLegacyMatchingTagsRequireCompatibleManifestBeforeBindingHash() async throws {
        let directory = try workspace(), fixture = FolderProvider(jobID:"legacy-job")
        var prior = JobRecord(id:"legacy-job",request:try request());prior.source = source()
        fixture.manifest = try Persistence.encoder.encode(prior)
        let delivery = try adapter(fixture)
        for _ in 0..<2 {
            let id = try await delivery.episodeFolder(source:source(),request:request(),jobID:prior.id,
                existingFolderID:FolderProvider.id,intentURL:directory.appendingPathComponent("no-intent.json"))
            XCTAssertEqual(id,FolderProvider.id)
        }
        XCTAssertEqual(fixture.properties["joeySourceSHA256"],source().sha256)
        XCTAssertEqual(fixture.mutations,1);XCTAssertEqual(fixture.mkdirCount,0)
    }

    func testLegacyMatchingTagsRejectConflictingSourceBytesBeforeMutation() async throws {
        let directory = try workspace(), fixture = FolderProvider(jobID:"legacy-job")
        var prior = JobRecord(id:"legacy-job",request:try request());prior.source = source()
        prior.source!.sha256 = String(repeating:"b",count:64)
        fixture.manifest = try Persistence.encoder.encode(prior)
        await assertRejected(try adapter(fixture),jobID:prior.id,intent:directory.appendingPathComponent("no-intent.json"))
        XCTAssertNil(fixture.properties["joeySourceSHA256"])
        XCTAssertEqual(fixture.mutations,0);XCTAssertEqual(fixture.mkdirCount,0)
    }

    func testCreationIntentCannotClaimFolderWithConflictingJobTag() async throws {
        let directory = try workspace(), fixture = FolderProvider(jobID:"different-job",untagged:true)
        let delivery = try adapter(fixture)
        await assertRejected(delivery,jobID:"recover-job",intent:try intent(in:directory,jobID:"recover-job"))
        XCTAssertEqual(fixture.properties["joeyJobID"],"different-job")
        XCTAssertEqual(fixture.mutations,0)
    }

    func testCreationIntentCannotClaimNonemptyOrUnrelatedFolder() async throws {
        let directory = try workspace()
        for wrongIntent in [false,true] {
            let fixture = FolderProvider(jobID:nil,untagged:true)
            fixture.hasChildren = !wrongIntent
            let delivery = try adapter(fixture)
            await assertRejected(delivery,jobID:"recover-job",intent:try intent(in:directory,jobID:wrongIntent ? "different-job" : "recover-job"))
            XCTAssertEqual(fixture.mutations,0)
        }
    }

    func testRecoveryRequiresFullTagReadback() async throws {
        let directory = try workspace(), fixture = FolderProvider(jobID:nil,untagged:true)
        fixture.corruptTagReadback = true
        let delivery = try adapter(fixture)
        await assertRejected(delivery,jobID:"recover-job",intent:try intent(in:directory,jobID:"recover-job"))
        XCTAssertEqual(fixture.mutations,1)
    }

    func testLostMkdirResponseRecoversWithoutCreatingSecondFolder() async throws {
        let directory = try workspace(), fixture = FolderProvider(jobID:nil,untagged:true)
        fixture.exists = false;fixture.loseMkdirResponse = true
        let delivery = try adapter(fixture), savedIntent = directory.appendingPathComponent("folder-intent.json")
        for _ in 0..<2 {
            let id = try await delivery.episodeFolder(source:source(),request:request(),jobID:"new-job",existingFolderID:nil,intentURL:savedIntent)
            XCTAssertEqual(id,FolderProvider.id)
        }
        XCTAssertEqual(fixture.mkdirCount,1)
        XCTAssertEqual(fixture.mutations,1)
        XCTAssertEqual(fixture.properties["joeyJobID"],"new-job")
    }

    func testFolderClaimedDuringMkdirIsNotRetagged() async throws {
        let directory = try workspace(), fixture = FolderProvider(jobID:nil,untagged:true)
        fixture.exists = false;fixture.claimDuringMkdir = true
        let delivery = try adapter(fixture)
        await assertRejected(delivery,jobID:"new-job",intent:directory.appendingPathComponent("folder-intent.json"))
        XCTAssertEqual(fixture.properties["joeyJobID"],"different-job")
        XCTAssertEqual(fixture.mutations,0)
    }

    func testFiledAndQAPassedRecoveryRejectOtherJobBeforeAnyUpload() async throws {
        for state in [JobState.qaPassed,.filed] {
            let directory = try workspace(), runtime = directory.appendingPathComponent("runtime")
            let original = directory.appendingPathComponent("original.synthetic")
            try Data("Synthetic original identity".utf8).write(to:original)
            var request = try Fixtures.request(dir:directory,path:original.path)
            request.owner = .taxstone;request.fileToDrive = true;request.sourceID = source().id;request.title = source().title
            let fullID = try request.stableID()
            request.mode = .highlights;request.fixedIntervals = [Interval(0,6)]
            var job = JobRecord(id:try request.stableID(),request:request)
            let jobDirectory = runtime.appendingPathComponent("jobs/"+job.id)
            try FileManager.default.createDirectory(at:jobDirectory,withIntermediateDirectories:true)
            let output = jobDirectory.appendingPathComponent("accepted.mp4")
            try Data("Synthetic accepted media identity".utf8).write(to:output)
            let hash = try Integrity.sha256(output)
            var inspected = source();inspected.path = original.path;inspected.sha256 = try Integrity.sha256(original)
            job.source = inspected
            job.transcript = Transcript(sourceID:inspected.id,sourceSHA256:inspected.sha256,duration:10,engine:"Synthetic",
                segments:[TranscriptSegment(start:0,end:10,text:"Complete synthetic transcript.")])
            job.planningBasis = .transcriptAssisted;job.state = state;job.folderID = FolderProvider.id
            job.clips = [ClipRecord(id:1,title:"Accepted",intervals:[Interval(0,6)],filename:output.lastPathComponent,
                measuredDuration:6,bytes:Int64(try Data(contentsOf:output).count),sha256:hash,
                qa:QAReport(checkedAt:Date(),checks:[:],outputSHA256:hash,passed:true,limitations:["Synthetic checkpoint"]))]
            try Persistence.save(job,to:jobDirectory.appendingPathComponent("job.json"))
            try Persistence.save(job.transcript,to:jobDirectory.appendingPathComponent("transcript.json"))
            let fixture = FolderProvider(jobID:fullID)
            let provider = FolderRecoveryDelivery(delivery:try adapter(fixture))
            let result = try await Coordinator.$deliveryOverride.withValue(provider) {try await Coordinator(root:runtime).run(request)}
            XCTAssertEqual(result.state,.qaPassed,result.error ?? "")
            XCTAssertEqual(result.stage,"Drive folder")
            XCTAssertTrue(result.error?.contains("job") == true,result.error ?? "No ownership error")
            let uploads = await provider.uploads
            XCTAssertEqual(uploads,0,"Saved folder IDs must not bypass current ownership before replacing canonical records")
            XCTAssertEqual(try Integrity.sha256(output),hash)
            XCTAssertEqual(fixture.properties["joeyJobID"],fullID)
        }
    }
}

private final class FolderProvider: @unchecked Sendable {
    static let id = "synthetic_episode_folder"
    static let name = "Date Unknown — Fixture — fixture-source"
    private let lock = NSLock()
    var properties: [String:String]
    var exists = true, hasChildren = false, corruptTagReadback = false
    var loseMkdirResponse = false, claimDuringMkdir = false
    var mutations = 0, mkdirCount = 0
    var manifest: Data?
    private var createdTime = "2026-01-02T00:00:00Z"
    init(jobID: String?, untagged: Bool = false) {
        properties = untagged ? [:] : ["joeySourceID":"fixture-source","joeyOwner":"taxstone"]
        properties["joeyJobID"] = jobID
    }
    func command(_ executable: String, _ arguments: [String]) throws -> ProcessResult {
        lock.lock();defer {lock.unlock()}
        guard executable == "rclone" else {throw JoeyError.failed("Unexpected fixture executable")}
        switch arguments.first {
        case "lsjson": return ProcessResult(stdout:Data("[]".utf8),stderr:"",status:0)
        case "config":
            let token = String(decoding:try JSONSerialization.data(withJSONObject:["access_token":"dummy-fixture-only"]),as:UTF8.self)
            return ProcessResult(stdout:try JSONSerialization.data(withJSONObject:["fixture":["type":"drive","token":token]]),stderr:"",status:0)
        case "copyto":
            guard let manifest,arguments[1] == "fixture:clip_manifest.json" else {throw JoeyError.failed("Unexpected fixture download")}
            try manifest.write(to:URL(fileURLWithPath:arguments[2]))
            return ProcessResult(stdout:Data(),stderr:"",status:0)
        case "mkdir":
            mkdirCount += 1;exists = true;createdTime = ISO8601DateFormatter().string(from:Date())
            if claimDuringMkdir {properties = ["joeySourceID":"fixture-source","joeyOwner":"taxstone","joeyJobID":"different-job"]}
            if loseMkdirResponse {throw JoeyError.failed("Synthetic lost mkdir response")}
            return ProcessResult(stdout:Data(),stderr:"",status:0)
        default: throw JoeyError.failed("Unexpected external command blocked by fixture")
        }
    }
    func response(_ request: URLRequest) throws -> Data {
        lock.lock();defer {lock.unlock()}
        let url = try XCTUnwrap(request.url)
        guard url.host == "www.googleapis.com" else {throw JoeyError.failed("Unexpected provider host")}
        let chain = [DriveDestination.taxstoneClips.id] + DriveDestination.taxstoneClips.ancestorIDs
        let root: [String:Any] = ["id":url.lastPathComponent,"name":DriveDestination.taxstoneClips.name,
            "mimeType":"application/vnd.google-apps.folder","trashed":false,
            "parents":chain.firstIndex(of:url.lastPathComponent).flatMap {$0+1 < chain.count ? [chain[$0+1]] : nil} ?? [],
            "permissions":[["type":"user","role":"owner"]]]
        func folder() -> [String:Any] {
            ["id":Self.id,"name":Self.name,"mimeType":"application/vnd.google-apps.folder","trashed":false,
             "permissions":[["type":"user","role":"owner"]],"parents":[DriveDestination.taxstoneClips.id],"appProperties":properties,"createdTime":createdTime]
        }
        let result: [String:Any]
        if request.httpMethod == "PATCH",url.lastPathComponent == Self.id {
            mutations += 1
            if let stream = request.httpBodyStream {
                stream.open();defer {stream.close()}
                var data = Data(), buffer = [UInt8](repeating:0,count:4096)
                while stream.hasBytesAvailable {let count = stream.read(&buffer,maxLength:buffer.count);if count <= 0 {break};data.append(buffer,count:count)}
                let body = try JSONSerialization.jsonObject(with:data) as! [String:Any]
                properties = body["appProperties"] as! [String:String]
            } else {
                let body = try JSONSerialization.jsonObject(with:try XCTUnwrap(request.httpBody)) as! [String:Any]
                properties = body["appProperties"] as! [String:String]
            }
            if corruptTagReadback {properties["joeyJobID"] = "different-job";properties["joeySourceID"] = "different-source"}
            result = folder()
        } else if request.httpMethod == "GET",chain.contains(url.lastPathComponent) {result = root}
        else if request.httpMethod == "GET",url.lastPathComponent == Self.id {result = folder()}
        else if request.httpMethod == "GET",url.lastPathComponent == "synthetic_manifest_id",let manifest {
            let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try manifest.write(to:temporary);defer {try? FileManager.default.removeItem(at:temporary)}
            result = ["id":"synthetic_manifest_id","name":"clip_manifest.json","parents":[Self.id],"trashed":false,
                "md5Checksum":try Integrity.md5(temporary)]
        }
        else if request.httpMethod == "GET",url.lastPathComponent == "files" {
            let query = URLComponents(url:url,resolvingAgainstBaseURL:false)?.queryItems?.first(where:{$0.name == "q"})?.value ?? ""
            if query.contains("'\(DriveDestination.taxstoneClips.id)'") {result = ["files":exists ? [folder()] : []]}
            else if query.contains("'\(Self.id)'") {result = ["files":manifest != nil ? [["id":"synthetic_manifest_id","name":"clip_manifest.json"]] : hasChildren ? [["id":"existing-record","name":"clip_manifest.json"]] : []]}
            else if query.contains("appProperties has") {result = ["files":[]]}
            else {throw JoeyError.failed("Unexpected folder listing")}
        } else {throw JoeyError.failed("Unexpected provider mutation blocked by fixture")}
        return try JSONSerialization.data(withJSONObject:result)
    }
}

private final class FolderProtocol: URLProtocol {
    static var fixture: FolderProvider!
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

private actor FolderRecoveryDelivery: CoordinatorDelivery {
    let delivery: DriveDelivery
    var uploads = 0
    init(delivery: DriveDelivery) {self.delivery = delivery}
    func metadata(_ id: String) async throws -> [String:Any] {throw JoeyError.failed("Unexpected source read")}
    func downloadOriginal(reference: String, directory: URL) async throws -> URL {throw JoeyError.failed("Saved source must be reused")}
    func archive(source: SourceRecord, request: JobRequest) async throws -> String {"https://example.invalid/synthetic-archive"}
    func episodeFolder(source: SourceRecord, request: JobRequest, jobID: String, existingFolderID: String?, intentURL: URL) async throws -> String {
        try await delivery.episodeFolder(source:source,request:request,jobID:jobID,existingFolderID:existingFolderID,intentURL:intentURL)
    }
    func resolveArtwork(source: SourceRecord, configuration: Configuration, root: URL) async throws -> Artwork {throw JoeyError.failed("Unexpected artwork")}
    func verifyPackage(job: JobRecord, directory: URL) async throws {
        guard job.hasRequiredCompletionEvidence else {throw JoeyError.failed("Synthetic package incomplete")}
    }
    func reconcileRegister(job: JobRecord, tab: String) async throws -> [String] {[]}
    func upload(_ local: URL, name: String?, parent: String, destination: FilingDestination, replaceCompanion: Bool) async throws -> DriveReceipt {
        uploads += 1
        return DriveReceipt(id:"synthetic_"+Integrity.textHash(local.lastPathComponent),name:name ?? local.lastPathComponent,parent:parent,
            bytes:Int64(try Data(contentsOf:local).count),md5:try Integrity.md5(local),sha256:try Integrity.sha256(local),
            url:"https://example.invalid/fixture",permissions:["user:owner"],verifiedAt:Date(),destination:destination,permissionFingerprint:String(repeating:"a",count:64))
    }
}
