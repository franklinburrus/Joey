import Foundation

public actor DriveDelivery {
    public static let videoRoot = "1fgABGYTtNC_h2u-v6fwTcPkVKjFd7GQx"
    public static let audioRoot = "1_s2K9Pw2Je93IwazQ6QgLjz_SimVYuPz"
    public static let masterSheet = "17uhDO06vmVEz96YrUnA6aHyV5fL_3AAs3ylOjrYRLwI"
    private let remote: String
    private var token: String?
    private let session: URLSession
    public init(remote: String, session: URLSession = .shared) throws {
        guard remote.range(of:"^[A-Za-z0-9_-]+$",options:.regularExpression) != nil else { throw JoeyError.invalid("Invalid existing rclone remote name") }
        self.remote = remote; self.session = session
    }
    public func preflight(tab: String) async throws -> [String:String] {
        var result: [String:String] = [:]
        for id in [Self.videoRoot,Self.audioRoot] {
            let info = try await metadata(id)
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
        _ = try await Processes.run("rclone",["lsjson",remote+":","--drive-root-folder-id",Self.videoRoot,"--max-depth","1"])
        let config = try await Processes.run("rclone",["config","dump"],maxOutput:1024*1024)
        guard let root = try JSONSerialization.jsonObject(with:config.stdout) as? [String:Any],
              let entry = root[remote] as? [String:Any], entry["type"] as? String == "drive",
              let raw = entry["token"] as? String, let data = raw.data(using:.utf8),
              let value = try JSONSerialization.jsonObject(with:data) as? [String:Any],
              let access = value["access_token"] as? String, !access.isEmpty else { throw JoeyError.dependency("Existing rclone remote does not expose a usable authorized Drive OAuth token") }
        token = access
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
            let (data,response) = try await Self.response(for:req,session:session)
            guard let http = response as? HTTPURLResponse else { throw JoeyError.failed("Missing provider HTTP response") }
            if http.statusCode == 401 && attempt == 0 { token = nil; try await authenticate(); continue }
            guard (200..<300).contains(http.statusCode) else {
                let obj = try? JSONSerialization.jsonObject(with:data) as? [String:Any]
                let error = obj?["error"] as? [String:Any]
                throw JoeyError.dependency("\(sheets ? "Sheets":"Drive") HTTP \(http.statusCode): \(error?["message"] as? String ?? "provider rejected request")")
            }
            return (try JSONSerialization.jsonObject(with:data) as? [String:Any]) ?? [:]
        }
        throw JoeyError.dependency("Provider authorization refresh failed")
    }
    /// Retry transient reads only. Mutations retain their caller's explicit
    /// readback/reconciliation loop, so an uncertain append is never replayed here.
    static func response(for request: URLRequest, session: URLSession) async throws -> (Data,URLResponse) {
        let fetch = {
            let result = try await session.data(for:request)
            if let http = result.1 as? HTTPURLResponse,
               [429,500,502,503,504].contains(http.statusCode) {
                throw JoeyError.dependency("Provider HTTP \(http.statusCode): transient request failure")
            }
            return result
        }
        if request.httpMethod == nil || request.httpMethod == "GET" {
            return try await Processes.retry(fetch)
        }
        return try await fetch()
    }
    func metadata(_ id: String) async throws -> [String:Any] {
        try await request("files/"+id,query:["fields":"id,name,mimeType,parents,size,md5Checksum,sha256Checksum,webViewLink,trashed,permissions(type,role,allowFileDiscovery),appProperties,createdTime"])
    }
    func children(_ parent: String) async throws -> [[String:Any]] {
        var all: [[String:Any]] = [], page: String?
        repeat {
            var query = ["q":"'\(parent)' in parents and trashed=false","fields":"nextPageToken,files(id,name,mimeType,size,md5Checksum,appProperties)","pageSize":"1000"]
            if let page { query["pageToken"] = page }
            let result = try await request("files",query:query)
            all += result["files"] as? [[String:Any]] ?? []; page = result["nextPageToken"] as? String
        } while page != nil
        return all
    }
    public func episodeFolder(source: SourceRecord, jobID: String, intentURL: URL) async throws -> String {
        let root = source.kind == .nativeVideo ? Self.videoRoot : Self.audioRoot
        let rootInfo = try await metadata(root)
        guard rootInfo["mimeType"] as? String == "application/vnd.google-apps.folder", rootInfo["trashed"] as? Bool != true else { throw JoeyError.dependency("Authoritative Joey root unavailable") }
        let name = "\(source.episodeDate ?? "Date Unknown") — \(Persistence.safeName(source.title)) — \(Persistence.safeName(source.id))"
        let existing = try await children(root)
        let matching = existing.filter { file in
            let props = file["appProperties"] as? [String:String]
            return props?["joeySourceID"] == source.id && props?["joeyOwner"] == source.owner.rawValue || file["name"] as? String == name
        }
        guard matching.count <= 1 else { throw JoeyError.dependency("Duplicate matching source folders require reconciliation; no new folder created") }
        if let found = matching.first, let id = found["id"] as? String {
            let props = found["appProperties"] as? [String:String]
            if props?["joeyOwner"] != source.owner.rawValue || props?["joeySourceID"] != source.id {
                let intent: [String:String]? = try? Persistence.load(intentURL)
                let meta = try await metadata(id)
                let created = ISO8601DateFormatter.fractional.date(from:meta["createdTime"] as? String ?? "")
                    ?? ISO8601DateFormatter().date(from:meta["createdTime"] as? String ?? "")
                let started = ISO8601DateFormatter().date(from:intent?["started"] ?? "")
                guard intent?["root"] == root, intent?["name"] == name, intent?["jobID"] == jobID,
                      let created, let started, created >= started,
                      props?["joeyOwner"] == nil, props?["joeySourceID"] == nil,
                      try await children(id).isEmpty else {
                    throw JoeyError.dependency("Existing folder lacks matching Joey ownership/source identity or a recoverable creation intent: \(id)")
                }
                _ = try await request("files/"+id,method:"PATCH",query:["fields":"id,appProperties"],body:["appProperties":["joeySourceID":source.id,"joeyOwner":source.owner.rawValue,"joeyJobID":jobID]])
                let fresh = try await metadata(id)
                guard (fresh["appProperties"] as? [String:String])?["joeyOwner"] == source.owner.rawValue else {throw JoeyError.failed("Recovered folder tagging readback failed")}
            }
            return id
        }
        // rclone creates the folder; an uncertain mkdir is reconciled by listing.
        try Persistence.save(["root":root,"name":name,"jobID":jobID,"started":ISO8601DateFormatter().string(from:Date())],to:intentURL)
        do { _ = try await Processes.run("rclone",["mkdir",remote+":"+name,"--drive-root-folder-id",root]) }
        catch { if try await children(root).filter({$0["name"] as? String == name}).isEmpty { throw error } }
        let matches = try await children(root).filter {$0["name"] as? String == name}
        guard matches.count == 1, let id = matches[0]["id"] as? String else { throw JoeyError.failed("Cannot read back unique episode folder") }
        _ = try await request("files/"+id,method:"PATCH",query:["fields":"id,appProperties"],body:["appProperties":["joeySourceID":source.id,"joeyOwner":source.owner.rawValue,"joeyJobID":jobID]])
        let fresh = try await metadata(id)
        guard (fresh["parents"] as? [String])?.contains(root) == true,
              (fresh["appProperties"] as? [String:String])?["joeyOwner"] == source.owner.rawValue else { throw JoeyError.failed("Episode folder identity readback failed") }
        return id
    }
    public func archive(source: SourceRecord, request: JobRequest) async throws -> String {
        let allowedRoots = ["1IIYLVDhCvwf5ZoMb0aM5vpSCe-eMCmyK","1GpuGWGIbSt3afwsi9L782soT9WJKOHS9","1wQMwzUconRC3UCvH2jpL1kD__ctBv29p"]
        if let reference = source.archiveReference {
            let parts = reference.components(separatedBy:CharacterSet(charactersIn:"/?=&"))
            guard let id = parts.first(where:{$0.range(of:"^[A-Za-z0-9_-]{20,}$",options:.regularExpression) != nil}) else {throw JoeyError.dependency("Archive reference must identify the verified existing original Drive file")}
            let info = try await metadata(id)
            guard info["trashed"] as? Bool != true,
                  Int64(info["size"] as? String ?? "") == source.bytes,
                  info["md5Checksum"] as? String == (try Integrity.md5(URL(fileURLWithPath:source.path))),
                  let link = info["webViewLink"] as? String else {throw JoeyError.failed("Existing archive is not byte-equivalent to the complete original")}
            return link
        }
        let root: String?
        if let explicit = request.archiveRootID {root = explicit}
        else if source.owner == .taxstone {root = allowedRoots[2]}
        else if source.originalURL?.contains("/broadcasts/") == true {root = allowedRoots[1]}
        else {root = nil}
        guard let root, allowedRoots.contains(root), (source.owner == .taxstone) == (root == allowedRoots[2]) else {
            throw JoeyError.dependency("New original needs its established full-length archive root; no source relocation or guessed archive destination")
        }
        let local = URL(fileURLWithPath:source.path), md5 = try Integrity.md5(local)
        let equivalent = try await children(root).filter {$0["md5Checksum"] as? String == md5 && Int64($0["size"] as? String ?? "") == source.bytes}
        if let file = equivalent.first, let id = file["id"] as? String {
            let info = try await metadata(id)
            guard let link = info["webViewLink"] as? String, (info["parents"] as? [String])?.contains(root) == true,
                  info["md5Checksum"] as? String == md5 else {throw JoeyError.failed("Original archive reuse readback failed")}
            return link
        }
        let name = (source.episodeDate ?? "Date Unknown")+" — "+Persistence.safeName(source.title)+" — "+Persistence.safeName(source.id)+"."+local.pathExtension
        return try await upload(local,name:name,parent:root).url
    }
    public func downloadOriginal(reference: String, directory: URL) async throws -> URL {
        let parts = reference.components(separatedBy:CharacterSet(charactersIn:"/?=&"))
        guard let id = parts.first(where:{$0.range(of:"^[A-Za-z0-9_-]{20,}$",options:.regularExpression) != nil}) else {throw JoeyError.invalid("Invalid original archive reference")}
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
        _ = try await Processes.retry {try await Processes.run("rclone",["copyto",self.remote+":"+name,partial.path,"--drive-root-folder-id",parent,"--transfers","1","--checkers","1"])}
        guard try Integrity.md5(partial) == md5 else {throw JoeyError.failed("Downloaded original differs from existing archive bytes")}
        if FileManager.default.fileExists(atPath:local.path) {throw JoeyError.failed("Different existing local original preserved; cannot overwrite")}
        try FileManager.default.moveItem(at:partial,to:local)
        return local
    }
    public func upload(_ local: URL, name: String? = nil, parent: String, replaceCompanion: Bool = false) async throws -> DriveReceipt {
        let filename = name ?? local.lastPathComponent
        guard !filename.contains("/"), !filename.contains("\\"), !filename.isEmpty else { throw JoeyError.invalid("Unsafe remote filename") }
        let sha = try Integrity.sha256(local), md5 = try Integrity.md5(local)
        let bytes = ((try FileManager.default.attributesOfItem(atPath:local.path))[.size] as? NSNumber)?.int64Value ?? 0
        for attempt in 0..<3 {
            let matches = try await children(parent).filter {$0["name"] as? String == filename}
            guard matches.count <= 1 else { throw JoeyError.dependency("Duplicate remote filename: \(filename)") }
            if let match = matches.first, let id = match["id"] as? String {
                if match["md5Checksum"] as? String == md5, Int64(match["size"] as? String ?? "") == bytes {
                    return try await verify(id:id,local:local,parent:parent,name:filename,sha:sha,md5:md5,bytes:bytes)
                }
                guard replaceCompanion else { throw JoeyError.failed("Existing remote file has different bytes; preserved: \(filename)") }
            }
            var args = ["copyto",local.path,remote+":"+filename,"--drive-root-folder-id",parent,"--retries","1","--low-level-retries","1","--transfers","1","--checkers","1"]
            args += replaceCompanion ? ["--ignore-times"] : ["--immutable"]
            do { _ = try await Processes.run("rclone",args) }
            catch {
                if error is CancellationError { throw error }
                // Re-list before retry: provider may have committed the write.
                let after = try await children(parent).filter {$0["name"] as? String == filename && $0["md5Checksum"] as? String == md5}
                if after.count == 1, let id = after[0]["id"] as? String {
                    return try await verify(id:id,local:local,parent:parent,name:filename,sha:sha,md5:md5,bytes:bytes)
                }
                if attempt == 2 { throw error }
                try await Task.sleep(nanoseconds:500_000_000)
            }
        }
        let matches = try await children(parent).filter {$0["name"] as? String == filename}
        guard matches.count == 1, let id = matches[0]["id"] as? String else { throw JoeyError.failed("Upload has no unique readback") }
        return try await verify(id:id,local:local,parent:parent,name:filename,sha:sha,md5:md5,bytes:bytes)
    }
    private func verify(id: String, local: URL, parent: String, name: String, sha: String, md5: String, bytes: Int64) async throws -> DriveReceipt {
        let value = try await metadata(id)
        guard value["id"] as? String == id, value["name"] as? String == name,
              value["trashed"] as? Bool != true, (value["parents"] as? [String]) == [parent],
              Int64(value["size"] as? String ?? "") == bytes, value["md5Checksum"] as? String == md5,
              let link = value["webViewLink"] as? String, let permissions = value["permissions"] as? [[String:Any]] else {
            throw JoeyError.failed("Independent Drive name/parent/size/checksum/link/access readback failed: \(id)")
        }
        return DriveReceipt(id:id,name:name,parent:parent,bytes:bytes,md5:md5,sha256:sha,url:link,
            permissions:permissions.map {"\($0["type"] as? String ?? "unknown"):\($0["role"] as? String ?? "unknown")"}.sorted(),verifiedAt:Date())
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
            _ = try await Processes.run("rclone",["copyto",remote+":"+name,local.path,"--drive-root-folder-id",parent])
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
                _ = try await Processes.run("rclone",["copyto",remote+":"+name,local.path,"--drive-root-folder-id",parent])
                return Artwork(owner:.taxstone,sourceID:source.id,driveID:id,file:EvidenceFile(path:local.path,sha256:try Integrity.sha256(local),basis:"Unique source-ID-matching image in established Taxstone archive"))
            }
        }
        throw JoeyError.dependency("Matching Taxstone artwork unresolved for \(source.id) after checking configured assets and established archive/operational folders")
    }
    public func reconcileRegister(job: JobRecord, tab: String) async throws -> [String] {
        guard job.request.owner == .dub else { return [] }
        let range = "'"+tab.replacingOccurrences(of:"'",with:"''")+"'!A1:AZ"
        let escaped = range.addingPercentEncoding(withAllowedCharacters:.urlPathAllowed)!
        let endpoint = "spreadsheets/"+Self.masterSheet+"/values/"+escaped
        let object = try await request(endpoint,sheets:true)
        guard let all = object["values"] as? [[Any]], let first = all.first else { throw JoeyError.dependency("Master Link List current schema unavailable") }
        let headers = first.map {String(describing:$0)}
        try Records.validateHeaders(headers)
        var receipts: [String] = []
        for clip in job.clips {
            guard let drive = clip.drive else { throw JoeyError.failed("Cannot register unverified clip") }
            let values = try Records.registerValues(job:job,clip:clip,headers:headers)
            // Always fresh-read before a possible append, including retry after
            // a network error. Identity is the verified Drive file ID.
            for attempt in 0..<3 {
                let current = try await request(endpoint,sheets:true)
                let rows = current["values"] as? [[Any]] ?? []
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
                    let fresh = try await request(endpoint,sheets:true)["values"] as? [[Any]] ?? []
                    let found = fresh.enumerated().filter {$0.offset > 0 && $0.element.count > idColumn && String(describing:$0.element[idColumn]) == drive.id}
                    guard found.count == 1, values.allSatisfy({$0.key < found[0].element.count && String(describing:found[0].element[$0.key]) == $0.value}) else { throw JoeyError.failed("Master Link List required cell readback failed") }
                    receipts.append("\(tab)!\(found[0].offset+1):\(drive.id)"); break
                }
                var row = Array(repeating:"",count:headers.count)
                for (column,value) in values { row[column] = value }
                do { _ = try await request(endpoint+":append",method:"POST",query:["valueInputOption":"RAW","insertDataOption":"INSERT_ROWS"],body:["values":[row]],sheets:true) }
                catch { if attempt == 2 { throw error } }
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
