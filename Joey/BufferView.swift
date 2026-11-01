import SwiftUI
import AppKit
import Combine

@MainActor final class BufferViewModel: ObservableObject {
    @Published var state = BufferHandoffState()
    @Published var selection = BufferSelection()
    @Published var channels: [BufferChannel] = []
    @Published var recommendations: [String:ClipRecommendation] = [:]
    @Published var recommendationErrors: [String:String] = [:]
    @Published var episodeID: String?
    @Published var lane = "All"
    @Published var busy = false
    @Published var checked = 0
    @Published var total = 0
    @Published var message: String?
    @Published var error: String?
    @Published var lastExport: URL?
    private var store: BufferHandoffStore?
    let root = Persistence.defaultRoot
    init() {
        do {
            store = try BufferHandoffStore(root:root)
            state = try store!.snapshot();selection = state.selection;channels = try store!.channels()
        } catch {self.error = error.localizedDescription}
    }
    func refresh(jobs: [JobRecord]) {
        guard !busy else {return}
        do {state = try store?.snapshot() ?? state;channels = try store?.channels() ?? []}
        catch {self.error = error.localizedDescription}
        for job in jobs where job.state == .completed {
            for clip in job.clips {
                let key = BufferPreparedClip.key(jobID:job.id,clipID:clip.id)
                guard recommendations[key] == nil, recommendationErrors[key] == nil else {continue}
                do {recommendations[key] = try ClipIntelligence.evaluate(job:job,clip:clip)}
                catch {recommendationErrors[key] = error.localizedDescription}
            }
        }
    }
    func saveSelection() {
        do {try store?.saveSelection(selection)} catch {self.error = error.localizedDescription}
    }
    func select(_ key: String,_ selected: Bool) {
        if selected {if !selection.clipKeys.contains(key) {selection.clipKeys.append(key)}}
        else {selection.clipKeys.removeAll {$0 == key}}
        saveSelection()
    }
    func preflight(jobs: [JobRecord]) {
        guard !busy,let store else {return}
        let chosen = selection.clipKeys
        busy = true;checked = 0;total = chosen.count;message = nil;error = nil
        Task {
            defer {busy = false}
            do {
                let configuration: Configuration = try Persistence.load(root.appendingPathComponent("settings.json"))
                for key in chosen {
                    guard let job = jobs.first(where:{job in job.clips.contains {BufferPreparedClip.key(jobID:job.id,clipID:$0.id) == key}}),
                          let clip = job.clips.first(where:{BufferPreparedClip.key(jobID:job.id,clipID:$0.id) == key}) else {
                        throw JoeyError.invalid("Selected job/clip no longer exists; refresh selection")
                    }
                    message = "Checking \(job.request.title) · Clip \(clip.id)"
                    _ = try await store.prepare(job:job,clip:clip,root:root,profile:job.request.owner == .taxstone ? configuration.taxstoneProfile:configuration.profile)
                    state = try store.snapshot();checked += 1
                }
                message = "Preflight saved. Review accounts, mode and blocked items before generating. No Buffer writes."
            } catch {self.error = error.localizedDescription}
        }
    }
    func generate() {
        guard !busy,let store else {return}
        do {
            let manifest = try store.generate(selection:selection,channels:channels)
            lastExport = try store.export(manifest);state = try store.snapshot()
            let blocked = manifest.operations.filter {$0.state == .blocked}.count
            message = "\(manifest.expectedOperationCount) operations; \(blocked) blocked. Batch \(manifest.id). Separate Frank execution request required."
            if let lastExport {NSWorkspace.shared.activateFileViewerSelecting([lastExport])}
        } catch {self.error = error.localizedDescription}
    }
    func importFile(channels: Bool = false) {
        guard !busy else {return}
        let panel = NSOpenPanel();panel.canChooseDirectories = false;panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard response == .OK,let url = panel.url,let self else {return}
            do {
                let values = try url.resourceValues(forKeys:[.fileSizeKey,.isRegularFileKey])
                guard values.isRegularFile == true,(values.fileSize ?? Int.max) <= 16_000_000 else {throw JoeyError.invalid("Choose a JSON evidence file smaller than 16 MB")}
                let data = try Data(contentsOf:url)
                if channels {try self.store?.importChannels(data);self.channels = try self.store?.channels() ?? []}
                else {try self.store?.importReceipts(data:data);self.state = try self.store?.snapshot() ?? self.state}
                self.message = channels ? "Channel evidence imported; execution still requires current provider readback." : "Receipts reconciled as GPT-mediated evidence. Missing results remain unresolved."
            } catch {self.error = error.localizedDescription}
        }
    }
    func history(_ key: String) -> String {
        let receipts = state.receipts.filter {BufferPreparedClip.key(jobID:$0.jobID,clipID:$0.clipID) == key}
        if !receipts.isEmpty {return receipts.map {"\($0.platform.rawValue): \($0.reconciliationState.rawValue) · \($0.providerState?.rawValue ?? "unknown")"}.joined(separator:"; ")}
        let batches = state.batches.filter {$0.operations.contains {$0.clip.key == key}}
        return batches.isEmpty ? "No submission receipts" : "\(batches.count) handoff(s); provider receipts missing"
    }
    func eligibility(_ key: String) -> String {
        guard let preparation = state.prepared[key] else {return "Preflight required"}
        if let error = preparation.error {return "Blocked: "+error}
        guard let media = preparation.media,media.validUntil > Date() else {return "Preflight expired; recheck"}
        return "Media preflight passed until "+media.validUntil.formatted(date:.omitted,time:.standard)
    }
}

