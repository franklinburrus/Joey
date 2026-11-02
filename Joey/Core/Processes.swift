import Foundation
import Darwin

public struct ProcessResult: Sendable { public var stdout: Data; public var stderr: String; public var status: Int32 }
public enum Processes {
    /// Helpers need local paths/locale, not the desktop or developer's API keys.
    /// Explicit overrides pass through the same allowlist as inherited values.
    static func childEnvironment(_ parent: [String:String], overrides: [String:String] = [:]) -> [String:String] {
        let allowed = ["HOME", "USER", "LOGNAME", "TMPDIR", "LANG", "LC_ALL"]
        let inputs = parent.merging(overrides) { _, new in new }
        var result = inputs.filter {allowed.contains($0.key)}
        result["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + FileManager.default.homeDirectoryForCurrentUser.path + "/Library/Python/3.12/bin"
        result["HF_HUB_OFFLINE"] = "1"
        result["TOKENIZERS_PARALLELISM"] = "false"
        return result
    }
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
                           environment: [String:String] = [:], input: Data? = nil,
                           timeout: TimeInterval? = nil) async throws -> ProcessResult {
        try Task.checkCancellation()
        guard (input?.count ?? 0) <= 16384, timeout == nil || (timeout!.isFinite && timeout! > 0) else {
            throw JoeyError.invalid("Invalid bounded process input or deadline")
        }
        let storageRoot = StorageManager.processingRoot
        let toolName = URL(fileURLWithPath:executable).lastPathComponent
        let writesMedia = toolName == "ffmpeg" || toolName == "yt-dlp" || toolName.hasPrefix("python") ||
            (toolName == "rclone" && arguments.first == "copyto" && arguments.count > 2 && arguments[2].hasPrefix("/"))
        let storageLease = try storageRoot.map {try ProcessingLock(directory:$0,name:"storage-workers.lock",shared:true)}
        defer {withExtendedLifetime(storageLease) {}}
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
        process.arguments = ["--supervise",String(getpid())]+(storageRoot.map {["--storage-root",$0.path]} ?? [])+[try self.executable(executable)]+arguments; process.currentDirectoryURL = directory
        process.standardOutput = out; process.standardError = err; process.standardInput = FileHandle.nullDevice
        let inputPipe = input.map {_ in Pipe()}
        var inputOpen = inputPipe != nil
        var written = 0
        if let pipe = inputPipe {
            // The parent pumps a small anonymous pipe without blocking any
            // executor. The supervisor inherits fd 0; no secret touches disk.
            process.standardInput = pipe.fileHandleForReading
            let fd = pipe.fileHandleForWriting.fileDescriptor
            guard fcntl(fd,F_SETFL,O_NONBLOCK) == 0, fcntl(fd,F_SETNOSIGPIPE,1) == 0 else {
                throw JoeyError.failed("Unable to create private process input")
            }
        }
        defer {
            try? inputPipe?.fileHandleForReading.close()
            if inputOpen {try? inputPipe?.fileHandleForWriting.close()}
        }
        process.environment = childEnvironment(ProcessInfo.processInfo.environment,overrides:environment)
        try process.run()
        try inputPipe?.fileHandleForReading.close()
        let deadline = timeout.map {ProcessInfo.processInfo.systemUptime + $0}
        do {
            var nextCapacityCheck = Date()
            while process.isRunning {
                if let deadline, ProcessInfo.processInfo.systemUptime >= deadline {throw JoeyError.failed("Local helper timed out")}
                if inputOpen, let input, let pipe = inputPipe {
                    if written < input.count {
                        let count = input.withUnsafeBytes {bytes in
                            Darwin.write(pipe.fileHandleForWriting.fileDescriptor,bytes.baseAddress!.advanced(by:written),input.count-written)
                        }
                        if count > 0 {written += count}
                        else if count < 0 && errno == EPIPE {written = input.count}
                        else if count < 0 && errno != EAGAIN && errno != EINTR {throw JoeyError.failed("Private process input failed")}
                    }
                    if written == input.count {try pipe.fileHandleForWriting.close();inputOpen = false}
                }
                try await Task.sleep(nanoseconds: 50_000_000)
                if writesMedia,let storageRoot, Date() >= nextCapacityCheck {
                    // Stop before consuming the OS reserve. Partial attempt stays
                    // owned and recoverable; no new worker starts during cleanup.
                    try StorageManager.checkCapacity(at:storageRoot,requiredBytes:128*1024*1024)
                    nextCapacityCheck = Date().addingTimeInterval(5)
                }
            }
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
            throw error
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
