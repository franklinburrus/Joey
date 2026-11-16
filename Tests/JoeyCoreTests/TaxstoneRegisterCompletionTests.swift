import XCTest
@testable import JoeyCore
@testable import JoeyInterface

final class TaxstoneRegisterCompletionTests: XCTestCase {
    func testValidTaxstoneReceiptPermitsCompletionAndSafeReopen() async throws {
        let root = try workspace()
        defer {try? FileManager.default.removeItem(at:root)}
        let job = try validJob(root:root)
        XCTAssertTrue(job.hasRequiredCompletionEvidence)
        XCTAssertTrue(JobPresentation(job:job).completed)
        let directory = root.appendingPathComponent("jobs/\(job.id)")
        try Persistence.save(job,to:directory.appendingPathComponent("job.json"))
        let before = try Data(contentsOf:directory.appendingPathComponent("job.json"))
        let reopened = try await Coordinator(root:root).run(job.request)
        XCTAssertEqual(reopened.state,.completed)
        XCTAssertEqual(reopened.taxstoneRegisterEvidence?.readbackDigest,job.taxstoneRegisterEvidence?.readbackDigest)
        XCTAssertEqual(reopened.taxstoneRegisterEvidence?.rows,job.taxstoneRegisterEvidence?.rows)
        XCTAssertEqual(try Data(contentsOf:directory.appendingPathComponent("job.json")),before)
    }

    func testMissingTaxstoneReceiptBlocksCompletionAndPresentation() throws {
        let root = try workspace(); defer {try? FileManager.default.removeItem(at:root)}
        var job = try validJob(root:root); job.taxstoneRegisterEvidence = nil
        XCTAssertFalse(job.hasRequiredCompletionEvidence)
        let view = JobPresentation(job:job)
        XCTAssertFalse(view.completed)
        XCTAssertEqual(view.recordStatus,"0/1 Taxstone register rows verified")
        XCTAssertFalse(view.stages.first {$0.id == "records"}!.verified)
    }

    func testStaleTaxstoneReceiptFieldsBlockCompletion() throws {
        let root = try workspace(); defer {try? FileManager.default.removeItem(at:root)}
        let original = try validJob(root:root)
        for mutation in 0..<5 {
            var job = original
            var receipt = try XCTUnwrap(job.taxstoneRegisterEvidence)
            switch mutation {
            case 0: receipt.sourceSHA256 = String(repeating:"b",count:64)
            case 1: receipt.folderID = "other-folder"
            case 2: receipt.rows[0].clipSHA256 = String(repeating:"b",count:64)
            case 3: receipt.rows[0].driveID = "other-drive"
            default: receipt.rows[0].rowDigest = "unreadable"
            }
            job.taxstoneRegisterEvidence = receipt
            XCTAssertFalse(job.hasRequiredCompletionEvidence,"mutation \(mutation)")
        }
    }

    func testTaxstoneEvidenceCannotSatisfyDUBCompletion() throws {
        let root = try workspace(); defer {try? FileManager.default.removeItem(at:root)}
        var job = try validJob(root:root)
        job.request.owner = .dub
        job.source!.owner = .dub
        XCTAssertFalse(job.hasRequiredCompletionEvidence)
    }

    func testMalformedTaxstoneCheckpointIsUnreadable() throws {
        let root = try workspace(); defer {try? FileManager.default.removeItem(at:root)}
        let job = try validJob(root:root)
        let directory = root.appendingPathComponent("jobs/\(job.id)")
        try Persistence.save(job,to:directory.appendingPathComponent("job.json"))
        var data = try Data(contentsOf:directory.appendingPathComponent("job.json"))
        data.append(Data("{malformed".utf8))
        try data.write(to:directory.appendingPathComponent("job.json"),options:.atomic)
        XCTAssertThrowsError(try Persistence.load(directory.appendingPathComponent("job.json")) as JobRecord)
    }

