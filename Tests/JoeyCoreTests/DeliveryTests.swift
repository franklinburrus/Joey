import XCTest
@testable import JoeyCore

final class DeliveryTests: XCTestCase {
    func testTransientReadRetriesButUncertainMutationDoesNotReplay() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TransientProvider.self]
        let session = URLSession(configuration:configuration)
        defer {session.invalidateAndCancel()}
        var request = URLRequest(url:URL(string:"https://joey-test.invalid/transient")!)
        TransientProvider.reset()
        _ = try await DriveDelivery.response(for:request,session:session)
        XCTAssertEqual(TransientProvider.count,3)
        TransientProvider.reset()
        request.httpMethod = "POST"
        do {
            _ = try await DriveDelivery.response(for:request,session:session)
            XCTFail("Uncertain mutation should return to its reconciliation owner")
        } catch {XCTAssertTrue(error.localizedDescription.contains("503"))}
        XCTAssertEqual(TransientProvider.count,1)
    }
}

private final class TransientProvider: URLProtocol {
    private static let lock = NSLock()
    private static var requests = 0
    static var count: Int {lock.lock();defer {lock.unlock()};return requests}
    static func reset() {lock.lock();requests = 0;lock.unlock()}
    override class func canInit(with request: URLRequest) -> Bool {true}
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {request}
    override func startLoading() {
        Self.lock.lock();Self.requests += 1;let count = Self.requests;Self.lock.unlock()
        let response = HTTPURLResponse(url:request.url!,statusCode:count < 3 ? 503:200,httpVersion:nil,headerFields:nil)!
        client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
