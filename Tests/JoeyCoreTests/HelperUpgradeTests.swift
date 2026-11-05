import XCTest
import Darwin
@testable import JoeyCore

final class HelperUpgradeTests: XCTestCase {
    private func workspace() throws -> URL {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        return try StorageManager.canonicalRoot(root)
    }

    private func write(_ text: String, to file: URL) throws {
        try FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true)
        try Data(text.utf8).write(to:file)
    }

    func testNormalLoadUpgradesLegacyOwnedHelperWithoutChangingItsBytes() throws {
        let root = try workspace()
        defer {try? FileManager.default.removeItem(at:root)}
        let legacy = root.appendingPathComponent("helpers/transcribe_source.py")
        try write("# Earlier app-owned adapter fixture\n",to:legacy)
        let previous = try Data(contentsOf:legacy)
        var saved = Configuration()
        saved.transcriptionScript = legacy.path
        try Persistence.save(saved,to:root.appendingPathComponent("settings.json"))

        let loaded = try Configuration.load(root:root)

        let selected = URL(fileURLWithPath:try XCTUnwrap(loaded.transcriptionScript))
        XCTAssertEqual(selected.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent,"asr")
        XCTAssertEqual(selected.deletingLastPathComponent().lastPathComponent,try Integrity.sha256(selected))
        XCTAssertEqual(try Data(contentsOf:legacy),previous)
        let persisted: Configuration = try Persistence.load(root.appendingPathComponent("settings.json"))
        XCTAssertEqual(persisted.transcriptionScript,selected.path)
    }

    func testSuppliedBundleUpgradeRetainsOldVersionsAndCustomPaths() throws {
        let root = try workspace()
        defer {try? FileManager.default.removeItem(at:root)}
        let oldBundle = root.appendingPathComponent("bundle-old.py")
        let newBundle = root.appendingPathComponent("bundle-new.py")
        try write("# old bundle\n",to:oldBundle)
        try write("# new bundle\n",to:newBundle)
        var config = Configuration()
        try config.installTranscriptionHelper(from:oldBundle,root:root)
        let oldPath = try XCTUnwrap(config.transcriptionScript)
        let oldBytes = try Data(contentsOf:URL(fileURLWithPath:oldPath))

        try config.installTranscriptionHelper(from:newBundle,root:root)

        XCTAssertNotEqual(config.transcriptionScript,oldPath)
        XCTAssertEqual(try Data(contentsOf:URL(fileURLWithPath:oldPath)),oldBytes)
        XCTAssertEqual(try Integrity.sha256(URL(fileURLWithPath:try XCTUnwrap(config.transcriptionScript))),try Integrity.sha256(newBundle))
        let custom = root.appendingPathComponent("custom-adapter.py")
        try write("# custom adapter\n",to:custom)
        config.transcriptionScript = custom.path
        try config.installTranscriptionHelper(from:root.appendingPathComponent("missing-bundle.py"),root:root)
        XCTAssertEqual(config.transcriptionScript,custom.path)
        XCTAssertEqual(try Data(contentsOf:custom),Data("# custom adapter\n".utf8))
    }

    func testRepeatedLoadDoesNotRewriteHelperOrSettings() throws {
        let root = try workspace()
        defer {try? FileManager.default.removeItem(at:root)}
        let first = try Configuration.load(root:root)
        let helper = URL(fileURLWithPath:try XCTUnwrap(first.transcriptionScript))
        let settings = root.appendingPathComponent("settings.json")
        let beforeHelper = try FileManager.default.attributesOfItem(atPath:helper.path)
        let beforeSettings = try FileManager.default.attributesOfItem(atPath:settings.path)

        let second = try Configuration.load(root:root)

        let afterHelper = try FileManager.default.attributesOfItem(atPath:helper.path)
        let afterSettings = try FileManager.default.attributesOfItem(atPath:settings.path)
        XCTAssertEqual(second.transcriptionScript,first.transcriptionScript)
        for key in [FileAttributeKey.systemFileNumber,.modificationDate] {
            XCTAssertEqual(beforeHelper[key] as? NSObject,afterHelper[key] as? NSObject)
            XCTAssertEqual(beforeSettings[key] as? NSObject,afterSettings[key] as? NSObject)
        }
    }

    func testNormalLoadAcceptsMacOSTemporaryDirectoryAlias() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let legacy = root.appendingPathComponent("helpers/transcribe_source.py")
        try write("# legacy alias fixture\n",to:legacy)
        var saved = Configuration()
        saved.transcriptionScript = legacy.path
        try Persistence.save(saved,to:root.appendingPathComponent("settings.json"))
        let loaded = try Configuration.load(root:root)
        XCTAssertNotEqual(loaded.transcriptionScript,legacy.path)
        let selected = URL(fileURLWithPath:try XCTUnwrap(loaded.transcriptionScript))
        XCTAssertEqual(selected.deletingLastPathComponent().lastPathComponent,try Integrity.sha256(selected))
        XCTAssertEqual(try Data(contentsOf:legacy),Data("# legacy alias fixture\n".utf8))
    }

    func testNormalLoadCreatesItsFreshWorkingRoot() throws {
        let parent = try workspace()
        defer {try? FileManager.default.removeItem(at:parent)}
        let root = parent.appendingPathComponent("new-working-root")
        let loaded = try Configuration.load(root:root)
        let selected = URL(fileURLWithPath:try XCTUnwrap(loaded.transcriptionScript))
        XCTAssertEqual(selected.deletingLastPathComponent().lastPathComponent,try Integrity.sha256(selected))
        XCTAssertTrue(FileManager.default.fileExists(atPath:root.appendingPathComponent("settings.json").path))
    }

    func testConcurrentInstallersConvergeOnOneVerifiedVersion() async throws {
        let root = try workspace()
        defer {try? FileManager.default.removeItem(at:root)}
        let bundle = root.appendingPathComponent("bundle.py")
        try write("# concurrent bundle fixture\n",to:bundle)
        let paths = try await withThrowingTaskGroup(of:String.self) {group in
            for _ in 0..<8 {
                group.addTask {
                    var config = Configuration()
                    try config.installTranscriptionHelper(from:bundle,root:root)
                    return try XCTUnwrap(config.transcriptionScript)
                }
            }
            var paths: [String] = []
            for try await path in group {paths.append(path)}
            return paths
        }
        XCTAssertEqual(Set(paths).count,1)
        let installed = URL(fileURLWithPath:try XCTUnwrap(paths.first))
        XCTAssertEqual(try Integrity.sha256(installed),try Integrity.sha256(bundle))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:root.appendingPathComponent("helpers/asr").path),[installed.deletingLastPathComponent().lastPathComponent])
    }

    func testConcurrentConfigurationLoadsPersistOnePointerAndPreserveOtherSettings() async throws {
        let root = try workspace()
        defer {try? FileManager.default.removeItem(at:root)}
        var saved = Configuration()
        saved.rcloneRemote = "fixture-remote"
        saved.pythonPath = "/fixture/python"
        saved.modelPath = "/fixture/model"
        saved.dubArtwork = Artwork(owner:.dub,driveID:"fixture-artwork",file:EvidenceFile(path:"/fixture/artwork",sha256:String(repeating:"a",count:64),basis:"Synthetic configuration fixture"))
        try Persistence.save(saved,to:root.appendingPathComponent("settings.json"))
        let paths = try await withThrowingTaskGroup(of:String.self) {group in
            for _ in 0..<8 {
                group.addTask {
                    let config = try Configuration.load(root:root)
                    return try XCTUnwrap(config.transcriptionScript)
                }
            }
            var paths: [String] = []
            for try await path in group {paths.append(path)}
            return paths
        }
        XCTAssertEqual(Set(paths).count,1)
        let persisted: Configuration = try Persistence.load(root.appendingPathComponent("settings.json"))
        XCTAssertEqual(persisted.transcriptionScript,paths.first)
        XCTAssertEqual(persisted.rcloneRemote,saved.rcloneRemote)
        XCTAssertEqual(persisted.dubArtwork,saved.dubArtwork)
        XCTAssertEqual(persisted.pythonPath,saved.pythonPath)
        XCTAssertEqual(persisted.modelPath,saved.modelPath)
    }

    func testCorruptOrMissingManagedVersionPreservesPriorConfiguration() throws {
        for missing in [false,true] {
            let root = try workspace()
            defer {try? FileManager.default.removeItem(at:root)}
            let bundle = root.appendingPathComponent("bundle.py")
            try write("# verified bundle\n",to:bundle)
            var config = Configuration()
            try config.installTranscriptionHelper(from:bundle,root:root)
            let selected = URL(fileURLWithPath:try XCTUnwrap(config.transcriptionScript))
            let settings = root.appendingPathComponent("settings.json")
            try Persistence.save(config,to:settings)
            let before = try Data(contentsOf:settings)
            if missing {try FileManager.default.removeItem(at:selected)}
            else {try write("# changed cache\n",to:selected)}

            XCTAssertThrowsError(try config.installTranscriptionHelper(from:bundle,root:root))

            XCTAssertEqual(config.transcriptionScript,selected.path)
            XCTAssertEqual(try Data(contentsOf:settings),before)
        }
    }

    func testIncompleteOrUnwritableNewVersionPreservesLegacyConfiguration() throws {
        for interrupted in [true,false] {
            let root = try workspace()
            defer {try? FileManager.default.removeItem(at:root)}
            let legacy = root.appendingPathComponent("helpers/transcribe_source.py")
            let bundle = root.appendingPathComponent("bundle.py")
            try write("# retained legacy\n",to:legacy)
            try write("# new bundle\n",to:bundle)
            var config = Configuration()
            config.transcriptionScript = legacy.path
            let settings = root.appendingPathComponent("settings.json")
            try Persistence.save(config,to:settings)
            let before = try Data(contentsOf:settings)
            let versions = root.appendingPathComponent("helpers/asr")
            try FileManager.default.createDirectory(at:versions,withIntermediateDirectories:true)
            if interrupted {
                try FileManager.default.createDirectory(at:versions.appendingPathComponent(try Integrity.sha256(bundle)),withIntermediateDirectories:false)
            } else {
                XCTAssertEqual(chmod(versions.path,0o500),0)
            }
            defer {_ = chmod(versions.path,0o700)}

            XCTAssertThrowsError(try config.installTranscriptionHelper(from:bundle,root:root))

            XCTAssertEqual(config.transcriptionScript,legacy.path)
            XCTAssertEqual(try Data(contentsOf:settings),before)
            XCTAssertEqual(try Data(contentsOf:legacy),Data("# retained legacy\n".utf8))
        }
    }

    func testManagedDirectoriesAndFilesCannotEscapeThroughLinks() throws {
        for linkedDirectory in [true,false] {
            let root = try workspace()
            defer {try? FileManager.default.removeItem(at:root)}
            let bundle = root.appendingPathComponent("bundle.py")
            try write("# new bundle\n",to:bundle)
            let outside = root.appendingPathComponent("outside")
            try FileManager.default.createDirectory(at:outside,withIntermediateDirectories:true)
            let hash = try Integrity.sha256(bundle)
            let managed = root.appendingPathComponent("helpers/asr/"+hash)
            try FileManager.default.createDirectory(at:managed.deletingLastPathComponent(),withIntermediateDirectories:true)
            if linkedDirectory {
                try FileManager.default.createSymbolicLink(at:managed,withDestinationURL:outside)
            } else {
                try FileManager.default.createDirectory(at:managed,withIntermediateDirectories:false)
                let outsideFile = outside.appendingPathComponent("transcribe_source.py")
                try write("# protected outside\n",to:outsideFile)
                try FileManager.default.createSymbolicLink(at:managed.appendingPathComponent("transcribe_source.py"),withDestinationURL:outsideFile)
            }
            var config = Configuration()

            XCTAssertThrowsError(try config.installTranscriptionHelper(from:bundle,root:root))

            XCTAssertNil(config.transcriptionScript)
            let outsideFiles = try FileManager.default.contentsOfDirectory(atPath:outside.path)
            XCTAssertEqual(outsideFiles,linkedDirectory ? [] : ["transcribe_source.py"])
        }
    }

    func testBuildMigrationRequiresMatchingBytesAndInstallerBoundsSource() throws {
        let root = try workspace()
        defer {try? FileManager.default.removeItem(at:root)}
        let bundle = root.appendingPathComponent("bundle.py")
        let build = root.appendingPathComponent(".build/resources/transcribe_source.py")
        try write("# bundle\n",to:bundle)
        try write("# different build helper\n",to:build)
        var config = Configuration()
        config.transcriptionScript = build.path
        XCTAssertThrowsError(try config.installTranscriptionHelper(from:bundle,root:root))
        XCTAssertEqual(config.transcriptionScript,build.path)
        try write("# bundle\n",to:build)
        try config.installTranscriptionHelper(from:bundle,root:root)
        XCTAssertNotEqual(config.transcriptionScript,build.path)
        let oversized = root.appendingPathComponent("oversized.py")
        try Data(repeating:65,count:1_048_577).write(to:oversized)
        var empty = Configuration()
        XCTAssertThrowsError(try empty.installTranscriptionHelper(from:oversized,root:root))
        XCTAssertNil(empty.transcriptionScript)
    }

    func testFIFOHelpersAreRejectedWithoutWaitingForAWriter() throws {
        for location in ["bundle","legacy","managed"] {
            let root = try workspace()
            defer {try? FileManager.default.removeItem(at:root)}
            let bundle = root.appendingPathComponent("bundle.py")
            try write("# regular bundled helper\n",to:bundle)
            let fifo: URL
            let configured: String?
            switch location {
            case "legacy":
                fifo = root.appendingPathComponent("helpers/transcribe_source.py")
                configured = fifo.path
            case "managed":
                fifo = root.appendingPathComponent("helpers/asr/" + String(repeating:"a",count:64) + "/transcribe_source.py")
                configured = fifo.path
            default:
                try FileManager.default.removeItem(at:bundle)
                fifo = bundle
                configured = nil
            }
            try FileManager.default.createDirectory(at:fifo.deletingLastPathComponent(),withIntermediateDirectories:true)
            XCTAssertEqual(mkfifo(fifo.path,0o600),0)
            let started = DispatchSemaphore(value:0)
            let finished = DispatchGroup()
            finished.enter()
            DispatchQueue.global().async {
                defer {finished.leave()}
                var config = Configuration()
                config.transcriptionScript = configured
                started.signal()
                do {
                    try config.installTranscriptionHelper(from:bundle,root:root)
                    XCTFail("FIFO helper was accepted")
                } catch {}
                XCTAssertEqual(config.transcriptionScript,configured)
            }
            XCTAssertEqual(started.wait(timeout:.now() + .seconds(2)),.success)
            let rejectedWithoutWriter = finished.wait(timeout:.now() + .milliseconds(200)) == .success
            if !rejectedWithoutWriter {
                // Bound the red case too. Release a blocking reader with a
                // nonblocking writer, then wait for its normal type rejection.
                for _ in 0..<200 {
                    let writer = open(fifo.path,O_WRONLY | O_NONBLOCK | O_CLOEXEC)
                    if writer >= 0 {Darwin.close(writer);break}
                    usleep(10_000)
                }
            }
            XCTAssertEqual(finished.wait(timeout:.now() + .seconds(2)),.success)
            XCTAssertTrue(rejectedWithoutWriter,"\(location) FIFO helper waited for a writer")
        }
    }
}
