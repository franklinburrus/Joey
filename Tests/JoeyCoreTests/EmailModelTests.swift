import XCTest
@testable import JoeyCore
@testable import JoeyInterface

final class EmailModelTests: XCTestCase {
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
        model.task = Task {try? await Task.sleep(nanoseconds:30_000_000_000)}
        let processing = try XCTUnwrap(model.task)
        let queue = Task {await processing.value}
        model.automationTask = queue
        defer {processing.cancel();queue.cancel()}
        model.pauseJoe()
        for _ in 0..<5 {await Task.yield()}
        XCTAssertFalse(model.cancelling)
        XCTAssertFalse(processing.isCancelled)
        XCTAssertFalse(queue.isCancelled)
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
