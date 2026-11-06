#if SWIFT_PACKAGE
import JoeyCore
#endif
import SwiftUI

/// Native entry for the existing capability contract. This records evidence;
/// it does not infer eligibility from an encoder setting or a successful render.
struct ProductionSetupView: View {
    @ObservedObject var model: JobModel
    let owner: Owner
    @Environment(\.dismiss) private var dismiss
    @State private var x: SurfaceCapability
    @State private var instagram: SurfaceCapability
    @State private var error: String?

    init(model: JobModel, owner: Owner) {
        self.model = model;self.owner = owner
        let selectedProfile = owner == .taxstone ? model.configuration?.taxstoneProfile : model.configuration?.profile
        func empty(_ platform: String) -> SurfaceCapability {
            SurfaceCapability(platform:platform,account:"",surface:"",checkedAt:Date(),validUntil:Date(),
                maxDuration:0,maxBytes:0,maxWidth:0,maxHeight:0,maxFPS:0,officialURLs:[],
                accountEvidence:EvidenceFile(path:"",sha256:"",basis:""))
        }
        _x = State(initialValue:selectedProfile?.x ?? empty("X"))
        _instagram = State(initialValue:selectedProfile?.instagram ?? empty("Instagram"))
    }
    func persist(profile: SharedProfile) throws {try model.saveProfile(profile,owner:owner)}
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            Text(owner == .taxstone ? "Taxstone production setup" : "DUB production setup").font(.title.bold())
            Text("Record current limits for your actual accounts and upload surfaces. Attach existing account evidence and official sources. Encoder tests do not prove account eligibility. Native video uses a 1920×1080 landscape canvas; audio uses the approved portrait canvas. Each clip has one shared X/Instagram file and must fit both surfaces. No JSON is required.")
                .font(.callout)
            TabView {
                capabilityForm($x).tabItem {Text("X account")}
                capabilityForm($instagram).tabItem {Text("Instagram surface")}
                VStack(alignment:.leading,spacing:16) {
                    Text("Uses the existing authorized dubdrive connection and Joey destinations. No new account, permission change or competing register.")
                    Text("DUB delivery requires editable access to the existing Master Link List and Sheets API enabled for its OAuth project. Full Drive scope is supported; a separate Sheets scope is not automatically required.")
                    Button(model.checkingDelivery ? "Checking…":"Check existing connection") {model.checkDelivery()}
                        .disabled(model.checkingDelivery)
                    if let result = model.deliveryCheck {ScrollView {Text(result).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)}}
                    Spacer()
                }.padding().tabItem {Text("Drive and register")}
            }
            if let error {Text(error).foregroundStyle(.red).textSelection(.enabled)}
            HStack {
                Button("Close") {dismiss()}
                Spacer()
                Button("Save verified profile") {
                    do {
                        guard !x.accountEvidence.path.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,
                              !instagram.accountEvidence.path.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else {
                            throw JoeyError.dependency("Choose actual X and Instagram account evidence files before saving. No profile was saved.")
                        }
                        var checkedX = x, checkedInstagram = instagram
                        checkedX.accountEvidence.sha256 = try Integrity.sha256(URL(fileURLWithPath:x.accountEvidence.path))
                        checkedInstagram.accountEvidence.sha256 = try Integrity.sha256(URL(fileURLWithPath:instagram.accountEvidence.path))
                        let profile = try SharedProfile.select(x:checkedX,instagram:checkedInstagram)
                        try persist(profile:profile)
                        dismiss()
                    } catch {self.error = error.localizedDescription}
                }.buttonStyle(.borderedProminent)
            }
        }.padding(24).frame(width:740,height:740)
    }
    private func capabilityForm(_ capability: Binding<SurfaceCapability>) -> some View {
        Form {
            TextField("Account / handle",text:capability.account)
            TextField("Upload surface",text:capability.surface)
            DatePicker("Evidence checked",selection:capability.checkedAt)
            DatePicker("Evidence valid until",selection:capability.validUntil)
            TextField("Maximum duration (seconds)",value:capability.maxDuration,format:.number)
            TextField("Maximum file size (bytes)",value:capability.maxBytes,format:.number)
            TextField("Maximum width (pixels)",value:capability.maxWidth,format:.number)
            TextField("Maximum height (pixels)",value:capability.maxHeight,format:.number)
            TextField("Maximum frame rate",value:capability.maxFPS,format:.number)
            TextField("Official sources (one HTTPS URL per line)",text:Binding(
                get:{capability.wrappedValue.officialURLs.joined(separator:"\n")},
                set:{capability.wrappedValue.officialURLs = $0.split(whereSeparator: \.isNewline).map(String.init)}),axis:.vertical)
            HStack {
                TextField("Account evidence file",text:capability.accountEvidence.path)
                Button("Choose evidence…") {model.chooseFile {if let path = $0 {capability.wrappedValue.accountEvidence.path = path}}}
            }
            TextField("What this evidence establishes",text:capability.accountEvidence.basis,axis:.vertical)
            Text("Use actual account/upload evidence, never a synthetic fixture. Keep the selected evidence file available; its hash is checked again before processing.").font(.caption)
        }.formStyle(.grouped)
    }
}
