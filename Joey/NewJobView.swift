#if SWIFT_PACKAGE
import JoeyCore
#endif
import SwiftUI

struct NewJobView: View {
    @ObservedObject var model: JobModel
    var initialURL: String = ""
    var initialContent: LinkContent = .dub
    var started: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var content: LinkContent = .dub
    @State private var mode: JobMode = .fullShow
    @State private var url = ""
    @State private var archive = ""
    @State private var archiveRoot = ""
    @State private var transcript = ""
    @State private var advanced = false
    @State private var setup = false
    init(model: JobModel, initialURL: String = "", initialContent: LinkContent = .dub, started: @escaping () -> Void) {
        self.model = model;self.initialURL = initialURL;self.initialContent = initialContent;self.started = started
        _url = State(initialValue:initialURL)
        _content = State(initialValue:initialContent)
    }
    var productionSetup: ProductionSetupView {
        ProductionSetupView(model:model,owner:content == .taxstone ? .taxstone:.dub)
    }
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:24) {
                HStack {
                    Text("Import Link").font(JoeyTheme.font(24,weight:.medium))
                    Spacer()
                    Button("Cancel") {dismiss()}.keyboardShortcut(.cancelAction).disabled(model.preparingSource)
                }
                JoeyPanel {
                    Text("Paste Link").font(.headline)
                    TextField("Paste Link",text:$url).textFieldStyle(.roundedBorder).accessibilityLabel("Paste Link")
                    Text("YouTube or X. The complete original is filed before clips are created.").font(.caption).foregroundStyle(.secondary)
                }
                JoeyPanel {
                    Picker("Content",selection:$content) {
                        Text("DUB").tag(LinkContent.dub)
                        Text("Taxstone").tag(LinkContent.taxstone)
                        Text("Joe Budden").tag(LinkContent.joeBudden)
                    }.pickerStyle(.segmented)
                    if content == .joeBudden {
                        Text("Workflow: Clip Entire Show").font(.headline)
                        Text("YouTube full episode → file original → 8–10-minute clips with DUB logo and approved outro → Drive.")
                        Text("Drive-only delivery. No platform-upload compatibility claim.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Picker("Workflow",selection:$mode) {
                            Text("Clip Entire Show").tag(JobMode.fullShow)
                            Text("Highlights").tag(JobMode.highlights)
                        }.pickerStyle(.segmented)
                        Text(mode == .fullShow ? "Clip the complete retained show chronologically, using the verified shared limits." : "One highlight per 15-minute block, including the final partial block. Clip length fits X and Instagram together.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                DisclosureGroup("Advanced Settings",isExpanded:$advanced) {
                    VStack(alignment:.leading,spacing:16) {
                        TextField("Existing full-length archive link (optional)",text:$archive).textFieldStyle(.roundedBorder)
                        if content == .dub {
                            Picker("Full-original destination",selection:$archiveRoot) {
                                Text("Resolve from source").tag("")
                                Text("DUB full X broadcasts").tag("1GpuGWGIbSt3afwsi9L782soT9WJKOHS9")
                            }
                        }
                        HStack {
                            TextField("Existing source-bound transcript (optional)",text:$transcript).textFieldStyle(.roundedBorder)
                            Button("Choose Transcript…") {model.chooseFile {if let path = $0 {transcript = path}}}
                        }
                        Text("Complete-original filing, transcript-assisted processing, automated QA and verified Drive records are required.").font(.caption)
                        Button("Production Configuration…") {setup = true}
                    }.padding(.top,16)
                }
            }.padding(32).frame(maxWidth:850,alignment:.leading).frame(maxWidth:.infinity,alignment:.topLeading)
        }.background(JoeyTheme.background(scheme)).tint(JoeyTheme.primary(scheme))
        .safeAreaInset(edge:.bottom) {
            HStack(spacing:20) {
                Text(model.preparingSource ? "Reading source details…" : model.busy ? "Processing continues in Jobs." : "Full original and clips are filed to Drive. Nothing is published.")
                    .font(.callout).foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.leading)
                Button("Start Processing",systemImage:"play.fill") {
                    model.startLink(url,content:content,mode:mode,archive:archive,archiveRoot:archiveRoot,transcript:transcript)
                }.modifier(JoeyPrimaryButton()).disabled(model.busy || model.libraryBusy || model.preparingSource || url.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
            }.padding(20).background(JoeyTheme.panel(scheme))
        }
        .interactiveDismissDisabled(model.preparingSource)
        .onChange(of:model.busy) {_,busy in if busy {started()}}
        .sheet(isPresented:$setup) {productionSetup}
    }
}