    func testNativeTaxstoneWriterReadsSeparateSchemaAndBindsRows() async throws {
        let root = try workspace(); defer {try? FileManager.default.removeItem(at:root)}
        let job = try validJob(root:root)
        let provider = TaxstoneRegisterFixture()
        TaxstoneRegisterProtocol.provider = provider
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TaxstoneRegisterProtocol.self]
        let session = URLSession(configuration:configuration)
        defer {session.invalidateAndCancel()}
        let delivery = try DriveDelivery(remote:"fixture",session:session,runHelper:{_,args,_ in
            if args.first == "lsjson" {return ProcessResult(stdout:Data("[]".utf8),stderr:"",status:0)}
            return ProcessResult(stdout:Data(#"{"fixture":{"type":"drive","token":"{\"access_token\":\"dummy-only\"}"}}"#.utf8),stderr:"",status:0)
        })
        let evidence = try await delivery.reconcileTaxstoneRegister(job:job)
        XCTAssertEqual(evidence.spreadsheetID,TaxstoneRegisterContract.spreadsheetID)
        XCTAssertEqual(evidence.tab,"Master")
        XCTAssertEqual(evidence.rows.count,1)
        XCTAssertEqual(evidence.rows[0].driveID,job.clips[0].drive!.id)
        let appendCount = await provider.appends
        let rowCount = await provider.rows.count
        XCTAssertEqual(appendCount,1)
        XCTAssertEqual(rowCount,2)
        var bound = job;bound.taxstoneRegisterEvidence = evidence
        XCTAssertTrue(bound.hasRequiredCompletionEvidence)
    }

    func testExactTaxstoneRowIsReusedWithoutMutation() async throws {
        let root = try workspace(); defer {try? FileManager.default.removeItem(at:root)}
        let job = try validJob(root:root)
        let values = try Records.taxstoneRegisterValues(job:job,clip:job.clips[0])
        let provider = TaxstoneRegisterFixture()
        await provider.replaceRows([TaxstoneRegisterContract.headers,values])
        TaxstoneRegisterProtocol.provider = provider
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TaxstoneRegisterProtocol.self]
        let session = URLSession(configuration:configuration)
        defer {session.invalidateAndCancel()}
        let delivery = try fixtureDelivery(session:session)

        let evidence = try await delivery.reconcileTaxstoneRegister(job:job)
        let appends = await provider.appends
        let rows = await provider.snapshot()
        XCTAssertEqual(evidence.rows.map(\.rowNumber),[2])
        XCTAssertEqual(appends,0)
        XCTAssertEqual(rows,[TaxstoneRegisterContract.headers,values])
    }

    func testConflictingHistoricalTaxstoneRowIsPreserved() async throws {
        let root = try workspace(); defer {try? FileManager.default.removeItem(at:root)}
        let job = try validJob(root:root)
        var historical = try Records.taxstoneRegisterValues(job:job,clip:job.clips[0])
        historical[TaxstoneRegisterContract.jobIDColumn] = "historical-job"
        historical[TaxstoneRegisterContract.runIDColumn] = "historical-run"
        let provider = TaxstoneRegisterFixture()
        await provider.replaceRows([TaxstoneRegisterContract.headers,historical])
        TaxstoneRegisterProtocol.provider = provider
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TaxstoneRegisterProtocol.self]
        let session = URLSession(configuration:configuration)
        defer {session.invalidateAndCancel()}
        let delivery = try fixtureDelivery(session:session)
        let before = await provider.snapshot()

