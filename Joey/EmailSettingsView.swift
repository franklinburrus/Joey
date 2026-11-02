import SwiftUI
import AppKit

struct EmailSettingsView: View {
    @ObservedObject var model: EmailIntakeModel
    var selectJob: (String) -> Void
    @State private var settings = EmailIntakeSettings()
    @State private var senders = ""
    @State private var password = ""
    @State private var template = ""
    @State private var templateError: String?
    @State private var confirmBaseline = false

    var body: some View {
        JoeyPanel {
            VStack(alignment:.leading,spacing:14) {
                Text("iCloud Email Intake").font(.headline)
                Text(EmailIntakeSettings.alias).font(.body.monospaced()).textSelection(.enabled)
                Text("Send new messages directly to this alias in To or Cc, from an allowed address, with your secret Joey token. Joey checks INBOX while the app and Mac are awake. Mail moved by another client before a check may be missed.")
                    .font(.callout).foregroundStyle(.secondary)
                Text("Email only saves links. Choose Content and Workflow for a queued link, then click Process when ready.")
                    .font(.callout)
                Label(model.state.enabled ? "Email intake enabled":"Email intake paused",systemImage:model.state.enabled ? "checkmark.circle.fill":"pause.circle")
                    .foregroundStyle(model.state.enabled ? .green:.secondary)
                LabeledContent("Pending intake",value:String(model.state.pendingCount))
                LabeledContent("Last saved mailbox check",value:model.state.lastCheckedAt?.formatted() ?? "Not checked")
                if let status = model.connectionStatus {Text(status).font(.callout).textSelection(.enabled)}
                if let error = model.error {Text(error).foregroundStyle(.red).textSelection(.enabled)}
                else if let code = model.state.lastError {Text(MailCheckFailure.message(code)).foregroundStyle(.red).textSelection(.enabled)}
                HStack {
                    Button("Test Connection") {model.testConnection()}.disabled(model.checking || model.state.settings.account.isEmpty)
                    Button(model.state.enabled ? "Pause":"Enable") {
                        if model.state.enabled {model.pause()} else {model.enable()}
                    }.disabled(model.checking || model.state.settings.account.isEmpty || model.state.requiresResynchronization)
                    Button("Check Now") {model.checkNow()}.disabled(model.checking || !model.state.enabled || model.state.requiresResynchronization)
                    if model.checking {ProgressView().controlSize(.small)}
                }
                if model.state.requiresResynchronization {
                    Button("Establish New-Mail Baseline…") {confirmBaseline = true}
                        .disabled(model.checking)
                }
                VStack(alignment:.leading,spacing:16) {
                    Text("Queued Links").font(.headline)
                    let pending = model.state.work.filter {$0.status != .completed}
                    if pending.isEmpty {Text("No queued links.").foregroundStyle(.secondary)}
                    ForEach(pending) {work in
                        EmailQueuedLinkView(model:model,work:work,selectJob:selectJob)
                        Divider()
                    }
                }
                DisclosureGroup("Connection and Email Template") {
                    VStack(alignment:.leading,spacing:12) {
                        Text("The app-specific password accesses the parent mailbox, not only this alias. Joey uses read-only IMAP and never sends, moves, marks or deletes mail. Use a separate app-specific password from your Apple Account; never enter your main account password.")
                            .font(.callout)
                        TextField("Primary iCloud Mail address",text:$settings.account)
                            .textContentType(.username).autocorrectionDisabled()
                        SecureField("App-specific password (leave blank to retain)",text:$password)
                        TextField("Allowed senders, separated by commas",text:$senders,axis:.vertical)
                            .autocorrectionDisabled()
                        Button("Save Secure Setup") {
                            settings.allowedSenders = senders.components(separatedBy:CharacterSet(charactersIn:",;\n")).filter {!$0.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty}
                            model.saveSetup(settings,password:password)
                            password = "";template = ""
                        }.disabled(model.checking)
                        HStack {
                            Button(template.isEmpty ? "Show Email Template":"Hide Email Template") {
                                if !template.isEmpty {template = "";return}
                                do {template = try model.template();templateError = nil} catch {templateError = error.localizedDescription}
                            }
                            Button("Replace Intake Token") {template = "";model.rotateToken()}.disabled(model.checking)
                        }
                        if !template.isEmpty {
                            Text("Keep this token private. Save the body in your own email template; anyone with the token and an allowed From address can authorize intake. Replacing it invalidates old templates.").font(.callout)
                            Text(template).font(.body.monospaced()).textSelection(.enabled)
                                .padding(12).background(.quaternary,in:RoundedRectangle(cornerRadius:8))
                        }
                        if let templateError {Text(templateError).foregroundStyle(.red)}
                        Link("Create or revoke an Apple app-specific password",destination:URL(string:"https://account.apple.com/")!)
                        Button("Disconnect") {password = "";template = "";model.disconnect()}
                    }.padding(.top,12)
                }
                DisclosureGroup("Pending Authorization and Recent Receipts") {
                    VStack(alignment:.leading,spacing:16) {
                        if model.state.receipts.isEmpty {Text("No new email receipts saved.")}
                        ForEach(model.displayedReceipts) {receipt in
                            VStack(alignment:.leading,spacing:6) {
                                Text(receipt.receivedAt.formatted()).font(.callout)
                                Text(receipt.status == "queued" ? "Links saved to queue":receipt.status).font(.subheadline.bold())
                                Text(MailCheckFailure.message(receipt.reason)).font(.callout)
                                ForEach(receipt.sources,id:\.id) {source in Text(source.url).font(.caption).textSelection(.enabled)}
                                ForEach(receipt.workIDs,id:\.self) {id in
                                    if let work = model.state.work.first(where:{$0.id == id}) {
                                        Text("Job: \(work.status.rawValue)").font(.callout.bold())
                                        if let reason = work.reason {Text(reason).font(.callout).textSelection(.enabled)}
                                        if let jobID = work.jobID {
                                            Button("Open Job") {selectJob(jobID)}
                                        }
                                    }
                                }
                                if receipt.status == "pendingAuthorization" {
                                    Button("Dismiss Local Receipt") {model.dismiss(receipt.id)}
                                }
                            }
                            Divider()
                        }
                    }.padding(.top,12)
                }
                Text("Up to 10 distinct links per message, 1 MiB per message and 100 pending items. Intake is separate from media completion. No outgoing email or social publication.")
                    .font(.caption).foregroundStyle(.secondary)
            }.disabled(!model.available)
        }
        .onAppear {settings = model.state.settings;senders = settings.allowedSenders.joined(separator:", ")}
        .onDisappear {password = "";template = ""}
        .confirmationDialog("Start a fresh INBOX baseline?",isPresented:$confirmBaseline) {
            Button("Exclude Existing Mail and Enable") {model.enable(rebaseline:true)}
        } message: {
            Text("Saved receipts and jobs remain. Existing INBOX messages will not be replayed. Resend any uncaptured source links as fresh mail after enabling.")
        }
    }
}

