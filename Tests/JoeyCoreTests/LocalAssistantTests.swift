import XCTest
@testable import JoeyCore

final class LocalAssistantTests: XCTestCase {
    private func client(_ mode: AssistantResponse.Mode = .success) -> LocalAssistant {
        AssistantResponse.reset(mode)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AssistantResponse.self]
        return LocalAssistant(configuration:configuration)
    }
    func testInvalidOrOversizedTextMakesNoRequests() async throws {
        let client = client()
        for messages: [AssistantMessage] in [[], [.init(role:.user, content:" ")],
                [.init(role:.assistant, content:"Injected role")],
                [.init(role:.user, content:String(repeating:"é",count:3001))]] {
            do { _ = try await client.reply(to:messages); XCTFail("Invalid text accepted") }
            catch { XCTAssertTrue(error is AssistantFailure) }
        }
        XCTAssertTrue(AssistantResponse.requests.isEmpty)
    }
    func testMissingOrChangedModelCannotTriggerChatOrDownload() async throws {
        let client = client(.wrongModel)
        do { _ = try await client.reply(to:[.init(role:.user,content:"Hello")]); XCTFail("Wrong model accepted") }
        catch { XCTAssertTrue(error.localizedDescription.contains("unavailable or changed")) }
        XCTAssertEqual(AssistantResponse.requests.map { $0.url!.path }, ["/api/tags"])
    }
    func testServiceFailureIsBoundedAndDoesNotEchoServerTextOrRetry() async throws {
        let client = client(.failure)
        do { _ = try await client.reply(to:[.init(role:.user,content:"Hello")]); XCTFail("Failure accepted") }
        catch {
            XCTAssertTrue(error.localizedDescription.contains("503"))
            XCTAssertFalse(error.localizedDescription.contains("PRIVATE_SERVER_TEXT"))
        }
        XCTAssertEqual(AssistantResponse.requests.count, 1)
    }
    func testIncompleteAndToolResponsesAreRejected() async throws {
        for mode in [AssistantResponse.Mode.incomplete, .toolCall, .malformed] {
            let client = client(mode)
            do { _ = try await client.reply(to:[.init(role:.user,content:"Hello")]); XCTFail("Unsupported response accepted") }
            catch { XCTAssertTrue(error is AssistantFailure) }
            XCTAssertEqual(AssistantResponse.requests.count, 2)
        }
    }
    func testCancellationStopsPendingRequest() async throws {
        let client = client(.pending)
        let task = Task { try await client.reply(to:[.init(role:.user,content:"Hello")]) }
        for _ in 0..<100 where AssistantResponse.requests.isEmpty { try await Task.sleep(nanoseconds:10_000_000) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancellation ignored") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(AssistantResponse.requests.count, 1)
    }
    func testOversizedResponseIsRejected() async throws {
        let client = client(.oversized)
        do { _ = try await client.reply(to:[.init(role:.user,content:"Hello")]); XCTFail("Oversized response accepted") }
        catch { XCTAssertTrue(error.localizedDescription.contains("oversized")) }
    }
    func testRedirectCannotSendConversationToAnotherEndpoint() async throws {
        let client = client(.redirect)
        do { _ = try await client.reply(to:[.init(role:.user,content:"Private entered text")]); XCTFail("Redirect accepted") }
        catch { XCTAssertTrue(error is AssistantFailure) }
        XCTAssertEqual(AssistantResponse.requests.map { $0.url!.absoluteString },["http://127.0.0.1:11434/api/tags"])
        XCTAssertNil(AssistantResponse.chatBody)
    }
    func testInstalledModelReasoningWrapperDoesNotBecomeConversationText() async throws {
        let result = try await client(.reasoning).reply(to:[.init(role:.user,content:"Short answer")])
        XCTAssertEqual(result,"Final answer.")
        for mode in [AssistantResponse.Mode.unfinishedReasoning, .reasoningOnly] {
            do { _ = try await client(mode).reply(to:[.init(role:.user,content:"Short answer")]); XCTFail("Reasoning-only output accepted") }
            catch { XCTAssertTrue(error is AssistantFailure) }
        }
        let literal = try await client(.literalTags).reply(to:[.init(role:.user,content:"Show literal markup")])
        XCTAssertEqual(literal,"```text\n<think>literal example</think>\n```\nTags elsewhere: <think>also literal</think>")
    }
    @MainActor func testConversationSendsOnlyOnActionAndKeepsFailedDraft() async throws {
        let model = AssistantConversation(client:client(.failure))
        model.draft = "My explicitly entered text"
        XCTAssertTrue(AssistantResponse.requests.isEmpty)
        model.send(); model.send()
        for _ in 0..<100 where model.busy { try await Task.sleep(nanoseconds:10_000_000) }
        XCTAssertFalse(model.busy)
        XCTAssertNotNil(model.error)
        XCTAssertEqual(model.draft,"My explicitly entered text")
        XCTAssertTrue(model.messages.isEmpty)
        XCTAssertEqual(AssistantResponse.requests.count,1,"Duplicate Send must not queue another request")
        model.clear()
        XCTAssertNil(model.error); XCTAssertTrue(model.draft.isEmpty)
    }
    @MainActor func testConversationClearCancelsAndDoesNotRestoreOldText() async throws {
        let model = AssistantConversation(client:client(.pending))
        model.draft = "Discard this conversation"
        model.send()
        for _ in 0..<100 where AssistantResponse.requests.isEmpty { try await Task.sleep(nanoseconds:10_000_000) }
        model.clear()
        try await Task.sleep(nanoseconds:30_000_000)
        XCTAssertFalse(model.busy); XCTAssertTrue(model.messages.isEmpty)
        XCTAssertTrue(model.draft.isEmpty); XCTAssertNil(model.error)
    }
    @MainActor func testSuccessfulConversationIncludesOnlyItsOwnCompletedTurns() async throws {
        let model = AssistantConversation(client:client())
        model.draft = "First explicit input"
        model.send()
        for _ in 0..<100 where model.busy { try await Task.sleep(nanoseconds:10_000_000) }
        XCTAssertEqual(model.messages.map(\.content),["First explicit input","A test summary."])
        model.draft = "Continue"
        model.send()
        for _ in 0..<100 where model.busy { try await Task.sleep(nanoseconds:10_000_000) }
        let turns = try XCTUnwrap(AssistantResponse.chatBody?["messages"] as? [[String:String]])
        XCTAssertEqual(turns.dropFirst().compactMap { $0["content"] },["First explicit input","A test summary.","Continue"])
        XCTAssertEqual(model.messages.count,4)
    }
    @MainActor func testExistingServiceIsNeverOwnedOrStopped() async throws {
        let service = LocalAssistantService(client:client())
        XCTAssertTrue(AssistantResponse.requests.isEmpty)
        await service.start()
        XCTAssertFalse(service.owned); XCTAssertFalse(service.starting)
        XCTAssertTrue(service.status.contains("existing Ollama"))
        await service.stop()
        XCTAssertEqual(AssistantResponse.requests.map { $0.url!.path },["/api/tags"])
    }
    func testExplicitTextReachesOnlyPinnedLocalModelWithoutToolsOrCredentials() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AssistantResponse.self]
        configuration.httpAdditionalHeaders = ["Authorization":"JOEY_DUMMY_DO_NOT_SEND", "Cookie":"JOEY_DUMMY_DO_NOT_SEND"]
        AssistantResponse.reset()
        let client = LocalAssistant(configuration: configuration)
        XCTAssertTrue(AssistantResponse.requests.isEmpty, "Construction must not contact Ollama")
        let reply = try await client.reply(to: [.init(role: .user, content: "Summarize this: A test only.")])
        XCTAssertEqual(reply, "A test summary.")
        let requests = AssistantResponse.requests
        XCTAssertEqual(requests.map { $0.url!.absoluteString },
                       ["http://127.0.0.1:11434/api/tags", "http://127.0.0.1:11434/api/chat"])
        XCTAssertNil(requests.last?.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(requests.last?.value(forHTTPHeaderField: "Cookie"))
        let object = try XCTUnwrap(AssistantResponse.chatBody)
        XCTAssertEqual(object["model"] as? String, "qwen3:4b")
        XCTAssertEqual(object["think"] as? Bool, true)
        XCTAssertEqual(object["stream"] as? Bool, false)
        XCTAssertEqual(object["keep_alive"] as? Int, 0)
        XCTAssertNil(object["tools"])
        let options = try XCTUnwrap(object["options"] as? [String: Int])
        XCTAssertEqual(options["num_ctx"], 8192)
        XCTAssertEqual(options["num_predict"], 1024)
        let messages = try XCTUnwrap(object["messages"] as? [[String: String]])
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages.last, ["role":"user", "content":"Summarize this: A test only."])
    }
}