struct BufferReadyView: View {
    @ObservedObject var buffer: BufferViewModel
    @ObservedObject var model: JobModel
    private struct Row: Identifiable {
        let job: JobRecord
        let clip: ClipRecord
        var id: String {BufferPreparedClip.key(jobID:job.id,clipID:clip.id)}
    }
    private var rows: [Row] {
        model.jobs.filter {$0.state == .completed && (buffer.episodeID == nil || $0.id == buffer.episodeID) &&
            (buffer.lane == "All" || $0.request.owner.rawValue == buffer.lane)}
            .flatMap {job in job.clips.map {Row(job:job,clip:$0)}}
            .sorted {
                let a = buffer.recommendations[$0.id],b = buffer.recommendations[$1.id]
                let scoreA = (a?.xScore ?? 0)+(a?.instagramScore ?? 0),scoreB = (b?.xScore ?? 0)+(b?.instagramScore ?? 0)
                return scoreA == scoreB ? $0.id < $1.id:scoreA > scoreB
            }
    }
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                Text("Ready for Buffer").font(JoeyTheme.font(24,weight:.medium))
                Text("Completed clips · Recommended first").foregroundStyle(.secondary)
                Text("Scores are editorial heuristics, not probabilities of virality.").font(JoeyTheme.font(11)).foregroundStyle(.secondary)
                Picker("Content",selection:$buffer.lane) {
                    Text("All").tag("All");Text("DUB").tag("dub");Text("Taxstone").tag("taxstone")
                }.pickerStyle(.segmented)
                if buffer.episodeID != nil {Button("Show all completed episodes") {buffer.episodeID = nil}}
                if rows.isEmpty {Text("No completed clips in this selection.").foregroundStyle(.secondary)}
                LazyVStack(alignment:.leading,spacing:20) {
                    ForEach(rows) {row in
                        VStack(alignment:.leading,spacing:8) {
                            Toggle(isOn:Binding(get:{buffer.selection.clipKeys.contains(row.id)},set:{buffer.select(row.id,$0)})) {
                                Text(buffer.recommendations[row.id]?.title ?? row.clip.title).font(JoeyTheme.font(14,weight:.medium))
                            }.disabled(buffer.busy)
                            Text("\(row.job.request.owner.rawValue.uppercased()) · \(row.job.request.title) · Clip \(row.clip.id)").font(JoeyTheme.font(11)).foregroundStyle(.secondary)
                            Text("\(row.clip.measuredDuration ?? row.clip.expectedDuration,specifier:"%.3f") s · X \(buffer.recommendations[row.id]?.xScore ?? 0)/100 · Instagram \(buffer.recommendations[row.id]?.instagramScore ?? 0)/100")
                                .font(JoeyTheme.font(12)).monospacedDigit()
                            Text(buffer.eligibility(row.id)).font(JoeyTheme.font(11)).textSelection(.enabled)
                            Text(buffer.history(row.id)).font(JoeyTheme.font(11)).foregroundStyle(.secondary)
                            Button("Preview") {
                                NSWorkspace.shared.open(model.root.appendingPathComponent("jobs/\(row.job.id)/\(row.clip.filename)"))
                            }.controlSize(.small)
                            DisclosureGroup("Recommendation details") {
                                if let recommendation = buffer.recommendations[row.id] {
                                    Text(recommendation.confidence)
                                    ForEach(recommendation.rationale,id:\.self) {Text($0)}
                                    ForEach(recommendation.boundaryNotes + recommendation.restrictions,id:\.self) {Text($0)}
                                } else {Text(buffer.recommendationErrors[row.id] ?? "Unavailable")}
                            }.font(JoeyTheme.font(11)).foregroundStyle(.secondary)
                            Divider()
                        }
                    }
                }
            }.padding(28)
        }.task {buffer.refresh(jobs:model.jobs)}
    }
}

