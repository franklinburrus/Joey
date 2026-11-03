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
    @TaskLocal public static var processingRoot: URL?
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
    private static let scratchNames: Set<String> = ["render.partial.mp4","render.json","selected.wav","selected-with-outro.wav","audio-video.mp4","background.png","expected-artwork.png","expected-picture.gray","actual-picture.gray","expected-source.wav","final-audio.m4a","final-waveform.f32","qa-actual.f32","qa-art.raw","qa-expected.f32","qa-wave.f32","qa-wave.rgb","waveform.f32"]

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
    private static func openDirectory(_ url: URL) throws -> Int32 {
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
        while let data = try handle.read(upToCount:1024*1024),!data.isEmpty {hash.update(data:data)}
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
        try Self.noLinks(output)
        guard try Integrity.sha256(output) == hash else {return false}
        let evidence = jobDir.appendingPathComponent("evidence/\(a.clipID)/qa.json")
        try Self.noLinks(evidence)
        let qa: QAReport = try Persistence.load(evidence)
        guard qa.passed,qa.outputSHA256 == hash else {return false}
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
        try Persistence.save(result,to:receipt) // Fail closed if audit cannot be saved.
        for var a in try candidates() {
            do {
                guard try accepted(a) else {continue}
                let url = try work(a)
                let fd = try Self.openDirectory(url)
                defer {Darwin.close(fd)}
                var directoryStat = stat()
                guard fstat(fd,&directoryStat) == 0,UInt64(directoryStat.st_ino) == a.inode,directoryStat.st_dev == a.device,
                      try files(url) == a.files else {throw JoeyError.invalid("Scratch changed before cleanup")}
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
        try Persistence.save(result,to:receipt)
        return result
    }
}
