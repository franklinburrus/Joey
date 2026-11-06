import Foundation

public actor DriveDelivery {
    private struct ProviderHTTPError: LocalizedError {
        let status: Int
        let message: String
        var transient: Bool {[429,500,502,503,504].contains(status)}
        var errorDescription: String? {message}
    }
    public static let videoRoot = DriveDestination.dubVideoClips.id
    public static let audioRoot = DriveDestination.dubAudioClips.id
    public static let masterSheet = "17uhDO06vmVEz96YrUnA6aHyV5fL_3AAs3ylOjrYRLwI"
    private let remote: String
    private var token: String?
    private let session: URLSession
    private let helperRunner: @Sendable (String, [String], Int) async throws -> ProcessResult
    private var nextSheetsRequest = ContinuousClock.now
    public init(remote: String, session: URLSession = .shared,
                runHelper: @escaping @Sendable (String, [String], Int) async throws -> ProcessResult = {try await Processes.run($0,$1,maxOutput:$2)}) throws {
        guard remote.range(of:"^[A-Za-z0-9_-]+$",options:.regularExpression) != nil else { throw JoeyError.invalid("Invalid existing rclone remote name") }
        self.remote = remote; self.session = session; self.helperRunner = runHelper
    }
    private func runHelper(_ executable: String, _ arguments: [String], maxOutput: Int = 16*1024*1024) async throws -> ProcessResult {
        var boundedArguments = arguments
        if executable == "rclone", arguments.first != "config" {
            // Native readers or mutation reconciliation own the attempt budget.
            for flag in ["--retries", "--low-level-retries"] where !boundedArguments.contains(flag) {
                boundedArguments += [flag, "1"]
            }
        }
        return try await helperRunner(executable,boundedArguments,maxOutput)
    }
    private func runReadHelper(_ executable: String, _ arguments: [String], maxOutput: Int = 16*1024*1024) async throws -> ProcessResult {
        try await Processes.retry {
            try await self.runHelper(executable,arguments,maxOutput:maxOutput)
        }
    }
    public func preflight(tab: String) async throws -> [String:String] {
        var result: [String:String] = [:]
        for destination in DriveDestination.active {
            let id = destination.id
            let info = try await verifyRoot(destination)
            result[id] = "\(info["name"] as? String ?? "unnamed"): \(try await children(id).count) children"
        }
        let range = ("'"+tab.replacingOccurrences(of:"'",with:"''")+"'!A1:AZ1").addingPercentEncoding(withAllowedCharacters:.urlPathAllowed)!
        let data = try await request("spreadsheets/"+Self.masterSheet+"/values/"+range,sheets:true)
        guard let values = data["values"] as? [[String]], let headers = values.first else {throw JoeyError.dependency("Master Link List header read returned no values")}
        try Records.validateHeaders(headers)
        result["Master Link List"] = "Current schema read: \(headers.count) columns; \(headers.joined(separator:" | "))"
        return result
    }
    private func authenticate() async throws {
        // Let the already authorized rclone remote refresh its own token. Secrets
        // stay in process memory and its existing config, never job records/logs.
        _ = try await runReadHelper("rclone",["lsjson",remote+":","--drive-root-folder-id",DestinationResolver.dubRoot,"--max-depth","1"])
        do {
            let config = try await runHelper("rclone",["config","dump"],maxOutput:1024*1024)
            guard config.status == 0,
                  let root = try JSONSerialization.jsonObject(with:config.stdout) as? [String:Any],
                  let entry = root[remote] as? [String:Any], entry["type"] as? String == "drive",
                  let raw = entry["token"] as? String, let data = raw.data(using:.utf8),
                  let value = try JSONSerialization.jsonObject(with:data) as? [String:Any],
                  let access = value["access_token"] as? String, !access.isEmpty else {
                throw JoeyError.dependency("Existing rclone remote does not expose a usable authorized Drive OAuth token")
            }
            token = access
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // A malformed dump or helper error may contain token material.
            throw JoeyError.dependency("Existing rclone OAuth configuration could not be read; check the authorized remote")
        }
    }
    func request(_ path: String, method: String = "GET", query: [String:String] = [:], body: Any? = nil, sheets: Bool = false) async throws -> [String:Any] {
        if token == nil { try await authenticate() }
        var c = URLComponents(string:(sheets ? "https://sheets.googleapis.com/v4/":"https://www.googleapis.com/drive/v3/")+path)!
        c.queryItems = query.map {URLQueryItem(name:$0.key,value:$0.value)}
        guard let url = c.url else { throw JoeyError.invalid("Invalid provider path") }
        for attempt in 0..<2 {
            var req = URLRequest(url:url); req.httpMethod = method; req.timeoutInterval = 60
            req.setValue("Bearer "+(token ?? ""),forHTTPHeaderField:"Authorization")
            if let body { req.httpBody = try JSONSerialization.data(withJSONObject:body); req.setValue("application/json",forHTTPHeaderField:"Content-Type") }
            let (data,response) = try await response(for:req)
            guard let http = response as? HTTPURLResponse else { throw JoeyError.failed("Missing provider HTTP response") }
            if http.statusCode == 401 && attempt == 0 { token = nil; try await authenticate(); continue }
            guard (200..<300).contains(http.statusCode) else {
                let obj = try? JSONSerialization.jsonObject(with:data) as? [String:Any]
                let error = obj?["error"] as? [String:Any]
                throw ProviderHTTPError(status:http.statusCode,message:"\(sheets ? "Sheets":"Drive") HTTP \(http.statusCode): \(error?["message"] as? String ?? "provider rejected request")")
            }
            return (try JSONSerialization.jsonObject(with:data) as? [String:Any]) ?? [:]
        }
        throw JoeyError.dependency("Provider authorization refresh failed")
    }
    private func waitForSheetsRequestSlot() async throws {
        // Sheets permits 60 reads and 60 writes per minute per user/project.
        // Reserve slots before suspension so concurrent calls and retries
        // cannot burst through that limit. Drive calls are unaffected.
        let slot = max(ContinuousClock.now,nextSheetsRequest)
        nextSheetsRequest = slot.advanced(by:.milliseconds(1100))
        try await Task.sleep(until:slot,clock:.continuous)
    }
    /// Retry transient reads only. Mutations retain their caller's explicit
    /// readback/reconciliation loop, so an uncertain append is never replayed here.
    func response(for request: URLRequest) async throws -> (Data,URLResponse) {
        let fetch = {
            try Task.checkCancellation()
            if request.url?.host == "sheets.googleapis.com" {
                try await self.waitForSheetsRequestSlot()
            }
            try Task.checkCancellation()
            let result = try await self.session.data(for:request)
            if let http = result.1 as? HTTPURLResponse,
               [429,500,502,503,504].contains(http.statusCode) {
                throw ProviderHTTPError(status:http.statusCode,message:"Provider HTTP \(http.statusCode): transient request failure")
            }
            return result
        }
        if request.httpMethod == nil || request.httpMethod == "GET" {
            return try await Processes.retry(fetch)
        }
        return try await fetch()
    }
    func metadata(_ id: String) async throws -> [String:Any] {
        try await request("files/"+id,query:["fields":"id,name,mimeType,parents,size,md5Checksum,sha256Checksum,webViewLink,trashed,permissions(id,type,role,allowFileDiscovery,domain,emailAddress),capabilities(canAddChildren),appProperties,createdTime,videoMediaMetadata(width,height,durationMillis)"])
    }
    func children(_ parent: String) async throws -> [[String:Any]] {
        try await requestFiles(query:"'\(parent)' in parents and trashed=false")
    }
    private func requestFiles(query filter: String) async throws -> [[String:Any]] {
        var all: [[String:Any]] = [], page: String?
        repeat {
            var query = ["q":filter,"fields":"nextPageToken,files(id,name,mimeType,size,md5Checksum,parents,appProperties)","pageSize":"1000"]
            if let page {query["pageToken"] = page}
            let result = try await request("files",query:query)
            guard let files = result["files"] as? [[String:Any]] else {throw JoeyError.failed("Drive listing is missing its files result")}
            all += files;page = result["nextPageToken"] as? String
        } while page != nil
        return all
    }
    public func episodeFolder(source: SourceRecord, request: JobRequest, jobID: String, existingFolderID: String?, intentURL: URL) async throws -> String {
        let route = try DestinationResolver.resolve(source:source,request:request,asset:.clip)
        let root = route.rootID
        _ = try await verifyRoot(route.destination)
        if let existingFolderID {
            let prior = try await metadata(existingFolderID)
            guard prior["parents"] as? [String] == [root] else {
                throw JoeyError.dependency("Existing package is incorrectly routed: \(existingFolderID), actual parents \(prior["parents"] ?? "missing"), expected \(root). Accepted media preserved; no relocation or duplicate delivery.")
            }
        }
        let name = "\(source.episodeDate ?? "Date Unknown") — \(Persistence.safeName(source.title)) — \(Persistence.safeName(source.id))"
        let existing = try await children(root)
        let matching = existing.filter { file in
            let props = file["appProperties"] as? [String:String]
            return props?["joeySourceID"] == source.id && props?["joeyOwner"] == source.owner.rawValue || file["name"] as? String == name
        }
        guard matching.count <= 1 else { throw JoeyError.dependency("Duplicate matching source folders require reconciliation; no new folder created") }
        if let found = matching.first {
            guard let id = found["id"] as? String else {throw JoeyError.failed("Matching episode folder has no provider identity")}
            if let existingFolderID, existingFolderID != id {throw JoeyError.failed("Matching episode folder differs from saved provider identity") }
            return try await reconcileEpisodeFolder(id:id,root:root,name:name,source:source,request:request,jobID:jobID,intentURL:intentURL)
        }
        if let existingFolderID {
            throw JoeyError.dependency("Saved episode folder \(existingFolderID) is not the unique matching source folder under \(root)")
        }
        // Search exact source tags across Drive as well as the canonical name.
        // This detects moved legacy packages, not just retired Joey folders.
        let escapedID = source.id.replacingOccurrences(of:"\\",with:"\\\\").replacingOccurrences(of:"'",with:"\\'")
        let escapedName = name.replacingOccurrences(of:"\\",with:"\\\\").replacingOccurrences(of:"'",with:"\\'")
        let candidates = try await requestFiles(query:"trashed=false and mimeType='application/vnd.google-apps.folder' and (appProperties has { key='joeySourceID' and value='\(escapedID)' } or name='\(escapedName)')")
        guard candidates.isEmpty else {
            throw JoeyError.dependency("Existing source package is outside authoritative root \(root): \(candidates.compactMap {$0["id"] as? String}.joined(separator:", ")). No duplicate package created or media relocated.")
        }
        // rclone creates the folder; an uncertain mkdir is reconciled by listing.
        try Persistence.save(["root":root,"name":name,"jobID":jobID,"started":ISO8601DateFormatter().string(from:Date())],to:intentURL)
        do { _ = try await runHelper("rclone",["mkdir",remote+":"+name,"--drive-root-folder-id",root]) }
        catch { if try await children(root).filter({$0["name"] as? String == name}).isEmpty { throw error } }
        let matches = try await children(root).filter {$0["name"] as? String == name}
        guard matches.count == 1, let id = matches[0]["id"] as? String else { throw JoeyError.failed("Cannot read back unique episode folder") }
        return try await reconcileEpisodeFolder(id:id,root:root,name:name,source:source,request:request,jobID:jobID,intentURL:intentURL)
    }
    private func reconcileEpisodeFolder(id: String, root: String, name: String, source: SourceRecord, request: JobRequest, jobID: String, intentURL: URL) async throws -> String {
        let expected = ["joeySourceID":source.id,"joeyOwner":source.owner.rawValue,"joeyJobID":jobID]
        func matchesLocation(_ metadata: [String:Any]) -> Bool {
            metadata["id"] as? String == id && metadata["mimeType"] as? String == "application/vnd.google-apps.folder"
                && metadata["trashed"] as? Bool != true && metadata["parents"] as? [String] == [root]
        }
        // Listing identity is only a candidate. Fresh metadata must bind the
        // folder to this immutable job before any clips or records are written.
        let meta = try await metadata(id)
        guard matchesLocation(meta) else {throw JoeyError.failed("Episode folder identity/location readback failed: \(id)")}
        let props = meta["appProperties"] as? [String:String] ?? [:]
        let permissions = try Self.permissionFingerprint(meta)
        if let hash = props["joeySourceSHA256"], hash != source.sha256 {
            throw JoeyError.failed("Episode source hash changed")
        }
        if expected.allSatisfy({props[$0.key] == $0.value}), props["joeySourceSHA256"] == source.sha256 {
            return id
        }
        guard expected.keys.allSatisfy({props[$0] == nil || props[$0] == expected[$0]}) else {
            throw JoeyError.dependency("Existing episode folder has conflicting job ownership; prior package preserved: \(id)")
        }
        let intent: [String:String]? = try? Persistence.load(intentURL)
        let created = ISO8601DateFormatter.fractional.date(from:meta["createdTime"] as? String ?? "")
            ?? ISO8601DateFormatter().date(from:meta["createdTime"] as? String ?? "")
        let started = ISO8601DateFormatter().date(from:intent?["started"] ?? "")
        let contents = try await children(id)
        let recoveringEmpty = intent?["root"] == root && intent?["name"] == name && intent?["jobID"] == jobID &&
            meta["name"] as? String == name && created != nil && started != nil && created! >= started! && contents.isEmpty
        if !recoveringEmpty {
            do {
                // A pre-existing compatible package can be adopted only from its
                // independently downloaded manifest, never its folder name alone.
                let manifests = contents.filter {$0["name"] as? String == "clip_manifest.json"}
                guard manifests.count == 1,let manifestID = manifests[0]["id"] as? String else {
                    throw JoeyError.dependency("Existing folder lacks verified job ownership, compatible manifest or recoverable empty-folder creation intent: \(id)")
                }
                let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("joey-folder-manifest-"+UUID().uuidString)
                defer {try? FileManager.default.removeItem(at:temporary)}
                let info = try await metadata(manifestID)
                guard info["parents"] as? [String] == [id],info["trashed"] as? Bool == false else {throw JoeyError.failed("Existing manifest location changed")}
                _ = try await runReadHelper("rclone",["copyto",remote+":clip_manifest.json",temporary.path,"--drive-root-folder-id",id,"--retries","1"])
                guard try Integrity.md5(temporary) == info["md5Checksum"] as? String else {throw JoeyError.failed("Existing manifest integrity readback failed")}
                let prior: JobRecord = try Persistence.load(temporary)
                guard prior.source?.id == source.id,prior.source?.owner == source.owner,prior.source?.sha256 == source.sha256,
                      try prior.request.identityData() == request.identityData(),prior.id == jobID else {
                    throw JoeyError.dependency("Existing episode manifest belongs to a different source or job contract: \(id)")
                }
            } catch {
                throw JoeyError.dependency("Existing folder job manifest could not be verified; prior package preserved: \(id). \(error.localizedDescription)")
            }
        }
        var bound = props.merging(expected,uniquingKeysWith:{$1})
        bound["joeySourceSHA256"] = source.sha256
        _ = try await self.request("files/"+id,method:"PATCH",query:["fields":"id,appProperties"],body:["appProperties":bound])
        let fresh = try await metadata(id), freshProps = fresh["appProperties"] as? [String:String] ?? [:]
        guard matchesLocation(fresh), bound.allSatisfy({freshProps[$0.key] == $0.value}), try Self.permissionFingerprint(fresh) == permissions else {
            throw JoeyError.failed("Episode folder job/source/owner identity readback failed: \(id)")
        }
        return id
    }
    public func archive(source: SourceRecord, request: JobRequest) async throws -> String {
        let route = try DestinationResolver.resolve(source:source,request:request,asset:.fullEpisode)
        if let reference = source.archiveReference {
            let id = try Self.archiveID(reference)
            let info = try await metadata(id)
            guard let parent = (info["parents"] as? [String]).flatMap({$0.count == 1 ? $0[0] : nil}),
                  let name = info["name"] as? String else {throw JoeyError.failed("Existing archive has ambiguous parent/name: \(id)")}
            // Existing byte-equivalent originals remain in their verified archives,
            // even outside the new-delivery roots. Never move or duplicate them.
            let receipt = try await verify(id:id,local:URL(fileURLWithPath:source.path),parent:parent,name:name,
                sha:source.sha256,md5:Integrity.md5(URL(fileURLWithPath:source.path)),bytes:source.bytes,
                destination:nil,expectedPermissions:Self.permissionFingerprint(info))
            return receipt.url
        }
        let local = URL(fileURLWithPath:source.path)
        let name: String
        if route.owner == .joeBudden {
            name = try SourceDiscovery.joeEpisodeName(source.title)+"."+local.pathExtension
        } else {
            name = (source.episodeDate ?? "Date Unknown")+" — "+Persistence.safeName(source.title)+" — "+Persistence.safeName(source.id)+"."+local.pathExtension
        }
        let root = route.rootID
        _ = try await verifyRoot(route.destination)
        let md5 = try Integrity.md5(local)
        let equivalent = try await children(root).filter {$0["md5Checksum"] as? String == md5 && Int64($0["size"] as? String ?? "") == source.bytes}
        guard equivalent.count <= 1 else {throw JoeyError.dependency("Duplicate byte-equivalent originals in \(root); no new archive upload")}
        if let file = equivalent.first, let id = file["id"] as? String {
            let info = try await metadata(id)
            guard let name = info["name"] as? String else {throw JoeyError.failed("Original archive name missing")}
            return try await verify(id:id,local:local,parent:root,name:name,sha:source.sha256,md5:md5,bytes:source.bytes,
                destination:route,expectedPermissions:Self.permissionFingerprint(info)).url
        }
        return try await upload(local,name:name,parent:root,destination:route).url
    }
    public func downloadOriginal(reference: String, directory: URL) async throws -> URL {
        let id = try Self.archiveID(reference)
        let info = try await metadata(id)
        guard let parent = (info["parents"] as? [String])?.first, let name = info["name"] as? String,
              !name.contains("/"), let bytes = Int64(info["size"] as? String ?? ""), bytes > 0,
              let md5 = info["md5Checksum"] as? String, info["trashed"] as? Bool != true else {throw JoeyError.dependency("Original archive has no complete downloadable metadata/checksum")}
        let matches = try await children(parent).filter {$0["name"] as? String == name}
        guard matches.count == 1, matches[0]["id"] as? String == id else {throw JoeyError.dependency("Original archive name is ambiguous; no substitute downloaded")}
        let local = directory.appendingPathComponent("original."+(name as NSString).pathExtension)
        if FileManager.default.fileExists(atPath:local.path), (try? Integrity.md5(local)) == md5 {return local}
        try Persistence.checkDisk(at:directory,requiredBytes:bytes)
        let partial = directory.appendingPathComponent("original-download.partial")
        _ = try await Processes.retry {try await self.runHelper("rclone",["copyto",self.remote+":"+name,partial.path,"--drive-root-folder-id",parent,"--transfers","1","--checkers","1"])}
        guard try Integrity.md5(partial) == md5 else {throw JoeyError.failed("Downloaded original differs from existing archive bytes")}
        if FileManager.default.fileExists(atPath:local.path) {throw JoeyError.failed("Different existing local original preserved; cannot overwrite")}
        try FileManager.default.moveItem(at:partial,to:local)
        return local
    }
    /// Metadata is read by exact IDs, independently of rclone's path-based write.
    func verifyRoot(_ destination: DriveDestination) async throws -> [String:Any] {
        let chain = [destination.id] + destination.ancestorIDs
        var first: [String:Any] = [:]
        for (index,id) in chain.enumerated() {
            let value = try await metadata(id)
            guard value["id"] as? String == id, value["trashed"] as? Bool == false,
                  value["mimeType"] as? String == "application/vnd.google-apps.folder" else {
                throw JoeyError.dependency("Drive destination ancestry is unavailable or invalid: \(id)")
            }
            if index < chain.count-1, value["parents"] as? [String] != [chain[index+1]] {
                throw JoeyError.dependency("Drive destination ancestry changed at \(id); expected parent \(chain[index+1])")
            }
            if index == 0 {
                guard value["name"] as? String == destination.name else {throw JoeyError.dependency("Drive destination name changed: \(id), expected \(destination.name)")}
                _ = try Self.permissionFingerprint(value)
                first = value
            }
        }
        return first
    }
    func verifyLocation(parent: String, destination: FilingDestination) async throws -> [String:Any] {
        let root = try await verifyRoot(destination.destination)
        if destination.asset == .fullEpisode {
            guard parent == destination.rootID else {throw JoeyError.failed("Wrong full-episode parent: \(parent); expected \(destination.rootID)")}
            return root
        }
        let folder = try await metadata(parent)
        let props = folder["appProperties"] as? [String:String] ?? [:]
        guard folder["id"] as? String == parent, folder["trashed"] as? Bool == false,
              folder["mimeType"] as? String == "application/vnd.google-apps.folder",
              folder["parents"] as? [String] == [destination.rootID],
              props["joeySourceID"] == destination.sourceID, props["joeyOwner"] == destination.storedOwner,
              props["joeySourceSHA256"].map({$0 == destination.sourceSHA256}) ?? true else {
            throw JoeyError.failed("Episode folder identity/actual parent does not match authoritative destination \(destination.rootID): \(parent)")
        }
        _ = try Self.permissionFingerprint(folder)
        return folder
    }
    static func permissionFingerprint(_ metadata: [String:Any]) throws -> String {
        guard let permissions = metadata["permissions"] as? [[String:Any]], !permissions.isEmpty else {
            throw JoeyError.dependency("Drive sharing permissions could not be independently read")
        }
        let canonical = try permissions.map { permission -> String in
            guard permission["type"] as? String != nil,permission["role"] as? String != nil else {throw JoeyError.failed("Incomplete Drive permission")}
            return String(decoding:try JSONSerialization.data(withJSONObject:permission,options:[.sortedKeys]),as:UTF8.self)
        }.sorted().joined(separator:"\n")
        return Integrity.textHash(canonical)
    }
    static func archiveID(_ reference: String) throws -> String {
        guard let url = URL(string:reference),url.scheme == "https",url.host == "drive.google.com",
              url.user == nil,url.password == nil else {throw JoeyError.invalid("Archive reference must identify an existing Google Drive file")}
        let parts = url.pathComponents
        let id = parts.count >= 4 && parts[1] == "file" && parts[2] == "d" ? parts[3] :
            URLComponents(url:url,resolvingAgainstBaseURL:false)?.queryItems?.first(where:{$0.name == "id"})?.value
        guard let id,id.range(of:"^[A-Za-z0-9_-]{20,}$",options:.regularExpression) != nil else {throw JoeyError.invalid("Archive reference lacks a unique Drive file ID")}
        return id
    }
    public func upload(_ local: URL, name: String? = nil, parent: String, destination: FilingDestination, replaceCompanion: Bool = false) async throws -> DriveReceipt {
        let filename = name ?? local.lastPathComponent
        guard !filename.contains("/"), !filename.contains("\\"), !filename.isEmpty else { throw JoeyError.invalid("Unsafe remote filename") }
        if replaceCompanion, !(filename == "clip_manifest.json" || filename == "RECONCILE.md" ||
            filename.hasPrefix("Clip Index — ") && filename.hasSuffix(".csv") || filename.hasSuffix(" — Full Transcript.txt")) {
            throw JoeyError.invalid("Only canonical companion files may be updated")
        }
        let sha = try Integrity.sha256(local), md5 = try Integrity.md5(local)
        let bytes = ((try FileManager.default.attributesOfItem(atPath:local.path))[.size] as? NSNumber)?.int64Value ?? 0
        let parentInfo = try await verifyLocation(parent:parent,destination:destination)
        let parentPermissions = try Self.permissionFingerprint(parentInfo)
        var expectedPermissions: String?
        var existingID: String?
        for attempt in 0..<3 {
            let currentParent = try await verifyLocation(parent:parent,destination:destination)
            guard try Self.permissionFingerprint(currentParent) == parentPermissions else {throw JoeyError.failed("Destination sharing changed during filing; no permission changes attempted")}
            let contents = try await children(parent)
            if !replaceCompanion,contents.contains(where:{$0["name"] as? String != filename && $0["md5Checksum"] as? String == md5 && Int64($0["size"] as? String ?? "") == bytes}) {
                throw JoeyError.dependency("Equivalent media already exists under another filename in \(parent); no duplicate uploaded")
            }
            let matches = contents.filter {$0["name"] as? String == filename}
            guard matches.count <= 1 else { throw JoeyError.dependency("Duplicate remote filename: \(filename)") }
            if let match = matches.first, let id = match["id"] as? String {
                let before = try await metadata(id)
                if let existingID, existingID != id {throw JoeyError.failed("Remote file identity changed during filing")}
                existingID = id
                if expectedPermissions == nil {expectedPermissions = try Self.permissionFingerprint(before)}
                guard before["parents"] as? [String] == [parent], before["name"] as? String == filename,
                      try Self.permissionFingerprint(before) == expectedPermissions else {throw JoeyError.failed("Remote identity or sharing changed before upload")}
                if match["md5Checksum"] as? String == md5, Int64(match["size"] as? String ?? "") == bytes {
                    let receipt = try await verify(id:id,local:local,parent:parent,name:filename,sha:sha,md5:md5,bytes:bytes,
                        destination:destination,expectedPermissions:expectedPermissions!)
                    if replaceCompanion {try await readCompanion(local:local,receipt:receipt)}
                    return receipt
                }
                guard replaceCompanion else { throw JoeyError.failed("Existing remote file has different bytes; preserved: \(filename)") }
            } else {
                guard existingID == nil else {throw JoeyError.failed("Existing remote file disappeared; no replacement created")}
                // New children must inherit the destination's existing access.
                expectedPermissions = parentPermissions
            }
            if let capability = currentParent["capabilities"] as? [String:Bool], capability["canAddChildren"] == false {
                throw JoeyError.dependency("No write access to authoritative destination: \(parent)")
            }
            var args = ["copyto",local.path,remote+":"+filename,"--drive-root-folder-id",parent,"--retries","1","--low-level-retries","1","--transfers","1","--checkers","1"]
            args += replaceCompanion ? ["--ignore-times"] : ["--immutable"]
            var writeError: Error?
            do { _ = try await runHelper("rclone",args) }
            catch {if error is CancellationError {throw error};writeError = error}
            // Always reconcile the complete filename set, even if rclone lost
            // its response. A single matching hash cannot hide a second file.
            let after = try await children(parent).filter {$0["name"] as? String == filename}
            guard after.count <= 1 else {throw JoeyError.failed("Duplicate remote filename after upload: \(filename)")}
            if let file = after.first,let id = file["id"] as? String,
               file["md5Checksum"] as? String == md5,Int64(file["size"] as? String ?? "") == bytes {
                if let existingID, existingID != id {throw JoeyError.failed("Upload replaced the existing provider file identity")}
                let receipt = try await verify(id:id,local:local,parent:parent,name:filename,sha:sha,md5:md5,bytes:bytes,
                    destination:destination,expectedPermissions:expectedPermissions!)
                if replaceCompanion {try await readCompanion(local:local,receipt:receipt)}
                return receipt
            }
            if let blocked = writeError as? StorageBlocked {throw blocked}
            if attempt == 2 {throw writeError ?? JoeyError.failed("Upload has no unique integrity readback: \(filename)")}
            try await Task.sleep(nanoseconds:500_000_000)
        }
        throw JoeyError.failed("Upload reconciliation exhausted")
    }
    private func verify(id: String, local: URL, parent: String, name: String, sha: String, md5: String, bytes: Int64,
                        destination: FilingDestination?, expectedPermissions: String) async throws -> DriveReceipt {
        if let destination {_ = try await verifyLocation(parent:parent,destination:destination)}
        let value = try await metadata(id)
        let matches = try await children(parent).filter {$0["name"] as? String == name}
        guard value["id"] as? String == id, value["name"] as? String == name,
              value["trashed"] as? Bool == false, (value["parents"] as? [String]) == [parent],
              Int64(value["size"] as? String ?? "") == bytes, value["md5Checksum"] as? String == md5,
              (value["sha256Checksum"] as? String).map({$0 == sha}) ?? true,
              matches.count == 1,matches.first?["id"] as? String == id,
              try Integrity.sha256(local) == sha,
              try Self.permissionFingerprint(value) == expectedPermissions,
              let link = value["webViewLink"] as? String,let permissions = value["permissions"] as? [[String:Any]] else {
            throw JoeyError.failed("Independent Drive ID/name/parent/size/checksum/permissions/duplicate readback failed: \(id)")
        }
        return DriveReceipt(id:id,name:name,parent:parent,bytes:bytes,md5:md5,sha256:sha,url:link,
            permissions:permissions.map {"\($0["type"] as? String ?? "unknown"):\($0["role"] as? String ?? "unknown")"}.sorted(),verifiedAt:Date(),
            destination:destination,permissionFingerprint:expectedPermissions)
    }
    private func readCompanion(local: URL, receipt: DriveReceipt) async throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("joey-drive-readback-"+UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:temporary)}
        _ = try await runReadHelper("rclone",["copyto",remote+":"+receipt.name,temporary.path,"--drive-root-folder-id",receipt.parent,"--retries","1","--transfers","1","--checkers","1"])
        guard try Integrity.sha256(temporary) == receipt.sha256 else {throw JoeyError.failed("Downloaded companion bytes differ: \(receipt.name)")}
    }
    public func verifyPackage(job: JobRecord, directory: URL) async throws {
        guard job.hasRequiredCompletionEvidence, let source = job.source, let folder = job.folderID else {
            throw JoeyError.failed("Required QA, destination, companion or register evidence is incomplete")
        }
        let destination = try DestinationResolver.resolve(source:source,request:job.request,asset:.clip)
        for receipt in job.clips.compactMap(\.drive) + Array(job.companions.values) {
            guard let md5 = receipt.md5,let fingerprint = receipt.permissionFingerprint else {throw JoeyError.failed("Saved filing receipt lacks integrity/access proof: \(receipt.id)")}
            _ = try await verify(id:receipt.id,local:directory.appendingPathComponent(receipt.name),parent:folder,
                name:receipt.name,sha:receipt.sha256,md5:md5,bytes:receipt.bytes,destination:destination,expectedPermissions:fingerprint)
        }
        let names = try await children(folder).compactMap {$0["name"] as? String}
        guard names.filter({$0.hasPrefix("Clip Index")}).count == 1,
              Set(names.filter({$0.lowercased().hasSuffix(".mp4")})) == Set(job.clips.map(\.filename)) else {throw JoeyError.failed("Episode must contain one canonical Clip Index")}
    }
    public func resolveArtwork(source: SourceRecord, configuration: Configuration, root: URL) async throws -> Artwork {
        if source.owner == .dub, let art = configuration.dubArtwork { try art.file.validate(); return art }
        if let art = configuration.taxstoneArtwork[source.id] {
            guard art.owner == .taxstone, art.sourceID == source.id else { throw JoeyError.invalid("Taxstone artwork identity mismatch") }
            try art.file.validate(); return art
        }
        if source.owner == .dub {
            let id = "1fRg-Dfd-V_VdZQuPZVGDM3kdHD-qi6V1"
            let meta = try await metadata(id)
            guard let parent = (meta["parents"] as? [String])?.first, let name = meta["name"] as? String else { throw JoeyError.dependency("Approved DUB art metadata unavailable") }
            let local = root.appendingPathComponent("approved-dub-art.png")
            _ = try await runReadHelper("rclone",["copyto",remote+":"+name,local.path,"--drive-root-folder-id",parent])
            let sha = try Integrity.sha256(local)
            guard sha == "1522d2fbbbb6d943cd08cb07b617212be4fafcb841c7dcdba713fe81c4fdc790" else { throw JoeyError.failed("Approved DUB artwork bytes changed") }
            return Artwork(owner:.dub,sourceID:nil,driveID:id,file:EvidenceFile(path:local.path,sha256:sha,basis:"Exact approved Drive artwork"))
        }
        // Resolve episode-specific image from established source archive and
        // operational folders only. No universal example becomes an art master.
        let parents = ["1wQMwzUconRC3UCvH2jpL1kD__ctBv29p","1_DOLsqnp9SVeXG_Go82VdGAb6evs17pz","1fRaM_N4M4RnXYrlhcfr5l0vBJIZ4QULi"]
        for parent in parents {
            let matches = try await children(parent).filter {
                ($0["name"] as? String ?? "").contains(source.id) && ($0["mimeType"] as? String ?? "").hasPrefix("image/")
            }
            if matches.count == 1, let name = matches[0]["name"] as? String, let id = matches[0]["id"] as? String {
                let local = root.appendingPathComponent("taxstone-"+Persistence.safeName(source.id)+".art")
                _ = try await runReadHelper("rclone",["copyto",remote+":"+name,local.path,"--drive-root-folder-id",parent])
                return Artwork(owner:.taxstone,sourceID:source.id,driveID:id,file:EvidenceFile(path:local.path,sha256:try Integrity.sha256(local),basis:"Unique source-ID-matching image in established Taxstone archive"))
            }
        }
        throw JoeyError.dependency("Matching Taxstone artwork unresolved for \(source.id) after checking configured assets and established archive/operational folders")
    }
    private func registerRows(_ endpoint: String, matching headers: [String]? = nil) async throws -> [[Any]] {
        let object = try await request(endpoint,sheets:true)
        guard let rows = object["values"] as? [[Any]], let currentHeaders = rows.first as? [String] else {
            throw JoeyError.dependency("Master Link List current schema unavailable")
        }
        try Records.validateHeaders(currentHeaders)
        if let headers, currentHeaders != headers {
            throw JoeyError.dependency("Master Link List schema changed during reconciliation; retry requires a fresh schema read")
        }
        return rows
    }
    private func transientAppendFailure(_ error: Error) -> Bool {
        if let http = error as? ProviderHTTPError {return http.transient}
        guard let transport = error as? URLError else {return false}
        return [.timedOut,.networkConnectionLost,.cannotConnectToHost,.cannotFindHost,
                .dnsLookupFailed,.notConnectedToInternet].contains(transport.code)
    }
    public func reconcileRegister(job: JobRecord, tab: String) async throws -> [String] {
        guard DestinationResolver.requiresDUBRegister(job.request) else { return [] }
        let range = "'"+tab.replacingOccurrences(of:"'",with:"''")+"'!A1:AZ"
        let escaped = range.addingPercentEncoding(withAllowedCharacters:.urlPathAllowed)!
        let endpoint = "spreadsheets/"+Self.masterSheet+"/values/"+escaped
        let all = try await registerRows(endpoint)
        let headers = all[0].map {String(describing:$0)}
        var receipts: [String] = []
        for clip in job.clips {
            guard let drive = clip.drive else { throw JoeyError.failed("Cannot register unverified clip") }
            let values = try Records.registerValues(job:job,clip:clip,headers:headers)
            // Always fresh-read before a possible append, including retry after
            // a network error. Identity is the verified Drive file ID.
            var appendAttempts = 0
            var appendFailure: Error?
            while true {
                try Task.checkCancellation()
                let rows = try await registerRows(endpoint,matching:headers)
                let idColumn = headers.firstIndex(of:"Drive file ID")!
                let matches = rows.enumerated().filter {$0.offset > 0 && $0.element.count > idColumn && String(describing:$0.element[idColumn]) == drive.id}
                guard matches.count <= 1 else { throw JoeyError.dependency("Duplicate Master Link List rows for \(drive.id)") }
                if let match = matches.first {
                    let existing = match.element.map {String(describing:$0)}
                    // Only fill/update supported cells. Existing unknown columns,
                    // including formulas, are never cleared or overwritten.
                    for (column,value) in values where column >= existing.count || existing[column] != value {
                        let cell = "'"+tab.replacingOccurrences(of:"'",with:"''")+"'!"+Records.columnName(column)+String(match.offset+1)
                        let path = "spreadsheets/"+Self.masterSheet+"/values/"+cell.addingPercentEncoding(withAllowedCharacters:.urlPathAllowed)!
                        _ = try await request(path,method:"PUT",query:["valueInputOption":"RAW"],body:["values":[[value]]],sheets:true)
                    }
                    let fresh = try await registerRows(endpoint,matching:headers)
                    let found = fresh.enumerated().filter {$0.offset > 0 && $0.element.count > idColumn && String(describing:$0.element[idColumn]) == drive.id}
                    guard found.count == 1, values.allSatisfy({$0.key < found[0].element.count && String(describing:found[0].element[$0.key]) == $0.value}) else { throw JoeyError.failed("Master Link List required cell readback failed") }
                    receipts.append("\(tab)!\(found[0].offset+1):\(drive.id)"); break
                }
                // Even the final uncertain append gets read back above. Only
                // an absent identity plus a transient failure permits replay.
                if appendAttempts > 0 && appendFailure == nil {
                    throw JoeyError.failed("Master Link List successful append missing from readback; no additional append attempted")
                }
                if let appendFailure, !transientAppendFailure(appendFailure) {throw appendFailure}
                guard appendAttempts < 3 else {
                    throw appendFailure ?? JoeyError.failed("Register append/readback incomplete; retry will reconcile by file ID")
                }
                var row = Array(repeating:"",count:headers.count)
                for (column,value) in values { row[column] = value }
                appendAttempts += 1
                do {
                    _ = try await request(endpoint+":append",method:"POST",query:["valueInputOption":"RAW","insertDataOption":"INSERT_ROWS"],body:["values":[row]],sheets:true)
                    appendFailure = nil
                } catch is CancellationError {throw CancellationError()}
                catch let error as URLError where error.code == .cancelled {throw CancellationError()}
                catch let error as ProviderHTTPError where !error.transient {throw error}
                catch {appendFailure = error}
                // Successful append still loops through exact readback.
            }
        }
        guard receipts.count == job.clips.count else { throw JoeyError.failed("Register append/readback incomplete; retry will reconcile by file ID") }
        return receipts
    }
}

private extension ISO8601DateFormatter {
    static var fractional: ISO8601DateFormatter {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime,.withFractionalSeconds]; return f
    }
}
