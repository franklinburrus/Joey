import Foundation
import Combine

/// This state owns only text explicitly sent from the assistant's editor.
/// It has no media-job, filesystem, clipboard, account or execution capability.
@MainActor public final class AssistantConversation: ObservableObject {
    @Published public var draft = ""
    @Published public private(set) var messages: [AssistantMessage] = []
    @Published public private(set) var busy = false
    @Published public private(set) var error: String?
    private let client: LocalAssistant
    private var task: Task<Void,Never>?
    private var attempt = UUID()
    public init(client: LocalAssistant = LocalAssistant()) { self.client = client }
    public func send() {
        guard !busy, !draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { return }
        let input = AssistantMessage(role:.user,content:draft)
        let history = messages + [input]
        let id = UUID(); attempt = id; busy = true; error = nil
        task = Task { [weak self, client] in
            do {
                let response = try await client.reply(to:history)
                guard let self, self.attempt == id else { return }
                self.messages = history + [.init(role:.assistant,content:response)]
                self.draft = ""; self.busy = false; self.task = nil
            } catch {
                guard let self, self.attempt == id else { return }
                self.error = error is CancellationError ? nil:error.localizedDescription
                self.busy = false; self.task = nil
            }
        }
    }
    public func stop() {
        attempt = UUID(); task?.cancel(); task = nil; busy = false; error = nil
    }
    public func clear() { stop(); messages = []; draft = "" }
    deinit { task?.cancel() }
}
