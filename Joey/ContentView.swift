import SwiftUI
import UniformTypeIdentifiers

private enum JoeyDestination: String, CaseIterable {
    case process = "Process", jobs = "Jobs", shows = "Shows", buffer = "Ready for Buffer"
    var workspaceNavigationTitle: String {
        switch self {
        case .shows: return "Back to Shows"
        case .buffer: return "Clip List"
        default: return "Job List"
        }
    }
    var workspaceNavigationAccessibilityLabel: String {
        self == .shows ? "Return to Shows" : "Show " + workspaceNavigationTitle.lowercased()
    }
    var symbol: String {
        switch self {case .process: return "record.circle"; case .jobs: return "list.bullet.rectangle"; case .shows: return "mic";case .buffer:return "square.and.arrow.up"}
    }
}

struct ContentView: View {
    @ObservedObject var model: JobModel
    @StateObject private var buffer: BufferViewModel
    @State private var destination: JoeyDestination = .process
    @State private var selectedID: String?
    @State private var selectingJobs = false
    @State private var selectedJobIDs: Set<String> = []
    @State private var showingRemovedJobs = false
    @State private var showingDetail = true
    @State private var intake = false
    @State private var intakeURL = ""
    @State private var intakeContent: LinkContent = .dub
    @State private var settings = false
    @State private var assistant = false
    @State private var checkpointRecovery = false
    @State private var dropTargeted = false
    @AppStorage("joey.appearance") private var appearance = JoeyAppearance.light.rawValue
    @Environment(\.colorScheme) private var scheme
    private var selectedAppearance: JoeyAppearance {JoeyAppearance(rawValue:appearance) ?? .system}
    private var listedJobs: [JobRecord] {showingRemovedJobs && destination == .jobs ? model.removedJobs : model.visibleJobs}
    private var selectedJob: JobRecord? {JobPresentation.selectedJob(in:listedJobs,id:selectedID)}
    private var working: Bool {model.busy || model.libraryBusy || model.preparingSource}

    init(model: JobModel) {
        self.model = model
        _buffer = StateObject(wrappedValue:BufferViewModel(root:model.root))
    }

    var body: some View {
        GeometryReader { geometry in
            // Keep recovery notices and all panes inside the proposed window
            // viewport. Their intrinsic content must not enlarge its minimum.
            VStack(spacing:0) {
                if !model.checkpointFailures.isEmpty {checkpointNotice}
                // These thresholds come from the pane minimums, not a display's
                // half-screen size. macOS controls the actual tiled window bounds.
                if geometry.size.width >= 1100 {
                    HStack(spacing:0) {
                        sidebar.frame(width:220)
                        Divider()
                        panes
                    }
                } else {
                    VStack(spacing:0) {
                        compactNavigation(showDetailToggle:geometry.size.width < 900)
                        Divider()
                        if geometry.size.width >= 900 {
                            panes
                        } else if showingDetail && (selectedJob != nil || destination == .buffer) {
                            inspector
                        } else {
                            workspace
                        }
                    }
                }
            }.frame(width:geometry.size.width,height:geometry.size.height)
        }
        .font(JoeyTheme.font(16))
        .foregroundStyle(.primary)
        .background(JoeyTheme.background(scheme))
        .tint(JoeyTheme.primary(scheme))
        .frame(minWidth:440,minHeight:480)
        .sheet(isPresented:$checkpointRecovery) {checkpointRecoveryDetails}
        .preferredColorScheme(selectedAppearance.colorScheme)
        .onAppear {selectedAppearance.apply()}
        .onChange(of:appearance) {_,_ in selectedAppearance.apply()}
        .onChange(of:listedJobs.map(\.id)) {_,ids in selectedJobIDs.formIntersection(ids)}
        .onChange(of:destination) {_,_ in selectingJobs = false;selectedJobIDs = []}
        .sheet(isPresented:$intake) {
            NewJobView(model:model,initialURL:intakeURL,initialContent:intakeContent) {intake = false}
                .frame(width:760,height:700)
        }
        .sheet(isPresented:$settings) {
            VStack(spacing:0) {
                HStack {Text("Settings").font(.headline);Spacer();Button("Done") {settings = false}}.padding()
                Divider()
                JoeySettingsView(model:model,appearance:$appearance) {id in
                    selectedID = id;destination = .jobs;showingDetail = true;settings = false
                }
            }.frame(width:680,height:650)
        }
        .sheet(isPresented:$assistant) {AssistantView(mediaBusy:model.busy || model.libraryBusy)}
        .alert("Joey needs attention",isPresented:Binding(get:{model.error != nil},set:{if !$0 {model.error = nil}})) {
            Button("OK") {model.error = nil}
        } message: {Text(model.error ?? "")}
    }

