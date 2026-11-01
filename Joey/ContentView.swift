import SwiftUI
import UniformTypeIdentifiers

private enum JoeyDestination: String, CaseIterable {
    case process = "Process", jobs = "Jobs", shows = "Shows", buffer = "Ready for Buffer"
    var symbol: String {
        switch self {case .process: return "record.circle"; case .jobs: return "list.bullet.rectangle"; case .shows: return "mic";case .buffer:return "square.and.arrow.up"}
    }
}

struct ContentView: View {
    @ObservedObject var model: JobModel
    @StateObject private var buffer: BufferViewModel
    @State private var destination: JoeyDestination = .process
    @State private var selectedID: String?
    @State private var intake = false
    @State private var intakeURL = ""
    @State private var intakeContent: LinkContent = .dub
    @State private var settings = false
    @State private var assistant = false
    @State private var dropTargeted = false
    @AppStorage("joey.appearance") private var appearance = JoeyAppearance.light.rawValue
    @Environment(\.colorScheme) private var scheme
    private var selectedAppearance: JoeyAppearance {JoeyAppearance(rawValue:appearance) ?? .system}
    private var selectedJob: JobRecord? {JobPresentation.selectedJob(in:model.jobs,id:selectedID)}
    private var working: Bool {model.busy || model.libraryBusy || model.preparingSource}

    init(model: JobModel) {
        self.model = model
        _buffer = StateObject(wrappedValue:BufferViewModel(root:model.root))
    }

    var body: some View {
        HStack(spacing:0) {
            sidebar.frame(width:220)
            Divider()
            HSplitView {
                workspace.frame(minWidth:420,maxWidth:.infinity,maxHeight:.infinity)
                inspector.frame(minWidth:350,idealWidth:400,maxWidth:500,maxHeight:.infinity)
            }
        }
        .font(JoeyTheme.font(16))
        .foregroundStyle(.primary)
        .background(JoeyTheme.background(scheme))
        .tint(JoeyTheme.primary(scheme))
        .frame(minWidth:1040,minHeight:660)
        .preferredColorScheme(selectedAppearance.colorScheme)
        .onAppear {selectedAppearance.apply()}
        .onChange(of:appearance) {_,_ in selectedAppearance.apply()}
        .sheet(isPresented:$intake) {
            NewJobView(model:model,initialURL:intakeURL,initialContent:intakeContent) {intake = false}
                .frame(width:760,height:700)
        }
        .sheet(isPresented:$settings) {
            VStack(spacing:0) {
                HStack {Text("Settings").font(.headline);Spacer();Button("Done") {settings = false}}.padding()
                Divider()
                JoeySettingsView(model:model,appearance:$appearance)
            }.frame(width:680,height:650)
        }
        .sheet(isPresented:$assistant) {AssistantView(mediaBusy:model.busy || model.libraryBusy)}
        .alert("Joey needs attention",isPresented:Binding(get:{model.error != nil},set:{if !$0 {model.error = nil}})) {
            Button("OK") {model.error = nil}
        } message: {Text(model.error ?? "")}
    }

    private var sidebar: some View {
        VStack(alignment:.leading,spacing:36) {
            Text("Joey").font(JoeyTheme.font(38,weight:.bold)).tracking(-2).padding(.top,24)
            VStack(spacing:8) {
                ForEach(JoeyDestination.allCases,id:\.self) {item in
                    Button {destination = item} label: {
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
                Text(working ? "Working" : model.error != nil ? "Needs attention" : "Ready")
            } icon: {
                Circle().fill(working || model.error != nil ? Color.secondary : JoeyTheme.verified).frame(width:7,height:7)
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
                        Text(destination == .process ? "Recent jobs" : "Jobs").font(JoeyTheme.font(20,weight:.medium))
                        Spacer()
                        if destination == .jobs {
                            Button("Import Link",systemImage:"plus") {openIntake()}.disabled(working)
                        }
                    }
                    if model.jobs.isEmpty {
                        Text("No jobs yet").foregroundStyle(.secondary).padding(.vertical,32)
                    } else {
                        LazyVStack(spacing:0) {
                            ForEach(destination == .process ? Array(model.jobs.prefix(8)) : model.jobs) {job in
                                JobRow(job:job,selected:selectedJob?.id == job.id,isRunning:isRunning(job)) {selectedID = job.id}
                                Divider()
                            }
                        }
                    }
                    if destination == .process && model.jobs.count > 8 {
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
        (model.busy && model.jobs.first?.id == job.id) ||
        (model.libraryBusy && model.taxstoneLibrary.currentSourceID == job.request.sourceID && job.state != .completed)
    }
    @ViewBuilder private var inspector: some View {
        if destination == .buffer {
            BufferHandoffPanel(buffer:buffer,model:model)
        } else if let job = selectedJob {
            JobDetailView(model:model,job:job,isRunning:isRunning(job),onPrepare:{buffer.episodeID = job.id;destination = .buffer})
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
