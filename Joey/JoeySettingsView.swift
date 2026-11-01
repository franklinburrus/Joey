import SwiftUI

struct JoeySettingsView: View {
    @ObservedObject var model: JobModel
    @Binding var appearance: String
    @Environment(\.colorScheme) private var scheme
    @State private var production = false
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:24) {
                Text("Settings").font(.largeTitle.bold())
                JoeyPanel {
                    Text("Storage").font(.headline)
                    if let storage = model.storage {
                        LabeledContent("Available Disk Space",value:ByteCountFormatter.string(fromByteCount:storage.availableBytes,countStyle:.file))
                        Text("Joey Storage").font(.subheadline.bold())
                        LabeledContent("Temporary Files",value:ByteCountFormatter.string(fromByteCount:storage.temporaryBytes,countStyle:.file))
                        LabeledContent("Active Processing",value:ByteCountFormatter.string(fromByteCount:storage.activeBytes,countStyle:.file))
                        LabeledContent("Protected Data",value:ByteCountFormatter.string(fromByteCount:storage.protectedBytes,countStyle:.file))
                        LabeledContent("Verified Reclaimable Space",value:storage.reclaimableBytes.map {ByteCountFormatter.string(fromByteCount:$0,countStyle:.file)} ?? "Pending worker release")
                        DisclosureGroup("Storage Details") {
                            Text(storage.note).font(.callout)
                            Text("Measured \(storage.measuredAt.formatted()). Total Joey files: \(storage.totalBytes) bytes.").font(.caption)
                            if let message = model.storageMessage {Text(message).font(.callout).textSelection(.enabled)}
                            ForEach(Array(model.jobs.flatMap {$0.storageWarnings ?? []}.suffix(5).enumerated()),id:\.offset) {_,warning in
                                Text(warning).font(.caption)
                            }
                        }
                    } else {Text("Measuring working-volume storage…")}
                    Toggle("Automatic Cleanup",isOn:Binding(get:{model.configuration?.automaticCleanup != false},set:{model.setAutomaticCleanup($0)}))
                    Label("Low Disk Protection: Enabled",systemImage:"checkmark.shield")
                    HStack {
                        Button("Clean Now") {model.refreshStorage(clean:true)}
                            .disabled(model.checkingStorage || (model.storage?.reclaimableBytes ?? 0) == 0)
                        Button("Refresh") {model.refreshStorage()}.disabled(model.checkingStorage)
                    }
                    Text("Clean Now removes only the verified reclaimable amount shown above, rechecked before each deletion.").font(.caption).foregroundStyle(.secondary)
                }
                JoeyPanel {
                    Text("Appearance").font(.headline)
                    Picker("Appearance",selection:$appearance) {
                        ForEach(JoeyAppearance.allCases) {item in Text(item.title).tag(item.rawValue)}
                    }.pickerStyle(.segmented).labelsHidden().accessibilityLabel("Appearance")
                    Text("System follows your Mac. Your choice is saved for future launches.").font(.callout).foregroundStyle(.secondary)
                }
                JoeyPanel {
                    Text("Production").font(.headline)
                    if let profile = model.configuration?.profile {
                        Text("One shared X + Instagram MP4 · \(profile.width)×\(profile.height) · up to \(profile.maxDuration,specifier:"%.0f") seconds")
                    } else {Label("Production profile required",systemImage:"exclamationmark.circle")}
                    Button("Production Configuration…") {production = true}.disabled(model.busy || model.libraryBusy)
                    DisclosureGroup("Advanced Settings") {
                        VStack(alignment:.leading,spacing:12) {
                            Button("Import Verified Profile…") {model.importProfile()}.disabled(model.busy || model.libraryBusy)
                            Button("Import Job Request…") {model.importJob()}.disabled(model.busy || model.libraryBusy)
                            Button("Open Local Settings") {model.openSettings()}
                        }.padding(.top,12)
                    }
                }
            }.padding(32).frame(maxWidth:850,alignment:.leading).frame(maxWidth:.infinity,alignment:.topLeading)
        }.background(JoeyTheme.background(scheme)).tint(JoeyTheme.primary(scheme))
        .sheet(isPresented:$production) {ProductionSetupView(model:model,owner:.dub)}
        .task {model.refreshStorage()}
    }
}
