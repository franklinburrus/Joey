import XCTest
@testable import JoeyCore

/// Only HTTP and rclone are simulated. Reconciliation and retry decisions use
/// the production adapter, with no real credentials or provider mutations.
final class RegisterReconciliationTests: XCTestCase {
    private func setup() throws -> (JobRecord, RegisterProvider, DriveDelivery) {
        let (source,request) = try DestinationRoutingTests().fixture(kind:.nativeVideo)
        var job = JobRecord(id:"synthetic-register-job",request:request)
        job.source = source;job.folderID = "synthetic-folder"
        let drive = DriveReceipt(id:"synthetic-clip",name:"01_clip.mp4",parent:"synthetic-folder",bytes:12,
            sha256:"synthetic-hash",url:"https://drive.google.com/file/d/synthetic-clip/view",permissions:[],verifiedAt:Date(timeIntervalSince1970:0))
        job.clips = [ClipRecord(id:1,title:"Synthetic clip",intervals:[Interval(0,60)],filename:drive.name,measuredDuration:60,drive:drive)]
        let provider = RegisterProvider()
        RegisterProtocol.provider = provider
        let configuration = URLSessionConfiguration.ephemeral;configuration.protocolClasses = [RegisterProtocol.self]
        let session = URLSession(configuration:configuration);addTeardownBlock {session.invalidateAndCancel()}
        let delivery = try DriveDelivery(remote:"fixture",session:session,runHelper:{_,args,_ in
            if args.first == "lsjson" {return ProcessResult(stdout:Data("[]".utf8),stderr:"",status:0)}
            guard args == ["config","dump"] else {throw JoeyError.failed("Unexpected helper in register fixture")}
            return ProcessResult(stdout:Data(#"{"fixture":{"type":"drive","token":"{\"access_token\":\"dummy-only\"}"}}"#.utf8),stderr:"",status:0)
        })
        return (job,provider,delivery)
    }
    private func failure(_ delivery: DriveDelivery, _ job: JobRecord) async -> Error? {
        do {_ = try await delivery.reconcileRegister(job:job,tab:"Master Library");XCTFail("Unexpected register acceptance");return nil}
        catch {return error}
    }
    func testPermanentPermissionDenialIsNotRetried() async throws {
        let (job,provider,delivery) = try setup();provider.outcomes = [.status(403)]
        let error = await failure(delivery,job)
        XCTAssertTrue(error?.localizedDescription.contains("403") == true)
        XCTAssertEqual(provider.appends,1);XCTAssertEqual(provider.rows.count,1)
    }
    func testCommittedAppendWithLostResponseIsReconciledWithoutDuplicate() async throws {
        let (job,provider,delivery) = try setup();provider.outcomes = [.commitAndLoseResponse]
        let receipts = try await delivery.reconcileRegister(job:job,tab:"Master Library")
        XCTAssertEqual(receipts,["Master Library!2:synthetic-clip"])
        XCTAssertEqual(provider.appends,1);XCTAssertEqual(provider.rows.count,2)
    }
    func testThirdTransientAttemptStillGetsIndependentReadback() async throws {
        let (job,provider,delivery) = try setup();provider.outcomes = [.status(503),.status(503),.success]
        let receipts = try await delivery.reconcileRegister(job:job,tab:"Master Library")
        XCTAssertEqual(receipts,["Master Library!2:synthetic-clip"]);XCTAssertEqual(provider.appends,3)
        XCTAssertEqual(provider.events,["GET","GET","POST","GET","POST","GET","POST","GET","GET"])
    }
    func testCommittedThirdAttemptWithLostResponseStillGetsReadback() async throws {
        let (job,provider,delivery) = try setup();provider.outcomes = [.status(503),.status(503),.commitAndLoseResponse]
        let receipts = try await delivery.reconcileRegister(job:job,tab:"Master Library")
        XCTAssertEqual(receipts.count,1);XCTAssertEqual(provider.appends,3);XCTAssertEqual(provider.rows.count,2)
    }
    func testExhaustedTransientAttemptsReconcileOnceMoreWithoutFourthWrite() async throws {
        let (job,provider,delivery) = try setup();provider.outcomes = [.status(503)]
        let error = await failure(delivery,job)
        XCTAssertTrue(error?.localizedDescription.contains("503") == true)
        XCTAssertEqual(provider.appends,3)
        XCTAssertEqual(provider.events,["GET","GET","POST","GET","POST","GET","POST","GET"])
    }
    func testSuccessfulAppendMissingFromReadbackIsNotAppendedAgain() async throws {
        let (job,provider,delivery) = try setup();provider.outcomes = [.successWithoutCommit]
        _ = await failure(delivery,job)
        XCTAssertEqual(provider.appends,1);XCTAssertEqual(provider.events,["GET","GET","POST","GET"])
    }
    func testUnknownTransportFailureIsReadBackButNotReplayed() async throws {
        let (job,provider,delivery) = try setup();provider.outcomes = [.transport(.unsupportedURL)]
        _ = await failure(delivery,job)
        XCTAssertEqual(provider.appends,1);XCTAssertEqual(provider.events,["GET","GET","POST","GET"])
    }
    func testCancellationDoesNotContinueReconciliationOrMutation() async throws {
        let (job,provider,delivery) = try setup();provider.outcomes = [.transport(.cancelled)]
        let error = await failure(delivery,job)
        XCTAssertTrue(error.map {$0 is CancellationError} == true,"Coordinator must preserve the cancelled state")
        XCTAssertEqual(provider.events,["GET","GET","POST"])
    }
    func testMissingValuesCannotBeInterpretedAsEmptyRegister() async throws {
        let (job,provider,delivery) = try setup();provider.badRead = 2
        _ = await failure(delivery,job)
        XCTAssertEqual(provider.appends,0);XCTAssertEqual(provider.rows.count,1)
    }
    func testHeaderDriftBeforeAppendPreventsMutation() async throws {
        let (job,provider,delivery) = try setup();provider.changedHeaderRead = 2
        _ = await failure(delivery,job)
        XCTAssertEqual(provider.appends,0)
    }
    func testHeaderDriftAtFinalReadbackCannotReturnReceipt() async throws {
        let (job,provider,delivery) = try setup();provider.changedHeaderRead = 4
        _ = await failure(delivery,job)
        XCTAssertEqual(provider.appends,1)
    }
    func testExistingRowUpdatesOnlySupportedCellsAndReopenDoesNotWrite() async throws {
        let (job,provider,delivery) = try setup()
        var row = Array(repeating:"",count:RegisterProvider.headers.count)
        for (column,value) in try Records.registerValues(job:job,clip:job.clips[0],headers:RegisterProvider.headers) {row[column] = value}
        row[1] = "Old title";row[9] = "=1+1"
        let unrelated = ["unrelated","unchanged","","","","","other-file","","","=SUM(A1:A2)"]
        provider.rows += [unrelated,row]
        let receipts = try await delivery.reconcileRegister(job:job,tab:"Master Library")
        let writes = provider.events.filter {$0 != "GET"}
        let reopened = try await delivery.reconcileRegister(job:job,tab:"Master Library")
        XCTAssertEqual(receipts,["Master Library!3:synthetic-clip"]);XCTAssertEqual(reopened,receipts)
        XCTAssertEqual(provider.events.filter {$0 != "GET"},writes);XCTAssertEqual(writes,["PUT"])
        XCTAssertEqual(provider.rows[1],unrelated);XCTAssertEqual(provider.rows[2][9],"=1+1")
        XCTAssertEqual(provider.rows[2][1],job.clips[0].title)
    }
    func testDuplicateIdentitiesPreventAnyMutation() async throws {
        let (job,provider,delivery) = try setup()
        var row = Array(repeating:"",count:RegisterProvider.headers.count);row[6] = "synthetic-clip"
        provider.rows += [row,row]
        let error = await failure(delivery,job)
        XCTAssertTrue(error?.localizedDescription.contains("Duplicate") == true)
        XCTAssertTrue(provider.events.allSatisfy {$0 == "GET"})
    }
}

private final class RegisterProvider: @unchecked Sendable {
    enum Outcome {case status(Int), success, successWithoutCommit, commitAndLoseResponse, transport(URLError.Code)}
    static let headers = ["Clip #","Title","Start","End","Duration (sec)","Public link","Drive file ID","Episode key","Filename","Manual formula"]
    private let lock = NSLock()
    var rows = [headers], outcomes: [Outcome] = [.success], events: [String] = []
    var appends = 0, reads = 0, badRead = 0, changedHeaderRead = 0
    func response(_ request: URLRequest) throws -> (Int,Data) {
        lock.lock();defer {lock.unlock()}
        let method = request.httpMethod ?? "GET";events.append(method)
        if method == "GET" {
            reads += 1
            if reads == badRead {return (200,Data("{}".utf8))}
            var current = rows
            if reads == changedHeaderRead {current[0].swapAt(1,6)}
            return (200,try JSONSerialization.data(withJSONObject:["values":current]))
        }
        var data = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open();defer {stream.close()}
            var buffer = [UInt8](repeating:0,count:4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer,maxLength:buffer.count)
                guard count >= 0 else {throw JoeyError.failed("Fixture request body unavailable")}
                if count == 0 {break};data.append(contentsOf:buffer.prefix(count))
            }
        }
        let object = try JSONSerialization.jsonObject(with:data) as! [String:Any]
        let values = object["values"] as! [[String]]
        if method == "POST" {
            appends += 1
            let outcome = outcomes[min(appends-1,outcomes.count-1)]
            switch outcome {
            case .status(let code):return (code,Data(#"{"error":{"message":"Synthetic provider rejection"}}"#.utf8))
            case .transport(let code):throw URLError(code)
            case .success:rows += values
            case .successWithoutCommit:break
            case .commitAndLoseResponse:rows += values;throw URLError(.networkConnectionLost)
            }
        } else if method == "PUT" {
            let cell = request.url!.lastPathComponent.split(separator:"!").last!
            let letters = cell.prefix(while:{$0.isLetter})
            let column = letters.reduce(0) {$0*26+Int($1.asciiValue!-65)+1}-1
            let row = Int(cell.dropFirst(letters.count))!-1
            rows[row][column] = values[0][0]
        } else {throw JoeyError.failed("Unexpected register method")}
        return (200,Data("{}".utf8))
    }
}
private final class RegisterProtocol: URLProtocol {
    static var provider: RegisterProvider!
    override class func canInit(with request: URLRequest) -> Bool {true}
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {request}
    override func startLoading() {
        do {
            let (status,data) = try Self.provider.response(request)
            client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:status,httpVersion:nil,headerFields:nil)!,cacheStoragePolicy:.notAllowed)
            client?.urlProtocol(self,didLoad:data);client?.urlProtocolDidFinishLoading(self)
        } catch {client?.urlProtocol(self,didFailWithError:error)}
    }
    override func stopLoading() {}
}
