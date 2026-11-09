import Foundation
import Darwin

public struct ProcessResult: Sendable { public var stdout: Data; public var stderr: String; public var status: Int32 }
public enum Processes {
    /// Anonymous capture retains at most its byte budget. One 16 KiB read may
    /// detect overflow; remaining producer bytes stay in finite kernel pipes
    /// under backpressure while the existing supervisor stops the process group.
    private struct Capture {
        let pipe = Pipe()
        let limit: Int
        let tailOnly: Bool
        var bytes = Data()
        var total = 0
        var ended = false

        init(limit: Int, tailOnly: Bool = false) throws {
            self.limit = limit
            self.tailOnly = tailOnly
            let descriptor = pipe.fileHandleForReading.fileDescriptor
            let flags = fcntl(descriptor, F_GETFL)
            guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0 else {
                throw JoeyError.failed("Unable to create private process capture")
            }
        }
        mutating func drain() throws -> Bool {
            guard !ended else { return false }
            var buffer = [UInt8](repeating: 0, count: 16 * 1024)
            var progressed = false
            // A finite turn services both streams and cancellation fairly.
            for _ in 0..<16 {
                let count = Darwin.read(pipe.fileHandleForReading.fileDescriptor, &buffer, buffer.count)
                if count == 0 { ended = true; break }
                if count < 0 {
                    if errno == EINTR { continue }
                    if errno == EAGAIN { break }
                    throw JoeyError.failed("Private process capture failed")
                }
                guard count <= limit - total else {
                    throw JoeyError.failed("Command output exceeded bounded capture limit")
                }
                total += count
                bytes.append(contentsOf: buffer.prefix(count))
                if tailOnly, bytes.count > 6000 { bytes.removeFirst(bytes.count - 6000) }
                progressed = true
            }
            return progressed
        }
        func close() {
            try? pipe.fileHandleForReading.close()
            try? pipe.fileHandleForWriting.close()
        }
    }
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
    /// Shell interpreters never receive Joey helper work, including credential stdin.
    private static let blockedHelperNames: Set<String> = ["sh","bash","zsh","csh","ksh","fish","dash"]
    public static func refuseShellHelper(_ executable: String) throws {
        let name = URL(fileURLWithPath:executable).lastPathComponent.lowercased()
        if blockedHelperNames.contains(name) {
            throw JoeyError.invalid("Shell interpreters are not permitted as Joey helpers")
        }
    }
    /// Mail and other secret-bearing helpers may only use an owned Python binary.
    public static func credentialPython(_ configured: String?) throws -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let fallback = home.appendingPathComponent("Dub/.venv/bin/python").path
        let requested = (configured?.isEmpty == false) ? configured! : fallback
        guard requested.hasPrefix("/") else {throw JoeyError.invalid("Mail Python path must be absolute")}
        guard let resolved = realpath(requested,nil) else {throw JoeyError.dependency("Mail Python path is missing")}
        defer {free(resolved)}
        let path = String(cString:resolved)
        try refuseShellHelper(path)
        let name = URL(fileURLWithPath:path).lastPathComponent.lowercased()
        guard name == "python" || name.hasPrefix("python3") else {
            throw JoeyError.invalid("Mail credentials require a python executable, not \(name)")
        }
        let allowedRoots = [
            home.appendingPathComponent("Dub/.venv/bin").path,
            home.appendingPathComponent(".venv/bin").path
        ]
        guard allowedRoots.contains(where:{path.hasPrefix($0 + "/")}),
              FileManager.default.isExecutableFile(atPath:path) else {
            throw JoeyError.invalid("Mail Python must be an owned virtualenv interpreter under Dub/.venv or ~/.venv")
        }
        return path
    }
    /// Strip likely secret material from helper diagnostics before persistence.
    public static func sanitizeDiagnostic(_ text: String, status: Int32, executable: String) -> String {
        var lines = text.split(separator:"\n",omittingEmptySubsequences:false).map(String.init)
        let patterns = [
            "(?i)(api[_-]?key|access[_-]?token|refresh[_-]?token|authorization|bearer|password|passwd|secret|credential)[=:\\s]+[\"']?[^\\s\"']+",
            "(?i)bearer\\s+[A-Za-z0-9\\-._~+/=]+",
            "sk-[A-Za-z0-9]{10,}",
            "AIza[0-9A-Za-z\\-_]{10,}",
            "ya29\\.[0-9A-Za-z\\-_]+"
        ]
        for index in lines.indices {
            var line = lines[index]
            for pattern in patterns {
                line = line.replacingOccurrences(of:pattern,with:"[redacted]",options:.regularExpression)
            }
            if line.count > 400 {line = String(line.prefix(400))+"…"}
            lines[index] = line
        }
        let body = lines.joined(separator:"\n").trimmingCharacters(in:.whitespacesAndNewlines)
        let name = URL(fileURLWithPath:executable).lastPathComponent
        if body.isEmpty {return "\(name) exit \(status)"}
        return "\(name) exit \(status): \(body)"
    }
    /// maxOutput bounds each captured stream while the helper runs. Stderr
    /// retains its final 6000 bytes. Explicit stdout files bypass capture only.
    public static func run(_ executable: String, _ arguments: [String], directory: URL? = nil,
                           output: URL? = nil, maxOutput: Int = 16*1024*1024,
                           environment: [String:String] = [:], input: Data? = nil,
                           timeout: TimeInterval? = nil) async throws -> ProcessResult {
        try Task.checkCancellation()
        guard maxOutput >= 0, (input?.count ?? 0) <= 16384, timeout == nil || (timeout!.isFinite && timeout! > 0) else {
            throw JoeyError.invalid("Invalid bounded process input or deadline")
        }
        let resolvedExecutable = try self.executable(executable)
        // Credential-bearing stdin never enters a shell interpreter.
        if input != nil {try refuseShellHelper(resolvedExecutable)}
        let storageRoot = StorageManager.processingRoot
        let toolName = URL(fileURLWithPath:resolvedExecutable).lastPathComponent
        let writesMedia = toolName == "ffmpeg" || toolName == "yt-dlp" || toolName.hasPrefix("python") ||
            (toolName == "rclone" && arguments.first == "copyto" && arguments.count > 2 && arguments[2].hasPrefix("/"))
        let storageLease = try storageRoot.map {try ProcessingLock(directory:$0,name:"storage-workers.lock",shared:true)}
        defer {withExtendedLifetime(storageLease) {}}
        var stdout = try Capture(limit: maxOutput)
        defer { stdout.close() }
        var stderr = try Capture(limit: maxOutput, tailOnly: true)
        defer { stderr.close() }
        var outputFile: FileHandle?
        if let output {
            FileManager.default.createFile(atPath: output.path, contents: nil, attributes: [.posixPermissions:0o600])
            outputFile = try FileHandle(forWritingTo: output)
            stdout.ended = true
        }
        defer { try? outputFile?.close() }
        let process = Process(); process.executableURL = try ProcessSupervisor.executable()
        process.arguments = ["--supervise",String(getpid())]+(storageRoot.map {["--storage-root",$0.path]} ?? [])+[resolvedExecutable]+arguments; process.currentDirectoryURL = directory
        process.standardOutput = outputFile ?? stdout.pipe.fileHandleForWriting
        process.standardError = stderr.pipe.fileHandleForWriting
        process.standardInput = FileHandle.nullDevice
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
        let deadline = timeout.map {ProcessInfo.processInfo.systemUptime + $0}
        do {
            try stdout.pipe.fileHandleForWriting.close()
            try stderr.pipe.fileHandleForWriting.close()
            try inputPipe?.fileHandleForReading.close()
            var nextCapacityCheck = Date()
            var drainDeadline: TimeInterval?
            while process.isRunning || !stdout.ended || !stderr.ended {
                try Task.checkCancellation()
                if let deadline, ProcessInfo.processInfo.systemUptime >= deadline {throw JoeyError.failed("Local helper timed out")}
                if !process.isRunning {
                    if drainDeadline == nil { drainDeadline = ProcessInfo.processInfo.systemUptime + 2 }
                    if ProcessInfo.processInfo.systemUptime >= drainDeadline! {
                        throw JoeyError.failed("Local helper output did not close")
                    }
                }
                let stdoutProgress = try stdout.drain()
                let stderrProgress = try stderr.drain()
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
                if stdoutProgress || stderrProgress { await Task.yield() }
                else if process.isRunning || !stdout.ended || !stderr.ended {
                    try await Task.sleep(nanoseconds: 50_000_000)
                }
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
        let diagnostic = String(decoding: stderr.bytes, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw JoeyError.failed(sanitizeDiagnostic(diagnostic,status:process.terminationStatus,executable:resolvedExecutable))
        }
        return ProcessResult(stdout: stdout.bytes, stderr: diagnostic, status: process.terminationStatus)
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
