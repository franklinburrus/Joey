import SwiftUI

struct TaxstoneLibraryView: View {
    @ObservedObject var model: JobModel
    @Environment(\.colorScheme) private var scheme
    @State private var details = false
    @State private var setup = false

    private var library: TaxstoneLibraryState {model.taxstoneLibrary}
    private var currentEpisode: TaxstoneLibraryEpisode? {
        library.episodes.first {$0.id == library.currentSourceID}
    }

    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:24) {
                Text("Taxstone Library").font(.largeTitle.bold())
                Text("Resume the library. Reuse accepted clips. Verify each delivery.")
                    .font(.title3).foregroundStyle(.secondary)

                JoeyPanel {
                    Text(library.status).font(.title3.bold()).textSelection(.enabled)
                    HStack(alignment:.top,spacing:32) {
                        count("Episodes discovered",value:library.discoveredCount)
                        count("Episodes completed",value:library.completedCount)
                        count("Episodes remaining",value:library.remainingCount)
                    }
                    ProgressView(value:Double(library.completedCount),total:Double(max(1,library.discoveredCount))) {
                        Text("Verified episode deliveries")
                    } currentValueLabel: {
                        Text("\(library.completedCount) / \(library.discoveredCount)").monospacedDigit()
                    }
                    .accessibilityLabel("Verified episode deliveries")
                    .accessibilityValue("\(library.completedCount) of \(library.discoveredCount) episodes completed")
                    Text("An episode counts as completed only after required coverage, QA, Drive files and records are verified.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                if let episode = currentEpisode {
                    JoeyPanel {
                        Text("Current episode").font(.headline)
                        Text(episode.title).font(.title3).textSelection(.enabled)
                        Text(episode.status).font(.callout)
                        if episode.plannedClips > 0 {
                            ProgressView(value:Double(episode.acceptedClips),total:Double(episode.plannedClips)) {
                                Text("Clips passed automated QA")
                            } currentValueLabel: {
                                Text("\(episode.acceptedClips) / \(episode.plannedClips)").monospacedDigit()
                            }
                        } else {
                            Text("Clip count becomes available after planning.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        if let error = episode.error {errorMessage(error)}
                    }
                }

                if let error = library.error {
                    JoeyPanel {errorMessage(error)}
                }

                DisclosureGroup("Details and diagnostics",isExpanded:$details) {
                    VStack(alignment:.leading,spacing:16) {
                        HStack {
                            Button("Refresh Inventory") {model.refreshTaxstoneLibrary()}
                                .disabled(model.libraryBusy || model.busy)
                            Button("Taxstone Production Setup…") {setup = true}
                                .disabled(model.libraryBusy || model.busy)
                        }
                        Text("Legacy MP4s inventoried: \(library.remoteOutputCount); lacking mapped interval evidence: \(library.uncertainOutputCount)").font(.callout)
                        Text("Legacy duplicate interval records: \(library.duplicateCount)")
                            .font(.callout).monospacedDigit()
                        if library.episodes.isEmpty {
                            Text("No episodes are present in the saved inventory.")
                                .foregroundStyle(.secondary)
                        }
                        LazyVStack(alignment:.leading,spacing:14) {
                            ForEach(library.episodes,id:\.id) {episode in
                                JoeyPanel {
                                    Text(episode.title).font(.headline)
                                    Text(episode.status).font(.callout)
                                    Text("Source: \(episode.id)").font(.caption).textSelection(.enabled)
                                    Text("Accepted clips: \(episode.acceptedClips) / \(episode.plannedClips) · Legacy clips found: \(episode.legacyClipCount)")
                                        .font(.callout).monospacedDigit()
                                    if let seconds = episode.missingSeconds {
                                        Text("Missing eligible coverage: \(seconds,specifier:"%.3f") seconds")
                                            .font(.callout).monospacedDigit()
                                    }
                                    if let error = episode.error {errorMessage(error)}
                                }
                            }
                        }
                    }.padding(.top,16)
                }
            }
            .padding(32).frame(maxWidth:900,alignment:.leading)
            .frame(maxWidth:.infinity,alignment:.topLeading)
        }
        .background(JoeyTheme.background(scheme)).tint(JoeyTheme.primary(scheme))
        .safeAreaInset(edge:.bottom) {
            HStack(spacing:20) {
                Text(model.libraryBusy ? "Progress is saved as each stage completes." : model.busy ? "Another job is processing. Library progress is retained." : "Start resumes saved work. Keep Joey running and the Mac available.")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth:.infinity,alignment:.leading)
                if model.libraryBusy {
                    Button("Pause",systemImage:"pause.fill") {model.pauseTaxstoneLibrary()}
                        .modifier(JoeyPrimaryButton())
                        .accessibilityLabel("Pause Taxstone Library")
                } else {
                    Button("Start / Resume Taxstone Library",systemImage:"play.fill") {model.startTaxstoneLibrary()}
                        .modifier(JoeyPrimaryButton()).disabled(model.busy)
                }
            }.padding(20).background(JoeyTheme.panel(scheme))
        }
        .sheet(isPresented:$setup) {ProductionSetupView(model:model,owner:.taxstone)}
    }

    private func count(_ title: String, value: Int) -> some View {
        VStack(alignment:.leading,spacing:6) {
            Text(value,format:.number).font(.title.bold()).monospacedDigit()
            Text(title).font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth:.infinity,alignment:.leading)
        .accessibilityElement(children:.combine)
    }

    private func errorMessage(_ message: String) -> some View {
        Label(message,systemImage:"exclamationmark.triangle")
            .font(.callout).foregroundStyle(.red).textSelection(.enabled)
    }
}
