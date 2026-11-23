import Foundation
import Darwin
import CryptoKit

public struct StorageBlocked: Error, LocalizedError, Sendable {
    public let required: Int64
    public let available: Int64
    public var errorDescription: String? {"Storage blocked: need \(required) bytes including operating-system reserve; available \(available). Progress retained. Free space on Joey's working volume; capacity is checked again in 60 seconds while this job is active."}
}

public struct StorageSnapshot: Codable, Sendable {
    public var measuredAt = Date()
    public var availableBytes: Int64 = 0
    public var totalBytes: Int64 = 0
    public var temporaryBytes: Int64 = 0
    public var activeBytes: Int64 = 0
    public var protectedBytes: Int64 = 0
    public var reclaimableBytes: Int64?
    public var note = ""
}

public struct StorageCleanupResult: Codable, Sendable {
    public var at = Date()
    public var removedBytes: Int64 = 0
    public var freeBytesBefore: Int64 = 0
    public var freeBytesAfter: Int64 = 0
    public var removedFiles = 0
    public var errors: [String] = []
}

struct ScratchFile: Codable, Equatable {
    var name: String
    var bytes: Int64
    var inode: UInt64
    var device: Int32
    var sha256: String
}
struct ScratchAttempt: Codable {
    var version = 1
    var jobID: String
    var clipID: Int
    var id: String
    var creatorPID: Int32
    var inode: UInt64
    var device: Int32
    var closed = false
    var removed = false
    var files: [ScratchFile] = []
}


/// Owns fresh render-attempt scratch. All originals and unregistered legacy
/// storage are protected. The caller retains
/// the existing exclusive processing lock, so cleanup cannot race coordinator
/// work or another app instance.
public final class StorageManager {
    private enum MediaRemovalResult {case removed(Int64), absent, retained(String)}
    @TaskLocal public static var processingRoot: URL?
    @TaskLocal static var testMediaEvictionStopAfterUnlink: Int?
    // Internal dependency injection for isolated capacity/recovery tests. The
    // native application never overrides the real filesystem measurement.
    @TaskLocal static var capacityOverride: (@Sendable () -> Int64)?
    @TaskLocal static var capacityRetryNanoseconds: UInt64 = 60_000_000_000
    private let root: URL
    private let lock: ProcessingLock
    private let fm = FileManager.default
    private static let gib: Int64 = 1024*1024*1024
    // These are the pipeline's expendable products, not filename-based authority:
    // a fresh directory receipt, lifecycle, job and inode/hash checks are also required.
    private static let scratchNames: Set<String> = ["render.partial.mp4","render.json","selected.wav","selected-with-outro.wav","audio-video.mp4","background.png","expected-artwork.png","expected-picture.gray","actual-picture.gray","expected-picture.rgb","actual-picture.rgb","expected-source.wav","final-audio.m4a","final-waveform.f32","qa-actual.f32","qa-art.raw","qa-expected.f32","qa-wave.f32","qa-wave.rgb","waveform.f32"]

    static func automaticCleanupEnabled(root: URL) -> Bool {
        let url = root.appendingPathComponent("settings.json")
        guard FileManager.default.fileExists(atPath:url.path) else {return true}
        guard let config: Configuration = try? Persistence.load(url) else {return false}
        return config.automaticCleanup != false
    }

