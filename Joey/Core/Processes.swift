import Foundation

public struct ProcessResult: Sendable { public var stdout: Data; public var stderr: String; public var status: Int32 }
public enum Processes {
    public static func executable(_ name: String) throws -> String {
        if name.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: name) { return name }
        let candidates = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin",
                          FileManager.default.homeDirectoryForCurrentUser.path + "/Library/Python/3.12/bin"]
        for dir in candidates {
            let path = dir + "/" + name
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        throw JoeyError.dependency("Required local executable unavailable: \(name)")
    }
    public static func run(_ executable: String, _ arguments: [String], directory: URL? = nil,
                           output: URL? = nil, maxOutput: Int = 16*1024*1024,
                           environment: [String:String] = [:]) async throws -> ProcessResult {
        try Task.checkCancellation()
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("joey-process-"+UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true, attributes: [.posixPermissions:0o700])
        defer { try? FileManager.default.removeItem(at: temp) }
        let stdoutURL = output ?? temp.appendingPathComponent("stdout")
        let stderrURL = temp.appendingPathComponent("stderr")
        FileManager.default.createFile(atPath: stdoutURL.path, contents: nil, attributes: [.posixPermissions:0o600])
        FileManager.default.createFile(atPath: stderrURL.path, contents: nil, attributes: [.posixPermissions:0o600])
        let out = try FileHandle(forWritingTo: stdoutURL), err = try FileHandle(forWritingTo: stderrURL)
        defer { try? out.close(); try? err.close() }
        let process = Process(); process.executableURL = try ProcessSupervisor.executable()
        process.arguments = ["--supervise",String(getpid()),try self.executable(executable)]+arguments; process.currentDirectoryURL = directory
        process.standardOutput = out; process.standardError = err; process.standardInput = FileHandle.nullDevice
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + FileManager.default.homeDirectoryForCurrentUser.path + "/Library/Python/3.12/bin"
        env["HF_HUB_OFFLINE"] = "1"; env["TOKENIZERS_PARALLELISM"] = "false"
        env.merge(environment) { _, new in new }; process.environment = env
        try process.run()
        do {
            while process.isRunning { try await Task.sleep(nanoseconds: 50_000_000) }
            try Task.checkCancellation()
        } catch {
            if process.isRunning { process.terminate() }
            // Supervisor needs up to 1.05s to terminate its process group.
            // Keep this outer grace strictly longer, including scheduler delay.
            for _ in 0..<100 where process.isRunning {
                await Task.detached { try? await Task.sleep(nanoseconds:50_000_000) }.value
            }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            while process.isRunning { await Task.detached { try? await Task.sleep(nanoseconds:10_000_000) }.value }
            throw CancellationError()
        }
        // isRunning becoming false establishes termination. waitUntilExit spins
        // a thread-local run loop and can deadlock after async thread migration.
        let errors = try FileHandle(forReadingFrom: stderrURL); defer { try? errors.close() }
        let end = try errors.seekToEnd(); try errors.seek(toOffset: end > 6000 ? end-6000 : 0)
        let diagnostic = String(decoding: try errors.readToEnd() ?? Data(), as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw JoeyError.failed("\(URL(fileURLWithPath:executable).lastPathComponent) exit \(process.terminationStatus): \(diagnostic)")
        }
        let bytes = ((try FileManager.default.attributesOfItem(atPath: stdoutURL.path))[.size] as? NSNumber)?.intValue ?? 0
        guard output != nil || bytes <= maxOutput else { throw JoeyError.failed("Command output exceeded bounded capture limit") }
        return ProcessResult(stdout: output == nil ? try Data(contentsOf: stdoutURL) : Data(), stderr: diagnostic, status: process.terminationStatus)
    }
    public static func retry<T>(_ action: () async throws -> T) async throws -> T {
        for attempt in 0..<3 {
            do { return try await action() }
            catch is CancellationError { throw CancellationError() }
            catch {
                let message = error.localizedDescription.lowercased()
                let transient = ["timeout","timed out","429","500","502","503","504","connection reset","temporarily unavailable"].contains { message.contains($0) }
                if !transient || attempt == 2 { throw error }
                try await Task.sleep(nanoseconds: UInt64(attempt+1)*500_000_000)
            }
        }
        throw JoeyError.failed("Retry exhausted")
    }
}
