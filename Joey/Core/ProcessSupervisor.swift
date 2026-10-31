import Foundation
import Darwin

/// A native child supervisor shares the application binary. It owns a distinct
/// process group for the tool and its descendants and survives long enough to
/// terminate that group if the app disappears. It never opens a UI or a service.
public enum ProcessSupervisor {
    private static var stopping: Int32 = 0
    public static func handleInvocation() -> Bool {
        let args = CommandLine.arguments
        guard args.count >= 4, args[1] == "--supervise", let parent = Int32(args[2]) else {return false}
        signal(SIGTERM) {_ in ProcessSupervisor.stopping = 1}
        signal(SIGINT) {_ in ProcessSupervisor.stopping = 1}
        var attributes: posix_spawnattr_t?
        guard posix_spawnattr_init(&attributes) == 0 else {exit(125)}
        defer {posix_spawnattr_destroy(&attributes)}
        posix_spawnattr_setflags(&attributes,Int16(POSIX_SPAWN_SETPGROUP))
        posix_spawnattr_setpgroup(&attributes,0)
        let strings = args.dropFirst(3).map {strdup($0)}
        defer {strings.forEach {free($0)}}
        var argv = strings+[nil]
        let envStrings = ProcessInfo.processInfo.environment.map {strdup($0.key+"="+$0.value)}
        defer {envStrings.forEach {free($0)}}
        var env = envStrings+[nil]
        var child: pid_t = 0
        let status = posix_spawn(&child,args[3],nil,&attributes,&argv,&env)
        guard status == 0 else {exit(status)}
        var result: Int32 = 0
        while waitpid(child,&result,WNOHANG) == 0 {
            if stopping != 0 || getppid() != parent || kill(parent,0) != 0 {
                kill(-child,SIGTERM)
                for _ in 0..<20 {
                    if waitpid(child,&result,WNOHANG) != 0 {kill(-child,SIGKILL);exit(130)}
                    usleep(50_000)
                }
                kill(-child,SIGKILL); _ = waitpid(child,&result,0); exit(130)
            }
            usleep(50_000)
        }
        // A successful wrapper must not leave background descendants behind.
        kill(-child,SIGTERM)
        for _ in 0..<10 {
            if kill(-child,0) != 0 {break}
            usleep(50_000)
        }
        if kill(-child,0) == 0 {kill(-child,SIGKILL)}
        let code = (result & 0x7f) == 0 ? (result >> 8)&0xff : 128+(result&0x7f)
        exit(code)
    }
    static func executable() throws -> URL {
        #if SWIFT_PACKAGE
        var directory = Bundle.module.bundleURL.deletingLastPathComponent()
        for _ in 0..<6 {
            let candidate = directory.appendingPathComponent("joey-run")
            if FileManager.default.isExecutableFile(atPath:candidate.path) {return candidate}
            directory.deleteLastPathComponent()
        }
        #endif
        if let current = Bundle.main.executableURL, current.lastPathComponent != "xctest" {return current}
        throw JoeyError.dependency("Native subprocess supervisor is missing from this build")
    }
}
