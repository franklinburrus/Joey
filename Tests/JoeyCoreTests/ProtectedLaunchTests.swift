import XCTest
@testable import JoeyCore

final class ProtectedLaunchTests: XCTestCase {
    @MainActor func testServiceSandboxPreservesExistingHomeDataAndAllowsIdenticalOuterProfile() async throws {
        let home = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:home) }
        let names = ["Dub/source.mp4", "Library/Application Support/Joey Native/settings.json",
                     ".ollama/id_ed25519", ".ollama/id_ed25519.pub", ".ollama/models/canary",
                     ".config/rclone/rclone.conf", ".codex/auth.json", ".zshrc"]
        for name in names {
            let file = home.appendingPathComponent(name)
            try FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true)
            try Data("DUMMY CANARY ONLY".utf8).write(to:file)
        }
        let profile = LocalAssistantService.sandboxProfile(home:home)
        // An identical outer profile must preserve every denial, without a
        // skip-sandbox flag, process escape, or unrestricted fallback.
        let script = """
        import os, sys, errno
        assert len(sys.argv) == 9, len(sys.argv)
        denied = 0
        for path in sys.argv[1:]:
            try:
                fd = os.open(path, os.O_WRONLY)
                os.close(fd)
                print("unexpected writable fixture: " + os.path.realpath(path))
            except OSError as error:
                assert error.errno == errno.EPERM
                denied += 1
        print(denied)
        """
        let result = try await Processes.run("/usr/bin/sandbox-exec",[
            "-p",profile,"/usr/bin/sandbox-exec","-p",profile,
            "/opt/homebrew/bin/python3","-c",script
        ] + names.map { home.appendingPathComponent($0).path })
        XCTAssertEqual(String(decoding:result.stdout,as:UTF8.self).trimmingCharacters(in:.whitespacesAndNewlines),"8")
        for name in names { XCTAssertEqual(try Data(contentsOf:home.appendingPathComponent(name)),Data("DUMMY CANARY ONLY".utf8)) }
    }

    @MainActor func testServiceSandboxAllowsOnlyMissingLocalIdentityFiles() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let ollama = home.appendingPathComponent(".ollama")
        try FileManager.default.createDirectory(at:ollama,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:home) }
        let script = """
        import os, sys, errno
        for name in ['id_ed25519', 'id_ed25519.pub']:
            with open(os.path.join(sys.argv[1], name), 'w') as stream:
                stream.write('DUMMY CANARY ONLY - NOT A KEY')
        try:
            open(os.path.join(sys.argv[1], 'unrelated'), 'w')
            raise AssertionError('Unrelated home write allowed')
        except OSError as error:
            assert error.errno == errno.EPERM
        """
        _ = try await Processes.run("/usr/bin/sandbox-exec",[
            "-p",LocalAssistantService.sandboxProfile(home:home),
            "/opt/homebrew/bin/python3","-c",script,ollama.path])
        XCTAssertTrue(FileManager.default.fileExists(atPath:ollama.appendingPathComponent("id_ed25519").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath:ollama.appendingPathComponent("id_ed25519.pub").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath:ollama.appendingPathComponent("unrelated").path))
    }

    func testLoadingUnchangedConfigurationDoesNotReplaceSettings() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        _ = try Configuration.load(root:root,discoverTranscription:false)
        let file = root.appendingPathComponent("settings.json")
        let before = try FileManager.default.attributesOfItem(atPath:file.path)
        let bytes = try Data(contentsOf:file)
        _ = try Configuration.load(root:root,discoverTranscription:false)
        let after = try FileManager.default.attributesOfItem(atPath:file.path)
        XCTAssertEqual(before[.systemFileNumber] as? NSNumber,after[.systemFileNumber] as? NSNumber)
        XCTAssertEqual(before[.modificationDate] as? Date,after[.modificationDate] as? Date)
        XCTAssertEqual(try Data(contentsOf:file),bytes)
    }

    func testSyntheticImportCapabilityUsesControlledClockAndStillExpires() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:dir) }
        var request = try Fixtures.request(dir:dir,path:"synthetic-fixture.mp4")
        let now = Date(timeIntervalSince1970:1_793_400_000)
        request.profile.x!.checkedAt = now
        request.profile.x!.validUntil = now.addingTimeInterval(60)
        request.profile.instagram!.checkedAt = now
        request.profile.instagram!.validUntil = now.addingTimeInterval(60)
        let decoded = try Persistence.decoder.decode(JobRequest.self,from:Persistence.encoder.encode(request))
        XCTAssertNoThrow(try decoded.profile.validate(now:now))
        XCTAssertThrowsError(try decoded.profile.validate(now:now.addingTimeInterval(60)))
    }
}
