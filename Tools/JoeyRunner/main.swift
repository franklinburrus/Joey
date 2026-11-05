import Foundation
import JoeyCore

@main struct JoeyRunner {
    static func main() async {
        if ProcessSupervisor.handleInvocation() {return}
        do {
            let args = Array(CommandLine.arguments.dropFirst())
            guard !args.isEmpty else {
                print("Usage: joey-run run REQUEST.json [--root PATH] | list [--root PATH] | setup [--root PATH]")
                return
            }
            let invocation = try RunnerArguments(args)
            let root = invocation.root
            let coordinator = try Coordinator(root:root)
            switch invocation.command {
            case .storage:
                print(String(decoding:try Persistence.encoder.encode(StorageManager.inspect(root:root)),as:UTF8.self))
            case .storageClean:
                print(String(decoding:try Persistence.encoder.encode(StorageManager.clean(root:root)),as:UTF8.self))
            case .taxstoneInventory:
                let library = try TaxstoneLibrary(root:root)
                let state = try await library.inventory()
                print(String(decoding:try Persistence.encoder.encode(state),as:UTF8.self))
            case .taxstoneRun:
                let library = try TaxstoneLibrary(root:root)
                let state = try await library.run(limit:invocation.limit,jobProgress:{job in print("\(job.id): \(job.stage) \(job.error ?? "")")})
                print("Discovered: \(state.discoveredCount); completed: \(state.completedCount); remaining: \(state.remainingCount)")
            case .checkDrive:
                let config = try Configuration.load(root:root)
                let delivery = try DriveDelivery(remote:config.rcloneRemote)
                let result = try await delivery.preflight(tab:config.registerTab)
                for key in result.keys.sorted() {print("\(key): \(result[key]!)")}
            case .setup:
                let config = try Configuration.load(root:root)
                print("Settings: \(root.appendingPathComponent("settings.json").path)")
                print("Local ASR: \(config.modelPath == nil ? "missing":"found"); shared profile: \(config.profile == nil ? "requires account evidence":"configured")")
            case .list:
                let inventory = try await coordinator.inventory()
                print(String(decoding:try Persistence.encoder.encode(inventory.jobs),as:UTF8.self))
                for failure in inventory.failures {
                    FileHandle.standardError.write(Data(("Checkpoint " + failure.directoryID + ". " + failure.message + "\n").utf8))
                }
            case .run:
                guard let path = invocation.request else {throw JoeyError.invalid("Request path required")}
                let request: JobRequest = try Persistence.load(path)
                let job = try await coordinator.run(request) {job in
                    print("\(job.state.rawValue): \(job.stage)\(job.error.map {" — "+$0} ?? "")")
                }
                print("Checkpoint: \(root.appendingPathComponent("jobs/"+job.id+"/job.json").path)")
                if job.state != .completed && !(job.state == .qaPassed && !request.fileToDrive) {exit(1)}
            }
        } catch {FileHandle.standardError.write(Data((error.localizedDescription+"\n").utf8));exit(1)}
    }
}
