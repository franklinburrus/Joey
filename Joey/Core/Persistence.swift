import Foundation
import CryptoKit
import Darwin

public enum Integrity {
    public static func sha256(_ url: URL) throws -> String { try digest(url, md5: false) }
    public static func md5(_ url: URL) throws -> String { try digest(url, md5: true) }
    private static func digest(_ url: URL, md5: Bool) throws -> String {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var sha = SHA256(); var md = Insecure.MD5()
        while let data = try handle.read(upToCount: 1024*1024), !data.isEmpty {
            if md5 { md.update(data: data) } else { sha.update(data: data) }
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
        let attrs = try FileManager.default.attributesOfFileSystem(forPath: url.path)
        let available = (attrs[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        guard available >= requiredBytes + 512*1024*1024 else {
            throw JoeyError.dependency("Insufficient disk space: need \(requiredBytes + 512*1024*1024) bytes; available \(available)")
        }
    }
}
public final class ProcessingLock {
    private var fd: Int32 = -1
    public init(directory: URL) throws {
        fd = open(directory.appendingPathComponent("processing.lock").path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { throw JoeyError.failed("Cannot open processing lock") }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { close(fd); fd = -1; throw JoeyError.dependency("Another Joey process is processing this library") }
    }
    deinit { if fd >= 0 { flock(fd, LOCK_UN); close(fd) } }
}
