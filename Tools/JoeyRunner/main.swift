import Foundation
import JoeyCore

@main struct JoeyRunner {
    static func main() async {
        if ProcessSupervisor.handleInvocation() {return}
        do {
            let args = Array(CommandLine.arguments.dropFirst())
            let root: URL
            if let i = args.firstIndex(of:"--root"), i+1 < args.count {root = URL(fileURLWithPath:args[i+1])}
            else {root = Persistence.defaultRoot}
            let coordinator = try Coordinator(root:root)
            guard let command = args.first else {
                print("Usage: joey-run run REQUEST.json [--root PATH] | list [--root PATH] | setup [--root PATH]")
                return
            }
            switch command {
            case "check-drive":
                let config = try Configuration.load(root:root)
                let delivery = try DriveDelivery(remote:config.rcloneRemote)
                let result = try await delivery.preflight(tab:config.registerTab)
                for key in result.keys.sorted() {print("\(key): \(result[key]!)")}
            case "setup":
                let config = try Configuration.load(root:root)
                print("Settings: \(root.appendingPathComponent("settings.json").path)")
                print("Local ASR: \(config.modelPath == nil ? "missing":"found"); shared profile: \(config.profile == nil ? "requires account evidence":"configured")")
            case "list":
                let jobs = try await coordinator.jobs()
                print(String(decoding:try Persistence.encoder.encode(jobs),as:UTF8.self))
            case "run":
                guard args.count >= 2 else {throw JoeyError.invalid("Request path required")}
                let request: JobRequest = try Persistence.load(URL(fileURLWithPath:args[1]))
                let job = try await coordinator.run(request) {job in
                    print("\(job.state.rawValue): \(job.stage)\(job.error.map {" — "+$0} ?? "")")
                }
                print("Checkpoint: \(root.appendingPathComponent("jobs/"+job.id+"/job.json").path)")
                if job.state != .completed && !(job.state == .qaPassed && !request.fileToDrive) {exit(1)}
            default: throw JoeyError.invalid("Unknown command: \(command)")
            }
        } catch {FileHandle.standardError.write(Data((error.localizedDescription+"\n").utf8));exit(1)}
    }
}
