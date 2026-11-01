import XCTest
import Darwin
@testable import JoeyCore

final class LocalAssistantOfflineTests: XCTestCase {
    @MainActor func testExplicitStartOfflineReplyAndOwnedStop() async throws {
        guard ProcessInfo.processInfo.environment["JOEY_LOCAL_ASSISTANT_SMOKE"] == "1" else {
            throw XCTSkip("Opt-in installed-model offline smoke; no service startup in the ordinary suite")
        }
        let client = LocalAssistant()
        // Do not stop or borrow a service another application already owns.
        do { try await client.checkModel(); throw XCTSkip("Existing Ollama listener; owned-start acceptance requires an idle port") }
        catch is AssistantFailure { }
        let service = LocalAssistantService(client:client)
        await service.start()
        do {
            XCTAssertTrue(service.owned,service.status)
            guard service.owned else { throw AssistantFailure.unavailable }
            let profile = LocalAssistantService.sandboxProfile(home:FileManager.default.homeDirectoryForCurrentUser)
            let child = try await Processes.run("/usr/bin/sandbox-exec",[
                "-p",profile,"/usr/bin/env","JOEY_LOCAL_ASSISTANT_SMOKE=client",
                "/Applications/Xcode.app/Contents/Developer/usr/bin/xctest","-XCTest",
                "JoeyCoreTests.LocalAssistantOfflineTests/testNetworkDeniedClientResponse",
                Bundle(for:LocalAssistantOfflineTests.self).bundleURL.path])
            XCTAssertEqual(child.status,0)
            let evidence = String(decoding:child.stdout,as:UTF8.self) + child.stderr
            XCTAssertTrue(evidence.contains("external TCP denied with EPERM in inference client"))
            XCTAssertTrue(evidence.contains("received nonempty response; synthetic prompt only"))
            XCTAssertTrue(evidence.contains("Executed 1 test, with 0 failures"))
            print(evidence)
            let firstStop = Task { await service.stop() }
            for _ in 0..<100 where service.owned { try await Task.sleep(nanoseconds:1_000_000) }
            let secondStop = Task { await service.stop() }
            // Start during shutdown must not create a second owned server.
            if service.starting { await service.start() }
            await firstStop.value; await secondStop.value
            XCTAssertFalse(service.owned); XCTAssertFalse(service.starting)
            do { try await client.checkModel(); XCTFail("Owned listener survived Stop") }
            catch { XCTAssertTrue(error is AssistantFailure) }
        } catch {
            await service.stop()
            throw error
        }
    }
    func testNetworkDeniedClientResponse() async throws {
        guard ProcessInfo.processInfo.environment["JOEY_LOCAL_ASSISTANT_SMOKE"] == "client" else {
            throw XCTSkip("Invoked only by the owned-service offline harness")
        }
        let socket = Darwin.socket(AF_INET,SOCK_STREAM,0)
        guard socket >= 0 else { throw AssistantFailure.unavailable }
        defer { Darwin.close(socket) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(443).bigEndian
        address.sin_addr.s_addr = inet_addr("1.1.1.1")
        let result = withUnsafePointer(to:&address) {
            $0.withMemoryRebound(to:sockaddr.self,capacity:1) {
                Darwin.connect(socket,$0,socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        let errorCode = errno
        XCTAssertEqual(result,-1); XCTAssertEqual(errorCode,EPERM)
        guard result == -1, errorCode == EPERM else { throw AssistantFailure.invalidResponse }
        print("LOCAL_ASSISTANT_SMOKE: external TCP denied with EPERM in inference client")
        let reply = try await LocalAssistant().reply(to:[.init(role:.user,content:"Reply in one short sentence: what is 2 plus 2? Do not use tools.")])
        XCTAssertFalse(reply.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
        XCTAssertLessThan(reply.utf8.count,4096)
        XCTAssertTrue(reply.contains("4") || reply.localizedCaseInsensitiveContains("four"))
        XCTAssertFalse(reply.contains("<think>")); XCTAssertFalse(reply.contains("</think>"))
        XCTAssertLessThan(reply.utf8.count,256,"This one-sentence smoke must yield a final answer, not its internal draft")
        print("LOCAL_ASSISTANT_SMOKE: received nonempty response; synthetic prompt only; no performance benchmark")
        print("LOCAL_ASSISTANT_SYNTHETIC_REPLY: " + reply)
    }

}
