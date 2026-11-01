import Foundation
import JoeyCore

/// Parse the complete invocation before creating a runtime directory or starting
/// a command. A malformed scope or episode limit must never fall back silently.
struct RunnerArguments {
    enum Command: String {
        case run, list, setup, storage
        case storageClean = "storage-clean"
        case taxstoneInventory = "taxstone-inventory"
        case taxstoneRun = "taxstone-run"
        case checkDrive = "check-drive"
    }
    let command: Command
    let root: URL
    let request: URL?
    let limit: Int?

    init(_ arguments: [String]) throws {
        guard let first = arguments.first, let command = Command(rawValue: first) else {
            throw JoeyError.invalid("A supported command is required")
        }
        var rootPath: String?, requestPath: String?, limit: Int?
        var index = 1
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--root" || argument == "--limit" {
                guard index + 1 < arguments.count,
                      !arguments[index + 1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !arguments[index + 1].hasPrefix("--") else {
                    throw JoeyError.invalid("\(argument) requires a value")
                }
                let value = arguments[index + 1]
                if argument == "--root" {
                    guard rootPath == nil else {throw JoeyError.invalid("--root may be supplied only once")}
                    rootPath = value
                } else {
                    guard command == .taxstoneRun, limit == nil, let parsed = Int(value), parsed > 0 else {
                        throw JoeyError.invalid("--limit requires one positive integer for taxstone-run")
                    }
                    limit = parsed
                }
                index += 2
            } else {
                guard command == .run, requestPath == nil, !argument.hasPrefix("-"), !argument.isEmpty else {
                    throw JoeyError.invalid("Unexpected argument; no operation started")
                }
                requestPath = argument
                index += 1
            }
        }
        guard command != .run || requestPath != nil else {throw JoeyError.invalid("Request path required")}
        self.command = command
        self.root = rootPath.map {URL(fileURLWithPath: $0)} ?? Persistence.defaultRoot
        self.request = requestPath.map {URL(fileURLWithPath: $0)}
        self.limit = limit
    }
}
