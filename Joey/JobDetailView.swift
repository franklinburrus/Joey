import SwiftUI
import AVKit

/// Persistent inspector. All numbers and stage markers come from the saved job.
struct JobDetailView: View {
    @ObservedObject var model: JobModel
    let job: JobRecord
    let isRunning: Bool
    var onPrepare: (() -> Void)? = nil
    @Environment(\.colorScheme) private var scheme
    @State private var resumeIssue: String? = "Checking saved requirements…"
    @State private var productionSetup = false
    @State private var capabilityDetails: [String] = []
    private var presentation: JobPresentation {JobPresentation(job:job)}
    private var sourceLabel: String {
        job.source.map {URL(fileURLWithPath:$0.path).lastPathComponent} ?? job.request.originalURL ?? job.request.sourceID
    }
    private var previewURL: URL? {
        // An accepted audio MP4 already contains its real waveform. Never draw
        // a synthetic waveform over native video or pretend artwork is playback.
        if let source = job.source, source.kind == .nativeVideo,
           FileManager.default.fileExists(atPath:source.path) {return URL(fileURLWithPath:source.path)}
        if let clip = job.clips.first(where:{$0.qa?.passed == true}) {
            let url = model.root.appendingPathComponent("jobs/\(job.id)/\(clip.filename)")
            if FileManager.default.fileExists(atPath:url.path) {return url}
        }
        return nil
    }
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                VStack(alignment:.leading,spacing:7) {
                    Text(job.request.productionWorkflow == .joeBudden ? "Joe Budden" : job.request.owner == .dub ? "DUB" : "Taxstone")
                        .font(JoeyTheme.font(30,weight:.bold)).tracking(-0.8)
                    // Selectable Text can retain an older native accessibility
                    // value. Recreate only changed text, preserving the preview.
                    Text(job.request.title).font(JoeyTheme.font(16)).textSelection(.enabled).id(job.request.title)
                    Text(presentation.status).font(JoeyTheme.font(12)).foregroundStyle(presentation.completed ? JoeyTheme.verified : .secondary)
                }
                if !presentation.completed && !isRunning {
                    attention
                    controls
                } else if isRunning {
                    controls
                }
                JobPreview(url:previewURL,isAudio:job.source?.kind == .audio)
                    .aspectRatio(16.0 / 9,contentMode:.fit)
                VStack(alignment:.leading,spacing:10) {
                    Text(presentation.stage).font(JoeyTheme.font(13,weight:.medium))
                    JobProgressView(presentation:presentation,isRunning:isRunning)
                }
                VStack(alignment:.leading,spacing:14) {
                    ForEach(presentation.stages) {stage in
                        HStack(alignment:.top,spacing:12) {
                            Image(systemName:stage.verified ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(stage.verified ? JoeyTheme.verified : isRunning && presentation.activeStageID == stage.id ? JoeyTheme.primary(scheme) : .secondary)
                                .font(.system(size:13)).frame(width:15)
                            VStack(alignment:.leading,spacing:3) {
                                Text(stage.title).font(JoeyTheme.font(12,weight:.medium))
                                Text(stage.detail).font(JoeyTheme.font(11)).foregroundStyle(.secondary)
                            }
                        }.accessibilityElement(children:.combine)
                    }
                }
                if presentation.completed {controls}
                Divider()
                metadata
                Divider()
                results
            }.padding(24)
        }.background(JoeyTheme.panel(scheme))
        .task(id:job.id + String(job.updatedAt.timeIntervalSince1970)) {
            while !Task.isCancelled {
                checkResume()
                do {try await Task.sleep(nanoseconds:30_000_000_000)} catch {return}
            }
        }
        .onReceive(model.$configuration) {_ in checkResume()}
        .onReceive(NotificationCenter.default.publisher(for:NSApplication.didBecomeActiveNotification)) {_ in checkResume()}
        .sheet(isPresented:$productionSetup,onDismiss:checkResume) {
            ProductionSetupView(model:model,owner:job.request.owner)
        }
    }
    private func checkResume() {
        guard !isRunning else {return}
        resumeIssue = presentation.completed ? nil : model.resumeIssue(for:job)
        capabilityDetails = presentation.completed ? [] : model.resumeDiagnostics(for:job)
    }
    @ViewBuilder private var attention: some View {
        if let issue = resumeIssue {
            VStack(alignment:.leading,spacing:10) {
                Label("Needs attention",systemImage:"exclamationmark.circle")
                    .font(JoeyTheme.font(13,weight:.medium))
                Text(issue).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
                Text("Accepted clips and saved progress are retained.").foregroundStyle(.secondary)
                ViewThatFits(in:.horizontal) {
                    HStack {
                        Button("Production Setup…") {productionSetup = true}
                        Button("Check Again",action:checkResume)
                    }
                    VStack(alignment:.leading,spacing:8) {
                        Button("Production Setup…") {productionSetup = true}
                        Button("Check Again",action:checkResume)
                    }
                }
            }.font(JoeyTheme.font(12)).controlSize(.small)
        } else if job.error != nil {
            VStack(alignment:.leading,spacing:8) {
                Label(job.stage == "capability verification" ? "Requirements ready to recheck" : "Progress saved",systemImage:"info.circle")
                if job.stage == "capability verification" {
                    Text("Current evidence supports the saved contract. Resume rechecks the checkpoint and continues missing work.")
                } else {
                    Text(job.error ?? "").textSelection(.enabled)
                    Text(presentation.recovery)
                }
            }.font(JoeyTheme.font(12))
        }
        if !capabilityDetails.isEmpty {
            DisclosureGroup("Capability details") {
                VStack(alignment:.leading,spacing:8) {
                    ForEach(capabilityDetails,id:\.self) {detail in
                        Text(detail).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
                    }
                }.padding(.top,8)
            }.font(JoeyTheme.font(11))
        }
        if let error = job.error {
            DisclosureGroup("Previous attempt diagnostics") {
                Text(error).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
            }.font(JoeyTheme.font(11))
        }
    }
    private var controls: some View {
        VStack(alignment:.leading,spacing:10) {
            if isRunning {
                Button("Cancel and Save Progress",systemImage:"stop.circle") {model.cancel()}
                    .help("Stops this attempt. Resume reuses accepted clips and saved progress.")
            } else if !presentation.completed {
                Button("Resume",systemImage:"play") {
                    checkResume()
                    if resumeIssue == nil {model.resume(job)}
                }
                    .disabled(resumeIssue != nil || model.busy || model.libraryBusy || model.preparingSource)
                    .help(resumeIssue ?? "Rechecks the saved job and reuses accepted clips and verified delivery records.")
            }
            ViewThatFits(in:.horizontal) {
                HStack {
                    Button("Open Clips") {model.openClips(job)}.disabled(presentation.accepted == 0)
                    Button("Report") {model.openReport(job)}.disabled(!model.hasReport(job))
                }
                VStack(alignment:.leading,spacing:8) {
                    Button("Open Clips") {model.openClips(job)}.disabled(presentation.accepted == 0)
                    Button("Report") {model.openReport(job)}.disabled(!model.hasReport(job))
                }
            }
        }.controlSize(.small)
    }
    private var metadata: some View {
        VStack(alignment:.leading,spacing:12) {
            Text("Source").font(JoeyTheme.font(13,weight:.medium))
            Text(sourceLabel)
                .font(JoeyTheme.font(12)).textSelection(.enabled).lineLimit(3).id(sourceLabel)
            LabeledContent("Workflow",value:job.request.mode == .fullShow ? "Clip Entire Show" : "Highlights")
            if let source = job.source {
                LabeledContent("Duration",value:Duration.seconds(source.duration).formatted(.time(pattern:.hourMinuteSecond)))
                LabeledContent("Media",value:source.kind == .audio ? "Audio · waveform MP4" : "Native video")
                if source.width > 0 {LabeledContent("Source size",value:"\(source.width) × \(source.height)")}
            }
            LabeledContent("Output",value:job.request.profile.isDriveOnly ? "Drive MP4" : "Shared X + Instagram MP4")
            LabeledContent("Updated",value:job.updatedAt.formatted(date:.abbreviated,time:.shortened))
            DisclosureGroup("Source details") {
                VStack(alignment:.leading,spacing:10) {
                    Text(job.request.sourceID)
                    Text("Saved state: \(job.state.rawValue) · \(job.stage)")
                    if let source = job.source {
                        if let output = try? job.request.profile.outputProfile(for:source.kind) {
                            Text("Export: \(output.width) × \(output.height)")
                        } else {
                            Text("Export: unavailable for the saved source and capability profile")
                        }
                        Text("SHA-256: \(source.sha256)")
                        Text(source.authorizationBasis)
                    } else {
                        Text("Export: pending source inspection")
                    }
                    if !job.unavailableTranscriptFeatures.isEmpty {
                        Text("Unavailable: " + job.unavailableTranscriptFeatures.joined(separator:"; "))
                    }
                    Text("Platform ingestion unverified. Nothing published or scheduled.")
                    Button("Show Local Files") {model.reveal(job)}
                }.padding(.top,10).textSelection(.enabled)
            }
        }.font(JoeyTheme.font(11)).foregroundStyle(.secondary)
    }
    private var results: some View {
        VStack(alignment:.leading,spacing:14) {
            Text("Results").font(JoeyTheme.font(13,weight:.medium))
            if presentation.completed, let onPrepare {Button("Prepare for Buffer",action:onPrepare)}
            LabeledContent("QA passed",value:"\(presentation.accepted)/\(presentation.total)")
            LabeledContent("Drive",value:presentation.deliveryStatus)
            Text(presentation.recordStatus).foregroundStyle(.secondary)
            if let folder = job.folderID, let url = URL(string:"https://drive.google.com/drive/folders/"+folder) {
                Link("Episode folder",destination:url)
            }
            if !job.clips.isEmpty {
                DisclosureGroup("Clips (\(job.clips.count))") {
                    LazyVStack(alignment:.leading,spacing:18) {
                        ForEach(job.clips) {clip in
                            VStack(alignment:.leading,spacing:7) {
                                Text("\(clip.id). \(clip.title)").font(JoeyTheme.font(12,weight:.medium))
                                Text(clip.intervals.map {String(format:"%.3f–%.3f s",$0.start,$0.end)}.joined(separator:"; ")).monospacedDigit()
                                Text("\(clip.measuredDuration ?? clip.expectedDuration,specifier:"%.3f") seconds · QA \(clip.qa?.passed == true ? "passed" : "pending")")
                                if let exception = clip.durationException {Text(exception).foregroundStyle(.secondary)}
                                if let error = clip.error {Text(error)}
                                HStack {
                                    if clip.qa?.passed == true {Button("Open Clip") {model.revealClip(job,clip)}}
                                    if let link = clip.drive?.url, let url = URL(string:link) {Link("Drive",destination:url)}
                                }
                                if let qa = clip.qa {
                                    DisclosureGroup("Automatic Checks") {
                                        ForEach(qa.checks.keys.sorted(),id:\.self) {key in Text("\(key): \(qa.checks[key]!)").textSelection(.enabled)}
                                    }
                                }
                            }
                        }
                    }.padding(.top,12)
                }
            }
        }.font(JoeyTheme.font(11)).controlSize(.small)
    }
}

private struct JobPreview: View {
    let url: URL?
    let isAudio: Bool
    @State private var player: AVPlayer?
    var body: some View {
        Group {
            if let player {
                VideoPlayer(player:player).accessibilityLabel(isAudio ? "Rendered audio clip with source-driven waveform" : "Source video preview")
            } else {
                VStack(spacing:10) {
                    Image(systemName:isAudio ? "waveform" : "film").font(.system(size:26,weight:.light))
                    Text(isAudio ? "Preview after first verified clip" : "Preview unavailable")
                        .font(JoeyTheme.font(11))
                }.foregroundStyle(.secondary).frame(maxWidth:.infinity,maxHeight:.infinity)
                    .background(Color.primary.opacity(0.035))
            }
        }.clipShape(RoundedRectangle(cornerRadius:4))
            .task(id:url) {player?.pause();player = url.map {AVPlayer(url:$0)}}
            .onDisappear {player?.pause()}
    }
}
