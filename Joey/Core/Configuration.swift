import Foundation

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
        if request.profile.driveOnlyJoe != true,
           let configured = request.owner == .taxstone ? taxstoneProfile : profile {
            renewed.profile = try request.profile.renewingEvidence(from:configured,requireCurrentEvidence:requireCurrentEvidence)
        }
        try renewed.validate(requireCurrentCapability:requireCurrentEvidence)
        return renewed
    }
    public static func load(root: URL, discoverTranscription: Bool = true) throws -> Configuration {
        let url = root.appendingPathComponent("settings.json")
        let exists = FileManager.default.fileExists(atPath:url.path)
        var c: Configuration = exists ? try Persistence.load(url) : Configuration()
        let home = FileManager.default.homeDirectoryForCurrentUser
        if discoverTranscription {
            let python = home.appendingPathComponent("Dub/.venv/bin/python").path
            if c.pythonPath == nil, FileManager.default.isExecutableFile(atPath: python) { c.pythonPath = python }
            #if SWIFT_PACKAGE
            let script = Bundle.module.url(forResource:"transcribe_source",withExtension:"py")
            #else
            let script = Bundle.main.url(forResource:"transcribe_source",withExtension:"py")
            #endif
            if let script {
                let helpers = root.appendingPathComponent("helpers")
                try FileManager.default.createDirectory(at:helpers,withIntermediateDirectories:true)
                let owned = helpers.appendingPathComponent("transcribe_source.py")
                if !FileManager.default.fileExists(atPath:owned.path) {try FileManager.default.copyItem(at:script,to:owned)}
                if c.transcriptionScript == nil || c.transcriptionScript?.contains(".build/") == true || c.transcriptionScript?.contains(".codex/plugins/") == true {
                    guard try Integrity.sha256(owned) == Integrity.sha256(script) else {throw JoeyError.dependency("Owned ASR adapter differs from bundled adapter; preserve and reconcile it")}
                    c.transcriptionScript = owned.path
                }
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
