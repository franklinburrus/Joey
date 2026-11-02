#if SWIFT_PACKAGE
import JoeyCore
#endif
import Foundation
import AppKit
import Combine
import Network

@MainActor final class EmailIntakeModel: ObservableObject {
    @Published private(set) var state = EmailIntakeState()
    @Published private(set) var checking = false
    @Published private(set) var connectionStatus: String?
    @Published private(set) var error: String?
    @Published private(set) var available = false
    let root: URL
    private(set) var store: EmailIntakeStore?
    private var lease: ProcessingLock?
    private var checkTask: Task<Void,Never>?
    private var monitorTask: Task<Void,Never>?
    private var wakeObserver: AnyCancellable?
    private var networkMonitor: NWPathMonitor?
    private var generation = 0
    private weak var owner: JobModel?
    var dispatching = false
    var lookup: (String) async throws -> DiscoveredSource = {try await SourceDiscovery.lookup($0)}
    var checkMailbox: (String, EmailIntakeSettings, MailSecret, EmailBaseline?, Int, URL) async throws -> EmailScan = {
        try await ICloudMail.check(action:$0,settings:$1,secret:$2,baseline:$3,capacity:$4,root:$5)
    }

    init(root: URL) {
        self.root = root
        do {
            let initial = try EmailIntakeStore(root:root)
            lease = try initial.lock()
            let current = try EmailIntakeStore(root:root)
            store = current;state = current.state;available = true
        } catch {self.error = "Email intake unavailable: " + error.localizedDescription}
    }
    deinit {checkTask?.cancel();monitorTask?.cancel();networkMonitor?.cancel()}

