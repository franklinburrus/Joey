import Foundation

public enum Records {
    /// Cached companion absence is not evidence that a verified remote object
    /// disappeared. When the manifest is present, its receipt and acceptance
    /// inputs must agree before the completed fast path can reuse it offline.
    public static func validateSavedManifest(job: JobRecord, directory: URL) throws {
        let url = directory.appendingPathComponent("clip_manifest.json")
        guard FileManager.default.fileExists(atPath:url.path) else {return}
        guard let receipt = job.companions[url.lastPathComponent],
              try Integrity.sha256(url) == receipt.sha256 else {
            throw JoeyError.failed("Saved manifest differs from its verified receipt; preserved for reconciliation")
        }
        let manifest: JobRecord = try Persistence.load(url)
        try manifest.validateAcceptedPlan()
        let object = try JSONSerialization.jsonObject(with:Data(contentsOf:url)) as? [String:Any]
        let mappings = object?["intervalMappings"] as? [[String:Any]]
        guard try manifest.acceptancePlanHash() == job.acceptancePlanHash(),
              let mappings, NSArray(array:mappings).isEqual(to:intervalMappings(job)) else {
            throw JoeyError.failed("Saved manifest disagrees with the complete accepted plan; preserved for reconciliation")
        }
    }
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
            "Platform destination":job.request.productionWorkflow == .joeBudden ? "Drive only; no platform ingestion claim":"Shared X + Instagram","Block number":String(clip.id)]
        return Dictionary(uniqueKeysWithValues:headers.enumerated().compactMap { index,header in values[header].map {(index,$0)} })
    }

    /// Build the separate Taxstone register row. Buffer identifiers remain
    /// empty: filing and register reconciliation do not claim publication.
    public static func taxstoneRegisterValues(job: JobRecord, clip: ClipRecord) throws -> [String] {
        guard job.request.owner == .taxstone,
              let source = job.source, let drive = clip.drive, let folder = job.folderID,
              let duration = clip.measuredDuration, clip.qa?.passed == true,
              let hash = clip.sha256, let bytes = clip.bytes else {
            throw JoeyError.failed("Incomplete verified Taxstone register input")
        }
        let episodeID = source.id.replacingOccurrences(of:"soundcloud:",with:"")
        let transcriptName = companionNames(source:source).first { $0.hasSuffix(" — Full Transcript.txt") }
        let transcriptEvidence: String
        if let transcriptName, let receipt = job.companions[transcriptName] {
            transcriptEvidence = "DRIVE:\(receipt.id); SHA-256:\(receipt.sha256)"
        } else {
            transcriptEvidence = "LOCAL:source-bound transcript in job checkpoint"
        }
        let runID = "joey-taxstone-\(job.id)"
        let packageIdentity = job.request.mode == .fullShow ? "FULLSHOW" :
            "HIGHLIGHTS_"+Persistence.safeName(job.id)
        let values: [String:String] = [
            "Clip #":String(clip.id),
            "Derivative ID":String(format:"taxstone-%@-C%02d_JOEY_%@",episodeID,clip.id,packageIdentity),
            "Friendly Title":clip.title,
            "Episode":source.title,
            "Episode ID":episodeID,
            "Episode Date":source.episodeDate ?? "",
            "Parent Source Drive File ID":archiveID(source.archiveReference) ?? "",
            "Source Filename":URL(fileURLWithPath:source.path).lastPathComponent,
            "Start":String(format:"%.6f",clip.intervals.first?.start ?? 0),
            "End":String(format:"%.6f",clip.intervals.last?.end ?? 0),
            "Duration":String(format:"%.6f",duration),
            "Transcript Status":"COMPLETE_TIMESTAMPED_LOCAL_EVIDENCE",
            "Transcript Evidence / File ID":transcriptEvidence,
            "Source Clip File ID":drive.id,
            "Buffer Delivery File ID":"",
            "Buffer Delivery Link":"",
            "Technical Status":"PASS",
            "Duplicate Status":"NEW_PACKAGE; HISTORICAL_SOURCE_ROWS_PRESERVED",
            "Title Status":"PASS",
            "Manifest Status":"VERIFIED_CLIP_MANIFEST",
            "QA Status":"PASS",
            "READY_FOR_BUFFER":"YES",
            "Review / Exception Reason":"One native Joey Full Show package; no social publication or scheduling authorized.",
            "Delivery Status":"FILED_NOT_PUBLISHED",
            "Last Updated":ISO8601DateFormatter().string(from:drive.verifiedAt),
            "Run ID":runID,
            "Control Center Job ID":job.id
        ]
        let row = TaxstoneRegisterContract.headers.map {values[$0] ?? ""}
        guard row.count == TaxstoneRegisterContract.headers.count,
              row[TaxstoneRegisterContract.sourceClipIDColumn] == drive.id,
              row[TaxstoneRegisterContract.jobIDColumn] == job.id,
              bytes > 0, hash.count == 64, !folder.isEmpty else {
            throw JoeyError.failed("Taxstone register row identity is incomplete")
        }
        return row
    }

    /// Adopt a preserved external receipt and its complete Sheets readback into
    /// Joey's native checkpoint. This validates evidence only; it never calls a
    /// provider or claims Joey performed the historical write.
    public static func adoptTaxstoneRegisterEvidence(job: JobRecord, receiptData: Data,
                                                       readbackData: Data) throws -> TaxstoneRegisterEvidence {
        guard job.request.owner == .taxstone, job.request.mode == .fullShow,
              job.request.fileToDrive, job.state == .completed,
              job.completionReconciliationRequired != true,
              job.registerRows.isEmpty, job.taxstoneRegisterEvidence == nil,
              let source = job.source, source.owner == .taxstone,
              source.id == job.request.sourceID, source.title == job.request.title,
              source.id.hasPrefix("soundcloud:"), source.kind == .audio, source.hasAudio,
              source.sha256.count == 64,
              job.request.expectedSourceSHA256 == nil || job.request.expectedSourceSHA256 == source.sha256,
              archiveID(job.request.archiveReference) != nil,
              archiveID(job.request.archiveReference) == archiveID(source.archiveReference),
              let folderID = job.folderID, job.hasRequiredPackageEvidence else {
            throw JoeyError.failed("Only a completed, package-verified Taxstone Full Show checkpoint without register evidence can adopt a readback")
        }
        try job.validateAcceptedPlan()
        let sourceURL = URL(fileURLWithPath:source.path)
        let sourceValues = try sourceURL.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
        guard sourceValues.isRegularFile == true, sourceValues.isSymbolicLink != true,
              let sourceBytes = sourceValues.fileSize, Int64(sourceBytes) == source.bytes,
              try Integrity.sha256(sourceURL) == source.sha256 else {
            throw JoeyError.failed("Taxstone archive bytes do not match the accepted source hash")
        }
        try validateSavedManifest(job:job,directory:sourceURL.deletingLastPathComponent())

        guard let receipt = try JSONSerialization.jsonObject(with:receiptData) as? [String:Any],
              receipt["schemaVersion"] as? Int == 1,
              receipt["jobID"] as? String == job.id,
              receipt["sourceID"] as? String == source.id,
              receipt["folderID"] as? String == folderID,
              receipt["spreadsheetId"] as? String == TaxstoneRegisterContract.spreadsheetID,
              receipt["tab"] as? String == TaxstoneRegisterContract.tab,
              let updatedRangeText = receipt["updatedRange"] as? String,
              let rowsReadBack = receipt["rowsReadBack"] as? Int, rowsReadBack == job.clips.count,
              let sourceRowsAfterWrite = receipt["sourceRowsAfterWrite"] as? Int,
              sourceRowsAfterWrite >= rowsReadBack,
              receipt["exactRowsMatch"] as? Bool == true,
              receipt["newDriveIDsUnique"] as? Bool == true,
              receipt["publication"] as? Bool == false,
              receipt["scheduling"] as? Bool == false,
              let observedAtText = receipt["observedAt"] as? String,
              let observedAt = ISO8601DateFormatter().date(from:observedAtText),
              let updatedRange = parseSheetRange(updatedRangeText),
              updatedRange.tab == TaxstoneRegisterContract.tab,
              updatedRange.startColumn == 1, updatedRange.endColumn == TaxstoneRegisterContract.headers.count,
              updatedRange.endRow - updatedRange.startRow + 1 == rowsReadBack else {
            throw JoeyError.failed("External Taxstone receipt identity, scope, or readback claims are invalid")
        }
        guard let readback = try JSONSerialization.jsonObject(with:readbackData) as? [String:Any],
              let readbackRangeText = readback["range"] as? String,
              let readbackRange = parseSheetRange(readbackRangeText),
              readbackRange.tab == TaxstoneRegisterContract.tab,
              readbackRange.startColumn == 1, readbackRange.startRow == 1,
              readbackRange.endColumn == TaxstoneRegisterContract.headers.count,
              readbackRange.endRow >= updatedRange.endRow,
              readback["majorDimension"] as? String == "ROWS",
              let rawRows = readback["values"] as? [[Any]], rawRows.count == readbackRange.endRow else {
            throw JoeyError.failed("Taxstone register readback range or row data is incomplete")
        }
        let values = try rawRows.map { row -> [String] in
            guard row.count == TaxstoneRegisterContract.headers.count else {
                throw JoeyError.failed("Taxstone register readback row has the wrong schema width")
            }
            return try row.map { cell in
                if cell is NSNull {return ""}
                if let text = cell as? String {return text}
                if let number = cell as? NSNumber {return number.stringValue}
                throw JoeyError.failed("Taxstone register readback contains an unsupported cell value")
            }
        }
        guard values.first == TaxstoneRegisterContract.headers else {
            throw JoeyError.failed("Taxstone register readback schema changed; no evidence adopted")
        }
        let allRows = Array(values.dropFirst()).enumerated().map {(rowNumber:$0.offset+2,values:$0.element)}
        let updateRows = allRows.filter {$0.rowNumber >= updatedRange.startRow && $0.rowNumber <= updatedRange.endRow}
        let jobRows = allRows.filter {$0.values[TaxstoneRegisterContract.jobIDColumn] == job.id}
        guard updateRows.count == rowsReadBack, jobRows.count == rowsReadBack,
              updateRows.map(\.rowNumber) == jobRows.map(\.rowNumber) else {
            throw JoeyError.failed("Taxstone receipt range does not contain exactly the job's read-back rows")
        }

        guard archiveID(source.archiveReference) != nil else {
            throw JoeyError.failed("Accepted Taxstone source has no verified archive ID")
        }
        let expectedDriveIDs = job.clips.compactMap {$0.drive?.id}
        guard expectedDriveIDs.count == job.clips.count, Set(expectedDriveIDs).count == job.clips.count else {
            throw JoeyError.failed("Accepted Taxstone job has missing or duplicate Drive clip IDs")
        }
        let globalDriveRows = Dictionary(grouping:allRows,by:{$0.values[TaxstoneRegisterContract.sourceClipIDColumn]})
        let jobsByDriveID = Dictionary(grouping:jobRows,by:{$0.values[TaxstoneRegisterContract.sourceClipIDColumn]})
        guard Set(jobsByDriveID.keys) == Set(expectedDriveIDs),
              expectedDriveIDs.allSatisfy({globalDriveRows[$0]?.count == 1 && jobsByDriveID[$0]?.count == 1}) else {
            throw JoeyError.failed("Taxstone register readback has missing or duplicate accepted Drive IDs")
        }

        var rows: [TaxstoneRegisterRowReceipt] = []
        var derivativeIDs = Set<String>(), clipNumbers = Set<String>(), runIDs = Set<String>()
        for clip in job.clips {
            guard let driveID = clip.drive?.id, let matches = jobsByDriveID[driveID], matches.count == 1,
                  validatesAdoptedTaxstoneRegisterRow(job:job,clip:clip,values:matches[0].values,
                                                       externalRunID:nil,observedAt:observedAt) else {
                throw JoeyError.failed("Taxstone register row does not match accepted clip \(clip.id)")
            }
            let rowValues = matches[0].values
            derivativeIDs.insert(rowValues[TaxstoneRegisterContract.derivativeIDColumn])
            clipNumbers.insert(rowValues[0])
            runIDs.insert(rowValues[TaxstoneRegisterContract.runIDColumn])
            rows.append(TaxstoneRegisterRowReceipt(clipID:clip.id,rowNumber:matches[0].rowNumber,
                driveID:driveID,clipSHA256:clip.sha256!,clipBytes:clip.bytes!,values:rowValues,
                rowDigest:TaxstoneRegisterContract.rowDigest(rowValues)))
        }
        guard derivativeIDs.count == job.clips.count, clipNumbers.count == job.clips.count,
              runIDs.count == 1, let externalRunID = runIDs.first, !externalRunID.isEmpty else {
            throw JoeyError.failed("Taxstone readback contains duplicate package identities or mixed run IDs")
        }
        let provenance = TaxstoneRegisterEvidenceProvenance(kind:.adoptedExternalReadback,
            receiptSHA256:Integrity.sha256(receiptData),readbackSHA256:Integrity.sha256(readbackData),
            archiveSHA256:source.sha256,externalRunID:externalRunID,updatedRange:updatedRangeText,
            readbackRange:readbackRangeText,observedAt:observedAt)
        let evidence = TaxstoneRegisterEvidence(spreadsheetID:TaxstoneRegisterContract.spreadsheetID,
            tab:TaxstoneRegisterContract.tab,sourceID:source.id,sourceSHA256:source.sha256,folderID:folderID,
            schema:TaxstoneRegisterContract.headers,rows:rows,rowsReadBack:rowsReadBack,
            sourceRowsAfterWrite:sourceRowsAfterWrite,readbackDigest:TaxstoneRegisterContract.readbackDigest(rows),
            observedAt:observedAt,provenance:provenance)
        var candidate = job
        candidate.taxstoneRegisterEvidence = evidence
        guard candidate.hasRequiredCompletionEvidence else {
            throw JoeyError.failed("Adopted Taxstone evidence does not satisfy the native completion contract")
        }
        return evidence
    }

    static func validatesAdoptedTaxstoneRegisterRow(job: JobRecord, clip: ClipRecord, values: [String],
                                                     externalRunID: String?, observedAt: Date?) -> Bool {
        guard values.count == TaxstoneRegisterContract.headers.count,
              let source = job.source, let drive = clip.drive, let hash = clip.sha256, let bytes = clip.bytes,
              let duration = clip.measuredDuration, clip.qa?.passed == true,
              let archive = archiveID(source.archiveReference) else {return false}
        let row = Dictionary(uniqueKeysWithValues:TaxstoneRegisterContract.headers.enumerated().map {($0.element,values[$0.offset])})
        let filename = row["Source Filename"] ?? ""
        guard let clipNumber = Int(values[0]), clipNumber > 0,
              let episode = row["Episode ID"],
              let expectedStart = Double(row["Start"] ?? ""),
              let expectedEnd = Double(row["End"] ?? ""),
              let expectedDuration = Double(row["Duration"] ?? ""),
              let lastUpdated = ISO8601DateFormatter().date(from:row["Last Updated"] ?? ""),
              !filename.isEmpty, URL(fileURLWithPath:filename).lastPathComponent == filename else {return false}
        let episodeID = source.id.replacingOccurrences(of:"soundcloud:",with:"")
        let derivativeID = String(format:"taxstone-%@-C%02d_JOEY_FULLSHOW",episodeID,clip.id)
        let transcriptName = companionNames(source:source).first {$0.hasSuffix(" — Full Transcript.txt")}
        guard let transcriptName, let transcriptReceipt = job.companions[transcriptName] else {return false}
        let transcriptEvidence = "DRIVE:\(transcriptReceipt.id); SHA-256:\(transcriptReceipt.sha256)"
        let intervalStart = clip.intervals.first?.start ?? 0
        let intervalEnd = clip.intervals.last?.end ?? 0
        let reviewReason = row["Review / Exception Reason"]?.lowercased() ?? ""
        return episode == episodeID &&
            row["Derivative ID"] == derivativeID &&
            row["Friendly Title"] == source.title+" — "+clip.title &&
            row["Episode"] == source.title &&
            row["Episode Date"] == (source.episodeDate ?? "") &&
            row["Parent Source Drive File ID"] == archive &&
            (filename as NSString).pathExtension.lowercased() == URL(fileURLWithPath:source.path).pathExtension.lowercased() &&
            filename.contains(episodeID) && (source.episodeDate == nil || filename.contains(source.episodeDate!)) &&
            abs(expectedStart-intervalStart) <= Planning.tolerance &&
            abs(expectedEnd-intervalEnd) <= Planning.tolerance &&
            abs(expectedDuration-duration) <= Planning.tolerance &&
            row["Transcript Status"] == "COMPLETE_TIMESTAMPED_LOCAL_EVIDENCE" &&
            row["Transcript Evidence / File ID"] == transcriptEvidence &&
            row["Source Clip File ID"] == drive.id &&
            row["Buffer Delivery File ID"] == "" && row["Buffer Delivery Link"] == "" &&
            row["Technical Status"] == "PASS" &&
            row["Duplicate Status"] == "NEW_PACKAGE; HISTORICAL_SOURCE_ROWS_PRESERVED" &&
            row["Title Status"] == "PASS" && row["Manifest Status"] == "VERIFIED_CLIP_MANIFEST" &&
            row["QA Status"] == "PASS" && row["READY_FOR_BUFFER"] == "YES" &&
            reviewReason.contains("no social publication") && reviewReason.contains("scheduling") &&
            row["Delivery Status"] == "FILED_NOT_PUBLISHED" &&
            row["Control Center Job ID"] == job.id &&
            (externalRunID == nil || row["Run ID"] == externalRunID) &&
            (observedAt == nil || lastUpdated <= observedAt!) && bytes > 0 && hash.count == 64 && clipNumber > 0
    }

    private static func parseSheetRange(_ value: String) -> (tab:String,startColumn:Int,startRow:Int,endColumn:Int,endRow:Int)? {
        let sheet = value.split(separator:"!",omittingEmptySubsequences:false).map(String.init)
        guard sheet.count == 2 else {return nil}
        let endpoints = sheet[1].split(separator:":",omittingEmptySubsequences:false).map(String.init)
        guard endpoints.count == 2,
              let start = parseSheetCell(endpoints[0]),let end = parseSheetCell(endpoints[1]),
              start.column <= end.column,start.row <= end.row else {return nil}
        return (sheet[0],start.column,start.row,end.column,end.row)
    }

    private static func parseSheetCell(_ value:String) -> (column:Int,row:Int)? {
        let letters = value.prefix(while:{$0 >= "A" && $0 <= "Z"})
        let digits = value.dropFirst(letters.count)
        guard !letters.isEmpty,!digits.isEmpty,digits.allSatisfy({$0 >= "0" && $0 <= "9"}),
              let row = Int(digits),row > 0 else {return nil}
        var column = 0
        for letter in letters {
            guard column <= (Int.max-26)/26, let ascii = letter.asciiValue else {return nil}
            column = column*26+Int(ascii)-64
        }
        return (column,row)
    }

    public static func archiveID(_ reference: String?) -> String? {
        guard let reference, let url = URL(string:reference) else {return reference}
        let components = url.path.split(separator:"/").map(String.init)
        if let index = components.firstIndex(of:"d"), components.count > index + 1 {
            return components[index + 1]
        }
        return components.last
    }
    public static func csv(_ rows: [[String]]) -> String {
        rows.map {row in row.map {value in
            // Spreadsheet formula injection protection for user/source titles.
            let safe = ["=","+","-","@"].contains(value.first.map(String.init) ?? "") ? "'"+value : value
            return "\""+safe.replacingOccurrences(of:"\"",with:"\"\"")+"\""
        }.joined(separator:",")}.joined(separator:"\r\n")+"\r\n"
    }
    public static func companionNames(source: SourceRecord) -> [String] {
        let base = Persistence.safeName(source.title)+" — "+Persistence.safeName(source.id)
        return ["Clip Index — "+base+".csv",base+" — Full Transcript.txt","clip_manifest.json","RECONCILE.md"]
    }
    public static func write(job: JobRecord, directory: URL) throws -> [URL] {
        guard let source = job.source else { throw JoeyError.failed("Source missing from local package") }
        let base = Persistence.safeName(source.title)+" — "+Persistence.safeName(source.id)
        let index = directory.appendingPathComponent("Clip Index — "+base+".csv")
        var rows = [["Clip #","Title","Source intervals (seconds)","Measured duration (seconds)","Filename","Source ID","Verified Drive link","QA"]]
        for clip in job.clips {
            rows.append([String(clip.id),clip.title,clip.intervals.map {String(format:"%.6f–%.6f",$0.start,$0.end)}.joined(separator:"; "),
                clip.measuredDuration.map {String(format:"%.6f",$0)} ?? "",clip.filename,source.id,clip.drive?.url ?? "",clip.qa?.passed == true ? "PASSED":"NOT PASSED"])
        }
        try csv(rows).write(to:index,atomically:true,encoding:.utf8)
        var files = [index]
        if let transcript = job.transcript {
            let text = directory.appendingPathComponent(base+" — Full Transcript.txt")
            let header = "Source: \(source.title)\nSource ID: \(source.id)\nSource SHA-256: \(source.sha256)\nDuration: \(source.duration) seconds\nTranscription: \(transcript.engine); automatic speech recognition is not infallible.\n\n"
            try (header+transcript.segments.map {String(format:"[%.3f – %.3f] ",$0.start,$0.end)+$0.text}.joined(separator:"\n")).write(to:text,atomically:true,encoding:.utf8)
            files.append(text)
        }
        let reconcile = directory.appendingPathComponent("RECONCILE.md")
        let accepted = job.clips.filter {$0.qa?.passed == true}.count, filed = job.clips.filter {$0.drive != nil}.count
        let summary = """
        # Joey reconciliation

        Source: \(source.title) — \(source.id)
        Owner: \((try? DestinationResolver.resolve(source:source,request:job.request,asset:.clip).owner.rawValue) ?? source.owner.rawValue)
        State: \(job.state.rawValue)
        Stage: \(job.stage)
        Planned clips: \(job.clips.count)
        Automatic QA passed: \(accepted)
        Independently verified Drive clips: \(filed)
        Required register rows read back: \(job.request.owner == .taxstone ? job.verifiedTaxstoneRegisterRowCount : job.registerRows.count)
        Coverage: \(job.request.mode.rawValue); exact fractional source/output mappings are in clip_manifest.json.
        Exclusions: \(job.exclusions.count); uncertain material retained.
        Planning basis: \(job.planningBasis?.rawValue ?? "Legacy transcript-assisted checkpoint")
        Transcript-assisted features: \(job.unavailableTranscriptFeatures.isEmpty ? "Transcript available; automated editorial checks are not infallible" : "UNAVAILABLE: "+job.unavailableTranscriptFeatures.joined(separator:"; "))
        Production editorial requirements: \(job.unavailableTranscriptFeatures.isEmpty ? "Transcript-assisted path" : "INCOMPLETE; local media QA does not establish production completion")
        Failure/dependency: \(job.error ?? "None recorded")

        \(job.request.productionWorkflow == .joeBudden ? "One Drive-only MP4 per clip: 8–10-minute source-content target, DUB logo lower-left, and the full approved 7.300-second outro. Platform-upload compatibility is not asserted." : "One shared file per clip for X and Instagram.") No social publication or email.
        Native frames retain proportions with black padding; source resolution and effective dimensions are in each QA record.
        Automated decoding, signal and sampled-image checks do not guarantee semantic perfection or platform ingestion.
        The canonical Clip Index is CSV; no duplicate native index is created.
        The manifest does not contain its own checksum. The local durable job checkpoint stores its independent final Drive receipt to avoid circular hashes.
        """
        try summary.write(to:reconcile,atomically:true,encoding:.utf8)
        let manifest = directory.appendingPathComponent("clip_manifest.json")
        // Explicit interval mapping also records output offsets across ad joins.
        var object = try JSONSerialization.jsonObject(with:Persistence.encoder.encode(job)) as! [String:Any]
        object["intervalMappings"] = intervalMappings(job)
        object["encodingToleranceSeconds"] = 0.075
        object["coverageArithmeticToleranceSeconds"] = Planning.tolerance
        object["unavailableTranscriptFeatures"] = job.unavailableTranscriptFeatures
        object["productionEditorialRequirementsMet"] = job.unavailableTranscriptFeatures.isEmpty
        var companions = object["companions"] as? [String:Any] ?? [:]
        companions.removeValue(forKey:"clip_manifest.json"); companions.removeValue(forKey:"RECONCILE.md")
        object["companions"] = companions
        try JSONSerialization.data(withJSONObject:object,options:[.prettyPrinted,.sortedKeys,.withoutEscapingSlashes]).write(to:manifest,options:.atomic)
        return files+[reconcile,manifest]
    }

    private static func intervalMappings(_ job: JobRecord) -> [[String:Any]] {
        job.clips.map { clip -> [String:Any] in
            var cursor = 0.0
            let ranges = clip.intervals.map { range -> [String:Double] in
                defer {cursor += range.duration}
                return ["sourceStart":range.start,"sourceEnd":range.end,"outputStart":cursor,"outputEnd":cursor+range.duration]
            }
            var mapping: [String:Any] = ["filename":clip.filename,"intervals":ranges]
            if job.request.productionWorkflow == .joeBudden {
                mapping["approvedOutro"] = ["driveFileID":JoeBranding.outroID,"sha256":JoeBranding.outroSHA256,
                    "outputStart":cursor,"outputEnd":cursor+7.3] as [String:Any]
                mapping["approvedLogo"] = ["driveFileID":JoeBranding.logoID,"sha256":JoeBranding.logoSHA256,
                    "x":34,"y":866,"width":180,"height":180] as [String:Any]
            }
            return mapping
        }
    }
}
