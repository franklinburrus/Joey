import XCTest
@testable import JoeyCore
import Darwin

final class StorageTests: XCTestCase {
    struct Fixture {
        let root: URL
        let lock: ProcessingLock
        let manager: StorageManager
        let work: URL
        let job: JobRecord
    }
    func fixture(accepted: Bool = true) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        addTeardownBlock {try? FileManager.default.removeItem(at:root)}
        let request = try Fixtures.request(dir:root,path:root.appendingPathComponent("original.mp4").path)
        var job = JobRecord(id:"dub-storage-test",request:request)
        let dir = root.appendingPathComponent("jobs/"+job.id)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        let output = dir.appendingPathComponent("accepted.mp4")
        try Data("accepted waiting for Drive".utf8).write(to:output)
        let hash = try Integrity.sha256(output)
        let qa = QAReport(checkedAt:Date(),checks:["fixture":"isolated"],outputSHA256:hash,passed:true,limitations:[])
        job.clips = [ClipRecord(id:1,title:"Fixture",intervals:[Interval(0,2)],filename:"accepted.mp4",sha256:accepted ? hash:nil,qa:accepted ? qa:nil)]
        job.state = accepted ? .qaPassed:.failed
        try Persistence.save(job,to:dir.appendingPathComponent("job.json"))
        try Persistence.save(qa,to:dir.appendingPathComponent("evidence/1/qa.json"))
        try Data("source".utf8).write(to:root.appendingPathComponent("original.mp4"))
        try Data("transcript".utf8).write(to:dir.appendingPathComponent("transcript.json"))
        let lock = try ProcessingLock(directory:root)
        let manager = try StorageManager(root:root,lock:lock)
        let work = try manager.begin(jobID:job.id,clipID:1)
        try Data(repeating:7,count:65536).write(to:work.appendingPathComponent("selected.wav"))
        try Data("{\"diagnostic\":true}".utf8).write(to:work.appendingPathComponent("render.json"))
        return Fixture(root:root,lock:lock,manager:manager,work:work,job:job)
    }
    func testClosedScratchCleanupMeasuresDeletionAndProtectsUnfiledAcceptedOutput() throws {
        let f = try fixture()
        let jobDir = f.root.appendingPathComponent("jobs/"+f.job.id)
        let protected = [f.root.appendingPathComponent("original.mp4"),jobDir.appendingPathComponent("accepted.mp4"),jobDir.appendingPathComponent("transcript.json"),jobDir.appendingPathComponent("job.json")]
        let hashes = try protected.map {try Integrity.sha256($0)}
        try f.manager.closeAttempt(f.work,jobID:f.job.id)
        let expected = 65536 + Data("{\"diagnostic\":true}".utf8).count
        let result = try f.manager.clean()
        XCTAssertEqual(result.removedBytes,Int64(expected));XCTAssertEqual(result.removedFiles,2)
        XCTAssertTrue(result.errors.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath:f.work.path))
        XCTAssertEqual(try protected.map {try Integrity.sha256($0)},hashes)
        XCTAssertTrue(FileManager.default.fileExists(atPath:jobDir.appendingPathComponent("storage-attempts/\(f.work.lastPathComponent)-render.json").path))
        XCTAssertEqual(try f.manager.clean().removedBytes,0)
        XCTAssertGreaterThan(result.freeBytesBefore,0);XCTAssertGreaterThan(result.freeBytesAfter,0)
    }
    func testFailedAttemptRequiredForRecoveryRemainsUntilAcceptedReplacement() throws {
        let f = try fixture(accepted:false)
        try f.manager.closeAttempt(f.work,jobID:f.job.id)
        XCTAssertEqual(try f.manager.clean().removedBytes,0)
        XCTAssertTrue(FileManager.default.fileExists(atPath:f.work.path))
    }
    func testMultiChunkScratchHashMatchesReceiptBeforeVerifiedCleanup() throws {
        let f = try fixture()
        try Data(repeating:7,count:2*1024*1024+17).write(to:f.work.appendingPathComponent("selected.wav"))
        try f.manager.closeAttempt(f.work,jobID:f.job.id)
        let receipt = f.root.appendingPathComponent("jobs/\(f.job.id)/storage-attempts/\(f.work.lastPathComponent).json")
        let attempt: ScratchAttempt = try Persistence.load(receipt)
        XCTAssertEqual(attempt.files.first(where:{$0.name == "selected.wav"})?.sha256,
            "f5930b95a132f0f0667e382a76ba676d79f48281e1336d74321d0c5f42b7e0b6")
        let result = try f.manager.clean()
        XCTAssertEqual(result.removedFiles,2)
        XCTAssertEqual(result.removedBytes,2*1024*1024+17+Int64(Data("{\"diagnostic\":true}".utf8).count))
        XCTAssertFalse(FileManager.default.fileExists(atPath:f.work.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath:f.root.appendingPathComponent("jobs/\(f.job.id)/accepted.mp4").path))
    }
    func testChangedByteBeyondFirstScratchChunkPreventsCleanup() throws {
        let f = try fixture()
        let scratch = f.work.appendingPathComponent("selected.wav")
        try Data(repeating:7,count:2*1024*1024+17).write(to:scratch)
        try f.manager.closeAttempt(f.work,jobID:f.job.id)
        let handle = try FileHandle(forWritingTo:scratch)
        try handle.seek(toOffset:1024*1024+11)
        try handle.write(contentsOf:Data([8]))
        try handle.close()
        XCTAssertEqual(try f.manager.clean().removedFiles,0)
        XCTAssertTrue(FileManager.default.fileExists(atPath:scratch.path))
    }
    func testLiveAttemptAndConcurrentWorkerAreNeverReclaimed() throws {
        let f = try fixture()
        XCTAssertEqual(try f.manager.clean().removedBytes,0)
        try f.manager.closeAttempt(f.work,jobID:f.job.id)
        let worker = try ProcessingLock(directory:f.root,name:"storage-workers.lock",shared:true)
        XCTAssertThrowsError(try f.manager.clean())
        XCTAssertThrowsError(try StorageManager.clean(root:f.root))
        withExtendedLifetime(worker) {}
        XCTAssertTrue(FileManager.default.fileExists(atPath:f.work.path))
    }
    func testOrphanRecoveryUsesReceiptAndAcceptedStateNotAge() throws {
        let f = try fixture()
        let receipt = f.root.appendingPathComponent("jobs/\(f.job.id)/storage-attempts/\(f.work.lastPathComponent).json")
        var attempt: ScratchAttempt = try Persistence.load(receipt)
        attempt.creatorPID = Int32.max // nonexistent PID, no production process affected
        try Persistence.save(attempt,to:receipt)
        let reopened = try StorageManager(root:f.root,lock:f.lock)
        XCTAssertEqual(try reopened.clean().removedFiles,2)
    }
    func testUnknownHistoricalAndUnrecognizedArtifactsArePreserved() throws {
        let f = try fixture()
        let historical = f.work.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:historical,withIntermediateDirectories:false)
        try Data([1]).write(to:historical.appendingPathComponent("selected.wav"))
        try Data([2]).write(to:f.work.appendingPathComponent("original.mp3"))
        XCTAssertThrowsError(try f.manager.closeAttempt(f.work,jobID:f.job.id))
        XCTAssertEqual(try f.manager.clean().removedBytes,0)
        XCTAssertTrue(FileManager.default.fileExists(atPath:historical.appendingPathComponent("selected.wav").path))
    }
    func testSymlinkHardLinkTraversalAndChangedInodeAreRejected() throws {
        let f = try fixture()
        XCTAssertThrowsError(try f.manager.begin(jobID:"../../outside",clipID:1))
        let scratch = f.work.appendingPathComponent("selected.wav")
        try FileManager.default.removeItem(at:scratch)
        let source = f.root.appendingPathComponent("original.mp4")
        try FileManager.default.createSymbolicLink(at:scratch,withDestinationURL:source)
        XCTAssertThrowsError(try f.manager.closeAttempt(f.work,jobID:f.job.id))
        XCTAssertEqual(try f.manager.clean().removedBytes,0)
        try FileManager.default.removeItem(at:scratch)
        XCTAssertEqual(link(source.path,scratch.path),0)
        XCTAssertThrowsError(try f.manager.closeAttempt(f.work,jobID:f.job.id))
        try FileManager.default.removeItem(at:scratch)
        try Data([3]).write(to:scratch)
        try f.manager.closeAttempt(f.work,jobID:f.job.id)
        try Data([4,5]).write(to:scratch,options:.atomic)
        XCTAssertEqual(try f.manager.clean().removedBytes,0)
        XCTAssertEqual(try Data(contentsOf:source),Data("source".utf8))
    }
    func testDirectorySymlinkCannotEscapeOwnedStorage() throws {
        let f = try fixture()
        try f.manager.closeAttempt(f.work,jobID:f.job.id)
        let moved = f.root.appendingPathComponent("retained-outside-scratch")
        try FileManager.default.moveItem(at:f.work,to:moved)
        try FileManager.default.createSymbolicLink(at:f.work,withDestinationURL:moved)
        XCTAssertEqual(try f.manager.clean().removedBytes,0)
        XCTAssertTrue(FileManager.default.fileExists(atPath:moved.appendingPathComponent("selected.wav").path))
    }
    func testCheckpointDependencyOverridesDisposableReceipt() throws {
        let f = try fixture()
        try f.manager.closeAttempt(f.work,jobID:f.job.id)
        var job = f.job;job.request.transcriptPath = f.work.appendingPathComponent("selected.wav").path
        try Persistence.save(job,to:f.root.appendingPathComponent("jobs/\(job.id)/job.json"))
        XCTAssertEqual(try f.manager.clean().removedBytes,0)
    }
    func testPartialCleanupRecoveryAndChangedAcceptedOutput() throws {
        let f = try fixture()
        try f.manager.closeAttempt(f.work,jobID:f.job.id)
        try FileManager.default.removeItem(at:f.work.appendingPathComponent("selected.wav"))
        XCTAssertEqual(try f.manager.clean().removedFiles,1)
        let other = try fixture()
        try other.manager.closeAttempt(other.work,jobID:other.job.id)
        try Data([8]).write(to:other.root.appendingPathComponent("jobs/\(other.job.id)/accepted.mp4"))
        XCTAssertEqual(try other.manager.clean().removedBytes,0)
    }
    func testClassificationAndPreferenceCompatibility() throws {
        let f = try fixture()
        let snapshot = try StorageManager.inspect(root:f.root)
        XCTAssertEqual(snapshot.temporaryBytes,65536+Int64(Data("{\"diagnostic\":true}".utf8).count))
        XCTAssertGreaterThan(snapshot.protectedBytes,0)
        XCTAssertEqual(snapshot.totalBytes,snapshot.temporaryBytes+snapshot.protectedBytes)
        XCTAssertNil(snapshot.reclaimableBytes) // current coordinator owns root
        let settings = f.root.appendingPathComponent("settings.json")
        let original = try Persistence.encoder.encode(Configuration())
        try original.write(to:settings)
        XCTAssertTrue(StorageManager.automaticCleanupEnabled(root:f.root))
        var config: Configuration = try Persistence.load(settings)
        XCTAssertEqual(try Persistence.encoder.encode(config),original)
        config.automaticCleanup = false;try Persistence.save(config,to:settings)
        XCTAssertFalse(StorageManager.automaticCleanupEnabled(root:f.root))
    }
    func testCapacityUsesWorkflowAndReserveWithoutFillingDisk() throws {
        let f = try fixture()
        let small = try StorageManager.peakBytes(duration:10,sourceBytes:100,clipDuration:10,audio:true)
        let large = try StorageManager.peakBytes(duration:1000,sourceBytes:1000,clipDuration:140,audio:true)
        XCTAssertGreaterThan(large,small)
        XCTAssertThrowsError(try StorageManager.peakBytes(duration:.nan,sourceBytes:0,clipDuration:10,audio:true))
        XCTAssertThrowsError(try StorageManager.checkCapacity(at:f.root,requiredBytes:small,available:small+99,reserve:100)) {error in
            XCTAssertTrue(error is StorageBlocked)
        }
        XCTAssertNoThrow(try StorageManager.checkCapacity(at:f.root,requiredBytes:small,available:small+100,reserve:100))
    }
    func testLocalSourceAdmissionDoesNotReserveAnotherOriginal() async throws {
        try await assertExistingSourceAdmission(reuse:false)
    }
    func testCrossJobSourceAdmissionDoesNotReserveAnotherOriginal() async throws {
        try await assertExistingSourceAdmission(reuse:true)
    }
    private func assertExistingSourceAdmission(reuse: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let source = root.appendingPathComponent("source.mp4")
        _ = try await Processes.run("ffmpeg",["-v","error","-f","lavfi","-i","testsrc2=s=320x180:r=30:d=2","-f","lavfi","-i","sine=frequency=440:duration=2","-c:v","libx264","-c:a","aac","-shortest",source.path])
        var request = try Fixtures.request(dir:root,path:source.path)
        request.expectedDuration = 2
        request.transcriptPolicy = reuse ? .assisted : .modelIndependent
        if reuse {
            request.localPath = nil
            request.originalURL = "https://x.com/i/broadcasts/synthetic"
        }
        let original = try await Media.inspect(source,request:request)
        if reuse {
            var priorRequest = request;priorRequest.title = "Previous request using the same original"
            var prior = JobRecord(id:try priorRequest.stableID(),request:priorRequest)
            prior.source = original
            prior.transcript = Transcript(sourceID:original.id,sourceSHA256:original.sha256,duration:original.duration,engine:"Synthetic fixture",
                segments:[TranscriptSegment(start:0,end:original.duration,text:"Complete synthetic source.")])
            try Persistence.save(prior,to:root.appendingPathComponent("jobs/\(prior.id)/job.json"))
        }
        let reserve = try StorageManager.capacity(at:root).reserve
        let renderPeak = try StorageManager.peakBytes(duration:original.duration,sourceBytes:0,clipDuration:original.duration,audio:false)
        // This is enough for all remaining output and scratch, but not an
        // additional copy of the already-present original. No disk is filled.
        let available = reserve + renderPeak + 1
        let coordinator = try Coordinator(root:root)
        do {
            let result = try await Task {
                try await StorageManager.$capacityOverride.withValue({available}) {
                    try await coordinator.run(request,estimatedDuration:2) {job in
                        if job.storageRequiredBytes != nil {withUnsafeCurrentTask {$0?.cancel()}}
                    }
                }
            }.value
            XCTAssertEqual(result.state,.qaPassed,result.error ?? "")
            XCTAssertEqual(result.source?.path,source.path)
            XCTAssertEqual(result.source?.sha256,original.sha256)
            XCTAssertEqual(result.clips.count,1)
            XCTAssertTrue(result.clips.allSatisfy {$0.qa?.passed == true})
            XCTAssertEqual(try result.request.identityData(),try request.identityData())
        } catch {
            XCTFail("Existing original was incorrectly charged as a new acquisition: \(error)")
        }
        XCTAssertEqual(try Integrity.sha256(source),original.sha256)
    }
    func testStageAdmissionStillBlocksInsufficientRenderCapacityAfterSourceInspection() async throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let source = root.appendingPathComponent("source.mp4")
        _ = try await Processes.run("ffmpeg",["-v","error","-f","lavfi","-i","testsrc2=s=320x180:r=30:d=2","-c:v","libx264",source.path])
        var request = try Fixtures.request(dir:root,path:source.path)
        request.expectedDuration = 2;request.transcriptPolicy = .modelIndependent
        let originalHash = try Integrity.sha256(source)
        let required = try StorageManager.peakBytes(duration:2,sourceBytes:0,clipDuration:2,audio:false) + StorageManager.capacity(at:root).reserve
        let coordinator = try Coordinator(root:root)
        do {
            _ = try await Task {
                try await StorageManager.$capacityOverride.withValue({required-1}) {
                    try await coordinator.run(request,estimatedDuration:2) {job in
                        if let needed = job.storageRequiredBytes {
                            XCTAssertEqual(needed,required)
                            withUnsafeCurrentTask {$0?.cancel()}
                        }
                    }
                }
            }.value
            XCTFail("Expected a capacity pause")
        } catch {XCTAssertTrue(error is CancellationError)}
        let jobs = try await coordinator.jobs()
        XCTAssertEqual(jobs.count,1)
        XCTAssertEqual(jobs[0].state,.cancelled)
        XCTAssertEqual(jobs[0].source?.sha256,originalHash,"Inspection and source checkpoint must precede render admission")
        XCTAssertTrue(jobs[0].clips.isEmpty)
        XCTAssertEqual(try Integrity.sha256(source),originalHash)
    }
    func testExpiredCapabilityReplacesStoredCapacityWaitWithTerminalFailure() async throws {
        try await assertCapabilityFailureEndsStoredCapacityWait(changedContract:false)
    }
    func testChangedCapabilityContractReplacesStoredCapacityWaitWithTerminalFailure() async throws {
        try await assertCapabilityFailureEndsStoredCapacityWait(changedContract:true)
    }
    private func assertCapabilityFailureEndsStoredCapacityWait(changedContract: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        var request = try Fixtures.request(dir:root,path:root.appendingPathComponent("unused-source.mp4").path)
        request.transcriptPolicy = .modelIndependent
        var config = Configuration();config.automaticCleanup = false
        if changedContract {
            var proposed = request.profile
            proposed.x!.account = "different-fixture-account"
            config.profile = proposed
        } else {
            request.profile.x!.checkedAt = Date().addingTimeInterval(-7200)
            request.profile.x!.validUntil = Date().addingTimeInterval(-3600)
        }
        try Persistence.save(config,to:root.appendingPathComponent("settings.json"))
        var saved = JobRecord(id:try request.stableID(),request:request)
        saved.state = .processing
        saved.stage = "Storage blocked — capacity recheck in 60 seconds"
        saved.storageRequiredBytes = 1
        saved.error = "Synthetic prior capacity shortage"
        let checkpoint = root.appendingPathComponent("jobs/\(saved.id)/job.json")
        try Persistence.save(saved,to:checkpoint)
        let expectedError = changedContract ? "saved account" : "expired"
        let running = Task {
            try await StorageManager.$capacityOverride.withValue({100_000_000_000}) {
                try await Coordinator(root:root).run(request) {job in
                    if job.error?.contains(expectedError) == true,job.storageRequiredBytes != nil {
                        // Bound the pre-fix regression: cancellation exposes the
                        // erroneous capacity wait without sleeping for a minute.
                        withUnsafeCurrentTask {$0?.cancel()}
                    }
                }
            }
        }
        do {
            let result = try await running.value
            XCTAssertEqual(result.state,.failed)
            XCTAssertEqual(result.stage,"capability verification")
            XCTAssertNil(result.storageRequiredBytes)
            XCTAssertTrue(result.error?.contains(expectedError) == true,result.error ?? "")
            XCTAssertEqual(result.id,saved.id)
            XCTAssertEqual(try result.request.identityData(),try saved.request.identityData())
        } catch {
            XCTFail("Capability rejection must return its failure, not enter a capacity wait: \(error)")
        }
        let persisted: JobRecord = try Persistence.load(checkpoint)
        XCTAssertEqual(persisted.state,.failed)
        XCTAssertEqual(persisted.stage,"capability verification")
        XCTAssertNil(persisted.storageRequiredBytes)
        XCTAssertTrue(persisted.error?.contains(expectedError) == true,persisted.error ?? "")
    }
    func testSupervisedWorkerKeepsCleanupLeaseUntilDrained() async throws {
        let f = try fixture()
        try f.manager.closeAttempt(f.work,jobID:f.job.id)
        let worker = Task {
            try await StorageManager.$processingRoot.withValue(f.root) {
                try await Processes.run("/bin/sleep",["2"])
            }
        }
        try await Task.sleep(nanoseconds:300_000_000)
        XCTAssertThrowsError(try f.manager.clean())
        worker.cancel()
        do {_ = try await worker.value;XCTFail("Expected cancellation")}
        catch {XCTAssertTrue(error is CancellationError)}
        XCTAssertEqual(try f.manager.clean().removedFiles,2)
    }
    final class CapacityBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Int64 = 0
        func set(_ value: Int64) {lock.lock();self.value = value;lock.unlock()}
        func get() -> Int64 {lock.lock();defer {lock.unlock()};return value}
    }
    func testLowDiskPauseRestartAndAutomaticCapacityRecoveryPreserveJobIdentity() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let source = root.appendingPathComponent("source.mp4")
        _ = try await Processes.run("ffmpeg",["-v","error","-f","lavfi","-i","testsrc2=s=320x180:r=30:d=2","-f","lavfi","-i","sine=frequency=440:duration=2","-c:v","libx264","-c:a","aac","-shortest",source.path])
        var request = try Fixtures.request(dir:root,path:source.path)
        request.transcriptPolicy = .modelIndependent
        let runtime = root.appendingPathComponent("runtime")
        let coordinator = try Coordinator(root:runtime)
        let box = CapacityBox()
        do {
            _ = try await Task {
                try await StorageManager.$capacityOverride.withValue({box.get()}) {
                    try await coordinator.run(request) {job in
                        if job.storageRequiredBytes != nil {withUnsafeCurrentTask {$0?.cancel()}}
                    }
                }
            }.value
            XCTFail("Expected pause during capacity wait")
        } catch {XCTAssertTrue(error is CancellationError)}
        let paused = try await coordinator.jobs()
        XCTAssertEqual(paused.count,1);XCTAssertEqual(paused[0].state,.cancelled)
        XCTAssertTrue(paused[0].clips.isEmpty)
        let restarted = try Coordinator(root:runtime)
        // The test changes only an injected reading; production volume is never filled.
        let recovered = try await StorageManager.$capacityOverride.withValue({box.get()}) {
            try await StorageManager.$capacityRetryNanoseconds.withValue(10_000_000) {
                try await restarted.run(request) {job in
                    if job.storageRequiredBytes != nil {box.set(100_000_000_000)}
                }
            }
        }
        XCTAssertEqual(recovered.id,paused[0].id)
        XCTAssertEqual(recovered.state,.qaPassed,recovered.error ?? "")
        XCTAssertEqual(recovered.clips.count,1)
        let canonicalRoot = try StorageManager.canonicalRoot(runtime)
        let output = canonicalRoot.appendingPathComponent("jobs/\(recovered.id)/\(recovered.clips[0].filename)")
        let acceptedHash = try Integrity.sha256(output)
        let again = try await restarted.run(request)
        XCTAssertEqual(again.clips[0].sha256,acceptedHash)
        let jobsAfter = try await restarted.jobs()
        XCTAssertEqual(jobsAfter.count,1)
        XCTAssertNil(again.clips[0].drive)
        XCTAssertTrue(again.registerRows.isEmpty)
    }

}
