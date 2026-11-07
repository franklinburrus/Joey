import Foundation
import CryptoKit
import Darwin

public enum Integrity {
    public static func sha256(_ url: URL) throws -> String { try digest(url, md5: false) }
    public static func md5(_ url: URL) throws -> String { try digest(url, md5: true) }
    private static func digest(_ url: URL, md5: Bool) throws -> String {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var sha = SHA256(); var md = Insecure.MD5()
        while true {
            // FileHandle can autorelease each read buffer. Drain it per chunk
            // so hashing an original does not retain the whole file in memory.
            let finished = try autoreleasepool {
                guard let data = try handle.read(upToCount:1024*1024), !data.isEmpty else {return true}
                if md5 {md.update(data:data)} else {sha.update(data:data)}
                return false
            }
            if finished {break}
        }
        return (md5 ? Array(md.finalize()) : Array(sha.finalize())).map { String(format:"%02x",$0) }.joined()
    }
    public static func textHash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
public enum Persistence {
    public static var encoder: JSONEncoder {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted,.sortedKeys,.withoutEscapingSlashes]; e.dateEncodingStrategy = .iso8601; return e
    }
    public static var decoder: JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }
    public static func save<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try encoder.encode(value).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let fd = open(url.path, O_RDONLY); if fd >= 0 { _ = fsync(fd); close(fd) }
    }
    public static func load<T: Decodable>(_ url: URL) throws -> T { try decoder.decode(T.self, from: Data(contentsOf: url)) }
    public static func safeName(_ text: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:\0").union(.controlCharacters)
        let parts = text.components(separatedBy: illegal).joined(separator: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return String((parts.isEmpty ? "Untitled" : parts).prefix(90))
    }
    public static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Joey Native",isDirectory:true)
    }
    public static func checkDisk(at url: URL, requiredBytes: Int64) throws {
        try StorageManager.checkCapacity(at:url,requiredBytes:requiredBytes)
    }
}
public final class ProcessingLock {
    private var fd: Int32 = -1
    public let directory: URL
    public init(directory: URL, name: String = "processing.lock", shared: Bool = false) throws {
        self.directory = directory
        fd = open(directory.appendingPathComponent(name).path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw JoeyError.failed("Cannot open processing lock") }
        guard flock(fd, (shared ? LOCK_SH : LOCK_EX) | LOCK_NB) == 0 else { close(fd); fd = -1; throw JoeyError.dependency("Another Joey process is processing this library") }
    }
    deinit { if fd >= 0 { flock(fd, LOCK_UN); close(fd) } }
}

/// Queue visibility and dispatch intent are separate from immutable media and
/// delivery checkpoints. All writers merge under the same cross-process lock.
public enum JobQueue {
    public static func removedIDs(root: URL) throws -> Set<String> {
        let url = root.appendingPathComponent("job-queue.json")
        guard FileManager.default.fileExists(atPath:url.path) else {return []}
        let values = try url.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey])
        guard values.isRegularFile == true,values.isSymbolicLink != true else {
            throw JoeyError.dependency("Saved queue disposition cannot be read safely. Restore job-queue.json before processing; job files are preserved.")
        }
        return try Persistence.load(url)
    }
    public static func setRemoved(_ ids: Set<String>, removed: Bool, root: URL) throws {
        let lock = try ProcessingLock(directory:root,name:"job-queue.lock")
        defer {withExtendedLifetime(lock) {}}
        var saved = try removedIDs(root:root)
        if removed {saved.formUnion(ids)} else {saved.subtract(ids)}
        try Persistence.save(saved.sorted(),to:root.appendingPathComponent("job-queue.json"))
    }
}
