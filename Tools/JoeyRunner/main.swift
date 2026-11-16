import Foundation
import JoeyCore
import Darwin

@main struct JoeyRunner {
    static func main() async {
        if ProcessSupervisor.handleInvocation() {return}
        do {
            let args = Array(CommandLine.arguments.dropFirst())
            guard !args.isEmpty else {
                print("Usage: joey-run run REQUEST.json [--root PATH] | list [--root PATH] | setup [--root PATH] | taxstone-adopt-register-evidence --root PATH --job-id ID --receipt PATH --readback PATH [--apply]")
                return
            }
            let invocation = try RunnerArguments(args)
            let root = invocation.root
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
                let coordinator = try Coordinator(root:root)
                let inventory = try await coordinator.inventory()
                print(String(decoding:try Persistence.encoder.encode(inventory.jobs),as:UTF8.self))
                for failure in inventory.failures {
                    FileHandle.standardError.write(Data(("Checkpoint " + failure.directoryID + ". " + failure.message + "\n").utf8))
                }
            case .run:
                let coordinator = try Coordinator(root:root)
                guard let path = invocation.request else {throw JoeyError.invalid("Request path required")}
                let request: JobRequest = try Persistence.load(path)
                let job = try await coordinator.run(request) {job in
                    print("\(job.state.rawValue): \(job.stage)\(job.error.map {" — "+$0} ?? "")")
                }
                print("Checkpoint: \(root.appendingPathComponent("jobs/"+job.id+"/job.json").path)")
                if job.state != .completed && !(job.state == .qaPassed && !request.fileToDrive) {exit(1)}
            case .taxstoneRegisterAdopt:
                guard let jobID = invocation.jobID, let receiptURL = invocation.receipt,
                      let readbackURL = invocation.readback else {throw JoeyError.invalid("Taxstone adoption inputs missing")}
                let rootValues = try root.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])
                guard rootValues.isDirectory == true, rootValues.isSymbolicLink != true else {
                    throw JoeyError.invalid("Taxstone adoption root must be an existing real directory")
                }
                let lock = try ProcessingLock(directory:root)
                defer {withExtendedLifetime(lock) {}}
                let jobDirectory = root.appendingPathComponent("jobs",isDirectory:true).appendingPathComponent(jobID,isDirectory:true)
                let directoryValues = try jobDirectory.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])
                guard directoryValues.isDirectory == true, directoryValues.isSymbolicLink != true else {
                    throw JoeyError.failed("Selected Taxstone job directory is absent or unsafe")
                }
                let jobURL = jobDirectory.appendingPathComponent("job.json")
                let jobValues = try jobURL.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey])
                guard jobValues.isRegularFile == true, jobValues.isSymbolicLink != true else {
                    throw JoeyError.failed("Selected Taxstone job checkpoint is absent or unsafe")
                }
                let priorData = try Data(contentsOf:jobURL)
                let priorHash = Integrity.sha256(priorData)
                var job: JobRecord = try Persistence.decoder.decode(JobRecord.self,from:priorData)
                guard job.id == jobID else {throw JoeyError.failed("Taxstone job ID does not match its runtime directory")}
                func readEvidence(_ url:URL) throws -> Data {
                    let values = try url.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey])
                    guard values.isRegularFile == true,values.isSymbolicLink != true else {
                        throw JoeyError.failed("Taxstone adoption evidence input is absent or unsafe: \(url.lastPathComponent)")
                    }
                    return try Data(contentsOf:url)
                }
                let receiptData = try readEvidence(receiptURL)
                let readbackData = try readEvidence(readbackURL)
                let receiptHash = Integrity.sha256(receiptData),readbackHash = Integrity.sha256(readbackData)
                guard job.request.owner == .taxstone,job.request.mode == .fullShow,job.request.fileToDrive,
                      job.state == .completed,job.completionReconciliationRequired != true,
                      job.registerRows.isEmpty,let source = job.source,source.owner == .taxstone,
                      source.id == job.request.sourceID,source.title == job.request.title,
                      source.id.hasPrefix("soundcloud:"),source.kind == .audio,source.hasAudio,
                      source.sha256.count == 64,
                      job.request.expectedSourceSHA256 == nil || job.request.expectedSourceSHA256 == source.sha256,
                      job.request.archiveReference == source.archiveReference,
                      job.folderID != nil,job.hasRequiredPackageEvidence else {
                    throw JoeyError.failed("Selected checkpoint is not a package-verified Taxstone Full Show without pending register reconciliation")
                }
                let copiedSource = jobDirectory.appendingPathComponent(URL(fileURLWithPath:source.path).lastPathComponent)
                let copiedSourceValues = try copiedSource.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
                guard copiedSourceValues.isRegularFile == true,copiedSourceValues.isSymbolicLink != true,
                      let copiedBytes = copiedSourceValues.fileSize,Int64(copiedBytes) == source.bytes,
                      try Integrity.sha256(copiedSource) == source.sha256 else {
                    throw JoeyError.failed("Task/runtime job copy lacks the verified accepted archive; no migration applied")
                }
                job.source!.path = copiedSource.path
                try Records.validateSavedManifest(job:job,directory:jobDirectory)
                if let current = job.taxstoneRegisterEvidence {
                    guard job.hasRequiredCompletionEvidence,
                          current.provenance?.kind == .adoptedExternalReadback,
                          current.provenance?.receiptSHA256 == receiptHash,
                          current.provenance?.readbackSHA256 == readbackHash else {
                        throw JoeyError.failed("A different Taxstone register receipt is already saved; no checkpoint changed")
                    }
                    print("Taxstone register evidence already adopted and validated; no files changed.")
                    return
                }
                let evidence = try Records.adoptTaxstoneRegisterEvidence(job:job,receiptData:receiptData,readbackData:readbackData)
                job.taxstoneRegisterEvidence = evidence
                guard job.hasRequiredCompletionEvidence,job.registerRows.isEmpty else {
                    throw JoeyError.failed("Adopted Taxstone checkpoint failed native completion validation")
                }
                let backupDirectory = root.appendingPathComponent(".migration-backups/taxstone-register-adoption/\(jobID)",isDirectory:true)
                let backupURL = backupDirectory.appendingPathComponent("job.json.\(priorHash).bak")
                if invocation.applyMigration {
                    let backupRoot = root.appendingPathComponent(".migration-backups",isDirectory:true)
                    for directory in [backupRoot,backupRoot.appendingPathComponent("taxstone-register-adoption",isDirectory:true),backupDirectory] {
                        if FileManager.default.fileExists(atPath:directory.path) {
                            let values = try directory.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])
                            guard values.isDirectory == true,values.isSymbolicLink != true else {
                                throw JoeyError.failed("Taxstone migration backup path is not a safe directory")
                            }
                        } else {
                            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false,
                                attributes:[.posixPermissions:0o700])
                        }
                    }
                    if FileManager.default.fileExists(atPath:backupURL.path) {
                        guard Integrity.sha256(try Data(contentsOf:backupURL)) == priorHash else {
                            throw JoeyError.failed("Existing Taxstone migration backup does not match the current checkpoint")
                        }
                    } else {
                        let fd = open(backupURL.path,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0o600)
                        guard fd >= 0 else {throw JoeyError.failed("Could not create an exclusive Taxstone checkpoint backup")}
                        let handle = FileHandle(fileDescriptor:fd,closeOnDealloc:true)
                        do {try handle.write(contentsOf:priorData);try handle.synchronize()}
                        catch {try? handle.close();throw error}
                    }
                    guard Integrity.sha256(try Data(contentsOf:backupURL)) == priorHash else {
                        throw JoeyError.failed("Taxstone checkpoint backup failed byte verification")
                    }
                    try Persistence.save(job,to:jobURL)
                    let reopened: JobRecord = try Persistence.load(jobURL)
                    guard reopened.id == jobID,reopened.hasRequiredCompletionEvidence,
                          reopened.registerRows.isEmpty,
                          reopened.taxstoneRegisterEvidence?.provenance?.receiptSHA256 == receiptHash,
                          reopened.taxstoneRegisterEvidence?.provenance?.readbackSHA256 == readbackHash else {
                        throw JoeyError.failed("Saved Taxstone adoption failed readback; restore the exact backup")
                    }
                    print("Taxstone register evidence adopted.\nJob: \(jobID)\nRows: \(evidence.rowsReadBack)\nProvenance: prior external readback; no historical Joey write claimed\nBackup: \(backupURL.path)\nCheckpoint SHA-256: \(Integrity.sha256(try Data(contentsOf:jobURL)))")
                } else {
                    print("Taxstone register evidence validated; not applied.\nJob: \(jobID)\nRows: \(evidence.rowsReadBack)\nReceipt SHA-256: \(receiptHash)\nReadback SHA-256: \(readbackHash)\nArchive SHA-256: \(evidence.sourceSHA256)\nRun again with --apply to save job.json and create an exact backup.")
                }
            }
        } catch {FileHandle.standardError.write(Data((error.localizedDescription+"\n").utf8));exit(1)}
    }
}
