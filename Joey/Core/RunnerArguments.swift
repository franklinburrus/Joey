import Foundation

/// Parse the complete invocation before creating a runtime directory or starting
/// a command. A malformed scope or episode limit must never fall back silently.
public struct RunnerArguments {
    public enum Command: String {
        case run, list, setup, storage
        case storageClean = "storage-clean"
        case taxstoneInventory = "taxstone-inventory"
        case taxstoneRun = "taxstone-run"
        case taxstoneRegisterAdopt = "taxstone-adopt-register-evidence"
        case checkDrive = "check-drive"
    }
    public let command: Command
    public let root: URL
    public let request: URL?
    public let limit: Int?
    public let jobID: String?
    public let receipt: URL?
    public let readback: URL?
    public let applyMigration: Bool

    public init(_ arguments: [String]) throws {
        guard let first = arguments.first, let command = Command(rawValue: first) else {
            throw JoeyError.invalid("A supported command is required")
        }
        var rootPath: String?, requestPath: String?, limit: Int?, jobID: String?, receiptPath: String?, readbackPath: String?
        var applyMigration = false
        var index = 1
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--root" || argument == "--limit" || argument == "--job-id" ||
                argument == "--receipt" || argument == "--readback" {
                guard index + 1 < arguments.count,
                      !arguments[index + 1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !arguments[index + 1].hasPrefix("--") else {
                    throw JoeyError.invalid("\(argument) requires a value")
                }
                let value = arguments[index + 1]
                if argument == "--root" {
                    guard rootPath == nil else {throw JoeyError.invalid("--root may be supplied only once")}
                    rootPath = value
                } else if argument == "--job-id" {
                    guard command == .taxstoneRegisterAdopt, jobID == nil,
                          value.range(of:"^[A-Za-z0-9_-]{1,120}$",options:.regularExpression) != nil else {
                        throw JoeyError.invalid("--job-id requires one safe identifier for taxstone-adopt-register-evidence")
                    }
                    jobID = value
                } else if argument == "--receipt" {
                    guard command == .taxstoneRegisterAdopt, receiptPath == nil else {
                        throw JoeyError.invalid("--receipt is only valid once for taxstone-adopt-register-evidence")
                    }
                    receiptPath = value
                } else if argument == "--readback" {
                    guard command == .taxstoneRegisterAdopt, readbackPath == nil else {
                        throw JoeyError.invalid("--readback is only valid once for taxstone-adopt-register-evidence")
                    }
                    readbackPath = value
                } else {
                    guard command == .taxstoneRun, limit == nil, let parsed = Int(value), parsed > 0 else {
                        throw JoeyError.invalid("--limit requires one positive integer for taxstone-run")
                    }
                    limit = parsed
                }
                index += 2
            } else if argument == "--apply" {
                guard command == .taxstoneRegisterAdopt, !applyMigration else {
                    throw JoeyError.invalid("--apply is only valid once for taxstone-adopt-register-evidence")
                }
                applyMigration = true
                index += 1
            } else {
                guard command == .run, requestPath == nil, !argument.hasPrefix("-"), !argument.isEmpty else {
                    throw JoeyError.invalid("Unexpected argument; no operation started")
                }
                requestPath = argument
                index += 1
            }
        }
        guard command != .run || requestPath != nil else {throw JoeyError.invalid("Request path required")}
        if command == .taxstoneRegisterAdopt {
            guard jobID != nil, receiptPath != nil, readbackPath != nil else {
                throw JoeyError.invalid("taxstone-adopt-register-evidence requires --job-id, --receipt and --readback")
            }
        } else {
            guard jobID == nil, receiptPath == nil, readbackPath == nil, !applyMigration else {
                throw JoeyError.invalid("Taxstone adoption options require taxstone-adopt-register-evidence")
            }
        }
        self.command = command
        self.root = rootPath.map {URL(fileURLWithPath: $0)} ?? Persistence.defaultRoot
        self.request = requestPath.map {URL(fileURLWithPath: $0)}
        self.limit = limit
        self.jobID = jobID
        self.receipt = receiptPath.map {URL(fileURLWithPath:$0)}
        self.readback = readbackPath.map {URL(fileURLWithPath:$0)}
        self.applyMigration = applyMigration
    }
}
