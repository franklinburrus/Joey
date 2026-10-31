import Foundation

public enum Records {
    public static func columnName(_ index: Int) -> String {
        var n = index+1, name = ""
        while n > 0 { n -= 1; name = String(UnicodeScalar(65+n%26)!)+name; n /= 26 }; return name
    }
    public static func validateHeaders(_ headers: [String]) throws {
        guard Set(headers.filter {!$0.isEmpty}).count == headers.filter({!$0.isEmpty}).count,
              ["Clip #","Title","Start","End","Duration (sec)","Public link","Drive file ID","Episode key","Filename"].allSatisfy(headers.contains) else {
            throw JoeyError.dependency("Master Link List schema lacks unique required identity/clip fields; no schema change attempted")
        }
    }
    public static func registerValues(job: JobRecord, clip: ClipRecord, headers: [String]) throws -> [Int:String] {
        try validateHeaders(headers)
        guard let source = job.source, let drive = clip.drive, let folder = job.folderID,
              let duration = clip.measuredDuration else { throw JoeyError.failed("Incomplete verified register input") }
        let index = job.companions.first {$0.key.hasPrefix("Clip Index") }?.value.url ?? ""
        let values: [String:String] = ["Broadcast date":source.episodeDate ?? "Date Unknown","Clip #":String(clip.id),"Title":clip.title,
            "Start":String(format:"%.6f",clip.intervals.first!.start),"End":String(format:"%.6f",clip.intervals.last!.end),
            "Duration (sec)":String(format:"%.6f",duration),"Public link":drive.url,"Drive file ID":drive.id,
            "Source broadcast URL":source.originalURL ?? "","Content type":source.kind.rawValue,"Episode key":source.id,
            "Show sequence":String(clip.id),"Episode folder link":"https://drive.google.com/drive/folders/"+folder,
            "Episode Clip Index link":index,"Filename":clip.filename,"Parent block or associated asset":source.archiveReference ?? "",
            "Public-access status":drive.permissions.contains("anyone:reader") ? "Existing anyone-with-link read access":"Existing permissions preserved",
            "Episode-index status":"Verified","Metadata verification status":"Drive integrity and automatic QA passed",
            "Last verified":ISO8601DateFormatter().string(from:drive.verifiedAt),"Notes or legacy exception":"Joey job \(job.id); \(clip.durationException ?? ""); no social publication",
            "Workflow route":"Joey","Asset class":source.kind == .audio ? "Audio-template MP4":"Native-video clip",
            "Platform destination":"Shared X + Instagram","Block number":String(clip.id)]
        return Dictionary(uniqueKeysWithValues:headers.enumerated().compactMap { index,header in values[header].map {(index,$0)} })
    }
    public static func csv(_ rows: [[String]]) -> String {
        rows.map {row in row.map {value in
            // Spreadsheet formula injection protection for user/source titles.
            let safe = ["=","+","-","@"].contains(value.first.map(String.init) ?? "") ? "'"+value : value
            return "\""+safe.replacingOccurrences(of:"\"",with:"\"\"")+"\""
        }.joined(separator:",")}.joined(separator:"\r\n")+"\r\n"
    }
    public static func write(job: JobRecord, directory: URL) throws -> [URL] {
        guard let source = job.source, let transcript = job.transcript else { throw JoeyError.failed("Source/transcript missing from delivery package") }
        let base = Persistence.safeName(source.title)+" — "+Persistence.safeName(source.id)
        let index = directory.appendingPathComponent("Clip Index — "+base+".csv")
        var rows = [["Clip #","Title","Source intervals (seconds)","Measured duration (seconds)","Filename","Source ID","Verified Drive link","QA"]]
        for clip in job.clips {
            rows.append([String(clip.id),clip.title,clip.intervals.map {String(format:"%.6f–%.6f",$0.start,$0.end)}.joined(separator:"; "),
                clip.measuredDuration.map {String(format:"%.6f",$0)} ?? "",clip.filename,source.id,clip.drive?.url ?? "",clip.qa?.passed == true ? "PASSED":"NOT PASSED"])
        }
        try csv(rows).write(to:index,atomically:true,encoding:.utf8)
        let text = directory.appendingPathComponent(base+" — Full Transcript.txt")
        let header = "Source: \(source.title)\nSource ID: \(source.id)\nSource SHA-256: \(source.sha256)\nDuration: \(source.duration) seconds\nTranscription: \(transcript.engine); automatic speech recognition is not infallible.\n\n"
        try (header+transcript.segments.map {String(format:"[%.3f – %.3f] ",$0.start,$0.end)+$0.text}.joined(separator:"\n")).write(to:text,atomically:true,encoding:.utf8)
        let reconcile = directory.appendingPathComponent("RECONCILE.md")
        let accepted = job.clips.filter {$0.qa?.passed == true}.count, filed = job.clips.filter {$0.drive != nil}.count
        let summary = """
        # Joey reconciliation

        Source: \(source.title) — \(source.id)
        Owner: \(source.owner.rawValue)
        State: \(job.state.rawValue)
        Stage: \(job.stage)
        Planned clips: \(job.clips.count)
        Automatic QA passed: \(accepted)
        Independently verified Drive clips: \(filed)
        Required register rows read back: \(job.registerRows.count)
        Coverage: \(job.request.mode.rawValue); exact fractional source/output mappings are in clip_manifest.json.
        Exclusions: \(job.exclusions.count); uncertain material retained.
        Failure/dependency: \(job.error ?? "None recorded")

        One shared file per clip for X and Instagram. No social publication or email.
        Native frames retain proportions with black padding; source resolution and effective dimensions are in each QA record.
        Automated decoding, signal and sampled-image checks do not guarantee semantic perfection or platform ingestion.
        The canonical Clip Index is CSV; no duplicate native index is created.
        The manifest does not contain its own checksum. The local durable job checkpoint stores its independent final Drive receipt to avoid circular hashes.
        """
        try summary.write(to:reconcile,atomically:true,encoding:.utf8)
        let manifest = directory.appendingPathComponent("clip_manifest.json")
        // Explicit interval mapping also records output offsets across ad joins.
        var object = try JSONSerialization.jsonObject(with:Persistence.encoder.encode(job)) as! [String:Any]
        object["intervalMappings"] = job.clips.map { clip -> [String:Any] in
            var cursor = 0.0
            let ranges = clip.intervals.map { range -> [String:Double] in
                defer {cursor += range.duration}
                return ["sourceStart":range.start,"sourceEnd":range.end,"outputStart":cursor,"outputEnd":cursor+range.duration]
            }
            return ["filename":clip.filename,"intervals":ranges]
        }
        object["encodingToleranceSeconds"] = 0.075
        object["coverageArithmeticToleranceSeconds"] = Planning.tolerance
        var companions = object["companions"] as? [String:Any] ?? [:]
        companions.removeValue(forKey:"clip_manifest.json"); companions.removeValue(forKey:"RECONCILE.md")
        object["companions"] = companions
        try JSONSerialization.data(withJSONObject:object,options:[.prettyPrinted,.sortedKeys,.withoutEscapingSlashes]).write(to:manifest,options:.atomic)
        return [index,text,reconcile,manifest]
    }
}