    private var checkpointNotice: some View {
        VStack(alignment:.leading,spacing:8) {
            Label("History needs recovery",systemImage:"exclamationmark.circle").font(.headline)
            Text("\(model.checkpointFailures.count) saved checkpoint(s) need repair. Readable history remains available. New jobs wait for identity reconciliation.")
                .fixedSize(horizontal:false,vertical:true)
            HStack {
                Button("Recovery Details") {checkpointRecovery = true}
                Button("Refresh History") {Task {await model.refresh()}}
            }.controlSize(.small)
        }.font(JoeyTheme.font(12)).padding(12).frame(maxWidth:.infinity,alignment:.leading)
            .background(JoeyTheme.panel(scheme))
    }
    private var checkpointRecoveryDetails: some View {
        VStack(alignment:.leading,spacing:16) {
            Text("Saved checkpoint recovery").font(.title2)
            ScrollView {
                VStack(alignment:.leading,spacing:20) {
                    ForEach(model.checkpointFailures) {failure in
                        VStack(alignment:.leading,spacing:8) {
                            Text(failure.directoryID).font(.headline).textSelection(.enabled)
                            Text(failure.message).fixedSize(horizontal:false,vertical:true)
                            Button("Show Folder") {model.revealCheckpoint(failure)}
                        }
                    }
                    if model.checkpointFailures.isEmpty {Text("All saved checkpoints are readable.")}
                }.frame(maxWidth:.infinity,alignment:.leading)
            }
            HStack {
                Button("Refresh History") {Task {await model.refresh()}}
                Spacer()
                Button("Done") {checkpointRecovery = false}.keyboardShortcut(.cancelAction)
            }
        }.padding(24).frame(minWidth:360,idealWidth:620,maxWidth:620,minHeight:260,idealHeight:420)
    }

    private var panes: some View {
        HSplitView {
            workspace.frame(minWidth:380,maxWidth:.infinity,maxHeight:.infinity)
            inspector.frame(minWidth:350,idealWidth:400,maxWidth:500,maxHeight:.infinity)
        }
    }

    private func compactNavigation(showDetailToggle: Bool) -> some View {
        HStack(spacing:12) {
            Menu {
                ForEach(JoeyDestination.allCases,id:\.self) {item in
                    Button(item.rawValue,systemImage:item.symbol) {destination = item;showingDetail = false}
                }
                Divider()
                Button("Settings…") {settings = true}
                Button("Local Assistant…") {assistant = true}.disabled(working)
            } label: {Label("Navigate",systemImage:"sidebar.left")}
                .accessibilityLabel("Navigation and settings")
            Spacer(minLength:0)
            if showDetailToggle && (selectedJob != nil || destination == .buffer) {
                Button(showingDetail ? destination.workspaceNavigationTitle : (destination == .buffer ? "Handoff" : "Job Details"),systemImage:showingDetail ? "list.bullet" : "info.circle") {
                    showingDetail.toggle()
                }.accessibilityLabel(showingDetail ? destination.workspaceNavigationAccessibilityLabel : (destination == .buffer ? "Show Buffer handoff" : "Show selected job details"))
            }
        }.controlSize(.regular).padding(12)
    }

