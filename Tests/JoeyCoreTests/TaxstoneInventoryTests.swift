import XCTest
@testable import JoeyCore

/// Exercises the real inventory/restart path with read-only provider and feed responses.
/// Saved artifacts are synthetic identities, not media acceptance evidence.
final class TaxstoneInventoryTests: XCTestCase {
    func testMixedCurrentHistoricalAndUnknownInventoryPreservesOwnershipAcrossRestart() async throws {
        let fixture = try TaxstoneInventoryFixture()
        defer {fixture.remove()}
        let complete = try fixture.addJob(track:"1001",completed:true)
        let partial = try fixture.addJob(track:"1002",completed:false)
        try fixture.addHistorical(track:"1003",unknown:false)
        try fixture.addHistorical(track:"1004",unknown:true)
        let before = try fixture.checkpointBytes()
        for _ in 0..<2 {
            let library = try fixture.library()
            let state = try await library.inventory()
            let episodes = Dictionary(uniqueKeysWithValues:state.episodes.map {($0.id,$0)})
            XCTAssertEqual(episodes[complete.request.sourceID]?.status,"COMPLETED")
            XCTAssertEqual(episodes[partial.request.sourceID]?.status,"RESUMABLE")
            XCTAssertEqual(episodes[partial.request.sourceID]?.jobID,partial.id)
            XCTAssertEqual(try episodes[partial.request.sourceID]?.request?.identityData(),try partial.request.identityData())
            XCTAssertEqual(episodes["soundcloud:1003"]?.status,"READY")
            XCTAssertEqual(episodes["soundcloud:1003"]?.reuseCandidates?.count,1)
            XCTAssertEqual(episodes["soundcloud:1004"]?.status,"BLOCKED")
            XCTAssertTrue(episodes["soundcloud:1004"]?.error?.contains("no resolvable candidate") == true)
            XCTAssertEqual(state.completedCount,1)
            XCTAssertEqual(state.remoteOutputCount,4)
            XCTAssertEqual(state.uncertainOutputCount,1)
            XCTAssertEqual(try fixture.checkpointBytes(),before)
        }
        XCTAssertEqual(fixture.mutations,0)
        XCTAssertEqual(fixture.unexpectedHelpers,0)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:fixture.root.appendingPathComponent("jobs").path).count,2)
    }

    func testMissingAcceptedCachePreservesKnownRemoteOwnershipAndRecoveryFailure() async throws {
        let fixture = try TaxstoneInventoryFixture();defer {fixture.remove()}
        let job = try fixture.addJob(track:"4001",completed:false)
        let output = fixture.root.appendingPathComponent("jobs/"+job.id+"/"+job.clips[0].filename)
        try FileManager.default.removeItem(at:output)
        let before = try fixture.checkpointBytes()
        for _ in 0..<2 {
            let state = try await fixture.library().inventory()
            XCTAssertEqual(state.uncertainOutputCount,0)
            XCTAssertEqual(state.episodes.first?.status,"BLOCKED")
            XCTAssertFalse(state.episodes.first?.error?.contains("no resolvable candidate") == true)
            XCTAssertEqual(state.episodes.first?.jobID,job.id)
            XCTAssertEqual(try fixture.checkpointBytes(),before)
        }
        XCTAssertEqual(fixture.mutations,0)
        XCTAssertEqual(fixture.unexpectedHelpers,0)
    }

    func testCurrentOwnershipRejectsChangedProviderOrSavedEvidence() async throws {
        for fault in ["md5","size","name","qa","source","route","duplicateListing","duplicateReceipt","parent","hash"] {
            let fixture = try TaxstoneInventoryFixture()
            defer {fixture.remove()}
            var job = try fixture.addJob(track:"2001",completed:false)
            let id = job.clips[0].drive!.id
            switch fault {
            case "md5": fixture.listing[0]["Hashes"] = ["md5":String(repeating:"0",count:32)]
            case "size": fixture.listing[0]["Size"] = 999
            case "name": fixture.listing[0]["Name"] = "changed.mp4"
            case "qa": job.clips[0].qa!.outputSHA256 = String(repeating:"b",count:64)
            case "source": job.source!.sha256 = String(repeating:"b",count:64)
            case "duplicateListing": fixture.listing.append(fixture.listing[0])
            case "duplicateReceipt": job.clips.append(job.clips[0])
            case "parent": job.clips[0].drive!.parent = "different-package"
            case "hash": job.clips[0].drive!.sha256 = String(repeating:"b",count:64)
            default: job.clips[0].drive!.destination = FilingDestination(destination:.dubAudioClips,asset:.clip,
                owner:.dub,sourceID:job.request.sourceID,sourceSHA256:job.source!.sha256)
            }
            try Persistence.save(job,to:fixture.root.appendingPathComponent("jobs/"+job.id+"/job.json"))
            let library = try fixture.library()
            let state = try await library.inventory()
            XCTAssertEqual(state.episodes.first?.status,"BLOCKED",fault+" must not hide "+id)
            XCTAssertEqual(state.uncertainOutputCount,fault == "duplicateListing" ? 2:1,fault)
            XCTAssertEqual(fixture.mutations,0)
        }
    }

    func testHistoricalReceiptOwnershipDoesNotInventCurrentCompletionEvidence() async throws {
        let fixture = try TaxstoneInventoryFixture()
        defer {fixture.remove()}
        var job = try fixture.addJob(track:"3001",completed:true)
        job.clips[0].drive!.destination = nil
        job.clips[0].drive!.permissionFingerprint = nil
        try Persistence.save(job,to:fixture.root.appendingPathComponent("jobs/"+job.id+"/job.json"))
        let before = try fixture.checkpointBytes()
        let library = try fixture.library()
        let state = try await library.inventory()
        XCTAssertEqual(state.uncertainOutputCount,0,"Source-bound historical receipts establish ownership, not current delivery")
        XCTAssertEqual(state.completedCount,0)
        XCTAssertEqual(state.episodes.first?.status,"BLOCKED")
        XCTAssertTrue(state.episodes.first?.error?.contains("evidence is incomplete") == true)
        XCTAssertEqual(try fixture.checkpointBytes(),before)
        XCTAssertEqual(fixture.mutations,0)
    }
}