struct BufferHandoffPanel: View {
    @ObservedObject var buffer: BufferViewModel
    @ObservedObject var model: JobModel
    @State private var review = false
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:18) {
                Text("Selected Clips").font(JoeyTheme.font(22,weight:.medium))
                Text("\(buffer.selection.clipKeys.count) clips · \(buffer.selection.clipKeys.count * buffer.selection.platforms.count) operations")
                Picker("Destination",selection:Binding(get:{buffer.selection.platforms.count == 2 ? "Both":buffer.selection.platforms.first?.rawValue ?? "X"},set:{buffer.selection.platforms = $0 == "Both" ? [.x,.instagram]:[$0 == "X" ? .x:.instagram];buffer.saveSelection();review = false})) {
                    Text("X").tag("X");Text("Instagram").tag("Instagram");Text("X + Instagram").tag("Both")
                }
                Picker("Delivery mode",selection:$buffer.selection.mode) {
                    ForEach(BufferMode.allCases,id:\.self) {Text($0.rawValue).tag($0)}
                }.onChange(of:buffer.selection.mode) {_,_ in buffer.saveSelection();review = false}
                if buffer.selection.mode == .scheduled {
                    DatePicker("Requested schedule",selection:Binding(get:{buffer.selection.scheduledAt ?? Date()},set:{buffer.selection.scheduledAt = $0;buffer.saveSelection();review = false}))
                    Text(TimeZone.current.identifier).font(.caption)
                }
                if buffer.selection.platforms.contains(.instagram) {
                    Picker("Instagram presentation",selection:$buffer.selection.instagramPresentation) {
                        ForEach(InstagramPresentation.allCases,id:\.self) {Text($0.rawValue).tag($0)}
                    }.onChange(of:buffer.selection.instagramPresentation) {_,_ in buffer.selection.instagramAcknowledged = false;buffer.saveSelection();review = false}
                    Toggle("I explicitly select this Reel presentation",isOn:$buffer.selection.instagramAcknowledged)
                        .disabled(buffer.selection.instagramPresentation == .traditionalFeed)
                        .onChange(of:buffer.selection.instagramAcknowledged) {_,_ in buffer.saveSelection();review = false}
                }
                ForEach(buffer.selection.platforms,id:\.self) {platform in
                    ForEach(buffer.selection.blockers(for:platform),id:\.self) {Text("\(platform.rawValue): \($0)").font(JoeyTheme.font(11)).foregroundStyle(.secondary)}
                }
                DisclosureGroup("Accounts and diagnostics") {
                    ForEach(buffer.channels,id:\.channelID) {channel in
                        Text("\(channel.lane) · \(channel.platform.rawValue) @\(channel.handle)\nOrganization \(channel.organizationID)\nChannel \(channel.channelID)\nEvidence expires \(channel.validUntil.formatted())").textSelection(.enabled)
                    }
                    Stepper("Operations per sub-batch: \(buffer.selection.maximumOperations)",value:$buffer.selection.maximumOperations,in:1...20)
                        .onChange(of:buffer.selection.maximumOperations) {_,_ in buffer.saveSelection();review = false}
                    Button("Import refreshed channel evidence…") {buffer.importFile(channels:true)}
                }.font(JoeyTheme.font(10))
                Button("Run Preflight") {review = false;buffer.preflight(jobs:model.jobs)}
                    .disabled(buffer.busy || buffer.selection.clipKeys.isEmpty)
                if buffer.busy {
                    ProgressView(value:Double(buffer.checked),total:Double(max(1,buffer.total)))
                    Text("\(buffer.checked)/\(buffer.total) clips checked").font(.caption)
                }
                ForEach(buffer.selection.clipKeys,id:\.self) {key in
                    VStack(alignment:.leading,spacing:4) {
                        Text(buffer.state.prepared[key]?.recommendation?.title ?? key).font(JoeyTheme.font(11,weight:.medium))
                        Text(buffer.eligibility(key)).font(JoeyTheme.font(10))
                    }
                }
                Toggle("Reviewed selected accounts, mode, placement and blocked items",isOn:$review)
                    .font(JoeyTheme.font(11))
                Text("Export is preparation only. Frank must separately authorize GPT execution of the exact batch and mode.")
                    .font(JoeyTheme.font(11)).foregroundStyle(.secondary)
                Button("Generate GPT Handoff") {buffer.generate()}
                    .buttonStyle(.borderedProminent).disabled(buffer.busy || !review || buffer.selection.clipKeys.isEmpty)
                Button("Import GPT Receipts…") {buffer.importFile()}.disabled(buffer.busy)
                if let url = buffer.lastExport {Button("Open Handoff Package") {NSWorkspace.shared.activateFileViewerSelecting([url])}}
                if let message = buffer.message {Text(message).font(JoeyTheme.font(11)).textSelection(.enabled)}
                if let error = buffer.error {Text(error).font(JoeyTheme.font(11)).foregroundStyle(.red).textSelection(.enabled)}
                DisclosureGroup("Handoff history") {
                    ForEach(buffer.state.batches.reversed(),id:\.manifestSHA256) {batch in
                        VStack(alignment:.leading,spacing:5) {
                            Text(batch.id).textSelection(.enabled)
                            Text("\(batch.expectedOperationCount) operations · \(batch.selection.mode.rawValue)")
                            ForEach(batch.operations) {op in
                                let receipt = buffer.state.receipts.last(where:{$0.operationID == op.id && $0.batchID == batch.id && $0.manifestSHA256 == batch.manifestSHA256})
                                Text("Clip \(op.clip.clipID) \(op.platform.rawValue): \(receipt?.reconciliationState.rawValue ?? op.state.rawValue) · \(receipt?.providerState?.rawValue ?? "No provider readback")")
                                if let postID = receipt?.postID {Text("Post \(postID)").textSelection(.enabled)}
                                ForEach(op.blockers,id:\.self) {Text($0)}
                            }
                            Divider()
                        }
                    }
                    Text("Imported receipts are GPT-mediated evidence. Buffer ingestion and publication remain separate.")
                }.font(JoeyTheme.font(10))
            }.padding(24).controlSize(.small)
        }
        .onChange(of:buffer.selection.clipKeys) {_,_ in review = false}
    }
}
