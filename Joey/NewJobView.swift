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
    @State private var coreDuration = 600.0
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
    private var selectsNativeDuration: Bool {
        content == .dub && mode == .fullShow && (try? DubBroadcastDiscovery.originalURL(url.trimmingCharacters(in:.whitespacesAndNewlines))) != nil
    }
    private var validSourceLink: Bool {
        (try? Acquisition.validateOriginalURL(url.trimmingCharacters(in:.whitespacesAndNewlines))) != nil
    }
    private var canStart: Bool {
        validSourceLink && model.checkpointFailures.isEmpty && !model.busy && !model.libraryBusy && !model.preparingSource
    }
    private var startMessage: String {
        if !model.checkpointFailures.isEmpty {return "Restore the unreadable checkpoints and Refresh History before starting a new job."}
        if model.preparingSource {return "Reading source details…"}
        if model.busy || model.libraryBusy {return "Processing continues in Jobs."}
        return validSourceLink ? "Selections complete. Source and delivery checks run next." : "Add a valid source link to complete your selections."
    }
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:24) {
                HStack {
                    Text("Import Link").font(JoeyTheme.font(24,weight:.medium))
                    Spacer()
                    Button("Cancel") {dismiss()}.keyboardShortcut(.cancelAction).disabled(model.preparingSource)
                }
                HStack(spacing:20) {
                    selectionStep("Source link",complete:validSourceLink)
                    selectionStep("Content",complete:true)
                    selectionStep("Workflow",complete:true)
                }
                JoeyPanel {
                    Text("Paste Link").font(JoeyTheme.font(18,weight:.medium))
                    TextField("Paste Link",text:$url).textFieldStyle(.roundedBorder).accessibilityLabel("Paste Link")
                    Text("YouTube or X. The complete original is filed before clips are created.").font(JoeyTheme.font(14)).foregroundStyle(.secondary)
                }
                JoeyPanel {
                    JoeyChoiceGroup(title:"Content",selection:$content,options:[
                        ("DUB",.dub),("Taxstone",.taxstone),("Joe Budden",.joeBudden)
                    ])
                    if content == .joeBudden {
                        Text("Workflow: Clip Entire Show").font(.headline)
                        Text("YouTube full episode → file original → 8–10-minute clips with DUB logo and approved outro → Drive.")
                        Text("Drive-only delivery. No platform-upload compatibility claim.").font(JoeyTheme.font(14)).foregroundStyle(.secondary)
                    } else {
                        JoeyChoiceGroup(title:"Workflow",selection:$mode,options:[
                            ("Clip Entire Show",.fullShow),("Highlights",.highlights)
                        ])
                        if selectsNativeDuration {
                            JoeyChoiceGroup(title:"Core clip length",selection:$coreDuration,options:[
                                ("8 minutes",480.0),("9 minutes",540.0),("10 minutes",600.0)
                            ])
                            Text("For DUB X broadcasts: target source-content length within 8–10 minutes, adjusted at natural boundaries. Native masters go to Drive; shorter Buffer clips are a separate workflow. Existing jobs retain their saved length.")
                                .font(JoeyTheme.font(14)).foregroundStyle(.secondary)
                        } else {
                            Text(mode == .fullShow ? "Clip the complete retained show chronologically, using the verified shared limits." : "One highlight per 15-minute block, including the final partial block. Clip length fits X and Instagram together.")
                                .font(JoeyTheme.font(14)).foregroundStyle(.secondary)
                        }
                    }
                }
                DisclosureGroup("Advanced Settings",isExpanded:$advanced) {
                    VStack(alignment:.leading,spacing:16) {
                        TextField("Existing full-length archive link (optional)",text:$archive).textFieldStyle(.roundedBorder)
                        Text("Drive destinations resolve automatically from the source and content owner.").font(.caption)
                        HStack {
                            TextField("Existing source-bound transcript (optional)",text:$transcript).textFieldStyle(.roundedBorder)
                            Button("Choose Transcript…") {model.chooseFile {if let path = $0 {transcript = path}}}
                        }
                        Text("Complete-original filing, transcript-assisted processing, automated QA and verified Drive records are required.").font(JoeyTheme.font(14))
                        Button("Production Configuration…") {setup = true}
                    }.padding(.top,16)
                }
            }.padding(32).frame(maxWidth:850,alignment:.leading).frame(maxWidth:.infinity,alignment:.topLeading)
        }.font(JoeyTheme.font(16)).controlSize(.large)
        .background(JoeyTheme.background(scheme)).tint(JoeyTheme.primary(scheme))
        .safeAreaInset(edge:.bottom) {
            HStack(spacing:20) {
                Text(startMessage)
                    .font(JoeyTheme.font(14)).foregroundStyle(canStart ? JoeyTheme.primary(scheme) : .secondary)
                    .frame(maxWidth:.infinity,alignment:.leading)
                Button("Start Processing",systemImage:"play.fill") {
                    model.startLink(url,content:content,mode:mode,archive:archive,archiveRoot:archiveRoot,transcript:transcript,preferredDuration:selectsNativeDuration ? coreDuration:nil)
                }.modifier(JoeyPrimaryButton()).disabled(!canStart)
            }.padding(20).background(JoeyTheme.panel(scheme))
        }
        .interactiveDismissDisabled(model.preparingSource)
        .onChange(of:model.busy) {_,busy in if busy {started()}}
        .sheet(isPresented:$setup) {productionSetup}
    }

    private func selectionStep(_ title: String, complete: Bool) -> some View {
        Label(title,systemImage:complete ? "checkmark.circle.fill" : "circle")
            .font(JoeyTheme.font(14,weight:.medium))
            .foregroundStyle(complete ? JoeyTheme.primary(scheme) : .secondary)
            .accessibilityValue(complete ? "Selected" : "Required")
            .frame(maxWidth:.infinity,alignment:.leading)
    }
}