private final class TaxstoneInventoryFixture: @unchecked Sendable {
    let root: URL
    let session: URLSession
    let lock = NSRecursiveLock()
    var evidence: [TaxstoneEvidenceEntry] = []
    var metadata: [String:[String:Any]] = [:]
    var listing: [[String:Any]] = []
    var mutations = 0
    var unexpectedHelpers = 0
    static let permissions: [[String:Any]] = [["id":"owner","type":"user","role":"owner"]]

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("joey-taxstone-inventory-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TaxstoneInventoryProtocol.self]
        session = URLSession(configuration:configuration)
        TaxstoneInventoryProtocol.fixture = self
        var settings = Configuration();settings.rcloneRemote = "fixture"
        settings.taxstoneProfile = try Fixtures.profile(dir:root)
        try Persistence.save(settings,to:root.appendingPathComponent("settings.json"))
        let destination = DriveDestination.taxstoneClips
        let chain = [destination.id]+destination.ancestorIDs
        for (index,id) in chain.enumerated() {
            metadata[id] = ["id":id,"name":destination.name,"mimeType":"application/vnd.google-apps.folder",
                "trashed":false,"parents":index+1 < chain.count ? [chain[index+1]] : [],"permissions":Self.permissions]
        }
    }
    func remove() {session.invalidateAndCancel();try? FileManager.default.removeItem(at:root)}
    func library() throws -> TaxstoneLibrary {
        try TaxstoneLibrary(root:root,session:session,runHelper:{_,args,_ in try self.command(args)},loadEvidence:{self.evidence})
    }
    func addOriginal(track: String) throws -> SourceRecord {
        let local = root.appendingPathComponent("original-"+track+".mp3")
        try Data(("synthetic original "+track).utf8).write(to:local)
        let source = SourceRecord(id:"soundcloud:"+track,owner:.taxstone,title:"Episode "+track,path:local.path,
            bytes:Int64(try Data(contentsOf:local).count),sha256:try Integrity.sha256(local),duration:100,
            width:0,height:0,fps:0,hasAudio:true,kind:.audio,streams:[],authorizationBasis:"Synthetic inventory fixture",classificationEvidence:"Synthetic only")
        let driveID = "original_drive_identity_"+track
        metadata[driveID] = ["id":driveID,"name":local.lastPathComponent,"mimeType":"audio/mpeg",
            "parents":[TaxstoneLibrary.archiveRoot],"sha256Checksum":source.sha256,"trashed":false]
        evidence.append(TaxstoneEvidenceEntry(driveID:driveID,trackID:track,title:source.title,duration:source.duration,
            sourceSHA256:source.sha256,legacyClips:[],notes:[]))
        return source
    }
    func receipt(local: URL, id: String, folder: String, route: FilingDestination) throws -> DriveReceipt {
        let bytes = Int64(try Data(contentsOf:local).count),sha = try Integrity.sha256(local),md5 = try Integrity.md5(local)
        metadata[id] = ["id":id,"name":local.lastPathComponent,"mimeType":"application/octet-stream","parents":[folder],
            "size":String(bytes),"sha256Checksum":sha,"md5Checksum":md5,"trashed":false,
            "permissions":Self.permissions,"webViewLink":"https://drive.google.com/file/d/"+id+"/view"]
        return DriveReceipt(id:id,name:local.lastPathComponent,parent:folder,bytes:bytes,md5:md5,sha256:sha,
            url:"https://drive.google.com/file/d/"+id+"/view",permissions:["user:owner"],verifiedAt:Date(),destination:route,
            permissionFingerprint:try DriveDelivery.permissionFingerprint(["permissions":Self.permissions]))
    }
    func addJob(track: String, completed: Bool) throws -> JobRecord {
        let source = try addOriginal(track:track)
        var request = try Fixtures.request(dir:root,path:source.path)
        request.owner = .taxstone;request.sourceID = source.id;request.title = source.title;request.fileToDrive = true
        let id = try request.stableID()
        let directory = root.appendingPathComponent("jobs/"+id)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let route = try DestinationResolver.resolve(source:source,request:request,asset:.clip)
        let folder = "episode_folder_"+track
        metadata[folder] = ["id":folder,"name":"Episode "+track,"mimeType":"application/vnd.google-apps.folder",
            "parents":[route.rootID],"trashed":false,"permissions":Self.permissions,
            "appProperties":["joeySourceID":source.id,"joeySourceSHA256":source.sha256,"joeyOwner":"taxstone"]]
        var job = JobRecord(id:id,request:request)
        job.source = source;job.folderID = folder;job.planningBasis = .transcriptAssisted
        job.transcript = Transcript(sourceID:source.id,sourceSHA256:source.sha256,duration:source.duration,engine:"Synthetic fixture",
            segments:[TranscriptSegment(start:0,end:100,text:"Synthetic complete transcript.")])
        let local = directory.appendingPathComponent("01_Clip_soundcloud-"+track+"_00-00-00_to_00-01-40.mp4")
        try Data(("synthetic accepted clip "+track).utf8).write(to:local)
        let accepted = try receipt(local:local,id:"current_clip_"+track,folder:folder,route:route)
        job.clips = [ClipRecord(id:1,title:"Clip",intervals:[Interval(0,100)],filename:local.lastPathComponent,
            measuredDuration:100,bytes:accepted.bytes,sha256:accepted.sha256,
            qa:QAReport(checkedAt:Date(),checks:[:],outputSHA256:accepted.sha256,passed:true,limitations:["Synthetic identity fixture"]),drive:accepted)]
        listing.append(["ID":accepted.id,"Name":accepted.name,"Path":"Episode "+track+"/"+accepted.name,
            "Size":accepted.bytes,"Hashes":["md5":accepted.md5!]])
        if completed {
            for (index,name) in Records.companionNames(source:source).enumerated() {
                let file = directory.appendingPathComponent(name)
                try Data(("synthetic companion "+name).utf8).write(to:file)
                job.companions[name] = try receipt(local:file,id:"companion_\(track)_\(index)",folder:folder,route:route)
            }
            job.state = .completed
            XCTAssertTrue(job.hasRequiredCompletionEvidence)
        } else {job.state = .qaPassed;job.stage = "delivery"}
        try Persistence.save(job,to:directory.appendingPathComponent("job.json"))
        return job
    }
    func addHistorical(track: String, unknown: Bool) throws {
        _ = try addOriginal(track:track)
        let id = (unknown ? "unknown_":"legacy_")+track
        let name = unknown ? "Unresolved_"+track+".mp4" : "taxstone-"+track+"-C01.mp4"
        let md5 = String(repeating:"a",count:32)
        metadata[id] = ["id":id,"name":name,"md5Checksum":md5,"videoMediaMetadata":["width":720,"height":1280,"durationMillis":"100000"]]
        listing.append(["ID":id,"Name":name,"Path":"Episode "+track+"/"+name,"Size":100,"Hashes":["md5":md5]])
        if !unknown {evidence[evidence.count-1].legacyClips = [TaxstoneLegacyClip(driveID:id,intervals:[Interval(0,100)],
            evidencePath:"Synthetic historical ledger",sequence:1)]}
    }
    func checkpointBytes() throws -> [String:Data] {
        let jobs = root.appendingPathComponent("jobs")
        return try Dictionary(uniqueKeysWithValues:FileManager.default.contentsOfDirectory(atPath:jobs.path).map {
            ($0,try Data(contentsOf:jobs.appendingPathComponent($0+"/job.json")))
        })
    }
    func command(_ args: [String]) throws -> ProcessResult {
        lock.lock();defer {lock.unlock()}
        if args.first == "config" {return ProcessResult(stdout:Data("{\"fixture\":{\"type\":\"drive\",\"token\":\"{\\\"access_token\\\":\\\"dummy-only\\\"}\"}}".utf8),stderr:"",status:0)}
        if args.first == "lsjson" {return ProcessResult(stdout:try JSONSerialization.data(withJSONObject:args.contains("--recursive") ? listing:[]),stderr:"",status:0)}
        unexpectedHelpers += 1
        throw JoeyError.failed("Unexpected helper; inventory must not render or upload")
    }
    func response(_ request: URLRequest) throws -> Data {
        lock.lock();defer {lock.unlock()}
        guard request.httpMethod == "GET" else {mutations += 1;throw JoeyError.failed("Inventory attempted provider mutation")}
        let url = request.url!
        if url.host == "itunes.apple.com" {
            return try JSONSerialization.data(withJSONObject:["results":evidence.map {[
                "collectionId":978037629,"episodeGuid":"tag:soundcloud,2010:tracks/"+$0.trackID,
                "artworkUrl600":"https://example.mzstatic.com/"+$0.trackID+".jpg","releaseDate":"2026-01-01T00:00:00Z"] as [String:Any]}])
        }
        if url.lastPathComponent == "files" {
            let query = URLComponents(url:url,resolvingAgainstBaseURL:false)!.queryItems!.first {$0.name == "q"}!.value!
            let parent = String(query.split(separator:"'").first!)
            return try JSONSerialization.data(withJSONObject:["files":metadata.values.filter {($0["parents"] as? [String]) == [parent]}])
        }
        guard let object = metadata[url.lastPathComponent] else {throw JoeyError.failed("Unexpected inventory metadata identity: "+url.lastPathComponent)}
        return try JSONSerialization.data(withJSONObject:object)
    }
}

private final class TaxstoneInventoryProtocol: URLProtocol {
    static var fixture: TaxstoneInventoryFixture!
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
