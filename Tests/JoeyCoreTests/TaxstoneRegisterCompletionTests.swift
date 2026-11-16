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
            rows:[row],rowsReadBack:1,sourceRowsAfterWrite:1,readbackDigest:TaxstoneRegisterContract.readbackDigest([row]),observedAt:Date())
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
