import SwiftUI
import AppKit
import Combine

@MainActor final class JobModel: ObservableObject {
    @Published var jobs: [JobRecord] = []
    @Published var selected: String?
    @Published var busy = false
    @Published var error: String?
    @Published var configuration: Configuration?
    private var coordinator: Coordinator?
    private var task: Task<Void,Never>?
    let root = Persistence.defaultRoot
    init() {
        do {coordinator = try Coordinator(root:root); configuration = try Configuration.load(root:root)}
        catch {self.error = error.localizedDescription}
        Task {
            await refresh()
            // Recover interrupted valid jobs once at launch. Explicitly
            // cancelled jobs remain cancelled until the user resumes them.
            let pending = jobs.filter(\.resumesAutomatically)
            for job in pending {
                start(job.request)
                await task?.value
            }
        }
    }
    func refresh() async {
        do {jobs = try await coordinator?.jobs() ?? []}
        catch {self.error = error.localizedDescription}
    }
    func start(_ request: JobRequest) {
        guard !busy, let coordinator else {return}
        busy = true; error = nil
        task = Task {
            defer {busy = false; task = nil}
            do {
                let result = try await coordinator.run(request) { [weak self] job in
                    await self?.receive(job)
                }
                receive(result)
            } catch {self.error = error.localizedDescription}
            await refresh()
        }
    }
    func receive(_ job: JobRecord) {
        jobs.removeAll {$0.id == job.id}; jobs.insert(job,at:0); selected = job.id
    }
    func cancel() {task?.cancel()}
    func chooseFile() -> String? {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
    func importJob() {
        guard let path = chooseFile() else {return}
        do {let request: JobRequest = try Persistence.load(URL(fileURLWithPath:path)); start(request)}
        catch {self.error = error.localizedDescription}
    }
    func importProfile() {
        guard let path = chooseFile(), var config = configuration else {return}
        do {
            let profile: SharedProfile = try Persistence.load(URL(fileURLWithPath:path)); try profile.validate()
            config.profile = profile; try Persistence.save(config,to:root.appendingPathComponent("settings.json")); configuration = config
        } catch {self.error = error.localizedDescription}
    }
    func reveal(_ job: JobRecord) {NSWorkspace.shared.activateFileViewerSelecting([root.appendingPathComponent("jobs/"+job.id)])}
    func openSettings() {NSWorkspace.shared.open(root.appendingPathComponent("settings.json"))}
}