    private var sidebar: some View {
        VStack(alignment:.leading,spacing:36) {
            Text("Joey").font(JoeyTheme.font(38,weight:.bold)).tracking(-2).padding(.top,24)
            VStack(spacing:8) {
                ForEach(JoeyDestination.allCases,id:\.self) {item in
                    Button {destination = item;showingDetail = false} label: {
                        HStack(spacing:12) {
                            Image(systemName:item.symbol).font(.system(size:19)).frame(width:24)
                            Text(item.rawValue).font(JoeyTheme.font(16,weight:.medium)).fixedSize(horizontal:false,vertical:true)
                            Spacer(minLength:0)
                        }.padding(.horizontal,12).padding(.vertical,14)
                            .foregroundStyle(destination == item ? JoeyTheme.primary(scheme) : Color.primary)
                            .background(destination == item ? Color.primary.opacity(0.045) : Color.clear,in:RoundedRectangle(cornerRadius:4))
                            .overlay(alignment:.leading) {
                                if destination == item {Rectangle().fill(JoeyTheme.primary(scheme)).frame(width:2).padding(.vertical,12)}
                            }
                    }.buttonStyle(.plain).accessibilityAddTraits(destination == item ? .isSelected : [])
                }
            }
            Spacer()
            Menu {
                Button("Settings…") {settings = true}
                Button("Local Assistant…") {assistant = true}.disabled(working)
            } label: {Label("Settings",systemImage:"gearshape").font(JoeyTheme.font(12))}
                .menuStyle(.borderlessButton).fixedSize().foregroundStyle(.secondary)
            Label {
                Text(working ? "Working" : model.error != nil || !model.checkpointFailures.isEmpty ? "Needs attention" : "Ready")
            } icon: {
                Circle().fill(working || model.error != nil || !model.checkpointFailures.isEmpty ? Color.secondary : JoeyTheme.verified).frame(width:7,height:7)
            }.font(JoeyTheme.font(12)).foregroundStyle(.secondary)
        }.padding(.horizontal,18).padding(.bottom,24)
    }