private struct EmailQueuedLinkView: View {
    @ObservedObject var model: EmailIntakeModel
    let work: EmailWork
    var selectJob: (String) -> Void
    @State private var workflow = EmailWorkflow()

    private var requested: Bool {work.processingRequested == true}
    private var active: Bool {work.status == .running || requested}

    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            Text(work.source.url).font(.callout).textSelection(.enabled)
            Text(work.status == .running ? "Processing" : requested ? "Waiting for the current job to finish" : work.status == .cancelled ? "Cancelled — saved for retry" : "Saved — waiting for you")
                .font(.subheadline.bold())
            if let reason = work.reason {Text(reason).font(.callout).textSelection(.enabled)}
            if work.request == nil {
                Picker("Content",selection:$workflow.content) {
                    Text("DUB").tag(LinkContent.dub)
                    Text("Taxstone").tag(LinkContent.taxstone)
                    Text("Joe Budden").tag(LinkContent.joeBudden)
                }.disabled(active)
                Picker("Workflow",selection:$workflow.mode) {
                    Text("Full Show").tag(JobMode.fullShow)
                    Text("Highlights").tag(JobMode.highlights)
                }.disabled(active || workflow.content == .joeBudden)
                Text("Drive destinations resolve automatically from the source and content owner.").font(.caption)
                Text("Uses existing production profiles, automatic QA and Drive filing. Official Joe Budden episodes keep their Joe workflow.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Saved workflow retained. Retry reuses the existing request and accepted work.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                Button(work.status == .retryable || work.status == .cancelled ? "Retry":"Process") {
                    model.process(work.id,workflow:workflow)
                }.disabled(active)
                Button("Cancel Queued Link") {model.cancelWork(work.id)}
                    .disabled(!work.canCancelFromQueue)
                    .help("Free this queue slot while retaining the saved link and any accepted work.")
                if let jobID = work.jobID {Button("Open Job") {selectJob(jobID)}}
            }
        }
        .onAppear {workflow = work.workflow}
        .onChange(of:work.workflow) {_,value in workflow = value}
        .onChange(of:workflow.content) {_,value in if value == .joeBudden {workflow.mode = .fullShow}}
    }
}