    func attach(to owner: JobModel) {
        guard monitorTask == nil, available else {return}
        self.owner = owner
        wakeObserver = NSWorkspace.shared.notificationCenter.publisher(for:NSWorkspace.didWakeNotification)
            .receive(on:DispatchQueue.main).sink {[weak self] _ in self?.wake()}
        let network = NWPathMonitor()
        network.pathUpdateHandler = {[weak self] path in
            guard path.status == .satisfied, let model = self else {return}
            Task {@MainActor in model.wake()}
        }
        network.start(queue:DispatchQueue(label:"Joey.email-connectivity"));networkMonitor = network
        monitorTask = Task {[weak self] in
            while !Task.isCancelled {
                guard let self else {return}
                self.tick()
                do {try await Task.sleep(nanoseconds:5_000_000_000)} catch {return}
            }
        }
    }
    func tick(now: Date = Date()) {
        guard available else {return}
        if state.enabled && !state.requiresAuthentication && !state.requiresResynchronization && (state.nextCheckAt ?? .distantPast) <= now {
            checkNow()
        }
        owner?.resumeJoeQueue(includeJoe:false)
    }
    func wake() {
        guard available, state.enabled, !state.requiresAuthentication, !state.requiresResynchronization else {return}
        checkNow();owner?.resumeJoeQueue(includeJoe:false)
    }
    func publish() {if let store {state = store.state}}
    func failedPersistence(_ failure: Error) {
        available = false;error = "Email intake stopped; saved state preserved. " + failure.localizedDescription
        checkTask?.cancel()
    }
    func saveSetup(_ settings: EmailIntakeSettings, password: String) {
        guard available, !checking, let store else {return}
        generation += 1
        do {
            let validated = try settings.validated()
            let prior = try MailCredentials.read(account:validated.account)
            let supplied = password.trimmingCharacters(in:.whitespacesAndNewlines)
            guard !supplied.isEmpty || prior != nil else {throw MailCheckFailure("credentialUnavailable")}
            let secret = MailSecret(password:supplied.isEmpty ? prior!.password:supplied,
                                    token:try prior?.token ?? MailCredentials.generateToken())
            // Pause before replacing credentials or workflow settings. A queued
            // receipt never acquires new defaults implicitly.
            try store.pause();publish()
            try MailCredentials.save(secret,account:validated.account)
            try store.configure(validated);publish()
            error = nil;connectionStatus = "Saved in this build's Keychain. Test Connection, then Enable."
        } catch {self.error = error.localizedDescription}
    }
    func template() throws -> String {
        guard let secret = try MailCredentials.read(account:state.settings.account) else {throw MailCheckFailure("credentialUnavailable")}
        return "To: \(EmailIntakeSettings.alias)\n\nPaste original HTTPS YouTube/X links here.\n\nJoey-Token: \(secret.token)"
    }
    func rotateToken() {
        guard available, !checking, let store else {return}
        generation += 1
        do {
            try store.pause();publish()
            guard var secret = try MailCredentials.read(account:state.settings.account) else {throw MailCheckFailure("credentialUnavailable")}
            secret.token = try MailCredentials.generateToken()
            try MailCredentials.save(secret,account:state.settings.account)
            connectionStatus = "Token replaced. Update your saved email template, then enable intake. Already accepted jobs are retained."
        } catch {self.error = error.localizedDescription}
    }
    func testConnection() {check(action:"test")}
    func enable(rebaseline: Bool = false) {check(action:rebaseline ? "rebaseline":"enable")}
    func checkNow() {
        guard state.enabled, !state.requiresResynchronization else {return}
        check(action:"scan")
    }
    private func check(action: String) {
        guard available, !checking, let store else {return}
        checking = true;error = nil
        let revision = generation, settings = state.settings, baseline = state.currentBaseline, capacity = state.capacity
        checkTask = Task {
            defer {checking = false;checkTask = nil}
            do {
                _ = try settings.validated()
                guard let secret = try MailCredentials.read(account:settings.account) else {throw MailCheckFailure("credentialUnavailable")}
                let scan = try await checkMailbox(action == "scan" ? "scan":(action == "test" ? "test":"baseline"),
                    settings,secret,baseline,capacity,root)
                try Task.checkCancellation()
                guard revision == generation else {return}
                do {
                    if action == "scan" {try store.ingest(scan)}
                    else if action != "test" {try store.activate(scan,replaceBaseline:action == "rebaseline")}
                    else {try store.connected()}
                    publish()
                } catch let failure as MailCheckFailure {
                    try store.recordFailure(failure.code);publish();self.error = failure.localizedDescription;return
                } catch {failedPersistence(error);return}
                connectionStatus = action == "test" ? "Connected to iCloud INBOX read-only. Alias delivery has not been tested." :
                    (action == "scan" ? "Mailbox check saved. Intake receipt is separate from media completion." : "Enabled. Existing INBOX mail excluded on first activation; saved queues retained.")
                owner?.resumeJoeQueue(includeJoe:false)
            } catch is CancellationError {
                connectionStatus = "Mail check stopped. Cursor and pending work retained."
            } catch {
                guard revision == generation else {return}
                self.error = error.localizedDescription
                let code = (error as? MailCheckFailure)?.code ?? "setupUnavailable"
                do {try store.recordFailure(code);publish()} catch {failedPersistence(error)}
            }
        }
    }
    func pause() {
        generation += 1;checkTask?.cancel()
        guard let store else {return}
        do {try store.pause();publish();connectionStatus = "Paused. Accepted media continues; receipts and queued work are retained."}
        catch {failedPersistence(error)}
    }
    func disconnect() {
        pause()
        guard available else {return}
        do {
            try MailCredentials.delete(account:state.settings.account)
            connectionStatus = "Disconnected; Joey's credential removed. Revoke the app-specific password at account.apple.com to invalidate it remotely. Receipts and jobs remain."
        } catch {self.error = error.localizedDescription}
    }
    func dismiss(_ id: String) {
        do {try store?.dismiss(id);publish()} catch {failedPersistence(error)}
    }
    func process(_ id: String, workflow: EmailWorkflow) {
        guard available, let store else {return}
        do {
            try store.requestProcessing(id,workflow:workflow);publish();error = nil
            owner?.resumeJoeQueue(includeJoe:false)
        }
        catch let failure as JoeyError {error = failure.localizedDescription}
        catch {failedPersistence(error)}
    }
}