    init(root: URL, lock: ProcessingLock) throws {
        guard root.standardizedFileURL == lock.directory.standardizedFileURL else {throw JoeyError.invalid("Storage lock does not own this root")}
        self.root = try Self.canonicalRoot(root); self.lock = lock
        try Self.noLinks(self.root)
    }
    static func canonicalRoot(_ url: URL) throws -> URL {
        guard let path = realpath(url.path,nil) else {throw JoeyError.invalid("Working storage root is missing")}
        defer {free(path)}
        return URL(fileURLWithPath:String(cString:path),isDirectory:true)
    }
    static func noLinks(_ url: URL) throws {
        let path = url
        // Foundation standardization aliases /private/var back to /var on
        // macOS. POSIX realpath gives the actual canonical path without that
        // presentation alias, and therefore also works for isolated temp tests.
        guard let resolved = realpath(path.path,nil) else {throw JoeyError.invalid("Storage path is missing")}
        defer {free(resolved)}
        guard String(cString:resolved) == path.path else {throw JoeyError.invalid("Storage path is not canonical or traverses a symbolic link: \(path.path) (resolved \(String(cString:resolved)))")}
        var part = URL(fileURLWithPath:"/",isDirectory:true)
        for name in path.pathComponents.dropFirst() {
            part.appendPathComponent(name)
            var st = stat()
            guard lstat(part.path,&st) == 0, (st.st_mode & S_IFMT) != S_IFLNK else {throw JoeyError.invalid("Storage path is missing or contains a symbolic link: \(part.path)")}
        }
    }
    private static func component(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".." && !value.contains("/") && !value.contains("\\") && !value.contains("\0")
    }
    /// Every ancestor is opened without following links. Subsequent file
    /// operations stay relative to this descriptor, never metadata paths.
    static func openDirectory(_ url: URL) throws -> Int32 {
        var fd = open("/",O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else {throw JoeyError.failed("Cannot open filesystem root")}
        do {
            for name in url.pathComponents.dropFirst() {
                guard component(name) else {throw JoeyError.invalid("Unsafe directory component")}
                let next = openat(fd,name,O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard next >= 0 else {throw JoeyError.invalid("Unsafe or missing storage ancestor")}
                Darwin.close(fd);fd = next
            }
            return fd
        } catch {Darwin.close(fd);throw error}
    }
    private static func verifiedFile(_ file: ScratchFile, directory: Int32) throws -> Bool {
        let fd = openat(directory,file.name,O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else {return false}
        let handle = FileHandle(fileDescriptor:fd,closeOnDealloc:true)
        defer {try? handle.close()}
        var st = stat()
        guard fstat(fd,&st) == 0,(st.st_mode & S_IFMT) == S_IFREG,st.st_nlink == 1,
              UInt64(st.st_ino) == file.inode,st.st_dev == file.device,st.st_size == file.bytes else {return false}
        var hash = SHA256()
        while true {
            // Keep the verified descriptor open while releasing each read
            // buffer before the next chunk; never reopen by an unchecked path.
            let finished = try autoreleasepool {
                guard let data = try handle.read(upToCount:1024*1024), !data.isEmpty else {return true}
                hash.update(data:data)
                return false
            }
            if finished {break}
        }
        return hash.finalize().map {String(format:"%02x",$0)}.joined() == file.sha256
    }
    public static func capacity(at url: URL) throws -> (free: Int64, reserve: Int64) {
        let a = try FileManager.default.attributesOfFileSystem(forPath:url.path)
        guard let free = (a[.systemFreeSize] as? NSNumber)?.int64Value,
              let total = (a[.systemSize] as? NSNumber)?.int64Value else {throw JoeyError.dependency("Cannot measure Joey working-volume capacity")}
        // Reserve scales with the volume, bounded to leave macOS usable on both
        // small and large disks. Purgeable/cloud bytes are not counted as free.
        return (capacityOverride?() ?? free,max(2*gib,min(8*gib,total/100)))
    }
    public static func checkCapacity(at url: URL, requiredBytes: Int64, available: Int64? = nil, reserve: Int64? = nil) throws {
        guard requiredBytes >= 0, requiredBytes <= Int64.max/2 else {throw JoeyError.invalid("Invalid storage estimate")}
        let measured = try capacity(at:url)
        let needed = requiredBytes + (reserve ?? measured.reserve)
        let free = available ?? measured.free
        guard free >= needed else {throw StorageBlocked(required:needed,available:free)}
    }
    /// 6 Mbps encoder ceiling + AAC/container allowance for retained MP4s;
    /// per-attempt WAV/PCM, two encodes, picture/waveform QA and faststart copies.
    public static func peakBytes(duration: Double, sourceBytes: Int64, clipDuration: Double, audio: Bool) throws -> Int64 {
        guard duration.isFinite, clipDuration.isFinite, duration >= 0, clipDuration >= 0,
              duration < 1_000_000, clipDuration < 1_000_000, sourceBytes >= 0, sourceBytes < Int64.max/4 else {throw JoeyError.invalid("Missing or invalid workflow storage estimate")}
        let retained = duration * 800_000
        let scratch = clipDuration * (audio ? 3_500_000 : 3_000_000)
        return sourceBytes + Int64(retained + scratch) + 256*1024*1024
    }
    private func work(_ a: ScratchAttempt) throws -> URL {
        guard a.version == 1, Self.component(a.jobID), a.clipID > 0, UUID(uuidString:a.id) != nil else {throw JoeyError.invalid("Invalid scratch identity")}
        let url = root.appendingPathComponent("jobs/\(a.jobID)/scratch/\(a.clipID)/\(a.id)")
        try Self.noLinks(url)
        var st = stat()
        guard lstat(url.path,&st) == 0, (st.st_mode & S_IFMT) == S_IFDIR,
              UInt64(st.st_ino) == a.inode, st.st_dev == a.device else {throw JoeyError.invalid("Scratch directory identity changed")}
        return url
    }
    private func receiptURL(_ a: ScratchAttempt) -> URL {root.appendingPathComponent("jobs/\(a.jobID)/storage-attempts/\(a.id).json")}
    func begin(jobID: String, clipID: Int) throws -> URL {
        guard Self.component(jobID),clipID > 0 else {throw JoeyError.invalid("Invalid scratch owner")}
        let parent = root.appendingPathComponent("jobs/\(jobID)/scratch/\(clipID)")
        // Check existing ancestors before any recursive creation.
        var ancestor = parent
        while !fm.fileExists(atPath:ancestor.path) {ancestor.deleteLastPathComponent()}
        try Self.noLinks(ancestor)
        try fm.createDirectory(at:parent,withIntermediateDirectories:true)
        try Self.noLinks(parent)
        let id = UUID().uuidString, url = parent.appendingPathComponent(id)
        try fm.createDirectory(at:url,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        var st = stat();guard lstat(url.path,&st) == 0 else {throw JoeyError.failed("Cannot identify scratch")}
        let a = ScratchAttempt(jobID:jobID,clipID:clipID,id:id,creatorPID:getpid(),inode:UInt64(st.st_ino),device:st.st_dev)
        let receipts = receiptURL(a).deletingLastPathComponent()
        if fm.fileExists(atPath:receipts.path) {try Self.noLinks(receipts)}
        try Persistence.save(a,to:receiptURL(a))
        return url
    }
    private func files(_ url: URL) throws -> [ScratchFile] {
        try fm.contentsOfDirectory(at:url,includingPropertiesForKeys:nil).sorted {$0.path < $1.path}.map {file in
            var st = stat()
            guard Self.scratchNames.contains(file.lastPathComponent), lstat(file.path,&st) == 0,
                  (st.st_mode & S_IFMT) == S_IFREG,st.st_nlink == 1 else {throw JoeyError.invalid("Unrecognized or linked scratch artifact; preserved")}
            return ScratchFile(name:file.lastPathComponent,bytes:st.st_size,inode:UInt64(st.st_ino),device:st.st_dev,sha256:try Integrity.sha256(file))
        }
    }
    func closeAttempt(_ url: URL, jobID: String) throws {
        guard Self.component(jobID),UUID(uuidString:url.lastPathComponent) != nil else {throw JoeyError.invalid("Invalid attempt")}
        let receipt = root.appendingPathComponent("jobs/\(jobID)/storage-attempts/\(url.lastPathComponent).json")
        try Self.noLinks(receipt)
        var a: ScratchAttempt = try Persistence.load(receipt)
        guard try work(a).path == url.path else {throw JoeyError.invalid("Attempt path mismatch")}
        let lease = try ProcessingLock(directory:root,name:"storage-workers.lock")
        defer {withExtendedLifetime(lease) {}}
        try seal(&a)
    }
    private func seal(_ a: inout ScratchAttempt) throws {
        let url = try work(a)
        a.files = try files(url)
        // Retain every JSON diagnostic outside disposable storage, including
        // failed render receipts. Cleanup audit receipts themselves are permanent.
        for file in a.files where file.name.hasSuffix(".json") {
            let destination = root.appendingPathComponent("jobs/\(a.jobID)/storage-attempts/\(a.id)-\(file.name)")
            if fm.fileExists(atPath:destination.path) {
                try Self.noLinks(destination)
                guard try Integrity.sha256(destination) == file.sha256 else {throw JoeyError.invalid("Retained attempt evidence differs")}
            } else {try fm.copyItem(at:url.appendingPathComponent(file.name),to:destination)}
        }
        a.closed = true
        try Persistence.save(a,to:receiptURL(a))
    }
    private func attempts() throws -> [ScratchAttempt] {
        let jobs = root.appendingPathComponent("jobs")
        guard fm.fileExists(atPath:jobs.path) else {return []}
        try Self.noLinks(jobs)
        var result: [ScratchAttempt] = []
        for job in try fm.contentsOfDirectory(at:jobs,includingPropertiesForKeys:nil) {
            let dir = job.appendingPathComponent("storage-attempts")
            guard (try? Self.noLinks(dir)) != nil else {continue}
            for receipt in try fm.contentsOfDirectory(at:dir,includingPropertiesForKeys:nil) where UUID(uuidString:receipt.deletingPathExtension().lastPathComponent) != nil {
                guard (try? Self.noLinks(receipt)) != nil, let a: ScratchAttempt = try? Persistence.load(receipt),
                      a.jobID == job.lastPathComponent, receipt.path == receiptURL(a).path, !a.removed else {continue}
                result.append(a)
            }
        }
        return result.sorted {$0.id < $1.id}
    }
    private func accepted(_ a: ScratchAttempt) throws -> Bool {
        let jobDir = root.appendingPathComponent("jobs/\(a.jobID)")
        let checkpoint = jobDir.appendingPathComponent("job.json")
        try Self.noLinks(checkpoint)
        let job: JobRecord = try Persistence.load(checkpoint)
        guard job.id == a.jobID, let clip = job.clips.first(where:{$0.id == a.clipID}),
              clip.qa?.passed == true,let hash = clip.sha256,clip.qa?.outputSHA256 == hash,
              Self.component(clip.filename) else {return false}
        let output = jobDir.appendingPathComponent(clip.filename)
        if fm.fileExists(atPath:output.path) {
            try Self.noLinks(output)
            guard try Integrity.sha256(output) == hash else {return false}
        } else {
            guard job.state == .completed, job.hasRequiredCompletionEvidence,
                  clip.drive?.sha256 == hash,
                  job.postDeliveryMediaCleanup?.files.contains(where:{
                      $0.role == .acceptedClip && $0.sha256 == hash && $0.driveID == clip.drive?.id &&
                      ($0.outcome == .removed || $0.outcome == .absent)
                  }) == true else {return false}
        }
        let evidence = jobDir.appendingPathComponent("evidence/\(a.clipID)/qa.json")
        try Self.noLinks(evidence)
        let qa: QAReport = try Persistence.load(evidence)
        guard qa.passed,qa.outputSHA256 == hash else {return false}
        // Retain render scratch until the accepted clip has a verified Drive
        // receipt (or the job completed). Local QA alone is not filing proof.
        guard clip.drive != nil || job.state == .completed else {return false}
        // Never discard a scratch dependency named by any job's immutable
        // request or accepted source, even if malformed metadata references it.
        let prefix = try work(a).path + "/"
        for dir in try fm.contentsOfDirectory(at:root.appendingPathComponent("jobs"),includingPropertiesForKeys:nil) {
            try Self.noLinks(dir)
            let other: JobRecord = try Persistence.load(dir.appendingPathComponent("job.json"))
            let refs = [other.source?.path,other.request.localPath,other.request.transcriptPath,other.request.artwork?.file.path].compactMap {$0}
            if refs.contains(where: {(try? Self.canonicalRoot(URL(fileURLWithPath:$0)).path.hasPrefix(prefix)) == true}) {return false}
        }
        return true
    }
    private func candidates() throws -> [ScratchAttempt] {
        var result: [ScratchAttempt] = []
        for var a in try attempts() {
            do {
                guard try accepted(a) else {continue}
                if !a.closed {
                    // A live creator may still hold in-process QA mappings.
                    guard kill(a.creatorPID,0) != 0,errno == ESRCH else {continue}
                    try seal(&a)
                }
                let remaining = try files(work(a))
                // A prior cleanup may have stopped after a verified unlink but
                // before saving its final receipt. Missing disposable files need
                // no repeat deletion; changed/new files still fail closed.
                guard remaining.allSatisfy({a.files.contains($0)}) else {continue}
                a.files = remaining
                result.append(a)
            } catch {continue} // Uncertainty is preservation, never deletion authority.
        }
        return result
    }

    private func retainedMediaFile(path: String, role: PostDeliveryMediaFile.Role,
                                   driveID: String?, reason: String) -> PostDeliveryMediaFile {
        PostDeliveryMediaFile(path:path,role:role,driveID:driveID,bytes:nil,sha256:nil,
            inode:nil,device:nil,outcome:.retained,reason:reason,updatedAt:Date())
    }
    private func canonicalMediaPath(_ path: String) -> String? {
        let expanded = (path as NSString).expandingTildeInPath
        guard let resolved = realpath(expanded,nil) else {return URL(fileURLWithPath:expanded).standardizedFileURL.path}
        defer {free(resolved)}
        return String(cString:resolved)
    }
    private func jobDependencyReason(for path: String, jobID: String) -> String? {
        let jobsDirectory = root.appendingPathComponent("jobs",isDirectory:true)
        guard fm.fileExists(atPath:jobsDirectory.path) else {return nil}
        do {
            try Self.noLinks(jobsDirectory)
            let candidate = canonicalMediaPath(path) ?? URL(fileURLWithPath:path).standardizedFileURL.path
            for entry in try fm.contentsOfDirectory(at:jobsDirectory,includingPropertiesForKeys:nil,options:.skipsHiddenFiles) {
                try Self.noLinks(entry)
                var directoryStat = stat()
                guard lstat(entry.path,&directoryStat) == 0,(directoryStat.st_mode & S_IFMT) == S_IFDIR else {continue}
                if entry.lastPathComponent == jobID {continue}
                let checkpoint = entry.appendingPathComponent("job.json")
                guard fm.fileExists(atPath:checkpoint.path) else {
                    if !(try fm.contentsOfDirectory(at:entry,includingPropertiesForKeys:nil,options:.skipsHiddenFiles)).isEmpty {
                        return "Unreconciled job folder may depend on this local media: \(entry.lastPathComponent)"
                    }
                    continue
                }
                try Self.noLinks(checkpoint)
                let other: JobRecord = try Persistence.load(checkpoint)
                let references = [other.source?.path,other.request.localPath,other.request.transcriptPath,
                    other.request.artwork?.file.path].compactMap {$0}
                if references.contains(where:{canonicalMediaPath($0) == candidate}) {
                    return "Referenced by another saved job: \(other.id)"
                }
            }
            return nil
        } catch {
            return "Job dependencies could not be reconciled: \(error.localizedDescription)"
        }
    }
    private func captureMediaFile(path: String, role: PostDeliveryMediaFile.Role,
                                  driveID: String?, expectedBytes: Int64?, expectedSHA256: String?,
                                  directory: URL) -> PostDeliveryMediaFile {
        let standardized = URL(fileURLWithPath:path)
        do {try Self.noLinks(standardized)}
        catch {return retainedMediaFile(path:standardized.path,role:role,driveID:driveID,
            reason:"Local media path contains a link or cannot be resolved safely")}
        let canonical = canonicalMediaPath(standardized.path) ?? standardized.path
        guard (canonical as NSString).deletingLastPathComponent == directory.path,
              Self.component((canonical as NSString).lastPathComponent) else {
            return retainedMediaFile(path:path,role:role,driveID:driveID,reason:"Not a direct Joey job-owned media file")
        }
        if let dependency = jobDependencyReason(for:canonical,jobID:directory.lastPathComponent) {
            return retainedMediaFile(path:canonical,role:role,driveID:driveID,reason:dependency)
        }
        do {
            try Self.noLinks(directory)
            let parent = try Self.openDirectory(directory)
            defer {Darwin.close(parent)}
            let name = (canonical as NSString).lastPathComponent
            let fd = openat(parent,name,O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
            if fd < 0 {
                if errno == ENOENT {
                    return PostDeliveryMediaFile(path:canonical,role:role,driveID:driveID,
                        bytes:expectedBytes,sha256:expectedSHA256,inode:nil,device:nil,outcome:.absent,
                        reason:"Local media was already absent; verified Drive delivery remains",updatedAt:Date())
                }
                throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno))
            }
            defer {Darwin.close(fd)}
            var st = stat()
            guard fstat(fd,&st) == 0,(st.st_mode & S_IFMT) == S_IFREG,st.st_nlink == 1,
                  st.st_size > 0,(expectedBytes == nil || st.st_size == expectedBytes),
                  Self.mediaHash(fd) == expectedSHA256 else {
                return retainedMediaFile(path:canonical,role:role,driveID:driveID,
                    reason:"Local media type, link count, size, or SHA-256 differs from accepted identity")
            }
            return PostDeliveryMediaFile(path:canonical,role:role,driveID:driveID,
                bytes:st.st_size,sha256:expectedSHA256,inode:UInt64(st.st_ino),device:st.st_dev,
                outcome:.pending,reason:"Joey-owned file; matching Drive receipt and package readback required before unlink",updatedAt:nil)
        } catch {
            return retainedMediaFile(path:canonical,role:role,driveID:driveID,
                reason:"Local file ownership could not be verified: \(error.localizedDescription)")
        }
    }
    private static func mediaHash(_ fd: Int32) -> String? {
        var digest = SHA256()
        let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount:1024*1024,alignment:16)
        defer {buffer.deallocate()}
        while true {
            let count = Darwin.read(fd,buffer.baseAddress!,buffer.count)
            if count < 0 {if errno == EINTR {continue};return nil}
            if count == 0 {break}
            digest.update(bufferPointer:UnsafeRawBufferPointer(start:buffer.baseAddress,count:count))
        }
        return digest.finalize().map {String(format:"%02x",$0)}.joined()
    }
    func preparePostDeliveryMediaCleanup(job: JobRecord, directory: URL) throws -> PostDeliveryMediaCleanup {
        guard job.state == .completed,job.hasRequiredCompletionEvidence,let source = job.source,
              directory.standardizedFileURL.path == root.appendingPathComponent("jobs/\(job.id)").standardizedFileURL.path else {
            throw JoeyError.failed("Post-delivery cleanup requires the completed job's verified package")
        }
        try Self.noLinks(directory)
        var directoryStat = stat()
        guard lstat(directory.path,&directoryStat) == 0,(directoryStat.st_mode & S_IFMT) == S_IFDIR else {
            throw JoeyError.failed("Completed job directory identity is unavailable")
        }
        let archiveReady = Records.archiveReceiptMatchesSource(source) &&
            !((job.clips.compactMap {$0.drive?.id} + Array(job.companions.values.map(\.id))).contains(source.archiveReceipt?.id ?? ""))
        let archiveID = source.archiveReceipt?.id
        let evidence = try Records.deliveryEvidenceSHA256(job:job)
        var files: [PostDeliveryMediaFile] = []
        if job.request.localPath != nil {
            files.append(retainedMediaFile(path:source.path,role:.sourceWorkingCopy,driveID:archiveID,
                reason:"User-selected original input is not Joey-owned; preserved"))
        } else if !archiveReady {
            files.append(retainedMediaFile(path:source.path,role:.sourceWorkingCopy,driveID:archiveID,
                reason:"Verified full-source Drive archive identity/readback is missing or mismatched"))
        } else {
            files.append(captureMediaFile(path:source.path,role:.sourceWorkingCopy,driveID:archiveID,
                expectedBytes:source.bytes,expectedSHA256:source.sha256,directory:directory))
        }
        for clip in job.clips {
            let path = directory.appendingPathComponent(clip.filename).path
            guard archiveReady,let receipt = clip.drive,receipt.name == clip.filename,
                  receipt.bytes == clip.bytes,receipt.sha256 == clip.sha256,
                  receipt.parent == job.folderID else {
                files.append(retainedMediaFile(path:path,role:.acceptedClip,driveID:clip.drive?.id,
                    reason:"Complete verified source archive and matching accepted-clip Drive receipt are required"))
                continue
            }
            files.append(captureMediaFile(path:path,role:.acceptedClip,driveID:receipt.id,
                expectedBytes:clip.bytes,expectedSHA256:clip.sha256,directory:directory))
        }
        return PostDeliveryMediaCleanup(jobID:job.id,sourceID:source.id,
            deliveryEvidenceSHA256:evidence,packageVerifiedAt:Date(),
            directoryInode:UInt64(directoryStat.st_ino),directoryDevice:directoryStat.st_dev,files:files)
    }
    func resumePostDeliveryMediaCleanup(job: inout JobRecord, checkpoint: URL) throws {
        guard var cleanup = job.postDeliveryMediaCleanup else {return}
        guard cleanup.version == 1,cleanup.jobID == job.id,job.state == .completed,
              let source = job.source,cleanup.sourceID == source.id else {
            retainPendingMedia(in:&cleanup,reason:"Cleanup intent identity is invalid; local media preserved")
            job.postDeliveryMediaCleanup = cleanup;try persistMediaCleanup(&job,to:checkpoint);return
        }
        let evidence = try? Records.deliveryEvidenceSHA256(job:job)
        guard job.hasRequiredCompletionEvidence,evidence == cleanup.deliveryEvidenceSHA256,
              Records.archiveReceiptMatchesSource(source) else {
            retainPendingMedia(in:&cleanup,reason:"Verified delivery or archive evidence changed; local media preserved")
            job.postDeliveryMediaCleanup = cleanup;try persistMediaCleanup(&job,to:checkpoint);return
        }
        let jobDirectory = root.appendingPathComponent("jobs/\(job.id)",isDirectory:true)
        do {
            try Self.noLinks(jobDirectory)
            let directoryFD = try Self.openDirectory(jobDirectory)
            defer {Darwin.close(directoryFD)}
            var directoryStat = stat()
            guard fstat(directoryFD,&directoryStat) == 0,(directoryStat.st_mode & S_IFMT) == S_IFDIR,
                  UInt64(directoryStat.st_ino) == cleanup.directoryInode,directoryStat.st_dev == cleanup.directoryDevice else {
                retainPendingMedia(in:&cleanup,reason:"Job directory identity changed; local media preserved")
                job.postDeliveryMediaCleanup = cleanup;try persistMediaCleanup(&job,to:checkpoint);return
            }
            let workerLock = try ProcessingLock(directory:root,name:"storage-workers.lock")
            defer {withExtendedLifetime(workerLock) {}}
            cleanup.lastAttemptAt = Date()
            if cleanup.freeBytesBefore == nil {cleanup.freeBytesBefore = try Self.capacity(at:root).free}
            job.postDeliveryMediaCleanup = cleanup;try persistMediaCleanup(&job,to:checkpoint)
            var unlinksThisAttempt = 0
            for index in cleanup.files.indices where cleanup.files[index].outcome == .pending {
                var item = cleanup.files[index]
                guard mediaItemStillBound(item,job:job,directory:jobDirectory) else {
                    item.outcome = .retained;item.reason = "Local file no longer matches its source/clip and Drive identities";item.updatedAt = Date()
                    cleanup.files[index] = item;job.postDeliveryMediaCleanup = cleanup;try persistMediaCleanup(&job,to:checkpoint);continue
                }
                if let dependency = jobDependencyReason(for:item.path,jobID:job.id) {
                    item.outcome = .retained;item.reason = dependency;item.updatedAt = Date()
                    cleanup.files[index] = item;job.postDeliveryMediaCleanup = cleanup;try persistMediaCleanup(&job,to:checkpoint);continue
                }
                do {
                    switch try unlinkMediaFile(item,directoryFD:directoryFD) {
                    case .absent:
                        item.outcome = .absent;item.reason = "Already absent when cleanup resumed; no second removal";item.updatedAt = Date()
                    case .retained(let reason):
                        item.outcome = .retained;item.reason = reason;item.updatedAt = Date()
                    case .removed(let bytes):
                        unlinksThisAttempt += 1
                        if Self.testMediaEvictionStopAfterUnlink == unlinksThisAttempt {
                            throw JoeyError.failed("Synthetic interruption after local unlink and before cleanup receipt update")
                        }
                        item.outcome = .removed;item.reason = "Joey-owned copy removed after Drive object, complete package, and creator records verified";item.updatedAt = Date()
                        cleanup.removedBytes += bytes
                    }
                    cleanup.files[index] = item;job.postDeliveryMediaCleanup = cleanup
                    try persistMediaCleanup(&job,to:checkpoint)
                } catch {
                    if error.localizedDescription.contains("Synthetic interruption after local unlink") {throw error}
                    item.reason = "Removal failed; preserved for safe retry: \(error.localizedDescription)";item.updatedAt = Date()
                    cleanup.files[index] = item;job.postDeliveryMediaCleanup = cleanup
                    try persistMediaCleanup(&job,to:checkpoint)
                }
            }
            cleanup.freeBytesAfter = try Self.capacity(at:root).free
            if cleanup.files.allSatisfy({$0.outcome != .pending}) {cleanup.completedAt = Date()}
            job.postDeliveryMediaCleanup = cleanup;try persistMediaCleanup(&job,to:checkpoint)
        } catch {
            throw error
        }
    }
    private func mediaItemStillBound(_ item: PostDeliveryMediaFile, job: JobRecord, directory: URL) -> Bool {
        guard let source = job.source else {return false}
        switch item.role {
        case .sourceWorkingCopy:
            guard job.request.localPath == nil,Records.archiveReceiptMatchesSource(source),
                  item.path == (canonicalMediaPath(source.path) ?? URL(fileURLWithPath:source.path).standardizedFileURL.path),
                  let receipt = source.archiveReceipt,item.driveID == receipt.id,
                  item.bytes == source.bytes,item.sha256 == source.sha256 else {return false}
            return true
        case .acceptedClip:
            guard let clip = job.clips.first(where:{$0.drive?.id == item.driveID}),
                  let receipt = clip.drive,
                  item.path == (canonicalMediaPath(directory.appendingPathComponent(clip.filename).path) ?? directory.appendingPathComponent(clip.filename).standardizedFileURL.path),
                  item.bytes == clip.bytes,item.sha256 == clip.sha256,
                  receipt.name == clip.filename,receipt.bytes == clip.bytes,receipt.sha256 == clip.sha256,
                  receipt.parent == job.folderID else {return false}
            return true
        }
    }
    private func unlinkMediaFile(_ item: PostDeliveryMediaFile, directoryFD: Int32) throws -> MediaRemovalResult {
        let name = (item.path as NSString).lastPathComponent
        guard Self.component(name),let bytes = item.bytes,let sha = item.sha256,
              let inode = item.inode,let device = item.device else {
            return .retained("Cleanup intent lacks exact file identity; local media preserved")
        }
        let fd = openat(directoryFD,name,O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        if fd < 0 {
            if errno == ENOENT {return .absent}
            throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno))
        }
        defer {Darwin.close(fd)}
        var st = stat()
        guard fstat(fd,&st) == 0,(st.st_mode & S_IFMT) == S_IFREG,st.st_nlink == 1,
              UInt64(st.st_ino) == inode,st.st_dev == device,st.st_size == bytes,
              Self.mediaHash(fd) == sha else {
            return .retained("Local file inode, device, link count, size, or SHA-256 changed; preserved")
        }
        guard unlinkat(directoryFD,name,0) == 0 else {throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno))}
        var absent = stat()
        guard fstatat(directoryFD,name,&absent,AT_SYMLINK_NOFOLLOW) != 0,errno == ENOENT else {
            throw JoeyError.failed("Local media unlink could not be verified")
        }
        return .removed(bytes)
    }
    private func retainPendingMedia(in cleanup: inout PostDeliveryMediaCleanup, reason: String) {
        for index in cleanup.files.indices where cleanup.files[index].outcome == .pending {
            cleanup.files[index].outcome = .retained;cleanup.files[index].reason = reason;cleanup.files[index].updatedAt = Date()
        }
        cleanup.completedAt = Date()
    }
    private func persistMediaCleanup(_ job: inout JobRecord, to checkpoint: URL) throws {
        job.updatedAt = Date();try Persistence.save(job,to:checkpoint)
    }
    public static func inspect(root: URL) throws -> StorageSnapshot {
        let root = try canonicalRoot(root)
        var snapshot = StorageSnapshot()
        snapshot.availableBytes = try capacity(at:root).free
        let fm = FileManager.default
        var activeJobs = Set<String>()
        if let dirs = try? fm.contentsOfDirectory(at:root.appendingPathComponent("jobs"),includingPropertiesForKeys:nil) {
            for dir in dirs {
                if let job: JobRecord = try? Persistence.load(dir.appendingPathComponent("job.json")),job.state == .processing {activeJobs.insert(job.id)}
            }
        }
        if let entries = fm.enumerator(at:root,includingPropertiesForKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey],options:[]) {
            for case let file as URL in entries {
                let values = try file.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
                if values.isSymbolicLink == true {entries.skipDescendants();continue}
                guard values.isRegularFile == true else {continue}
                let bytes = Int64(values.fileSize ?? 0)
                snapshot.totalBytes += bytes
                let relative = String(file.path.dropFirst(root.path.count+1)).split(separator:"/").map(String.init)
                if relative.count >= 5,relative[0] == "jobs",relative[2] == "scratch" {
                    snapshot.temporaryBytes += bytes
                    if activeJobs.contains(relative[1]) {snapshot.activeBytes += bytes}
                } else {snapshot.protectedBytes += bytes}
            }
        }
        do {
            let lock = try ProcessingLock(directory:root)
            let manager = try StorageManager(root:root,lock:lock)
            let workers = try ProcessingLock(directory:root,name:"storage-workers.lock")
            defer {withExtendedLifetime(workers) {}}
            snapshot.reclaimableBytes = try manager.candidates().flatMap(\.files).reduce(0) {$0+$1.bytes}
            snapshot.note = "Logical file bytes. Active Processing is a subset of Temporary Files. Unregistered/uncertain scratch remains protected from cleanup."
        } catch {
            snapshot.note = "Processing owns storage. Reclaimable space will be verified between jobs; no cleanup attempted. " + error.localizedDescription
        }
        return snapshot
    }
    public static func clean(root: URL) throws -> StorageCleanupResult {
        let lock = try ProcessingLock(directory:root)
        return try StorageManager(root:root,lock:lock).clean()
    }
    func clean() throws -> StorageCleanupResult {
        let workers = try ProcessingLock(directory:root,name:"storage-workers.lock")
        defer {withExtendedLifetime(workers) {}}
        var result = StorageCleanupResult()
        result.freeBytesBefore = try Self.capacity(at:root).free
        let audit = root.appendingPathComponent("storage-cleanup")
        if fm.fileExists(atPath:audit.path) {try Self.noLinks(audit)}
        let receipt = audit.appendingPathComponent(UUID().uuidString+".json")
        var receiptWritten = false
        for var a in try candidates() {
            do {
                guard try accepted(a) else {continue}
                let url = try work(a)
                let fd = try Self.openDirectory(url)
                defer {Darwin.close(fd)}
                var directoryStat = stat()
                guard fstat(fd,&directoryStat) == 0,UInt64(directoryStat.st_ino) == a.inode,directoryStat.st_dev == a.device,
                      try files(url) == a.files else {throw JoeyError.invalid("Scratch changed before cleanup")}
                if !receiptWritten {
                    try Persistence.save(result,to:receipt) // Fail closed if audit cannot be saved.
                    receiptWritten = true
                }
                for file in a.files {
                    var st = stat()
                    guard fstatat(fd,file.name,&st,AT_SYMLINK_NOFOLLOW) == 0,
                          (st.st_mode & S_IFMT) == S_IFREG,st.st_nlink == 1,
                          UInt64(st.st_ino) == file.inode,st.st_dev == file.device,st.st_size == file.bytes,
                          try Self.verifiedFile(file,directory:fd) else {throw JoeyError.invalid("Scratch file changed; preserved")}
                    guard unlinkat(fd,file.name,0) == 0 else {throw JoeyError.failed("Could not remove owned scratch file")}
                    var absent = stat()
                    guard fstatat(fd,file.name,&absent,AT_SYMLINK_NOFOLLOW) != 0,errno == ENOENT else {throw JoeyError.failed("Scratch removal could not be verified")}
                    result.removedBytes += file.bytes;result.removedFiles += 1
                    try Persistence.save(result,to:receipt)
                }
                // Remove only the empty, identity-matched directory through its
                // anchored parent; never follow a changed ancestor or recurse.
                let parent = try Self.openDirectory(url.deletingLastPathComponent())
                defer {Darwin.close(parent)}
                var child = stat()
                guard fstatat(parent,a.id,&child,AT_SYMLINK_NOFOLLOW) == 0,
                      (child.st_mode & S_IFMT) == S_IFDIR,UInt64(child.st_ino) == a.inode,child.st_dev == a.device else {
                    throw JoeyError.invalid("Scratch directory moved during cleanup")
                }
                guard unlinkat(parent,a.id,AT_REMOVEDIR) == 0 else {throw JoeyError.failed("Scratch directory is no longer empty; preserved")}
                a.removed = true;try Persistence.save(a,to:receiptURL(a))
            } catch {result.errors.append("\(a.jobID)/\(a.id): \(error.localizedDescription)")}
        }
        result.freeBytesAfter = try Self.capacity(at:root).free
        if receiptWritten || result.removedFiles > 0 || !result.errors.isEmpty {
            try Persistence.save(result,to:receipt)
        }
        return result
    }
}
