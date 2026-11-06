import XCTest
@testable import JoeyCore

final class DeliveryTests: XCTestCase {
    func testOAuthConfigurationFailureDoesNotExposeHelperDiagnostics() async throws {
        let canary = "JOEY_DUMMY_OAUTH_DIAGNOSTIC_DO_NOT_USE"
        let delivery = try DriveDelivery(remote: "fixture", runHelper: { _, arguments, _ in
            if arguments.first == "lsjson" { return ProcessResult(stdout: Data("[]".utf8), stderr: "", status: 0) }
            throw JoeyError.failed(canary)
        })
        do {
            _ = try await delivery.request("files/dummy-only")
            XCTFail("Failed configuration was accepted")
        } catch {
            XCTAssertFalse(error.localizedDescription.contains(canary))
            XCTAssertTrue(error.localizedDescription.contains("OAuth configuration"))
        }
    }

    func testRcloneHelpersDisableBothInternalRetryLevels() async throws {
        let delivery = try DriveDelivery(remote: "fixture", runHelper: { _, arguments, _ in
            if arguments.first == "config" { throw JoeyError.failed("Dummy configuration refusal") }
            for flag in ["--retries", "--low-level-retries"] {
                guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else {
                    XCTFail("Missing bounded rclone flag \(flag)")
                    continue
                }
                XCTAssertEqual(arguments[index + 1], "1")
            }
            if arguments.first == "lsjson" { return ProcessResult(stdout: Data("[]".utf8), stderr: "", status: 0) }
            throw JoeyError.failed("Dummy configuration refusal")
        })
        do { _ = try await delivery.request("files/dummy-only"); XCTFail("Expected dummy failure") }
        catch {}
    }

    func testAuthoritativeDUBRootsReplaceRetiredJoeyFolders() {
        XCTAssertEqual(DriveDelivery.videoRoot, "1380CHJ3a3kl7fXNIKWqUM7_DeTZUwxsy")
        XCTAssertEqual(DriveDelivery.audioRoot, "1FRi-yy2D9yenjQRailTA2iAbPaqAEPXm")
    }

    func testCancelledTaskCannotDispatchProviderMutation() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TransientProvider.self]
        let session = URLSession(configuration:configuration)
        defer {session.invalidateAndCancel()}
        let delivery = try DriveDelivery(remote:"fixture",session:session)
        var request = URLRequest(url:URL(string:"https://joey-test.invalid/cancelled")!)
        request.httpMethod = "POST"
        TransientProvider.reset()
        let task = Task {
            withUnsafeCurrentTask {$0?.cancel()}
            return try await delivery.response(for:request)
        }
        do {_ = try await task.value;XCTFail("Cancelled mutation was dispatched")}
        catch {XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled)}
        XCTAssertEqual(TransientProvider.count,0)
    }
    func testSheetsRequestsIncludingRetriesRespectPerUserQuota() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TransientProvider.self]
        let session = URLSession(configuration:configuration)
        defer {session.invalidateAndCancel()}
        let delivery = try DriveDelivery(remote:"fixture",session:session)
        let request = URLRequest(url:URL(string:"https://sheets.googleapis.com/v4/test-only")!)
        TransientProvider.reset()
        _ = try await delivery.response(for:request)
        let times = TransientProvider.times
        XCTAssertEqual(times.count,3)
        for (earlier,later) in zip(times,times.dropFirst()) {
            XCTAssertGreaterThanOrEqual(later.timeIntervalSince(earlier),1.0,
                "Sheets limits each user/project to 60 reads per minute; retries also consume quota")
        }
    }
    func testTransientReadRetriesButUncertainMutationDoesNotReplay() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TransientProvider.self]
        let session = URLSession(configuration:configuration)
        defer {session.invalidateAndCancel()}
        let delivery = try DriveDelivery(remote:"fixture",session:session)
        var request = URLRequest(url:URL(string:"https://joey-test.invalid/transient")!)
        TransientProvider.reset()
        _ = try await delivery.response(for:request)
        XCTAssertEqual(TransientProvider.count,3)
        TransientProvider.reset()
        request.httpMethod = "POST"
        do {
            _ = try await delivery.response(for:request)
            XCTFail("Uncertain mutation should return to its reconciliation owner")
        } catch {XCTAssertTrue(error.localizedDescription.contains("503"))}
        XCTAssertEqual(TransientProvider.count,1)
    }
}

private final class TransientProvider: URLProtocol {
    private static let lock = NSLock()
    private static var requests = 0
    private static var timestamps: [Date] = []
    static var times: [Date] {lock.lock();defer {lock.unlock()};return timestamps}
    static var count: Int {lock.lock();defer {lock.unlock()};return requests}
    static func reset() {lock.lock();requests = 0;timestamps = [];lock.unlock()}
    override class func canInit(with request: URLRequest) -> Bool {true}
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {request}
    override func startLoading() {
        Self.lock.lock();Self.requests += 1;Self.timestamps.append(Date());let count = Self.requests;Self.lock.unlock()
        let response = HTTPURLResponse(url:request.url!,statusCode:count < 3 ? 503:200,httpVersion:nil,headerFields:nil)!
        client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