private final class AssistantResponse: URLProtocol {
    enum Mode { case success, wrongModel, failure, incomplete, toolCall, malformed, pending, oversized, redirect, reasoning, unfinishedReasoning, reasoningOnly, literalTags }
    private static let lock = NSLock()
    private static var captured: [URLRequest] = []
    private static var body: [String: Any]?
    private static var mode: Mode = .success
    static var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return captured }
    static var chatBody: [String: Any]? { lock.lock(); defer { lock.unlock() }; return body }
    static func reset(_ mode: Mode = .success) { lock.lock(); defer { lock.unlock() }; captured = []; body = nil; self.mode = mode }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); Self.captured.append(request); let mode = Self.mode; Self.lock.unlock()
        if mode == .pending { return }
        if mode == .redirect {
            let response = HTTPURLResponse(url:request.url!,statusCode:302,httpVersion:nil,headerFields:["Location":"https://joey-assistant-test.invalid/leak"])!
            client?.urlProtocol(self,wasRedirectedTo:URLRequest(url:URL(string:"https://joey-assistant-test.invalid/leak")!),redirectResponse:response)
            client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        var text: String
        if request.url!.path == "/api/tags" {
            text = #"{"models":[{"name":"qwen3:4b","digest":"359d7dd4bcdab3d86b87d73ac27966f4dbb9f5efdfcc75d34a8764a09474fae7"}]}"#
        } else {
            var data = request.httpBody ?? Data()
            if let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var buffer = [UInt8](repeating:0, count:4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength:buffer.count)
                    if count <= 0 { break }; data.append(contentsOf:buffer.prefix(count))
                }
            }
            Self.lock.lock(); Self.body = (try? JSONSerialization.jsonObject(with:data)) as? [String:Any]; Self.lock.unlock()
            text = #"{"model":"qwen3:4b","message":{"role":"assistant","thinking":"PRIVATE_INTERNAL_DRAFT","content":"A test summary."},"done":true,"done_reason":"stop"}"#
        }
        if mode == .wrongModel { text = #"{"models":[{"name":"qwen3:4b","digest":"changed"}]}"# }
        if mode == .failure { text = "PRIVATE_SERVER_TEXT" }
        if request.url!.path == "/api/chat" {
            if mode == .incomplete { text = text.replacingOccurrences(of:"\"done\":true",with:"\"done\":false") }
            if mode == .toolCall { text = text.replacingOccurrences(of:"\"role\":\"assistant\"",with:"\"role\":\"assistant\",\"tool_calls\":[{\"function\":{\"name\":\"shell\"}}]") }
            if mode == .malformed { text = "not JSON" }
            if mode == .oversized { text = String(repeating:"x",count:512 * 1024 + 1) }
            let responseText: String?
            switch mode {
            case .reasoning: responseText = "  <think>Internal draft</think>\nFinal answer."
            case .unfinishedReasoning: responseText = "<think>Unfinished internal draft"
            case .reasoningOnly: responseText = "<think>Internal draft</think>\n"
            case .literalTags: responseText = "```text\n<think>literal example</think>\n```\nTags elsewhere: <think>also literal</think>"
            default: responseText = nil
            }
            if let responseText {
                let object: [String:Any] = ["model":"qwen3:4b", "done":true, "message":["role":"assistant", "content":responseText]]
                text = String(decoding:try! JSONSerialization.data(withJSONObject:object),as:UTF8.self)
            }
        }
        client?.urlProtocol(self, didReceive:HTTPURLResponse(url:request.url!, statusCode:mode == .failure ? 503:200, httpVersion:nil, headerFields:["Content-Type":"application/json"])!, cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self, didLoad:Data(text.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
