import SwiftUI

struct ShowsView: View {
    @ObservedObject var model: JobModel
    var useEpisode: (String) -> Void
    @State private var taxstone = false
    @Environment(\.colorScheme) private var scheme
    private var library: TaxstoneLibraryState {model.taxstoneLibrary}
    private var currentEpisode: TaxstoneLibraryEpisode? {
        library.episodes.first {$0.id == library.currentSourceID}
    }

    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:24) {
                Text("Shows").font(JoeyTheme.font(24,weight:.medium))
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
