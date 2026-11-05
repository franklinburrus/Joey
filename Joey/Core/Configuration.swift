import Foundation
import CryptoKit
import Darwin

public struct Configuration: Codable, Sendable {
    public var rcloneRemote = "dubdrive"
    public var pythonPath: String?
    public var transcriptionScript: String?
    public var modelPath: String?
    public var dubArtwork: Artwork?
    public var taxstoneArtwork: [String: Artwork] = [:]
    public var profile: SharedProfile?
    public var taxstoneProfile: SharedProfile?
    public var registerTab = "Master Library"
    // Optional preserves decoding and byte identity of existing settings.
    // Absence means enabled; capacity protection is never configurable.
    public var automaticCleanup: Bool?
    func renewingCapabilities(in request: JobRequest, requireCurrentEvidence: Bool = true) throws -> JobRequest {
        var renewed = request
        if !request.profile.isDriveOnly,
           let configured = request.owner == .taxstone ? taxstoneProfile : profile {
            renewed.profile = try request.profile.renewingEvidence(from:configured,requireCurrentEvidence:requireCurrentEvidence)
        }
        try renewed.validate(requireCurrentCapability:requireCurrentEvidence)
        return renewed
    }
    /// Uses the coordinator's renewal rules without changing settings, jobs or
    /// provider state. The coordinator repeats validation before any operation.
    public func resumeIssue(for request: JobRequest, sourceKind: MediaKind? = nil) -> String? {
        do {
            let renewed = try renewingCapabilities(in:request)
            if let sourceKind {_ = try renewed.profile.outputProfile(for:sourceKind)}
            return nil
        } catch {
            return error.localizedDescription
        }
    }
    /// Install only the application's adapter. A settings pointer changes after
    /// verified publication, while legacy files and all older versions remain.
    mutating func installTranscriptionHelper(from bundled: URL, root: URL) throws {
        // Match Coordinator's canonical working root, including macOS's /var
        // presentation alias. Managed descendants are still opened no-follow.
        let requestedRoot = root
        let root = try StorageManager.canonicalRoot(root)
        let legacy = root.appendingPathComponent("helpers/transcribe_source.py")
        let versions = root.appendingPathComponent("helpers/asr")
        let prior = transcriptionScript.map {path in
            path.hasPrefix(requestedRoot.path + "/") ? root.path + String(path.dropFirst(requestedRoot.path.count)) : path
        }
        let managed = prior?.hasPrefix(versions.path + "/") == true
        let migration = prior?.contains("/.build/") == true || prior?.contains("/.codex/plugins/") == true
        guard prior == nil || prior == legacy.path || managed || migration else {return}

        let bytes = try Self.helperBytes(at:bundled)
        let hash = SHA256.hash(data:bytes).map {String(format:"%02x",$0)}.joined()
        if let prior {
            let previous = URL(fileURLWithPath:prior)
            var previousHash: String?
            if managed {
                let relative = String(prior.dropFirst(versions.path.count + 1)).split(separator:"/",omittingEmptySubsequences:false)
                guard relative.count == 2, relative[1] == "transcribe_source.py",
                      relative[0].count == 64, relative[0].allSatisfy({"0123456789abcdef".contains($0)}) else {
                    throw JoeyError.dependency("Managed transcription helper is changed or has an invalid version identity. Existing settings and helper files are preserved.")
                }
                previousHash = String(relative[0])
            }
            let previousBytes = try Self.helperBytes(at:previous)
            if let previousHash, SHA256.hash(data:previousBytes).map({String(format:"%02x",$0)}).joined() != previousHash {
                throw JoeyError.dependency("Managed transcription helper bytes differ from their version SHA-256. Existing settings and helper files are preserved.")
            }
            if migration, previousBytes != bytes {
                throw JoeyError.dependency("Build or plugin transcription helper differs from the bundled adapter. Existing settings and helper files are preserved.")
            }
        }

        let rootFD = try StorageManager.openDirectory(root)
        defer {Darwin.close(rootFD)}
        let helpersFD = try Self.helperDirectory("helpers",under:rootFD)
        defer {Darwin.close(helpersFD)}
        let versionsFD = try Self.helperDirectory("asr",under:helpersFD)
        defer {Darwin.close(versionsFD)}
        var existing = stat()
        if fstatat(versionsFD,hash,&existing,AT_SYMLINK_NOFOLLOW) != 0 {
            guard errno == ENOENT else {
                throw JoeyError.dependency("Managed transcription helper cache cannot be inspected. Existing settings are preserved.")
            }
            try Self.publishHelper(bytes,version:hash,under:versionsFD)
        }
        let versionFD = openat(versionsFD,hash,O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard versionFD >= 0 else {
            throw JoeyError.dependency("Managed transcription helper version is missing or unsafe. Existing settings are preserved.")
        }
        defer {Darwin.close(versionFD)}
        guard try Self.helperBytes(named:"transcribe_source.py",under:versionFD) == bytes else {
            throw JoeyError.dependency("Managed transcription helper cache differs from its bundled version. Existing settings and helper files are preserved.")
        }
        transcriptionScript = versions.appendingPathComponent(hash + "/transcribe_source.py").path
    }

    private static func helperBytes(at file: URL) throws -> Data {
        let directory = try StorageManager.openDirectory(file.deletingLastPathComponent())
        defer {Darwin.close(directory)}
        return try helperBytes(named:file.lastPathComponent,under:directory)
    }

    private static func helperBytes(named name: String, under directory: Int32) throws -> Data {
        let fd = openat(directory,name,O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else {
            throw JoeyError.dependency("Transcription helper is missing, unreadable or linked. Existing settings and helper files are preserved.")
        }
        let handle = FileHandle(fileDescriptor:fd,closeOnDealloc:true)
        defer {try? handle.close()}
        var metadata = stat()
        let maximumBytes = 1_048_576
        guard fstat(fd,&metadata) == 0, (metadata.st_mode & S_IFMT) == S_IFREG,
              metadata.st_nlink == 1, metadata.st_size > 0, metadata.st_size <= maximumBytes else {
            throw JoeyError.dependency("Transcription helper must be a regular file with one hard link and at most 1 MiB. Existing settings are preserved.")
        }
        let bytes = try handle.read(upToCount:maximumBytes + 1) ?? Data()
        guard bytes.count == metadata.st_size else {
            throw JoeyError.dependency("Transcription helper changed while being read. Existing settings and helper files are preserved.")
        }
        return bytes
    }

    private static func helperDirectory(_ name: String, under parent: Int32) throws -> Int32 {
        guard mkdirat(parent,name,0o700) == 0 || errno == EEXIST else {
            throw JoeyError.dependency("Managed transcription helper directory cannot be created. Existing settings are preserved.")
        }
        let fd = openat(parent,name,O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else {
            throw JoeyError.dependency("Managed transcription helper directory is unsafe or unreadable. Existing settings are preserved.")
        }
        return fd
    }

    private static func publishHelper(_ bytes: Data, version: String, under directory: Int32) throws {
        let staging = ".install-" + UUID().uuidString
        guard mkdirat(directory,staging,0o700) == 0 else {
            throw JoeyError.dependency("Managed transcription helper staging cannot be created. Existing settings are preserved.")
        }
        let stagingFD = openat(directory,staging,O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard stagingFD >= 0 else {
            throw JoeyError.dependency("Managed transcription helper staging cannot be opened. Existing settings are preserved.")
        }
        var published = false
        defer {
            if !published {
                _ = unlinkat(stagingFD,"transcribe_source.py",0)
                _ = unlinkat(directory,staging,AT_REMOVEDIR)
            }
            Darwin.close(stagingFD)
        }
        let fd = openat(stagingFD,"transcribe_source.py",O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,0o600)
        guard fd >= 0 else {
            throw JoeyError.dependency("Managed transcription helper file cannot be created. Existing settings are preserved.")
        }
        let handle = FileHandle(fileDescriptor:fd,closeOnDealloc:true)
        defer {try? handle.close()}
        try handle.write(contentsOf:bytes)
        try handle.synchronize()
        guard try helperBytes(named:"transcribe_source.py",under:stagingFD) == bytes else {
            throw JoeyError.dependency("Staged transcription helper verification failed. Existing settings are preserved.")
        }
        guard fsync(stagingFD) == 0 else {
            throw JoeyError.failed("Staged transcription helper could not be synchronized. Existing settings are preserved.")
        }
        // Exclusive rename publishes an entire verified directory. A concurrent
        // winner is read back by the caller instead of replacing its version.
        if renameatx_np(directory,staging,directory,version,UInt32(RENAME_EXCL)) == 0 {
            published = true
            guard fsync(directory) == 0 else {
                throw JoeyError.failed("Transcription helper publication could not be synchronized. Existing settings are preserved.")
            }
        } else if errno != EEXIST {
            throw JoeyError.dependency("Managed transcription helper could not be published. Existing settings are preserved.")
        }
    }

    public static func load(root: URL, discoverTranscription: Bool = true) throws -> Configuration {
        let url = root.appendingPathComponent("settings.json")
        let exists = FileManager.default.fileExists(atPath:url.path)
        var c: Configuration = exists ? try Persistence.load(url) : Configuration()
        let home = FileManager.default.homeDirectoryForCurrentUser
        if discoverTranscription {
            if !FileManager.default.fileExists(atPath:root.path) {
                try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            }
            let python = home.appendingPathComponent("Dub/.venv/bin/python").path
            if c.pythonPath == nil, FileManager.default.isExecutableFile(atPath: python) { c.pythonPath = python }
            #if SWIFT_PACKAGE
            let script = Bundle.module.url(forResource:"transcribe_source",withExtension:"py")
            #else
            let script = Bundle.main.url(forResource:"transcribe_source",withExtension:"py")
            #endif
            if let script {
                try c.installTranscriptionHelper(from:script,root:root)
            }
            let models = home.appendingPathComponent(".cache/huggingface/hub/models--mlx-community--whisper-large-v3-turbo/snapshots")
            if c.modelPath == nil {c.modelPath = (try? FileManager.default.contentsOfDirectory(at: models, includingPropertiesForKeys:nil))?.first(where: {
                FileManager.default.fileExists(atPath:$0.appendingPathComponent("config.json").path)
            })?.path}
        }
        let cache = home.appendingPathComponent(".codex/plugins/cache/created-by-me-remote/dub-skill-family/1.3.5")
        let art = cache.appendingPathComponent("runtime/assets/audio-master-clean-v1.png")
        let expected = "1522d2fbbbb6d943cd08cb07b617212be4fafcb841c7dcdba713fe81c4fdc790"
        if c.dubArtwork == nil, (try? Integrity.sha256(art)) == expected {
            let assets = root.appendingPathComponent("assets")
            try FileManager.default.createDirectory(at:assets,withIntermediateDirectories:true)
            let owned = assets.appendingPathComponent("approved-dub-art.png")
            if !FileManager.default.fileExists(atPath:owned.path) {try FileManager.default.copyItem(at:art,to:owned)}
            c.dubArtwork = Artwork(owner:.dub, sourceID:nil, driveID:"1fRg-Dfd-V_VdZQuPZVGDM3kdHD-qi6V1",
                file:EvidenceFile(path:owned.path,sha256:expected,basis:"Approved DUB audio master in consolidated requirements"))
        }
        // Reading unchanged settings must also work in a read-only launch.
        // Preserve their identity and metadata instead of replacing them.
        if (try? Data(contentsOf:url)) != (try Persistence.encoder.encode(c)) {
            try Persistence.save(c, to:url)
        }
        return c
    }
}
