import XCTest
@testable import JoeyCore

final class EmailIntakeTests: XCTestCase {
    private func root() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        addTeardownBlock {try? FileManager.default.removeItem(at:root)}
        return root
    }
    func testCanonicalLinksRejectPortsAndAmbiguousIdentity() throws {
        XCTAssertEqual(try EmailSource("https://youtu.be/abcdefghijk?t=9").url,"https://www.youtube.com/watch?v=abcdefghijk")
        XCTAssertEqual(try EmailSource("https://youtube.com/live/abcdefghijk?feature=share").id,"youtube:abcdefghijk")
        for value in ["https://youtube.com:444/watch?v=abcdefghijk", "https://youtube.com/watch?v=abcdefghijk&v=zzzzzzzzzzz", "https://x.com/redirect/broadcasts/id", "https://user@youtu.be/abcdefghijk"] {
            XCTAssertThrowsError(try EmailSource(value))
        }
    }
    func testQueueAndCursorCommitTogetherAndDuplicatesReuseFrozenRequest() throws {
        let root = try root(), store = try EmailIntakeStore(root:root)
        var settings = EmailIntakeSettings();settings.account = "parent@icloud.com";settings.allowedSenders = ["sender@example.test"]
        try store.configure(settings)
        try store.activate(EmailScan(uidValidity:7,uidNext:11,frontier:10,messages:[]))
        let first = EmailMessage(uid:11,status:"authorized",reason:"templateToken",links:["https://youtu.be/abcdefghijk", "https://youtube.com/watch?v=abcdefghijk&t=10"])
        try store.ingest(EmailScan(uidValidity:7,uidNext:12,frontier:11,messages:[first]))
        XCTAssertEqual(store.state.work.count,1)
        XCTAssertEqual(store.state.currentBaseline?.frontier,11)
        let key = try XCTUnwrap(store.state.work.first?.id)
        let profile = try Fixtures.profile(dir:root)
        let request = try ProductionIntake.request(source:DiscoveredSource(id:"youtube:abcdefghijk",title:"Original title",url:"https://www.youtube.com/watch?v=abcdefghijk",duration:600),content:.dub,mode:.fullShow,sharedProfile:profile)
        try store.freeze(key,request:request)
        try store.ingest(EmailScan(uidValidity:7,uidNext:13,frontier:12,messages:[EmailMessage(uid:12,status:"authorized",reason:"templateToken",links:first.links)]))
        let reopened = try EmailIntakeStore(root:root)
        XCTAssertEqual(reopened.state.work.count,1)
        XCTAssertEqual(try Persistence.encoder.encode(reopened.state.work.first?.request),try Persistence.encoder.encode(request))
        XCTAssertEqual(reopened.state.receipts.count,2)
        XCTAssertEqual(reopened.state.currentBaseline?.frontier,12)
    }
    func testFailedSaveAndCorruptionDoNotAcknowledgeOrReset() throws {
        let root = try root(), store = try EmailIntakeStore(root:root)
        var settings = EmailIntakeSettings();settings.account = "parent@icloud.com";settings.allowedSenders = ["sender@example.test"]
        try store.configure(settings)
        try store.activate(EmailScan(uidValidity:7,uidNext:11,frontier:10,messages:[]))
        let saved = try Data(contentsOf:store.url)
        try FileManager.default.removeItem(at:store.url)
        try FileManager.default.createDirectory(at:store.url,withIntermediateDirectories:false)
        XCTAssertThrowsError(try store.ingest(EmailScan(uidValidity:7,uidNext:12,frontier:11,messages:[])))
        XCTAssertEqual(store.state.currentBaseline?.frontier,10)
        try FileManager.default.removeItem(at:store.url)
        try Data("corrupt".utf8).write(to:store.url)
        XCTAssertThrowsError(try EmailIntakeStore(root:root))
        XCTAssertEqual(try Data(contentsOf:store.url),Data("corrupt".utf8))
        XCTAssertFalse(saved.isEmpty)
    }
    func testMailboxResetAndAccountSwitchPreserveLedgerWithoutReplaying() throws {
        let store = try EmailIntakeStore(root:root())
        var settings = EmailIntakeSettings();settings.account = "one@icloud.com";settings.allowedSenders = ["sender@example.test"]
        try store.configure(settings);try store.activate(EmailScan(uidValidity:7,uidNext:11,frontier:10,messages:[]))
        XCTAssertThrowsError(try store.ingest(EmailScan(uidValidity:8,uidNext:100,frontier:99,messages:[])))
        XCTAssertEqual(store.state.currentBaseline?.uidValidity,7)
        settings.account = "two@icloud.com";try store.configure(settings)
        XCTAssertNil(store.state.currentBaseline)
        XCTAssertFalse(store.state.enabled)
        settings.account = "one@icloud.com";try store.configure(settings)
        XCTAssertEqual(store.state.currentBaseline?.frontier,10)
    }
    func testUnauthorizedMessagesNeverBecomeWorkAndLimitsDoNotTruncate() throws {
        let store = try EmailIntakeStore(root:root())
        var settings = EmailIntakeSettings();settings.account = "parent@icloud.com";settings.allowedSenders = ["sender@example.test"]
        try store.configure(settings);try store.activate(EmailScan(uidValidity:7,uidNext:1,frontier:0,messages:[]))
        try store.ingest(EmailScan(uidValidity:7,uidNext:2,frontier:1,messages:[EmailMessage(uid:1,status:"pendingAuthorization",reason:"intakeTokenMissingOrInvalid",links:["https://youtu.be/abcdefghijk"])]))
        XCTAssertTrue(store.state.work.isEmpty)
        let links = (0..<11).map {"https://x.com/i/broadcasts/source\($0)"}
        try store.ingest(EmailScan(uidValidity:7,uidNext:3,frontier:2,messages:[EmailMessage(uid:2,status:"authorized",reason:"templateToken",links:links)]))
        XCTAssertTrue(store.state.work.isEmpty)
        XCTAssertEqual(store.state.receipts.last?.reason,"tooManyLinks")
    }
    func testCrossProcessLockPreventsASecondIntakeOwner() throws {
        let store = try EmailIntakeStore(root:root())
        let lock = try store.lock()
        XCTAssertThrowsError(try store.lock())
        withExtendedLifetime(lock) {}
    }
    func testQueueCapacityAndBackoffRetainTheLastAcknowledgedFrontier() throws {
        let store = try EmailIntakeStore(root:root())
        var settings = EmailIntakeSettings();settings.account = "parent@icloud.com";settings.allowedSenders = ["sender@example.test"]
        try store.configure(settings);try store.activate(EmailScan(uidValidity:7,uidNext:1,frontier:0,messages:[]))
        for group in 0..<2 {
            let start = group * 50 + 1
            let messages = (start..<(start+50)).map {EmailMessage(uid:UInt64($0),status:"pendingAuthorization",reason:"intakeTokenMissingOrInvalid",links:["https://youtu.be/abcdefghijk"])}
            try store.ingest(EmailScan(uidValidity:7,uidNext:UInt64(start+50),frontier:UInt64(start+49),messages:messages))
        }
        XCTAssertEqual(store.state.capacity,0)
        try store.ingest(EmailScan(uidValidity:7,uidNext:102,frontier:101,messages:[EmailMessage(uid:101,status:"pendingAuthorization",reason:"intakeTokenMissingOrInvalid",links:["https://youtu.be/abcdefghijk"])]))
        XCTAssertEqual(store.state.currentBaseline?.frontier,100)
        let now = Date(timeIntervalSince1970:1_000)
        for delay in [60.0,120,300,900,900] {
            try store.recordFailure("networkUnavailable",now:now)
            XCTAssertEqual(store.state.nextCheckAt,now.addingTimeInterval(delay))
        }
        try store.recordFailure("authenticationFailed",now:now)
        XCTAssertTrue(store.state.requiresAuthentication)
        XCTAssertFalse(store.state.canDispatch)
    }
    func testSecondAccountCanDispatchTheSameFrozenMediaWork() throws {
        let store = try EmailIntakeStore(root:root())
        var settings = EmailIntakeSettings();settings.account = "one@icloud.com";settings.allowedSenders = ["sender@example.test"]
        let scan = EmailScan(uidValidity:7,uidNext:2,frontier:1,messages:[EmailMessage(uid:1,status:"authorized",reason:"templateToken",links:["https://youtu.be/abcdefghijk"])])
        try store.configure(settings);try store.activate(EmailScan(uidValidity:7,uidNext:1,frontier:0,messages:[]));try store.ingest(scan)
        let firstID = store.state.work.first?.id
        settings.account = "two@icloud.com";try store.configure(settings)
        try store.activate(EmailScan(uidValidity:7,uidNext:1,frontier:0,messages:[]));try store.ingest(scan)
        XCTAssertEqual(store.state.work.count,1)
        XCTAssertEqual(store.state.work.first?.id,firstID)
        XCTAssertEqual(store.state.work.first?.account,"two@icloud.com")
    }
    func testPausedMailboxResetHasARecoverableTypedFailure() throws {
        let store = try EmailIntakeStore(root:root())
        var settings = EmailIntakeSettings();settings.account = "parent@icloud.com";settings.allowedSenders = ["sender@example.test"]
        try store.configure(settings);try store.activate(EmailScan(uidValidity:7,uidNext:11,frontier:10,messages:[]));try store.pause()
        do {try store.activate(EmailScan(uidValidity:8,uidNext:50,frontier:49,messages:[]));XCTFail("Reset accepted")}
        catch {XCTAssertEqual((error as? MailCheckFailure)?.code,"uidValidityChanged")}
    }
    func testPrivateStdinReachesSupervisedChildWithEOFAndNoCaptureLeak() async throws {
        let secret = Data("JOEY_SYNTHETIC_STDIN_SECRET".utf8)
        let script = "import sys,os; value=sys.stdin.buffer.read(); assert len(value)==27; assert not any('JOEY_SYNTHETIC' in x for x in sys.argv+list(os.environ.values())); print('received-eof')"
        let result = try await Processes.run("/usr/bin/python3",["-c",script],input:secret,timeout:5)
        XCTAssertEqual(String(decoding:result.stdout,as:UTF8.self),"received-eof\n")
        XCTAssertFalse(result.stderr.contains("JOEY_SYNTHETIC"))
    }
    func testPrivateStdinEarlyExitAndTimeoutAreBounded() async throws {
        _ = try await Processes.run("/usr/bin/true",[],input:Data(repeating:65,count:16000),timeout:2)
        do {
            _ = try await Processes.run("/bin/sleep",["30"],input:Data(repeating:65,count:16000),timeout:0.2)
            XCTFail("Deadline ignored")
        } catch {XCTAssertTrue(error.localizedDescription.contains("timed out"))}
        let running = Task {try await Processes.run("/bin/sleep",["30"],input:Data(repeating:65,count:16000))}
        try await Task.sleep(nanoseconds:100_000_000);running.cancel()
        do {_ = try await running.value;XCTFail("Private-input cancellation ignored")}
        catch {XCTAssertTrue(error is CancellationError)}
    }
    func testKeychainStoresReadsUpdatesAndDeletesOnlyItsOwnDummyItem() throws {
        let account = "joey-fixture-\(UUID().uuidString)@icloud.com"
        defer {try? MailCredentials.delete(account:account)}
        let token = try MailCredentials.generateToken()
        let another = try MailCredentials.generateToken()
        XCTAssertEqual(token.count,43);XCTAssertNotEqual(token,another)
        try MailCredentials.save(MailSecret(password:"synthetic-app-password",token:token),account:account)
        XCTAssertEqual(try MailCredentials.read(account:account)?.token,token)
        try MailCredentials.save(MailSecret(password:"updated-synthetic-password",token:another),account:account)
        XCTAssertEqual(try MailCredentials.read(account:account)?.password,"updated-synthetic-password")
        try MailCredentials.delete(account:account)
        XCTAssertNil(try MailCredentials.read(account:account))
    }
}
