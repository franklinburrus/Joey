#if SWIFT_PACKAGE
import JoeyCore
#endif
import SwiftUI
import AppKit
import Combine

enum JobAcceptance: Equatable {case accepted, deferred, unavailable}

@MainActor final class JobModel: ObservableObject {
    @Published var jobs: [JobRecord] = []
    @Published var selected: String?
    @Published var busy = false
    @Published private(set) var cancelling = false
    @Published var error: String?
    @Published var configuration: Configuration?
    @Published var deliveryCheck: String?
    @Published var checkingDelivery = false
    @Published var preparingSource = false
    @Published var scanningJoe = false
    @Published var latestJoe: DiscoveredSource?
    @Published var joeStatus = "Checking recent numbered episodes…"
    @Published var joeAutomation = JoeAutomationState()
    @Published var taxstoneLibrary = TaxstoneLibraryState()
    @Published var libraryBusy = false
    @Published var storage: StorageSnapshot?
    @Published var storageMessage: String?
    @Published var checkingStorage = false
    private var library: TaxstoneLibrary?
    var libraryTask: Task<Void,Never>?
    var automationRunning = false
    var automationTask: Task<Void,Never>?
    private var joeResumeRequested = false
    private var monitorTask: Task<Void,Never>?
    private var automationStateReadable = true
    private var recovering = true
    private var coordinator: Coordinator?
    var task: Task<Void,Never>?
    let root: URL
    let email: EmailIntakeModel
    init(root: URL = Persistence.defaultRoot, startsAutomatically: Bool = true) {
        self.root = root
        self.email = EmailIntakeModel(root:root)
        do {coordinator = try Coordinator(root:root); configuration = try Configuration.load(root:root)}
        catch {self.error = error.localizedDescription}
        guard startsAutomatically else {return}
        Task {
            await refresh()
            do {try email.store?.reconcile(jobs);email.publish()} catch {email.failedPersistence(error)}
            // Recover interrupted valid jobs once at launch. Explicitly
            // cancelled jobs remain cancelled until the user resumes them.
            let stateURL = root.appendingPathComponent("joe-automation.json")
            if FileManager.default.fileExists(atPath:stateURL.path) {
                do {joeAutomation = try Persistence.load(stateURL)}
                catch {automationStateReadable = false;joeAutomation.lastError = "Saved automation state could not be read; preserve joe-automation.json and repair it before enabling automatic processing."}
            }
            do {library = try TaxstoneLibrary(root:root); taxstoneLibrary = await library!.snapshot()}
            catch {self.error = "Taxstone library state unreadable: "+error.localizedDescription}
            let queuedIDs = Set(joeAutomation.queue.map(\.id)).union(taxstoneLibrary.episodes.map(\.id))
            let emailJobs = Set(email.state.work.compactMap(\.jobID))
            let pending = jobs.filter { $0.resumesAutomatically && !queuedIDs.contains($0.request.sourceID) && !emailJobs.contains($0.id) }
            for job in pending {
                start(job.request)
                await task?.value
            }
            recovering = false
            email.attach(to:self)
            if joeAutomation.enabled && !joeAutomation.queue.isEmpty {await runJoeQueue()}
            if taxstoneLibrary.enabled {startTaxstoneLibrary()}
            scanJoe()
            resumeJoeQueue()
            monitorTask = Task { [weak self] in
                while !Task.isCancelled {
                    do {try await Task.sleep(nanoseconds:1_800_000_000_000)} catch {return}
                    guard let self else {return}
                    if self.joeAutomation.enabled {self.scanJoe()}
                }
            }
        }
    }
    func startLink(_ raw: String, content: LinkContent, mode: JobMode, archive: String, archiveRoot: String, transcript: String) {
        guard !cancelling, !busy, !libraryBusy, !preparingSource else {return}
        preparingSource = true;error = nil
        Task {
            defer {preparingSource = false}
            do {
                let source = try await SourceDiscovery.lookup(raw.trimmingCharacters(in:.whitespacesAndNewlines))
                let request = try ProductionIntake.request(source:source,content:content,mode:mode,sharedProfile:content == .taxstone ? configuration?.taxstoneProfile : configuration?.profile,
                    archive:archive.isEmpty ? nil:archive,archiveRoot:archiveRoot.isEmpty ? nil:archiveRoot,transcript:transcript.isEmpty ? nil:transcript)
                start(request)
            } catch {self.error = error.localizedDescription}
        }
    }
    private func saveJoe() throws {try Persistence.save(joeAutomation,to:root.appendingPathComponent("joe-automation.json"))}
    func scanJoe() {
        guard !scanningJoe else {return}
        scanningJoe = true
        Task {
            defer {scanningJoe = false}
            do {
                let episodes = try await SourceDiscovery.recentJoeEpisodes()
                latestJoe = episodes.first
                let completed = Set(jobs.filter {$0.state == .completed && $0.request.productionWorkflow == .joeBudden}.map {$0.request.sourceID})
                joeAutomation.reconcile(episodes,completed:completed)
                joeStatus = episodes.isEmpty ? "No completed numbered episode found among the 30 recent uploads." : "Latest numbered episode from Joe Budden TV. Recent-upload check completed."
                if automationStateReadable {try saveJoe()}
                resumeJoeQueue()
            } catch {
                joeStatus = "Episode check failed: "+error.localizedDescription
                joeAutomation.lastError = error.localizedDescription
                // A feed outage must not discard already queued work.
                resumeJoeQueue()
            }
        }
    }
    func enableJoe() {
        guard !cancelling, automationStateReadable else {return}
        do {
            try joeAutomation.enable(after:latestJoe)
            try saveJoe()
            joeStatus = "Automatic processing enabled for episodes after \(joeAutomation.afterEpisode ?? 0)."
            resumeJoeQueue()
            scanJoe()
        } catch {joeAutomation.enabled = false;self.error = error.localizedDescription}
    }
    func pauseJoe() {
        joeAutomation.enabled = false
        let queue = automationRunning ? automationTask:nil, processing = automationRunning ? task:nil
        queue?.cancel();processing?.cancel()
        do {try saveJoe()} catch {self.error = error.localizedDescription}
        joeStatus = "Pausing automatic processing; queue and accepted work retained."
        let ownsCancellation = !cancelling
        if ownsCancellation {cancelling = true}
        Task {
            await processing?.value
            await queue?.value
            joeStatus = "Automatic processing paused. Queue and accepted work retained."
            if ownsCancellation {cancelling = false}
        }
    }
    func resumeJoeQueue(includeJoe: Bool = true) {
        if includeJoe && joeAutomation.enabled && automationStateReadable {joeResumeRequested = true}
        guard !cancelling, !recovering, automationTask == nil,
              !busy, !libraryBusy, !preparingSource else {return}
        let emailReady = email.available && email.state.canDispatch && email.state.work.contains {
            $0.account == email.state.settings.account && ($0.status == .queued || $0.status == .retryable) && ($0.retryAt ?? .distantPast) <= Date()
        }
        guard joeResumeRequested || emailReady else {return}
        let runJoe = joeResumeRequested;joeResumeRequested = false
        automationTask = Task {
            await runEmailItem()
            if runJoe {await runJoeQueue()}
            automationTask = nil
            if joeResumeRequested {resumeJoeQueue(includeJoe:false)}
        }
    }
    private func runJoeQueue(interleaved: Bool = false) async {
        guard !cancelling, !automationRunning, !busy, (!libraryBusy || interleaved), !preparingSource else {return}
        automationRunning = true;defer {automationRunning = false}
        // One attempt per queued episode per pass; failures remain for the next
        // periodic check or explicit Resume. Independent episodes can continue.
        for episode in Array(joeAutomation.queue.prefix(interleaved ? 1:joeAutomation.queue.count)) {
            guard joeAutomation.enabled, !Task.isCancelled, !busy else {break}
            do {
                let prior = jobs.first {$0.request.sourceID == episode.id && $0.request.productionWorkflow == .joeBudden}
                if prior?.state != .completed {
                    let request: JobRequest
                    if let prior {request = prior.request}
                    else {
                        preparingSource = true
                        defer {preparingSource = false}
                        let source = try await SourceDiscovery.lookup(episode.url)
                        guard source.id == episode.id else {throw JoeyError.invalid("Queued episode identity changed")}
                        request = try ProductionIntake.request(source:source,content:.joeBudden,mode:.fullShow,sharedProfile:nil)
                    }
                    try Task.checkCancellation()
                    guard joeAutomation.enabled, !busy else {break}
                    start(request,automatic:true)
                    if let processing = task {await waitForProcessing(processing)}
                }
                if let done = jobs.first(where:{$0.request.sourceID == episode.id && $0.request.productionWorkflow == .joeBudden}), done.state == .completed {
                    joeAutomation.queue.removeAll {$0.id == episode.id}
                } else {
                    joeAutomation.lastError = jobs.first(where:{$0.request.sourceID == episode.id && $0.request.productionWorkflow == .joeBudden})?.error ?? "Episode remains incomplete; saved for retry."
                }
            } catch {
                if error is CancellationError {break}
                joeAutomation.lastError = error.localizedDescription
            }
            do {try saveJoe()}
            catch {
                // Do not start more work if its durable queue cannot be saved.
                joeAutomation.enabled = false
                self.error = "Automatic processing stopped: queue save failed. " + error.localizedDescription
                break
            }
            await runEmailItem(interleaved:interleaved)
        }
    }
    func refresh() async {
        do {jobs = try await coordinator?.jobs() ?? []}
        catch {self.error = error.localizedDescription}
    }
    @discardableResult func start(_ request: JobRequest, automatic: Bool = false) -> JobAcceptance {
        guard !cancelling, !busy, (!libraryBusy || automatic), (!automationRunning || automatic) else {return .deferred}
        guard let coordinator else {return .unavailable}
        busy = true; error = nil
        task = Task {
            defer {busy = false; task = nil;if !automatic {resumeJoeQueue()}}
            do {
                let result = try await coordinator.run(request) { [weak self] job in
                    await self?.receive(job)
                }
                receive(result)
            } catch {self.error = error.localizedDescription}
            await refresh()
        }
        return .accepted
    }
    /// One durable email request per turn. Library/Joe loops offer the same
    /// turn between episodes, so no automation owns an unbounded media queue.
    func runEmailItem(interleaved: Bool = false, now: Date = Date()) async {
        guard !cancelling, !busy, !preparingSource, (!libraryBusy || interleaved),
              email.available, email.state.canDispatch, !email.dispatching, let store = email.store else {return}
        do {try store.reconcile(jobs);email.publish()} catch {email.failedPersistence(error);return}
        guard let work = email.state.work.first(where:{
            $0.account == email.state.settings.account && ($0.status == .queued || $0.status == .retryable) && ($0.retryAt ?? .distantPast) <= now
        }) else {return}
        email.dispatching = true;preparingSource = true
        defer {email.dispatching = false;preparingSource = false}
        do {
            var request = work.request
            if request == nil {
                // Reuse a matching prior manual/automatic contract before
                // looking up mutable provider titles or constructing a new ID.
                let matches = jobs.filter {
                    $0.request.sourceID == work.source.id &&
                    $0.request.owner == (work.workflow.content == .taxstone ? .taxstone:.dub) &&
                    ($0.request.productionWorkflow == .link || $0.request.productionWorkflow == .joeBudden) &&
                    $0.request.mode == (work.workflow.content == .joeBudden ? .fullShow:work.workflow.mode) &&
                    $0.request.fixedIntervals == nil && $0.request.requestedCount == nil && $0.request.adExclusions.isEmpty &&
                    $0.request.preferredDuration == nil && $0.request.transcriptPolicy == nil &&
                    ($0.request.productionWorkflow == .joeBudden || ($0.request.archiveRootID ?? "") == work.workflow.archiveRoot) &&
                    (work.workflow.content != .joeBudden || $0.request.productionWorkflow == .joeBudden)
                }
                guard matches.count <= 1 else {throw JoeyError.dependency("Multiple existing source contracts match; select the existing job instead of creating another")}
                if let prior = matches.first {request = prior.request}
                else {
                    let source = try await email.lookup(work.source.url)
                    guard source.id == work.source.id else {throw JoeyError.invalid("Email source identity changed during discovery")}
                    request = try ProductionIntake.request(source:source,content:work.workflow.content,mode:work.workflow.mode,
                        sharedProfile:work.workflow.content == .taxstone ? configuration?.taxstoneProfile:configuration?.profile,
                        archiveRoot:work.workflow.archiveRoot.isEmpty ? nil:work.workflow.archiveRoot)
                }
                try Task.checkCancellation()
                guard email.state.canDispatch, !cancelling else {return}
                try store.freeze(work.id,request:request!);email.publish()
            }
            guard email.state.canDispatch, !cancelling, let request else {return}
            try store.updateWork(work.id,status:.running);email.publish()
            let acceptance = start(request,automatic:true)
            guard acceptance == .accepted, let processing = task else {
                try store.updateWork(work.id,status:acceptance == .deferred ? .queued:.retryable,reason:"Processing owner is unavailable")
                email.publish();return
            }
            // Pausing intake never cancels an accepted media task. The existing
            // Cancel action still owns explicit media cancellation.
            await processing.value
            try store.reconcile(jobs)
            let current = store.state.work.first {$0.id == work.id}
            if current?.status != .completed && current?.status != .cancelled {
                try store.updateWork(work.id,status:.retryable,reason:jobs.first {$0.id == current?.jobID}?.error ?? error ?? "Job remains incomplete; accepted work retained")
            }
            email.publish()
        } catch is CancellationError {
            // No cursor or frozen request is discarded on discovery cancellation.
        } catch {
            do {try store.updateWork(work.id,status:.retryable,reason:error.localizedDescription);email.publish()}
            catch {email.failedPersistence(error)}
        }
    }
    func receive(_ job: JobRecord) {
        jobs.removeAll {$0.id == job.id}; jobs.insert(job,at:0); selected = job.id
    }
    func waitForProcessing(_ processing: Task<Void,Never>) async {
        // Awaiting an unstructured task does not propagate cancellation by itself.
        await withTaskCancellationHandler {
            await processing.value
        } onCancel: {
            processing.cancel()
        }
    }
    func cancel() {
        if libraryBusy {pauseTaxstoneLibrary()}
        else if automationRunning {pauseJoe()}
        else {
            let processing = task
            processing?.cancel()
            cancelling = true
            Task {await processing?.value;cancelling = false}
        }
    }
    func refreshTaxstoneLibrary() {
        guard !cancelling, !busy, !libraryBusy, !preparingSource, let library else {return}
        libraryBusy = true
        libraryTask = Task {
            defer {libraryBusy = false;libraryTask = nil;resumeJoeQueue()}
            do {taxstoneLibrary = try await library.inventory {state in await self.receiveLibrary(state)}}
            catch {taxstoneLibrary.error = error.localizedDescription}
        }
    }
    func receiveLibrary(_ state: TaxstoneLibraryState) {taxstoneLibrary = state}
    func startTaxstoneLibrary() {
        guard !cancelling, !busy, !libraryBusy, !preparingSource, !automationRunning, let library else {return}
        libraryBusy = true
        libraryTask = Task {
            defer {libraryBusy = false;libraryTask = nil;resumeJoeQueue()}
            do {
                taxstoneLibrary = try await library.run(progress:{state in await self.receiveLibrary(state)},jobProgress:{job in await self.receive(job)},betweenEpisodes:{
                    await self.runEmailItem(interleaved:true)
                    await self.runJoeQueue(interleaved:true)
                })
            } catch {
                taxstoneLibrary = await library.snapshot()
                if !(error is CancellationError) {taxstoneLibrary.error = error.localizedDescription}
            }
            await refresh()
        }
    }
    func pauseTaxstoneLibrary() {
        guard !cancelling else {return}
        cancelling = true
        let processing = task, runningLibrary = libraryTask
        // Joe can own the active task while the library is between episodes.
        // Stop its queue too, before any completion callback can restart it.
        if automationRunning {pauseJoe()}
        processing?.cancel()
        runningLibrary?.cancel()
        Task {
            await processing?.value
            await runningLibrary?.value
            do {try await library?.pause();if let library {taxstoneLibrary = await library.snapshot()}}
            catch {self.error = error.localizedDescription}
            cancelling = false
        }
    }
    func chooseFile(_ completion: @escaping (String?) -> Void) {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        // Do not nest a modal run loop inside a SwiftUI main-actor action.
        // File validation must be able to finish after that action returns.
        panel.begin { response in completion(response == .OK ? panel.url?.path : nil) }
    }
    func importJob() {
        chooseFile { [weak self] path in
            guard let self, let path else {return}
            do {let request: JobRequest = try Persistence.load(URL(fileURLWithPath:path)); self.start(request)}
            catch {self.error = error.localizedDescription}
        }
    }
    func saveProfile(_ profile: SharedProfile, owner: Owner = .dub) throws {
        try profile.validate()
        guard var config = configuration else {throw JoeyError.dependency("Local settings could not be loaded")}
        if owner == .taxstone {config.taxstoneProfile = profile} else {config.profile = profile}
        try Persistence.save(config,to:root.appendingPathComponent("settings.json"))
        configuration = config
    }
    func checkDelivery() {
        guard !checkingDelivery, let config = configuration else {return}
        checkingDelivery = true
        deliveryCheck = "Checking existing Drive connection and Master Link List…"
        Task {
            defer {checkingDelivery = false}
            do {
                let provider = try DriveDelivery(remote:config.rcloneRemote)
                let result = try await provider.preflight(tab:config.registerTab)
                deliveryCheck = result.keys.sorted().map { $0+": "+result[$0]! }.joined(separator:"\n")
                    + "\nRead access/schema checked. No upload or register write performed."
            } catch {deliveryCheck = error.localizedDescription}
        }
    }
    func revealClip(_ job: JobRecord, _ clip: ClipRecord) {
        NSWorkspace.shared.activateFileViewerSelecting([root.appendingPathComponent("jobs/"+job.id+"/"+clip.filename)])
    }
    func importProfile() {
        chooseFile { [weak self] path in
            guard let self, let path else {return}
            do {
                let profile: SharedProfile = try Persistence.load(URL(fileURLWithPath:path)); try profile.validate()
                try self.saveProfile(profile)
            } catch {self.error = error.localizedDescription}
        }
    }
    func reveal(_ job: JobRecord) {NSWorkspace.shared.activateFileViewerSelecting([root.appendingPathComponent("jobs/"+job.id)])}
    func openClips(_ job: JobRecord) {
        if let folder = job.folderID, let url = URL(string:"https://drive.google.com/drive/folders/"+folder) {
            NSWorkspace.shared.open(url)
        } else {reveal(job)}
    }
    func hasReport(_ job: JobRecord) -> Bool {
        FileManager.default.fileExists(atPath:root.appendingPathComponent("jobs/"+job.id+"/RECONCILE.md").path)
    }
    func openReport(_ job: JobRecord) {
        let report = root.appendingPathComponent("jobs/"+job.id+"/RECONCILE.md")
        guard hasReport(job) else {error = "The report will be available after the first saved processing result.";return}
        NSWorkspace.shared.open(report)
    }
    func openSettings() {NSWorkspace.shared.open(root.appendingPathComponent("settings.json"))}
    func refreshStorage(clean: Bool = false) {
        guard !checkingStorage else {return}
        checkingStorage = true
        let storageRoot = root
        Task {
            defer {checkingStorage = false}
            do {
                let result = try await Task.detached {
                    let cleanup = clean ? try StorageManager.clean(root:storageRoot) : nil
                    return (try StorageManager.inspect(root:storageRoot),cleanup)
                }.value
                storage = result.0
                if let cleanup = result.1 {
                    storageMessage = "Removed \(cleanup.removedFiles) files, \(cleanup.removedBytes) measured bytes. Volume free-space change: \(cleanup.freeBytesAfter-cleanup.freeBytesBefore) bytes. " + cleanup.errors.joined(separator:"; ")
                }
            } catch {storageMessage = error.localizedDescription + ". Active work and protected files were preserved."}
        }
    }
    func setAutomaticCleanup(_ enabled: Bool) {
        do {
            var current = try Configuration.load(root:root,discoverTranscription:false)
            current.automaticCleanup = enabled
            try Persistence.save(current,to:root.appendingPathComponent("settings.json"))
            configuration = current
        } catch {storageMessage = error.localizedDescription}
    }
}
