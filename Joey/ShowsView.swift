import SwiftUI

struct ShowsView: View {
    @ObservedObject var model: JobModel
    var useEpisode: (String) -> Void
    var inspectEpisode: (String) -> Void
    @State private var taxstone = false
    @State private var dubURLs = ""
    @Environment(\.colorScheme) private var scheme
    private var library: TaxstoneLibraryState {model.taxstoneLibrary}
    private var currentEpisode: TaxstoneLibraryEpisode? {
        library.episodes.first {$0.id == library.currentSourceID}
    }

    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:24) {
                Text("Shows").font(JoeyTheme.font(24,weight:.medium))
                dubCard
                taxstoneCard
                joeCard
            }.padding(28)
        }
        .sheet(isPresented:$taxstone) {
            VStack(spacing:0) {
                HStack {Text("Taxstone").font(.headline);Spacer();Button("Done") {taxstone = false}}.padding()
                Divider()
                TaxstoneLibraryView(model:model)
            }.frame(width:760,height:680)
        }
    }

    private var dubCard: some View {
        JoeyPanel {
            HStack(alignment:.top) {
                Text("Dub Broadcasts").font(JoeyTheme.font(20,weight:.medium))
                Spacer()
                Button(model.scanningDub ? "Checking…" : "Check Now") {
                    model.checkDubBroadcasts(dubURLs.components(separatedBy:.whitespacesAndNewlines))
                }.modifier(JoeyPrimaryButton()).disabled(model.scanningDub || model.cancelling)
            }
            Text(model.dubBroadcasts.discoveryStatus ?? "Check Now scans DUB’s website and visible original X profile for broadcasts, then verifies original replay identity and completeness.").font(JoeyTheme.font(14)).foregroundStyle(.secondary).textSelection(.enabled)
            if let checked = model.dubBroadcasts.lastCheckedAt {
                Text("Last discovery check "+checked.formatted()).font(JoeyTheme.font(14))
            } else {Text("No discovery check yet").foregroundStyle(.secondary)}
            Text(model.scanningDub ? "Verifying original replays…" : model.dubRunning ? "Processing saved queue" : model.dubBroadcasts.paused ? "Paused; saved work retained" : "Ready for manual Check Now")
            HStack(alignment:.top,spacing:12) {
                count("New",value:model.dubBroadcasts.newCount)
                count("Queued",value:model.dubBroadcasts.entries.filter {$0.state == .planned}.count)
                count("Completed",value:model.dubBroadcasts.entries.filter {$0.state == .completed}.count)
                count("Needs attention",value:model.dubBroadcasts.entries.filter {$0.error != nil}.count)
            }
            DisclosureGroup("Original broadcast URLs / historical backfill") {
                VStack(alignment:.leading,spacing:8) {
                    Text("One original URL per line. Optional fallback. Check Now verifies these original URLs as explicit historical backfill alongside website/profile discovery.")
                        .font(JoeyTheme.font(14)).foregroundStyle(.secondary)
                    TextEditor(text:$dubURLs).font(.body).frame(minHeight:72,maxHeight:140)
                        .accessibilityLabel("Original Dub broadcast URLs")
                }
            }
            if let error = model.dubQueueError ?? model.dubBroadcasts.lastError {errorMessage(error)}
            if model.dubRunning || model.scanningDub {
                Button(model.scanningDub ? "Cancel Check" : "Pause",systemImage:"pause.fill") {model.pauseDubBroadcasts()}.disabled(model.cancelling)
            } else if model.dubBroadcasts.entries.contains(where:{$0.state != .completed}) {
                Button("Resume Saved Queue",systemImage:"play.fill") {model.resumeDubBroadcasts(retry:true)}
                    .disabled(model.busy || model.libraryBusy || model.cancelling || model.preparingSource)
            }
            ForEach(model.dubBroadcasts.entries) {entry in
                VStack(alignment:.leading,spacing:6) {
                    Text(entry.broadcast.source.title).font(JoeyTheme.font(18,weight:.medium)).textSelection(.enabled)
                    Text((entry.broadcast.source.episodeDate ?? "Date Unknown")+" · "+entry.state.rawValue)
                        .font(JoeyTheme.font(14)).foregroundStyle(.secondary)
                    if let job = model.jobs.first(where:{$0.id == entry.jobID || $0.request.sourceID == entry.id}) {
                        Text(job.stage+" · \(job.clips.filter {$0.qa?.passed == true}.count) / \(job.clips.count) native clips passed QA · \(job.clips.filter {$0.drive != nil}.count) filed")
                            .font(JoeyTheme.font(14)).textSelection(.enabled)
                        Button("Inspect Episode Results") {inspectEpisode(job.id)}
                        if let folder = job.folderID,job.state == .completed {
                            Link("Verified Drive Results",destination:URL(string:"https://drive.google.com/drive/folders/"+folder)!)
                        }
                    }
                    if let error = entry.error {errorMessage(error)}
                }.padding(.vertical,8)
            }
            Text("Complete broadcasts become 8–10-minute native masters, including short-source and final-remainder exceptions. Drive-only delivery. Restart resumes authorized interrupted work without discovering additional broadcasts.")
                .font(JoeyTheme.font(14)).foregroundStyle(.secondary)
        }
    }

    private var taxstoneCard: some View {
        JoeyPanel {
            showHeader("Taxstone episodes",enabled:library.enabled,
                       checking:model.libraryBusy && !library.enabled,
                       checkDisabled:model.libraryBusy || model.busy || model.cancelling || model.preparingSource) {
                model.refreshTaxstoneLibrary()
            }
            Text(library.status).textSelection(.enabled)
            HStack(alignment:.top,spacing:20) {
                count("Discovered",value:library.discoveredCount)
                count("Verified deliveries",value:library.completedCount)
                count("Remaining",value:library.remainingCount)
            }
            if library.discoveredCount > 0 {
                ProgressView(value:Double(library.completedCount),total:Double(library.discoveredCount))
                    .accessibilityLabel("Verified Taxstone episode deliveries")
                    .accessibilityValue("\(library.completedCount) of \(library.discoveredCount)")
            }
            if let episode = currentEpisode {
                VStack(alignment:.leading,spacing:6) {
                    Text("Current episode").font(JoeyTheme.font(14)).foregroundStyle(.secondary)
                    Text(episode.title).font(JoeyTheme.font(18,weight:.medium)).textSelection(.enabled)
                    Text(episode.status).font(JoeyTheme.font(14)).foregroundStyle(.secondary)
                    if episode.plannedClips > 0 {
                        Text("\(episode.acceptedClips) / \(episode.plannedClips) clips passed QA · Drive verification required")
                            .font(JoeyTheme.font(14)).foregroundStyle(.secondary)
                    }
                    if let error = episode.error {errorMessage(error)}
                }
            }
            if let error = library.error {errorMessage(error)}
            ViewThatFits(in:.horizontal) {
                HStack(spacing:16) {taxstoneControls;Spacer(minLength:0)}
                    .fixedSize(horizontal:true,vertical:false)
                VStack(alignment:.leading,spacing:12) {taxstoneControls}
            }
            Text("Processes unfinished archived episodes automatically, reuses accepted clips, and verifies every Drive delivery. Start refreshes the inventory; Check Now only checks it. Keep Joey open and the Mac available. Interrupted work resumes on reopening; paused work waits for Resume.")
                .font(JoeyTheme.font(14)).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var taxstoneControls: some View {
        if model.libraryBusy || library.enabled {
            Button(model.cancelling ? "Pausing…" : "Pause Automatic Processing",systemImage:"pause.fill") {model.pauseTaxstoneLibrary()}
                .disabled(model.cancelling)
        } else {
            Button(library.episodes.contains(where:{$0.jobID != nil}) ? "Resume Automatic Processing" : "Start Automatic Processing",systemImage:"play.fill") {model.startTaxstoneLibrary()}
                .modifier(JoeyPrimaryButton())
                .disabled(model.busy || model.preparingSource || model.cancelling)
        }
        Button("Library Details…") {taxstone = true}
    }

    private var joeCard: some View {
        JoeyPanel {
            showHeader("Joe Budden episodes",enabled:model.joeAutomation.enabled,
                       checking:model.scanningJoe,checkDisabled:model.scanningJoe) {model.scanJoe()}
            Text(model.joeStatus).textSelection(.enabled)
            if let episode = model.latestJoe {
                Text(episode.title).font(JoeyTheme.font(18,weight:.medium)).textSelection(.enabled)
                Button("Use This Episode") {useEpisode(episode.url)}
            }
            if let error = model.joeAutomation.lastError {errorMessage(error)}
            ViewThatFits(in:.horizontal) {
                HStack(spacing:16) {joeControls;Spacer(minLength:0)}
                    .fixedSize(horizontal:true,vertical:false)
                VStack(alignment:.leading,spacing:12) {joeControls}
            }
            Text("Checks on app opening, every 30 minutes while enabled, and Check Now. Once enabled, new numbered episodes process in the background while Joey stays open. The initial latest episode is not replayed. Sleep or Quit stops work; the saved queue resumes when Joey reopens. Only the 30 recent uploads are scanned.")
                .font(JoeyTheme.font(14)).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var joeControls: some View {
        if model.joeAutomation.enabled {
            Button("Pause Automatic Processing",systemImage:"pause.fill") {model.pauseJoe()}
        } else {
            Button(model.joeAutomation.afterEpisode == nil ? "Start Automatic Processing" : "Resume Automatic Processing",systemImage:"play.fill") {model.enableJoe()}
                .modifier(JoeyPrimaryButton())
                .disabled((model.latestJoe == nil && model.joeAutomation.afterEpisode == nil) || model.scanningJoe)
        }
        Text("\(model.joeAutomation.queue.count) episodes queued").font(JoeyTheme.font(14)).foregroundStyle(.secondary)
    }

    private func showHeader(_ title: String, enabled: Bool, checking: Bool, checkDisabled: Bool,
                            check: @escaping () -> Void) -> some View {
        ViewThatFits(in:.horizontal) {
            HStack(alignment:.top,spacing:16) {
                showTitle(title,enabled:enabled)
                Spacer(minLength:16)
                Button(checking ? "Checking…" : "Check Now",action:check).disabled(checkDisabled)
            }.fixedSize(horizontal:false,vertical:true)
            VStack(alignment:.leading,spacing:12) {
                showTitle(title,enabled:enabled)
                Button(checking ? "Checking…" : "Check Now",action:check).disabled(checkDisabled)
            }
        }
    }

    private func showTitle(_ title: String, enabled: Bool) -> some View {
        VStack(alignment:.leading,spacing:6) {
            Text(title).font(JoeyTheme.font(20,weight:.medium)).fixedSize()
            Label(enabled ? "Automatic processing on" : "Automatic processing off",
                  systemImage:enabled ? "checkmark.circle.fill" : "circle")
                .font(JoeyTheme.font(14))
                .foregroundStyle(enabled ? JoeyTheme.primary(scheme) : Color.secondary)
                .fixedSize()
        }
    }

    private func count(_ title: String, value: Int) -> some View {
        VStack(alignment:.leading,spacing:4) {
            Text(value,format:.number).font(JoeyTheme.font(24,weight:.medium)).monospacedDigit()
            Text(title).font(JoeyTheme.font(14)).foregroundStyle(.secondary)
        }.frame(maxWidth:.infinity,alignment:.leading)
            .accessibilityElement(children:.combine)
    }

    private func errorMessage(_ error: String) -> some View {
        Label(error,systemImage:"exclamationmark.triangle")
            .font(JoeyTheme.font(14)).foregroundStyle(.red).textSelection(.enabled)
    }
}
