import XCTest
@testable import JoeyCore
@testable import JoeyInterface

final class EmailModelTests: XCTestCase {
    @MainActor func testAutomaticStartupRequiresReadableEmailOwnership() async throws {
        for condition in ["readable", "corrupt", "leased"] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
            defer {try? FileManager.default.removeItem(at:root)}
            let store = try EmailIntakeStore(root:root)
            var settings = EmailIntakeSettings();settings.account = "parent@icloud.com";settings.allowedSenders = ["sender@example.test"]
            try store.configure(settings)
            try store.activate(EmailScan(uidValidity:7,uidNext:1,frontier:0,messages:[]))
            try store.ingest(EmailScan(uidValidity:7,uidNext:2,frontier:1,messages:[EmailMessage(uid:1,status:"authorized",reason:"templateToken",links:["https://youtu.be/abcdefghijk"])]))
            let work = try XCTUnwrap(store.state.work.first)
            var request = try Fixtures.request(dir:root,path:root.appendingPathComponent("protected-source.mp4").path)
            request.sourceID = work.source.id
            request.profile.x!.checkedAt = Date().addingTimeInterval(-7200)
            request.profile.instagram!.checkedAt = Date().addingTimeInterval(-7200)
            request.profile.x!.validUntil = Date().addingTimeInterval(-3600)
            request.profile.instagram!.validUntil = Date().addingTimeInterval(-3600)
            try store.freeze(work.id,request:request)
            try store.updateWork(work.id,status:.running)
            try store.pause()
            var job = JobRecord(id:try request.stableID(),request:request)
            job.state = .processing;job.stage = "source"
            let checkpoint = root.appendingPathComponent("jobs/\(job.id)/job.json")
            try Persistence.save(job,to:checkpoint)
            let media = root.appendingPathComponent("protected-source.mp4")
            try Data("accepted media preservation canary".utf8).write(to:media)
            let checkpointBefore = try Data(contentsOf:checkpoint), mediaBefore = try Data(contentsOf:media)
            let validLedger = try Data(contentsOf:store.url)
            if condition == "corrupt" {try Data("{corrupt ledger".utf8).write(to:store.url)}
            let ledgerBefore = try Data(contentsOf:store.url)
            var lease = condition == "leased" ? try store.lock() : nil
            var unrelated = job
            unrelated.request.sourceID = "unrelated-manual-source"
            unrelated.id = try unrelated.request.stableID()
            let unrelatedCheckpoint = root.appendingPathComponent("jobs/\(unrelated.id)/job.json")
            if condition == "readable" {try Persistence.save(unrelated,to:unrelatedCheckpoint)}
            let model = JobModel(root:root,startsAutomatically:true,recentJoeEpisodes:{[]})
            await model.startupTask?.value
            withExtendedLifetime(lease) {}
            XCTAssertEqual(try Data(contentsOf:checkpoint),checkpointBefore,condition)
            XCTAssertEqual(try Data(contentsOf:media),mediaBefore,condition)
            if condition != "readable" {
                XCTAssertFalse(model.email.available,condition)
                XCTAssertEqual(try Data(contentsOf:store.url),ledgerBefore,condition)
            }
            XCTAssertNil(model.task,condition)
            XCTAssertNil(model.email.state.nextRequestedWork(),condition)
            if condition == "readable" {
                let recovered: JobRecord = try Persistence.load(unrelatedCheckpoint)
                XCTAssertEqual(recovered.state,.failed)
                XCTAssertEqual(recovered.stage,"capability verification")
            } else {
                // Restore only this isolated damaged/leased ownership fixture.
                // A normal restart then holds email until explicit Process.
                lease = nil
                try validLedger.write(to:store.url)
                let recovered = JobModel(root:root,startsAutomatically:true,recentJoeEpisodes:{[]})
                await recovered.startupTask?.value
                XCTAssertTrue(recovered.email.available)
                XCTAssertEqual(try Data(contentsOf:checkpoint),checkpointBefore)
                recovered.email.lookup = {_ in XCTFail("Recovery must reuse the frozen request");throw CancellationError()}
                recovered.email.process(work.id,workflow:work.workflow)
                await recovered.automationTask?.value
                XCTAssertEqual(recovered.email.state.work.first?.jobID,job.id)
                XCTAssertEqual(try recovered.email.state.work.first?.request?.identityData(),try request.identityData())
                XCTAssertEqual(recovered.email.state.work.first?.status,.retryable)
                XCTAssertEqual(recovered.jobs.map(\.id),[job.id])
                XCTAssertEqual(try Data(contentsOf:media),mediaBefore)
                // Explicit manual Resume remains supported even while the first
                // model's mailbox ownership view is unavailable.
                XCTAssertEqual(model.start(request),.accepted)
                await model.task?.value
                XCTAssertEqual(model.jobs.map(\.id),[job.id])
            }
        }
    }

    @MainActor func testProcessRefreshesCheckpointCreatedAfterUIInventory() async throws {
        let model = try queuedModel(), store = try XCTUnwrap(model.email.store)
        await model.refresh()
        XCTAssertTrue(model.jobs.isEmpty)
        let work = try XCTUnwrap(store.state.work.first)
        let original = try ProductionIntake.request(source:DiscoveredSource(id:work.source.id,title:"Original title",
            url:work.source.url,duration:10,episodeDate:"2026-10-01"),content:.dub,mode:.fullShow,sharedProfile:model.configuration?.profile)
        var job = JobRecord(id:try original.stableID(),request:original)
        job.state = .failed
        job.source = SourceRecord(id:original.sourceID,owner:.dub,title:original.title,path:model.root.appendingPathComponent("missing.mp4").path,
            bytes:1,sha256:String(repeating:"a",count:64),duration:10,width:320,height:180,fps:30,hasAudio:false,kind:.nativeVideo,
            streams:[],authorizationBasis:"Synthetic fixture",classificationEvidence:"Synthetic fixture")
        try Persistence.save(job,to:model.root.appendingPathComponent("jobs/\(job.id)/job.json"))
        var calls = 0
        model.email.lookup = {_ in
            calls += 1
            return DiscoveredSource(id:work.source.id,title:"Changed title",url:work.source.url,duration:11,episodeDate:"2026-11-06")
        }
        // Both paths fail before acquisition/provider access. Identity adoption
        // still occurs before capability renewal and is independently observable.
        var settings = try Configuration.load(root:model.root)
        settings.profile = original.profile
        settings.profile?.x?.account = "different-fixture-account"
        settings.rcloneRemote = "synthetic-unavailable-remote"
        try Persistence.save(settings,to:model.root.appendingPathComponent("settings.json"))
        model.email.process(work.id,workflow:work.workflow)
        await model.runEmailItem()
        XCTAssertEqual(calls,0)
        XCTAssertEqual(model.email.state.work.first?.jobID,job.id)
        XCTAssertEqual(try model.email.state.work.first?.request?.identityData(),try original.identityData())
        XCTAssertEqual(model.jobs.map(\.id),[job.id])
    }

    @MainActor func testEmailAdmissionReconcilesCheckpointCreatedDuringDiscoveryBeforeFreezing() async throws {
        let model = try queuedModel(), store = try XCTUnwrap(model.email.store)
        let work = try XCTUnwrap(store.state.work.first)
        let original = try ProductionIntake.request(source:DiscoveredSource(id:work.source.id,title:"Original locked admission",
            url:work.source.url,duration:10,episodeDate:"2026-10-01"),content:.dub,mode:.fullShow,sharedProfile:model.configuration?.profile)
        var settings = try Configuration.load(root:model.root)
        settings.profile = original.profile;settings.profile?.x?.account = "different-fixture-account"
        try Persistence.save(settings,to:model.root.appendingPathComponent("settings.json"))
        var calls = 0
        model.email.lookup = {_ in
            calls += 1
            // A separate coordinator wins admission while discovery is suspended.
            // Its synthetic account mismatch stops before acquisition or providers.
            let other = try Coordinator(root:model.root)
            _ = try await other.run(original)
            return DiscoveredSource(id:work.source.id,title:"Provider title changed",url:work.source.url,duration:11,episodeDate:"2026-11-06")
        }
        model.email.process(work.id,workflow:work.workflow)
        await model.runEmailItem()
        XCTAssertEqual(calls,1)
        XCTAssertEqual(model.email.state.work.first?.jobID,try original.stableID())
        XCTAssertEqual(try model.email.state.work.first?.request?.identityData(),try original.identityData())
        XCTAssertEqual(model.jobs.map(\.id),[try original.stableID()])
        let first = try XCTUnwrap(model.email.state.work.first?.request)
        model.email.process(work.id,workflow:work.workflow)
        await model.runEmailItem()
        XCTAssertEqual(calls,1)
        XCTAssertEqual(try model.email.state.work.first?.request?.identityData(),try first.identityData())
        XCTAssertEqual(model.jobs.count,1)
    }

    @MainActor func testLinkAdmissionPreservesDistinctOwnerWorkflowAccountAndSelections() throws {
        let model = try queuedModel()
        let work = try XCTUnwrap(model.email.state.work.first)
        let original = try ProductionIntake.request(source:DiscoveredSource(id:work.source.id,title:"Original",
            url:work.source.url,duration:10),content:.dub,mode:.fullShow,sharedProfile:model.configuration?.profile)
        var proposed = original;proposed.title = "Changed metadata";proposed.expectedDuration = 11
        XCTAssertEqual(try ProductionIntake.existingRequest(matching:proposed,requests:[original]),original)
        var owner = original;owner.owner = .taxstone
        var workflow = original;workflow.mode = .highlights
        var account = original;account.profile.x!.account = "another-account"
        var selected = original;selected.mode = .highlights;selected.fixedIntervals = [Interval(0,5)]
        var preferred = original;preferred.preferredDuration = 480
        var archive = original;archive.archiveRootID = "explicit-archive-root"
        var artwork = original
        artwork.artwork = Artwork(owner:.dub,driveID:"explicit-artwork",file:try XCTUnwrap(original.profile.x?.accountEvidence))
        var sourceHash = original;sourceHash.expectedSourceSHA256 = String(repeating:"a",count:64)
        var local = original;local.localPath = "/explicit/source.mp4"
        for distinct in [owner,workflow,account,selected,preferred,archive,artwork,sourceHash,local] {
            XCTAssertNil(try ProductionIntake.existingRequest(matching:proposed,requests:[distinct]))
        }
        for explicit in [artwork,sourceHash,local] {
            XCTAssertNil(try ProductionIntake.existingRequest(matching:explicit,requests:[original]))
            XCTAssertNil(try ProductionIntake.existingRequest(for:work.source.url,content:.dub,mode:.fullShow,
                requests:[explicit],sharedProfile:original.profile))
        }
        XCTAssertNil(try ProductionIntake.existingRequest(matching:selected,requests:[original]))
    }

    @MainActor func testFreshManualDiscoveryAlsoReconcilesConcurrentEmailCheckpoint() async throws {
        let model = try queuedModel()
        let work = try XCTUnwrap(model.email.state.work.first)
        let original = try ProductionIntake.request(source:DiscoveredSource(id:work.source.id,title:"Email accepted first",
            url:work.source.url,duration:10),content:.dub,mode:.fullShow,sharedProfile:model.configuration?.profile)
        var settings = try Configuration.load(root:model.root)
        settings.profile = original.profile;settings.profile?.x?.account = "different-fixture-account"
        try Persistence.save(settings,to:model.root.appendingPathComponent("settings.json"))
        model.startLink(work.source.url,content:.dub,mode:.fullShow,archive:"",archiveRoot:"",transcript:"",lookup:{_ in
            let other = try Coordinator(root:model.root)
            _ = try await other.run(original)
            return DiscoveredSource(id:work.source.id,title:"Provider title changed",url:work.source.url,duration:11)
        })
        for _ in 0..<500 where model.preparingSource {try await Task.sleep(nanoseconds:10_000_000)}
        XCTAssertFalse(model.preparingSource)
        await model.task?.value
        XCTAssertEqual(model.jobs.map(\.id),[try original.stableID()])
        XCTAssertEqual(try model.jobs.first?.request.identityData(),try original.identityData())
    }
    @MainActor private func queuedModel() throws -> JobModel {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        addTeardownBlock {try? FileManager.default.removeItem(at:root)}
        let model = JobModel(root:root,startsAutomatically:false)
        model.configuration?.profile = try Fixtures.profile(dir:root)
        let store = try XCTUnwrap(model.email.store)
        var settings = EmailIntakeSettings();settings.account = "parent@icloud.com";settings.allowedSenders = ["sender@example.test"]
        try store.configure(settings);try store.activate(EmailScan(uidValidity:7,uidNext:1,frontier:0,messages:[]))
        try store.ingest(EmailScan(uidValidity:7,uidNext:2,frontier:1,messages:[EmailMessage(uid:1,status:"authorized",reason:"templateToken",links:["https://youtu.be/abcdefghijk"])]))
        model.email.publish()
        return model
    }
    @MainActor func testAllPendingReceiptsRemainDismissibleAfterRecentHistoryFills() throws {
        let model = try queuedModel(), store = try XCTUnwrap(model.email.store)
        for start in [2,52] {
            let messages = (start..<(start+50)).map {
                EmailMessage(uid:UInt64($0),status:"pendingAuthorization",reason:"intakeTokenMissingOrInvalid",links:["https://youtu.be/abcdefghijk"])
            }
            try store.ingest(EmailScan(uidValidity:7,uidNext:UInt64(start+50),frontier:UInt64(start+49),messages:messages))
        }
        // The authorized link occupies one slot, leaving 99 pending receipts.
        model.email.publish()
        XCTAssertEqual(model.email.state.capacity,0)
        XCTAssertEqual(model.email.displayedReceipts.filter {$0.status == "pendingAuthorization"}.count,99)
        let newest = Array(model.email.state.receipts.reversed().filter {$0.status == "pendingAuthorization"}.prefix(50))
        for receipt in newest {model.email.dismiss(receipt.id)}
        XCTAssertEqual(model.email.displayedReceipts.filter {$0.status == "pendingAuthorization"}.count,49)
        XCTAssertLessThanOrEqual(model.email.displayedReceipts.filter {$0.status != "pendingAuthorization"}.count,50)
        for receipt in model.email.displayedReceipts where receipt.status == "pendingAuthorization" {
            model.email.dismiss(receipt.id)
        }
        let reopened = try EmailIntakeStore(root:model.root)
        XCTAssertEqual(reopened.state.capacity,99)
        XCTAssertFalse(reopened.state.receipts.contains {$0.status == "pendingAuthorization"})
        XCTAssertEqual(reopened.state.work.count,1)
        XCTAssertNil(reopened.state.nextRequestedWork())
    }

    @MainActor func testAdoptedExpiredRequestReachesCoordinatorRenewalWithoutRediscovery() async throws {
        let model = try queuedModel(), store = try XCTUnwrap(model.email.store)
        let work = try XCTUnwrap(store.state.work.first)
        var request = try ProductionIntake.request(
            source:DiscoveredSource(id:work.source.id,title:"Synthetic adopted source",url:work.source.url,duration:10),
            content:.dub,mode:.fullShow,sharedProfile:model.configuration?.profile)
        let current = request.profile
        request.profile.x!.checkedAt = Date().addingTimeInterval(-7200)
        request.profile.instagram!.checkedAt = Date().addingTimeInterval(-7200)
        request.profile.x!.validUntil = Date().addingTimeInterval(-3600)
        request.profile.instagram!.validUntil = Date().addingTimeInterval(-3600)
        XCTAssertThrowsError(try request.validate())
        try request.validate(requireCurrentCapability:false)
        var prior = JobRecord(id:try request.stableID(),request:request)
        prior.state = .failed
        prior.source = SourceRecord(id:request.sourceID,owner:request.owner,title:request.title,
            path:model.root.appendingPathComponent("missing-synthetic-source.mp4").path,bytes:1,
            sha256:String(repeating:"a",count:64),duration:10,width:720,height:1280,fps:30,hasAudio:false,
            kind:.nativeVideo,streams:[],authorizationBasis:"Synthetic regression only",classificationEvidence:"Synthetic fixture")
        let checkpoint = model.root.appendingPathComponent("jobs/\(prior.id)/job.json")
        try Persistence.save(prior,to:checkpoint)
        model.jobs = [prior]
        var config = try Configuration.load(root:model.root)
        config.profile = current
        try Persistence.save(config,to:model.root.appendingPathComponent("settings.json"))
        model.email.lookup = {_ in XCTFail("Adopted request must not be rediscovered");throw CancellationError()}
        model.email.process(work.id,workflow:work.workflow)
        await model.runEmailItem()
        XCTAssertEqual(model.email.state.work.first?.jobID,prior.id)
        XCTAssertEqual(try model.email.state.work.first?.request?.identityData(),try request.identityData())
        let saved: JobRecord = try Persistence.load(checkpoint)
        XCTAssertEqual(try XCTUnwrap(saved.request.profile.x?.validUntil).timeIntervalSince1970,try XCTUnwrap(current.x?.validUntil).timeIntervalSince1970,accuracy:1)
        XCTAssertEqual(try XCTUnwrap(saved.request.profile.instagram?.validUntil).timeIntervalSince1970,try XCTUnwrap(current.instagram?.validUntil).timeIntervalSince1970,accuracy:1)
        XCTAssertEqual(saved.stage,"source") // renewed, then failed on missing local fixture
        XCTAssertEqual(model.email.state.work.first?.status,.retryable)
        XCTAssertEqual(model.jobs.count,1)
    }

    @MainActor func testBusyOwnersReturnDeferredAndLeaveDurableEmailQueued() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let model = JobModel(root:root,startsAutomatically:false)
        let request = try Fixtures.request(dir:root,path:"synthetic-local-source")
        for owner in ["manual", "library", "cancellation"] {
            model.busy = owner == "manual";model.libraryBusy = owner == "library"
            if owner == "cancellation" {model.cancel()}
            XCTAssertEqual(model.start(request),.deferred)
            XCTAssertNil(model.task)
        }
    }
    @MainActor func testNewEmailAndPeriodicTurnsNeverDiscoverBeforeProcess() async throws {
        let model = try queuedModel()
        var calls = 0
        model.email.lookup = {_ in calls += 1;throw JoeyError.dependency("Unexpected automatic discovery")}
        model.email.tick(now:.distantPast)
        await model.runEmailItem()
        await model.runEmailItem(interleaved:true,now:.distantFuture)
        XCTAssertEqual(calls,0)
        XCTAssertNil(model.task)
        XCTAssertTrue(model.jobs.isEmpty)
        XCTAssertNil(model.email.state.work.first?.request)
        XCTAssertEqual(model.email.state.work.first?.status,.queued)
        let reopened = try EmailIntakeStore(root:model.root)
        XCTAssertEqual(reopened.state.work.count,1)
        XCTAssertEqual(reopened.state.currentBaseline?.frontier,1)
    }
    @MainActor func testPauseDoesNotCancelAcceptedMediaAndStopsMailCollection() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let model = JobModel(root:root,startsAutomatically:false)
        let task = Task {try? await Task.sleep(nanoseconds:30_000_000_000)}
        defer {task.cancel()}
        model.task = Task {await task.value}
        model.email.pause()
        XCTAssertFalse(task.isCancelled)
        XCTAssertFalse(model.email.state.enabled)
    }
    @MainActor func testBusyQueueSurvivesAndDiscoveryRunsAfterOwnerReleases() async throws {
        let model = try queuedModel()
        let work = try XCTUnwrap(model.email.state.work.first)
        model.email.process(work.id,workflow:work.workflow)
        var calls = 0
        model.email.lookup = {_ in calls += 1;throw JoeyError.dependency("Synthetic source is unavailable")}
        for owner in ["manual","library"] {
            model.busy = owner == "manual";model.libraryBusy = owner == "library"
            await model.runEmailItem()
            XCTAssertEqual(calls,0);XCTAssertEqual(model.email.state.work.first?.status,.queued)
        }
        model.busy = false;model.libraryBusy = false
        await model.runEmailItem()
        XCTAssertEqual(calls,1);XCTAssertEqual(model.email.state.work.first?.status,.retryable)
        let saved = try EmailIntakeStore(root:model.root)
        XCTAssertEqual(saved.state.currentBaseline?.frontier,1)
        XCTAssertEqual(saved.state.work.count,1)
    }
    @MainActor func testExplicitProcessWorksWhileMailIsPausedAndFailureDoesNotRetry() async throws {
        let model = try queuedModel(), store = try XCTUnwrap(model.email.store)
        let work = try XCTUnwrap(store.state.work.first)
        model.email.pause()
        var workflow = EmailWorkflow();workflow.content = .taxstone;workflow.mode = .highlights
        model.email.process(work.id,workflow:workflow)
        var calls = 0
        model.email.lookup = {_ in calls += 1;throw JoeyError.dependency("Synthetic discovery failure")}
        await model.runEmailItem()
        XCTAssertEqual(calls,1)
        XCTAssertEqual(model.email.state.work.first?.workflow,workflow)
        XCTAssertEqual(model.email.state.work.first?.status,.retryable)
        XCTAssertNil(model.email.state.nextRequestedWork(now:.distantFuture))
        await model.runEmailItem(now:.distantFuture)
        XCTAssertEqual(calls,1)
        XCTAssertFalse(model.email.state.enabled)
        model.email.process(work.id,workflow:workflow)
        await model.runEmailItem()
        XCTAssertEqual(calls,2)
    }
    @MainActor func testFrozenRequestEntersRealCoordinatorWithoutRediscoveryAfterCrash() async throws {
        let model = try queuedModel(), store = try XCTUnwrap(model.email.store)
        let work = try XCTUnwrap(store.state.work.first)
        // Use the real coordinator, but fail at local source inspection before
        // any provider access. The request/checkpoint still proves handoff.
        let request = try Fixtures.request(dir:model.root,path:model.root.appendingPathComponent("missing-synthetic-source.mp4").path)
        var frozen = request;frozen.sourceID = work.source.id
        try store.freeze(work.id,request:frozen)
        try store.updateWork(work.id,status:.running) // crash before dispatch
        model.email.publish()
        model.email.lookup = {_ in XCTFail("Frozen request must not be rediscovered");throw CancellationError()}
        await model.runEmailItem()
        XCTAssertTrue(model.jobs.isEmpty) // an interrupted legacy item waits for Process
        model.email.process(work.id,workflow:work.workflow)
        await model.runEmailItem()
        let jobID = try XCTUnwrap(model.email.state.work.first?.jobID)
        let checkpoint = model.root.appendingPathComponent("jobs/\(jobID)/job.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath:checkpoint.path))
        XCTAssertEqual(model.jobs.count,1)
        XCTAssertEqual(model.email.state.work.first?.status,.retryable)
        let first: JobRecord = try Persistence.load(checkpoint)
        try store.updateWork(work.id,status:.running) // crash after dispatch
        try store.reconcile(model.jobs);model.email.publish()
        model.email.process(work.id,workflow:work.workflow)
        await model.runEmailItem(now:Date().addingTimeInterval(1000))
        XCTAssertEqual(model.jobs.map(\.id),[first.id])
        XCTAssertEqual(model.email.state.work.first?.jobID,first.id)
    }
    @MainActor func testCancelledDiscoveryWaitsForExplicitRetry() async throws {
        let model = try queuedModel()
        let work = try XCTUnwrap(model.email.state.work.first)
        model.email.process(work.id,workflow:work.workflow)
        var calls = 0
        model.email.lookup = {_ in
            calls += 1
            let interrupted = try EmailIntakeStore(root:model.root)
            XCTAssertNil(interrupted.state.work.first?.processingRequested)
            try interrupted.reconcile([])
            XCTAssertEqual(interrupted.state.work.first?.status,.queued)
            XCTAssertNil(interrupted.state.nextRequestedWork())
            throw CancellationError()
        }
        await model.runEmailItem()
        await model.runEmailItem(now:.distantFuture)
        XCTAssertEqual(calls,1)
        XCTAssertNil(model.email.state.nextRequestedWork(now:.distantFuture))
        XCTAssertNil(model.email.state.work.first?.request)
    }
    @MainActor func testExplicitRetryOfCancelledJobSurvivesReconciliation() async throws {
        let model = try queuedModel(), store = try XCTUnwrap(model.email.store)
        let work = try XCTUnwrap(store.state.work.first)
        var request = try Fixtures.request(dir:model.root,path:model.root.appendingPathComponent("missing-synthetic.mp4").path)
        request.sourceID = work.source.id
        try store.freeze(work.id,request:request)
        let id = try request.stableID()
        var job = JobRecord(id:id,request:request);job.state = .cancelled
        try Persistence.save(job,to:model.root.appendingPathComponent("jobs/\(id)/job.json"))
        model.jobs = [job]
        try store.updateWork(work.id,status:.cancelled);model.email.publish()
        model.email.process(work.id,workflow:work.workflow)
        await model.runEmailItem()
        let saved: JobRecord = try Persistence.load(model.root.appendingPathComponent("jobs/\(id)/job.json"))
        XCTAssertNotEqual(saved.state,.cancelled)
    }
    @MainActor func testPausingJoeDoesNotWaitForUnrelatedEmailTurn() async throws {
        let model = try queuedModel()
        model.email.dispatching = true
        model.automationRunning = true // Joe remains active around an interleaved email turn.
        model.task = Task {try? await Task.sleep(nanoseconds:30_000_000_000)}
        let processing = try XCTUnwrap(model.task)
        let queue = Task {await processing.value}
        model.automationTask = queue
        defer {processing.cancel();queue.cancel()}
        model.pauseJoe()
        XCTAssertFalse(model.cancelling) // Discovery must not observe another workflow's cancellation.
        for _ in 0..<5 {await Task.yield()}
        XCTAssertFalse(model.cancelling)
        XCTAssertFalse(processing.isCancelled)
        XCTAssertFalse(queue.isCancelled)
    }
    @MainActor func testCancelDuringInterleavedEmailPausesJoeAndLibraryAndCancelsProcessing() async throws {
        for libraryBusy in [false,true] {
            let model = try queuedModel()
            model.email.dispatching = true
            model.automationRunning = true
            model.joeAutomation.enabled = true
            model.libraryBusy = libraryBusy
            let processing = Task<Void,Never> {try? await Task.sleep(nanoseconds:30_000_000_000)}
            let queue = Task {await processing.value}
            model.task = processing;model.automationTask = queue
            if libraryBusy {
                model.libraryTask = Task {await processing.value}
            }
            model.cancel()
            XCTAssertTrue(processing.isCancelled)
            XCTAssertFalse(model.joeAutomation.enabled)
            await processing.value
            queue.cancel()
            for _ in 0..<5 {await Task.yield()}
        }
    }

    @MainActor func testWakeDoesNotOverlapChecksOrRetryAuthenticationAndExplicitSuccessRecovers() async throws {
        let model = try queuedModel(), store = try XCTUnwrap(model.email.store)
        var settings = store.state.settings
        settings.account = "joey-fixture-\(UUID().uuidString.lowercased())@icloud.com"
        try store.configure(settings);try store.activate(EmailScan(uidValidity:7,uidNext:1,frontier:0,messages:[]));model.email.publish()
        try MailCredentials.save(MailSecret(password:"dummy-app-password",token:MailCredentials.generateToken()),account:settings.account)
        defer {try? MailCredentials.delete(account:settings.account)}
        var calls = 0
        model.email.checkMailbox = {_,_,_,_,_,_ in
            calls += 1
            try await Task.sleep(nanoseconds:30_000_000)
            if calls == 1 {throw MailCheckFailure("authenticationFailed")}
            return EmailScan(uidValidity:7,uidNext:1,frontier:0,messages:[])
        }
        model.email.wake();model.email.wake()
        for _ in 0..<100 where model.email.checking {try await Task.sleep(nanoseconds:10_000_000)}
        XCTAssertEqual(calls,1);XCTAssertTrue(model.email.state.requiresAuthentication)
        model.email.wake();await Task.yield();XCTAssertEqual(calls,1)
        model.email.checkNow()
        for _ in 0..<100 where model.email.checking {try await Task.sleep(nanoseconds:10_000_000)}
        XCTAssertEqual(calls,2);XCTAssertFalse(model.email.state.requiresAuthentication)
        XCTAssertNotNil(model.email.state.lastCheckedAt)
    }
}