    @ViewBuilder private var workspace: some View {
        if destination == .buffer {
            BufferReadyView(buffer:buffer,model:model)
        } else if destination == .shows {
            ShowsView(model:model) {url in openIntake(url,content:.joeBudden)}
        } else {
            ScrollView {
                VStack(alignment:.leading,spacing:28) {
                    if destination == .process {dropArea}
                    HStack {
                        Text(destination == .process ? "Recent jobs" : showingRemovedJobs ? "Removed jobs" : "Jobs").font(JoeyTheme.font(20,weight:.medium))
                        Spacer()
                        if destination == .jobs {
                            Menu {
                                Button(showingRemovedJobs ? "Show Queue" : "Show Removed Jobs") {
                                    showingRemovedJobs.toggle();selectedJobIDs = [];selectedID = nil;selectingJobs = false
                                }
                            } label: {Image(systemName:"ellipsis.circle")}
                                .accessibilityLabel("Job list options")
                            Button(selectingJobs ? "Done" : "Select") {
                                selectingJobs.toggle();selectedJobIDs = []
                            }.disabled(listedJobs.isEmpty || model.removingJobs)
                            if !selectingJobs && !showingRemovedJobs {
                                Button("Import Link",systemImage:"plus") {openIntake()}.disabled(working)
                            }
                        }
                    }
                    if selectingJobs {
                        HStack {
                            Button(selectedJobIDs.count == listedJobs.count ? "Deselect All" : "Select All") {
                                selectedJobIDs = selectedJobIDs.count == listedJobs.count ? [] : Set(listedJobs.map(\.id))
                            }.disabled(model.removingJobs)
                            Spacer()
                            Button(showingRemovedJobs ? "Restore Selected (\(selectedJobIDs.count))" : "Remove Selected (\(selectedJobIDs.count))") {
                                let ids = selectedJobIDs
                                if showingRemovedJobs {
                                    if model.restoreJobs(ids) {selectedJobIDs = []}
                                } else {
                                    Task {if await model.removeJobs(ids) {selectedJobIDs = []}}
                                }
                            }.disabled(selectedJobIDs.isEmpty || model.removingJobs || model.cancelling)
                        }.controlSize(.small)
                        Text(showingRemovedJobs ? "Restore returns jobs to the queue without starting them." : "Removal stops selected active jobs. Saved files, progress and Drive records are kept.")
                            .font(JoeyTheme.font(12)).foregroundStyle(.secondary)
                    }
                    if listedJobs.isEmpty {
                        Text(showingRemovedJobs ? "No removed jobs" : "No jobs in queue").foregroundStyle(.secondary).padding(.vertical,32)
                    } else {
                        LazyVStack(spacing:0) {
                            ForEach(destination == .process ? Array(listedJobs.prefix(8)) : listedJobs) {job in
                                HStack(spacing:8) {
                                    if selectingJobs {
                                        Toggle("Select \(job.request.title)",isOn:Binding(get:{selectedJobIDs.contains(job.id)},set:{checked in
                                            if checked {selectedJobIDs.insert(job.id)} else {selectedJobIDs.remove(job.id)}
                                        })).toggleStyle(.checkbox).labelsHidden()
                                            .accessibilityLabel("Select \(job.request.title)")
                                            .disabled(model.removingJobs)
                                    }
                                    JobRow(job:job,selected:selectingJobs ? selectedJobIDs.contains(job.id) : selectedJob?.id == job.id,isRunning:isRunning(job)) {
                                        if selectingJobs {
                                            if selectedJobIDs.contains(job.id) {selectedJobIDs.remove(job.id)} else {selectedJobIDs.insert(job.id)}
                                        } else {selectedID = job.id;showingDetail = true}
                                    }.disabled(model.removingJobs)
                                }
                                Divider()
                            }
                        }
                    }
                    if destination == .process && listedJobs.count > 8 {
                        Button("View all jobs") {destination = .jobs}.buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                }.padding(28)
            }
        }
    }

    private var dropArea: some View {
        Button {openIntake()} label: {
            VStack(spacing:18) {
                Image(systemName:"square.and.arrow.up").font(.system(size:38,weight:.light))
                Text("Drop a link or import").font(JoeyTheme.font(17,weight:.medium))
                Text("YouTube or X").font(JoeyTheme.font(12)).foregroundStyle(.secondary)
            }.frame(maxWidth:.infinity).frame(height:250)
                .background(dropTargeted ? JoeyTheme.primary(scheme).opacity(0.06) : Color.primary.opacity(0.015))
                .overlay(RoundedRectangle(cornerRadius:4).strokeBorder(Color.primary.opacity(dropTargeted ? 0.5 : 0.2),style:StrokeStyle(lineWidth:1,dash:[5,4])))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(working)
            .accessibilityLabel("Import a YouTube or X link")
            .onDrop(of:[UTType.url, UTType.plainText],isTargeted:$dropTargeted) {providers in
                guard !working, providers.count == 1, let provider = providers.first else {return false}
                if provider.canLoadObject(ofClass:NSURL.self) {
                    _ = provider.loadObject(ofClass:NSURL.self) {value,_ in
                        guard let value = value as? NSURL else {return}
                        let raw = (value as URL).absoluteString
                        Task { @MainActor in
                            guard !working else {return}
                            _ = acceptLink(raw)
                        }
                    }
                    return true
                }
                if provider.canLoadObject(ofClass:NSString.self) {
                    _ = provider.loadObject(ofClass:NSString.self) {value,_ in
                        guard let value = value as? NSString else {return}
                        let raw = value as String
                        Task { @MainActor in
                            guard !working else {return}
                            _ = acceptLink(raw)
                        }
                    }
                    return true
                }
                return false
            }
    }

    private func acceptLink(_ raw: String) -> Bool {
        do {
            let url = try Acquisition.validateOriginalURL(raw.trimmingCharacters(in:.whitespacesAndNewlines))
            openIntake(url.absoluteString)
            return true
        } catch {model.error = error.localizedDescription;return false}
    }
    private func openIntake(_ url: String = "", content: LinkContent = .dub) {intakeURL = url;intakeContent = content;intake = true}
    private func isRunning(_ job: JobRecord) -> Bool {
        model.isRunning(job)
    }
    @ViewBuilder private var inspector: some View {
        if destination == .buffer {
            BufferHandoffPanel(buffer:buffer,model:model)
        } else if let job = selectedJob {
            if model.removedJobIDs.contains(job.id) {
                VStack(spacing:16) {
                    Text(job.request.title).font(.headline)
                    Text("Removed from queue. Saved files and delivery records are kept.")
                    Button("Restore to Queue") {if model.restoreJobs([job.id]) {showingRemovedJobs = false;selectedID = job.id}}
                }.padding(28).frame(maxWidth:.infinity,maxHeight:.infinity)
            } else {
                JobDetailView(model:model,job:job,isRunning:isRunning(job),onPrepare:{buffer.episodeID = job.id;destination = .buffer;showingDetail = false})
                    .id(job.id)
            }
        } else {
            VStack(spacing:16) {
                Image(systemName:"film.stack").font(.system(size:30,weight:.light))
                Text("Select a job").font(JoeyTheme.font(18,weight:.medium))
                Text("Preview, progress and results").font(JoeyTheme.font(12)).foregroundStyle(.secondary)
            }.frame(maxWidth:.infinity,maxHeight:.infinity)
        }
    }
}

private struct JobRow: View {
    let job: JobRecord
    let selected: Bool
    let isRunning: Bool
    var select: () -> Void
    @Environment(\.colorScheme) private var scheme
    private var presentation: JobPresentation {JobPresentation(job:job)}
    var body: some View {
        Button(action:select) {
            HStack(spacing:14) {
                Image(systemName:job.source?.kind == .audio ? "waveform" : "film")
                    .font(.system(size:21,weight:.light)).frame(width:44,height:54)
                    .background(Color.primary.opacity(0.04),in:RoundedRectangle(cornerRadius:3))
                VStack(alignment:.leading,spacing:7) {
                    Text(job.request.title).font(JoeyTheme.font(18,weight:.medium)).lineLimit(2)
                    Text(presentation.status).font(JoeyTheme.font(11)).foregroundStyle(.secondary)
                    JobProgressView(presentation:presentation,isRunning:isRunning)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
                Spacer(minLength:0)
                if presentation.completed {Image(systemName:"checkmark.circle.fill").foregroundStyle(JoeyTheme.verified)}
                else if job.error != nil {Image(systemName:"exclamationmark.circle").foregroundStyle(.secondary)}
                else if isRunning {Circle().fill(Color.secondary).frame(width:7,height:7)}
            }.padding(.vertical,16).padding(.horizontal,10)
                .frame(maxWidth:.infinity,alignment:.leading)
                .background(selected ? Color.primary.opacity(0.035) : Color.clear)
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityElement(children:.ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {select()}
            .accessibilityLabel("\(job.request.title), \(presentation.status)")
            .accessibilityValue(presentation.total > 0 ? "\(presentation.accepted) of \(presentation.total) clips passed QA" : "No clips planned")
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct JobProgressView: View {
    let presentation: JobPresentation
    let isRunning: Bool
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(alignment:.leading,spacing:5) {
            if let progress = presentation.clipProgress {
                ProgressView(value:progress)
                    .progressViewStyle(JoeyMeasuredProgressStyle(color:presentation.completed ? JoeyTheme.verified : .secondary))
                    .accessibilityLabel("Clips passed automated QA")
                    .accessibilityValue("\(presentation.accepted) of \(presentation.total)")
                Text("QA · \(presentation.accepted)/\(presentation.total) clips").font(JoeyTheme.font(11)).foregroundStyle(.secondary).monospacedDigit()
            } else if isRunning {
                ProgressView().progressViewStyle(.linear).tint(.secondary)
                    .accessibilityLabel("Processing; clip count not yet available")
            } else {
                Text("No clips planned").font(JoeyTheme.font(11)).foregroundStyle(.secondary)
            }
        }
    }
}

/// macOS's native linear indicator can ignore tint. Keep the standard progress
/// accessibility semantics while drawing the measured fraction in our palette.
private struct JoeyMeasuredProgressStyle: ProgressViewStyle {
    let color: Color
    func makeBody(configuration: ProgressViewStyleConfiguration) -> some View {
        GeometryReader {geometry in
            ZStack(alignment:.leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule().fill(color).frame(width:geometry.size.width * min(1,max(0,configuration.fractionCompleted ?? 0)))
            }
        }.frame(height:5)
    }
}
