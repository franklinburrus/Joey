import Foundation
import Combine
import Darwin

/// Explicitly started local service only. Model output cannot call this owner.
/// The existing process supervisor terminates owned descendants on app exit.
@MainActor public final class LocalAssistantService: ObservableObject {
    @Published public private(set) var starting = false
    @Published public private(set) var owned = false
    @Published public private(set) var status = "Ollama has not been started by Joey."
    private var lifetime: Task<Void,Never>?
    private var shutdown: Task<Void,Never>?
    private var attempt = UUID()
    private let client: LocalAssistant
    public init(client: LocalAssistant = LocalAssistant()) { self.client = client }

    public func start() async {
        guard !starting, !owned, lifetime == nil, shutdown == nil else { return }
        let id = UUID(); attempt = id; starting = true
        status = "Checking local Ollama…"
        do {
            try await client.checkModel()
            guard attempt == id else { return }
            starting = false
            status = "Connected to existing Ollama. Joey will not stop a service it did not start."
            return
        } catch AssistantFailure.unavailable {
            // Only an unavailable listener permits starting a new owned process.
        } catch {
            guard attempt == id else { return }
            starting = false; status = error.localizedDescription; return
        }
        guard attempt == id else { return }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let binary = home.appendingPathComponent("Applications/Ollama.app/Contents/Resources/ollama")
        guard FileManager.default.isExecutableFile(atPath:binary.path) else {
            starting = false; status = "The existing Ollama installation is unavailable. Nothing was downloaded."; return
        }
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("joey-assistant-" + UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at:scratch,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            let profile = scratch.appendingPathComponent("local-only.sb")
            try Self.sandboxProfile(home:home).write(to:profile,atomically:true,encoding:.utf8)
            status = "Starting local Ollama…"
            // All values are fixed local configuration, not arbitrary inherited
            // variables or assistant-generated command arguments.
            let arguments = ["-f",profile.path,"/usr/bin/env",
                "OLLAMA_NO_CLOUD=1", "OLLAMA_HOST=127.0.0.1:11434",
                "OLLAMA_MODELS=" + home.appendingPathComponent(".ollama/models").path,
                "OLLAMA_NOPRUNE=1", "OLLAMA_KEEP_ALIVE=0", "OLLAMA_MAX_LOADED_MODELS=1",
                "OLLAMA_NUM_PARALLEL=1", "OLLAMA_MAX_QUEUE=1", "OLLAMA_DEBUG=0", binary.path, "serve"]
            lifetime = Task { [weak self] in
                defer { try? FileManager.default.removeItem(at:scratch) }
                do { _ = try await Processes.run("/usr/bin/sandbox-exec",arguments) }
                catch {
                    guard let self, self.attempt == id else { return }
                    // Do not display daemon diagnostics or locally generated keys.
                    let diagnostic = error.localizedDescription
                    let reason: String
                    if diagnostic.contains("id_ed25519") { reason = "Ollama could not create or read its local identity." }
                    else if diagnostic.contains("address already in use") { reason = "The local Ollama port is already in use." }
                    else if diagnostic.contains("sandbox_apply") { reason = "macOS could not apply the local-only service sandbox." }
                    else if diagnostic.contains("Syntax error") || diagnostic.contains("syntax error") { reason = "The local-only service sandbox profile was rejected." }
                    else { reason = "Local Ollama stopped or could not start." }
                    self.status = reason + " Media jobs are unaffected."
                }
                guard let self, self.attempt == id else { return }
                self.owned = false; self.starting = false; self.lifetime = nil
            }
            let deadline = Date().addingTimeInterval(10)
            while Date() < deadline {
                try await Task.sleep(nanoseconds:200_000_000)
                guard attempt == id, lifetime != nil else { return }
                if (try? await client.checkModel()) != nil {
                    guard attempt == id, lifetime != nil else { return }
                    owned = true; starting = false; status = "Local Ollama running; cloud and external networking disabled."
                    return
                }
            }
            await stop(message:"Local Ollama did not become ready. No download or remote fallback was attempted.")
        } catch {
            guard attempt == id else { return }
            await stop(message:"Local Ollama could not start. Media jobs are unaffected.")
            try? FileManager.default.removeItem(at:scratch)
        }
    }

    public func stop() async {
        await stop(message:"Joey’s local Ollama service is stopped.")
    }
    private func stop(message: String) async {
        if let shutdown { await shutdown.value; return }
        let id = UUID(); attempt = id
        let running = lifetime
        lifetime = nil; owned = false; starting = true
        let cleanup = Task { running?.cancel(); await running?.value }
        shutdown = cleanup
        await cleanup.value
        guard attempt == id else { return }
        shutdown = nil
        starting = false; status = message
    }
    deinit { lifetime?.cancel() }

    static func sandboxProfile(home: URL) -> String {
        // Seatbelt matches kernel paths. Foundation may abbreviate /private/var
        // back to /var, which would make a path denial miss its target.
        let resolved = realpath(home.path,nil)
        let homePath = resolved.map { String(cString:$0) } ?? home.path
        if let resolved { free(resolved) }
        func quoted(_ path: String) -> String {
            "\"" + path.replacingOccurrences(of:"\\",with:"\\\\").replacingOccurrences(of:"\"",with:"\\\"") + "\""
        }
        // The service needs to read the user's model, not modify home data.
        // Preserve existing identities; permit only a missing standard identity
        // file to be generated after explicit Start. This is not API-key auth.
        let missingIdentityFiles = ["id_ed25519", "id_ed25519.pub"].map {
            homePath + "/.ollama/" + $0
        }.filter { !FileManager.default.fileExists(atPath:$0) }
        let identityExceptions = missingIdentityFiles.map {
            "(require-not (literal \(quoted($0))))"
        }.joined(separator:" ")
        return """
        (version 1)
        (allow default)
        (deny network*)
        (allow network-outbound (remote ip "localhost:*"))
        (allow network-inbound (local ip "localhost:*"))
        (allow network-bind (local ip "localhost:*"))
        (deny file-write* (require-all (subpath \(quoted(homePath))) \(identityExceptions)))
        (deny file-write* (subpath \(quoted(homePath + "/.ollama/models"))))
        (deny file-write* (subpath \(quoted(homePath + "/Applications"))))
        (deny file-write* (subpath \(quoted(Persistence.defaultRoot.path))))
        """
    }
}