        do {
            _ = try await delivery.reconcileTaxstoneRegister(job:job)
            XCTFail("Conflicting historical row must block mutation")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("prior row preserved"),error.localizedDescription)
        }
        let appends = await provider.appends
        let rows = await provider.snapshot()
        XCTAssertEqual(appends,0)
        XCTAssertEqual(rows,before)
    }

    func testTaxstoneDerivativeIDsSeparateFullShowAndHighlightPackages() throws {
        let root = try workspace(); defer {try? FileManager.default.removeItem(at:root)}
        let full = try validJob(root:root)
        let fullValues = try Records.taxstoneRegisterValues(job:full,clip:full.clips[0])

        var highlightA = full
        highlightA.id = "taxstone-highlight-a"
        highlightA.request.mode = .highlights
        let highlightAValues = try Records.taxstoneRegisterValues(job:highlightA,clip:highlightA.clips[0])

        var highlightB = highlightA
        highlightB.id = "taxstone-highlight-b"
        let highlightBValues = try Records.taxstoneRegisterValues(job:highlightB,clip:highlightB.clips[0])

        XCTAssertTrue(fullValues[TaxstoneRegisterContract.derivativeIDColumn].hasSuffix("_JOEY_FULLSHOW"))
        XCTAssertNotEqual(fullValues[TaxstoneRegisterContract.derivativeIDColumn],
                          highlightAValues[TaxstoneRegisterContract.derivativeIDColumn])
        XCTAssertNotEqual(highlightAValues[TaxstoneRegisterContract.derivativeIDColumn],
                          highlightBValues[TaxstoneRegisterContract.derivativeIDColumn])
        XCTAssertTrue(highlightAValues[TaxstoneRegisterContract.derivativeIDColumn].contains("HIGHLIGHTS_taxstone-highlight-a"))
    }

    func testAdoptedExternalReadbackBindsOriginalJobAndReopensWithoutProviderWrites() async throws {
        let root = try workspace();defer {try? FileManager.default.removeItem(at:root)}
        var job = try adoptionFixture(root:root)
        let input = try externalReadback(for:job)
        let evidence = try Records.adoptTaxstoneRegisterEvidence(job:job,receiptData:input.receipt,readbackData:input.readback)
        XCTAssertEqual(evidence.rows.count,1)
        XCTAssertEqual(evidence.rows[0].driveID,job.clips[0].drive?.id)
        XCTAssertEqual(evidence.provenance?.kind,.adoptedExternalReadback)
        XCTAssertEqual(evidence.provenance?.externalRunID,"joey-taxstone-acceptance-20261115")
        XCTAssertEqual(evidence.provenance?.archiveSHA256,job.source?.sha256)

        job.taxstoneRegisterEvidence = evidence
        XCTAssertTrue(job.hasRequiredCompletionEvidence)
        XCTAssertTrue(JobPresentation(job:job).completed)
        XCTAssertEqual(JobPresentation(job:job).recordStatus,
            "Verified from prior external readback; Joey did not perform the original write.")

        let jobDirectory = root.appendingPathComponent("jobs/\(job.id)",isDirectory:true)
        try FileManager.default.createDirectory(at:jobDirectory,withIntermediateDirectories:true)
        let acceptedFile = URL(fileURLWithPath:job.source!.path).deletingLastPathComponent().appendingPathComponent(job.clips[0].filename)
        try FileManager.default.copyItem(at:acceptedFile,
            to:jobDirectory.appendingPathComponent(job.clips[0].filename))
        // Missing cache media does not invalidate verified Drive/register evidence.
        try FileManager.default.removeItem(at:jobDirectory.appendingPathComponent(job.clips[0].filename))
        XCTAssertEqual(JobPresentation(job:job,runtimeRoot:root).localPlaybackMessage,
            "Local playback unavailable for 1 of 1 clips; verified Drive copies remain available.")
        try Persistence.save(job,to:jobDirectory.appendingPathComponent("job.json"))
        let before = try Data(contentsOf:jobDirectory.appendingPathComponent("job.json"))
        let reopened = try await Coordinator(root:root).run(job.request)
        XCTAssertTrue(reopened.hasRequiredCompletionEvidence)
        XCTAssertEqual(reopened.taxstoneRegisterEvidence?.provenance,evidence.provenance)
        XCTAssertEqual(try Data(contentsOf:jobDirectory.appendingPathComponent("job.json")),before)
    }

    func testExternalReadbackAdoptionRejectsMismatchedJobSourceArchiveAndRows() throws {
        let root = try workspace();defer {try? FileManager.default.removeItem(at:root)}
        let job = try adoptionFixture(root:root)
        let original = try externalReadback(for:job)
        for mutation in 0..<7 {
            var receipt = original.receipt, readback = original.readback
            switch mutation {
            case 0:
                var object = try JSONSerialization.jsonObject(with:receipt) as! [String:Any]
                object["jobID"] = "other-job"
                receipt = try JSONSerialization.data(withJSONObject:object)
            case 1:
                var object = try JSONSerialization.jsonObject(with:receipt) as! [String:Any]
                object["sourceID"] = "soundcloud:other-source"
                receipt = try JSONSerialization.data(withJSONObject:object)
            case 2:
                var object = try JSONSerialization.jsonObject(with:receipt) as! [String:Any]
                object["folderID"] = "other-folder"
                receipt = try JSONSerialization.data(withJSONObject:object)
            case 3:
                var object = try JSONSerialization.jsonObject(with:readback) as! [String:Any]
                var values = object["values"] as! [[String]]
                values[1][TaxstoneRegisterContract.sourceClipIDColumn] = "other-drive"
                object["values"] = values
                readback = try JSONSerialization.data(withJSONObject:object)
            case 4:
                var object = try JSONSerialization.jsonObject(with:readback) as! [String:Any]
                var values = object["values"] as! [[String]]
                values[1][TaxstoneRegisterContract.parentSourceColumn] = "other-archive"
                object["values"] = values
                readback = try JSONSerialization.data(withJSONObject:object)
            case 5:
                var object = try JSONSerialization.jsonObject(with:receipt) as! [String:Any]
                object["publication"] = true
                receipt = try JSONSerialization.data(withJSONObject:object)
            default:
                var object = try JSONSerialization.jsonObject(with:readback) as! [String:Any]
                object["range"] = "Master!A1:Z2"
                readback = try JSONSerialization.data(withJSONObject:object)
            }
            XCTAssertThrowsError(try Records.adoptTaxstoneRegisterEvidence(job:job,receiptData:receipt,readbackData:readback),
                "mutation \(mutation) must be rejected")
        }

        let changedArchive = job
        try Data("changed archive".utf8).write(to:URL(fileURLWithPath:job.source!.path),options:.atomic)
        XCTAssertThrowsError(try Records.adoptTaxstoneRegisterEvidence(job:changedArchive,receiptData:original.receipt,readbackData:original.readback))
    }

    private func adoptionFixture(root:URL) throws -> JobRecord {
        var job = try validJob(root:root)
        job.taxstoneRegisterEvidence = nil
        let sourceURL = root.appendingPathComponent("2015-04-15__fixture-200921906__fixture-taxstone.mp3")
        try Data("synthetic accepted archive bytes".utf8).write(to:sourceURL)
        let hash = try Integrity.sha256(sourceURL)
        job.request.expectedSourceSHA256 = hash
        job.source!.path = sourceURL.path
        job.source!.bytes = Int64(try Data(contentsOf:sourceURL).count)
        job.source!.sha256 = hash
        job.source!.kind = .audio
        job.source!.hasAudio = true
        job.transcript!.sourceSHA256 = hash
        let destination = try DestinationResolver.resolve(source:job.source!,request:job.request,asset:.clip)
        for index in job.clips.indices {
            job.clips[index].drive?.destination = destination
        }
        for name in Array(job.companions.keys) {
            job.companions[name]?.destination = destination
        }
        job.acceptedPlanSHA256 = try job.acceptancePlanHash()
        XCTAssertTrue(job.unavailableTranscriptFeatures.isEmpty)
        XCTAssertNoThrow(try job.validateAcceptedPlan())
        XCTAssertEqual(job.verifiedDriveClipCount,job.clips.count)
        XCTAssertEqual(Set(job.companions.keys),Set(Records.companionNames(source:job.source!)))
        XCTAssertTrue(job.hasRequiredPackageEvidence,"Adoption fixture must preserve valid package evidence without register evidence")
        return job
    }

    private func externalReadback(for job:JobRecord) throws -> (receipt:Data,readback:Data) {
        let source = try XCTUnwrap(job.source)
        let clip = try XCTUnwrap(job.clips.first)
        let drive = try XCTUnwrap(clip.drive)
        let episodeID = source.id.replacingOccurrences(of:"soundcloud:",with:"")
        let sourceFilename = "2015-04-15__\(episodeID)__fixture-taxstone.mp3"
        let headers = TaxstoneRegisterContract.headers
        var row = Dictionary(uniqueKeysWithValues:headers.map {($0,"")})
        row["Clip #"] = "327"
        row["Derivative ID"] = String(format:"taxstone-%@-C%02d_JOEY_FULLSHOW",episodeID,clip.id)
        row["Friendly Title"] = source.title+" — "+clip.title
        row["Episode"] = source.title
        row["Episode ID"] = episodeID
        row["Episode Date"] = source.episodeDate ?? ""
        row["Parent Source Drive File ID"] = "archive-source"
        row["Source Filename"] = sourceFilename
        row["Start"] = "0"
        row["End"] = "10"
        row["Duration"] = "10"
        row["Transcript Status"] = "COMPLETE_TIMESTAMPED_LOCAL_EVIDENCE"
        let transcriptName = try XCTUnwrap(Records.companionNames(source:source).first {$0.hasSuffix(" — Full Transcript.txt")})
        let transcript = try XCTUnwrap(job.companions[transcriptName])
        row["Transcript Evidence / File ID"] = "DRIVE:\(transcript.id); SHA-256:\(transcript.sha256)"
        row["Source Clip File ID"] = drive.id
        row["Technical Status"] = "PASS"
        row["Duplicate Status"] = "NEW_PACKAGE; HISTORICAL_SOURCE_ROWS_PRESERVED"
        row["Title Status"] = "PASS"
        row["Manifest Status"] = "VERIFIED_CLIP_MANIFEST"
        row["QA Status"] = "PASS"
        row["READY_FOR_BUFFER"] = "YES"
        row["Review / Exception Reason"] = "One Full Show package; no social publication or scheduling authorized."
        row["Delivery Status"] = "FILED_NOT_PUBLISHED"
        row["Last Updated"] = "2026-11-15T19:05:33Z"
        row["Run ID"] = "joey-taxstone-acceptance-20261115"
        row["Control Center Job ID"] = job.id
        let rowValues = headers.map {row[$0] ?? ""}
        let receipt:[String:Any] = ["schemaVersion":1,"observedAt":"2026-11-15T19:06:54Z","jobID":job.id,
            "sourceID":source.id,"folderID":job.folderID!,"spreadsheetId":TaxstoneRegisterContract.spreadsheetID,
            "tab":TaxstoneRegisterContract.tab,"updatedRange":"Master!A2:AA2","rowsReadBack":1,
            "sourceRowsAfterWrite":1,"exactRowsMatch":true,"newDriveIDsUnique":true,"publication":false,"scheduling":false]
        let readback:[String:Any] = ["range":"Master!A1:AA2","majorDimension":"ROWS","values":[headers,rowValues]]
        return (try JSONSerialization.data(withJSONObject:receipt,options:[.sortedKeys]),
                try JSONSerialization.data(withJSONObject:readback,options:[.sortedKeys]))
    }

    private func workspace() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("joey-taxstone-register-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        return root
    }

    private func validJob(root: URL) throws -> JobRecord {
        let sourceURL = root.appendingPathComponent("source.mp4")
        try Data("source bytes".utf8).write(to:sourceURL)
        var request = try Fixtures.request(dir:root,path:sourceURL.path)
        request.owner = .taxstone; request.sourceID = "soundcloud:fixture-200921906"; request.title = "Fixture Taxstone"
        request.episodeDate = "2015-04-15"; request.dateEvidence = "Synthetic fixture"
        request.originalURL = "https://soundcloud.com/taxstone/fixture-200921906"
        request.archiveReference = "https://drive.google.com/file/d/archive-source/view"
        request.expectedDuration = 10
        request.expectedSourceSHA256 = try Integrity.sha256(sourceURL)
        request.fileToDrive = true
        var job = JobRecord(id:"taxstone-register-fixture",request:request)
        let source = SourceRecord(id:request.sourceID,owner:.taxstone,title:request.title,episodeDate:request.episodeDate,
            originalURL:request.originalURL,path:sourceURL.path,bytes:Int64(try Data(contentsOf:sourceURL).count),
            sha256:try Integrity.sha256(sourceURL),duration:10,width:1920,height:1080,fps:30,hasAudio:true,
            kind:.nativeVideo,streams:[],authorizationBasis:"Synthetic fixture",archiveReference:request.archiveReference,
            classificationEvidence:"Synthetic fixture")
        job.source = source; job.folderID = "fixture-taxstone-folder"; job.planningBasis = .transcriptAssisted
        job.transcript = Transcript(sourceID:source.id,sourceSHA256:source.sha256,duration:10,engine:"Synthetic",segments:[TranscriptSegment(start:0,end:10,text:"Complete fixture transcript")])
        let output = root.appendingPathComponent("accepted.mp4")
        try Data("accepted output".utf8).write(to:output)
        let hash = try Integrity.sha256(output), bytes = Int64(try Data(contentsOf:output).count)
        let destination = try DestinationResolver.resolve(source:source,request:request,asset:.clip)
        let clipReceipt = DriveReceipt(id:"taxstone-drive-clip",name:output.lastPathComponent,parent:job.folderID!,bytes:bytes,
            md5:try Integrity.md5(output),sha256:hash,url:"https://example.invalid/clip",permissions:["user:owner"],
            verifiedAt:Date(),destination:destination,permissionFingerprint:String(repeating:"a",count:64))
        job.clips = [ClipRecord(id:1,title:"Fixture clip",intervals:[Interval(0,10)],filename:output.lastPathComponent,
            measuredDuration:10,bytes:bytes,sha256:hash,
            qa:QAReport(checkedAt:Date(),checks:["framing":"Source 1920x1080; effective picture 1920x1080 inside 1920x1080, no quality-upscale claim"],outputSHA256:hash,passed:true,limitations:[]),drive:clipReceipt)]
        for name in Records.companionNames(source:source) {
            var companion = clipReceipt; companion.id = "taxstone-companion-"+name; companion.name = name
            job.companions[name] = companion
        }
        let values = try Records.taxstoneRegisterValues(job:job,clip:job.clips[0])
        let row = TaxstoneRegisterRowReceipt(clipID:1,rowNumber:2,driveID:clipReceipt.id,clipSHA256:hash,clipBytes:bytes,
            values:values,rowDigest:TaxstoneRegisterContract.rowDigest(values))
        job.taxstoneRegisterEvidence = TaxstoneRegisterEvidence(spreadsheetID:TaxstoneRegisterContract.spreadsheetID,tab:"Master",
            sourceID:source.id,sourceSHA256:source.sha256,folderID:job.folderID!,schema:TaxstoneRegisterContract.headers,
            rows:[row],rowsReadBack:1,sourceRowsAfterWrite:1,readbackDigest:TaxstoneRegisterContract.readbackDigest([row]),observedAt:Date(),
            provenance:.nativeReconciliation)
        job.acceptedPlanSHA256 = try job.acceptancePlanHash()
        job.state = .completed; job.stage = "complete"
        return job
    }

    private func fixtureDelivery(session: URLSession) throws -> DriveDelivery {
        try DriveDelivery(remote:"fixture",session:session,runHelper:{_,args,_ in
            if args.first == "lsjson" {return ProcessResult(stdout:Data("[]".utf8),stderr:"",status:0)}
            return ProcessResult(stdout:Data(#"{"fixture":{"type":"drive","token":"{\"access_token\":\"dummy-only\"}"}}"#.utf8),stderr:"",status:0)
        })
    }
}

private actor TaxstoneRegisterFixture {
    var rows: [[String]] = [TaxstoneRegisterContract.headers]
    var appends = 0
    func replaceRows(_ rows: [[String]]) {self.rows = rows}
    func append(_ values: [String]) {rows.append(values);appends += 1}
    func snapshot() -> [[String]] {rows}
}

private final class TaxstoneRegisterProtocol: URLProtocol {
    static var provider: TaxstoneRegisterFixture!
    override class func canInit(with request: URLRequest) -> Bool {true}
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {request}
    override func startLoading() {
        Task {
            do {
                let method = request.httpMethod ?? "GET"
                var data = request.httpBody ?? Data()
                if let stream = request.httpBodyStream {
                    stream.open(); defer {stream.close()}
                    var buffer = [UInt8](repeating:0,count:4096)
                    while stream.hasBytesAvailable {
                        let count = stream.read(&buffer,maxLength:buffer.count)
                        if count <= 0 {break}; data.append(contentsOf:buffer.prefix(count))
                    }
                }
                if method == "POST" {
                    let object = try JSONSerialization.jsonObject(with:data) as! [String:Any]
                    let values = object["values"] as! [[String]]
                    await Self.provider.append(values[0])
                } else if method == "PUT" {
                    throw JoeyError.failed("Unexpected Taxstone fixture PUT")
                }
                let rows = await Self.provider.rows
                let payload = try JSONSerialization.data(withJSONObject:["values":rows])
                let response = HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!
                client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
                client?.urlProtocol(self,didLoad:payload);client?.urlProtocolDidFinishLoading(self)
            } catch {client?.urlProtocol(self,didFailWithError:error)}
        }
    }
    override func stopLoading() {}
}
