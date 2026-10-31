import SwiftUI

struct ContentView: View {
    @StateObject private var model = JobModel()
    @State private var newJob = false
    var body: some View {
        NavigationSplitView {
            List(selection:$model.selected) {
                Section("Jobs") {
                    ForEach(model.jobs) {job in
                        VStack(alignment:.leading,spacing:5) {
                            Text(job.request.title).font(.headline).lineLimit(2)
                            Text("\(job.request.owner.rawValue.uppercased()) · \(job.state.rawValue)")
                                .font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical,5).tag(job.id)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min:240,ideal:280,max:360)
            .navigationTitle("Joey")
            .toolbar {
                Button("New job",systemImage:"plus") {newJob = true}.disabled(model.busy)
                Menu("Setup",systemImage:"gearshape") {
                    Button("Import verified shared profile…") {model.importProfile()}
                    Button("Import job request…") {model.importJob()}.disabled(model.busy)
                    Button("Open local settings") {model.openSettings()}
                }
            }
        } detail: {
            if let job = model.jobs.first(where:{$0.id == model.selected}) {
                ScrollView {
                    VStack(alignment:.leading,spacing:18) {
                        Text(job.request.title).font(.largeTitle.bold())
                        Text("\(job.request.owner.rawValue.uppercased()) · \(job.request.sourceID)").foregroundStyle(.secondary).textSelection(.enabled)
                        HStack {
                            Label(job.state == .qaPassed && job.request.fileToDrive ? "QA_PASSED — NOT FILED" : job.state.rawValue,
                                  systemImage:job.state == .completed ? "checkmark.circle.fill":"clock")
                            if model.busy {ProgressView().controlSize(.small)}
                            Spacer()
                            if model.busy {Button("Cancel") {model.cancel()}}
                            else if job.state != .completed {Button("Resume") {model.start(job.request)}}
                            Button("Show files") {model.reveal(job)}
                        }
                        Text(job.stage).font(.headline)
                        if let error = job.error {Text(error).foregroundStyle(.red).textSelection(.enabled)}
                        if let source = job.source {
                            Text("\(source.kind == .nativeVideo ? "Native video":"Audio presentation") · \(source.duration, specifier:"%.2f") seconds · \(job.clips.count) clips")
                        }
                        if let folder = job.folderID, let url = URL(string:"https://drive.google.com/drive/folders/"+folder) {Link("Open episode folder",destination:url)}
                        Divider()
                        ForEach(job.clips) {clip in
                            VStack(alignment:.leading,spacing:7) {
                                Text("\(clip.id). \(clip.title)").font(.headline)
                                Text(clip.intervals.map {String(format:"%.3f–%.3f s",$0.start,$0.end)}.joined(separator:"; ")).monospacedDigit()
                                Text("Duration: \(clip.measuredDuration ?? clip.expectedDuration, specifier:"%.3f") s · QA: \(clip.qa?.passed == true ? "passed":"pending")").foregroundStyle(.secondary)
                                if let link = clip.drive?.url, let url = URL(string:link) {Link("Open verified clip",destination:url)}
                                if let qa = clip.qa {
                                    DisclosureGroup("Automatic checks") {
                                        ForEach(qa.checks.keys.sorted(),id:\.self) {key in Text("\(key): \(qa.checks[key]!)").font(.caption).textSelection(.enabled)}
                                    }
                                }
                            }.frame(maxWidth:.infinity,alignment:.leading).padding().background(.quaternary,in:RoundedRectangle(cornerRadius:12))
                        }
                    }.padding(28).frame(maxWidth:1000,alignment:.leading)
                }
            } else {
                ContentUnavailableView {
                    Label("Your media, ready to share",systemImage:"film.stack")
                } description: {
                    Text("Create shared X and Instagram clips from authorized DUB or Taxstone sources. Joey handles local processing, automatic checks and verified Drive filing.")
                } actions: {Button("New job") {newJob = true}.buttonStyle(.borderedProminent)}
            }
        }
        .frame(minWidth:960,minHeight:640)
        .sheet(isPresented:$newJob) {NewJobView(model:model,isPresented:$newJob)}
        .alert("Joey needs an input",isPresented:Binding(get:{model.error != nil},set:{if !$0 {model.error = nil}})) {
            Button("OK") {model.error = nil}
        } message: {Text(model.error ?? "")}
    }
}

private struct NewJobView: View {
    @ObservedObject var model: JobModel
    @Binding var isPresented: Bool
    @State private var owner: Owner = .dub
    @State private var mode: JobMode = .fullShow
    @State private var path = ""
    @State private var url = ""
    @State private var title = ""
    @State private var sourceID = ""
    @State private var authorization = ""
    @State private var archive = ""
    @State private var count = 10
    @State private var transcript = ""
    @State private var file = true
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            Text("New media job").font(.title.bold())
            Form {
                Picker("Owner",selection:$owner) {Text("DUB").tag(Owner.dub);Text("Taxstone").tag(Owner.taxstone)}
                HStack {TextField("Local original",text:$path);Button("Choose…") {if let p = model.chooseFile() {path = p}}}
                TextField("Original YouTube / X URL",text:$url)
                TextField("Stable source ID",text:$sourceID)
                TextField("Source title",text:$title)
                TextField("Authorization basis",text:$authorization)
                TextField("Existing full-length archive link",text:$archive)
                Picker("Coverage",selection:$mode) {Text("Full show").tag(JobMode.fullShow);Text("Highlights").tag(JobMode.highlights)}
                if mode == .highlights {Stepper("Highlights: \(count)",value:$count,in:1...100)}
                HStack {TextField("Existing full transcript (optional)",text:$transcript);Button("Choose…") {if let p = model.chooseFile() {transcript = p}}}
                Toggle("File verified outputs to Joey’s Drive folders",isOn:$file)
            }.formStyle(.grouped)
            if let profile = model.configuration?.profile {
                Text("Shared profile: \(profile.width)×\(profile.height), up to \(profile.maxDuration,specifier:"%.0f") seconds. Full-show planning uses natural boundaries up to ten minutes within this limit.").font(.caption).foregroundStyle(.secondary)
            } else {
                Label("Verified X and Instagram account/upload settings are required.",systemImage:"exclamationmark.circle").foregroundStyle(.orange)
                Button("Import verified shared profile…") {model.importProfile()}
            }
            HStack {
                Button("Cancel") {isPresented = false}; Spacer()
                Button("Start job") {
                    guard let profile = model.configuration?.profile else {return}
                    let request = JobRequest(owner:owner,sourceID:sourceID,title:title,originalURL:url.isEmpty ? nil:url,
                        localPath:path.isEmpty ? nil:path,authorizationBasis:authorization,archiveReference:archive.isEmpty ? nil:archive,
                        mode:mode,requestedCount:mode == .highlights ? count:nil,transcriptPath:transcript.isEmpty ? nil:transcript,profile:profile,fileToDrive:file)
                    model.start(request); isPresented = false
                }.buttonStyle(.borderedProminent).disabled(model.configuration?.profile == nil || sourceID.isEmpty || title.isEmpty || authorization.isEmpty || (path.isEmpty && url.isEmpty))
            }
        }.padding(24).frame(width:680,height:720)
    }
}
