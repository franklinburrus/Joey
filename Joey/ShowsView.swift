import SwiftUI

struct ShowsView: View {
    @ObservedObject var model: JobModel
    var useEpisode: (String) -> Void
    @State private var taxstone = false
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:24) {
                Text("Shows").font(JoeyTheme.font(24,weight:.medium))
                Button {taxstone = true} label: {
                    HStack {
                        VStack(alignment:.leading,spacing:8) {
                            Text("Taxstone").font(JoeyTheme.font(18,weight:.medium))
                            Text("\(model.taxstoneLibrary.completedCount) / \(model.taxstoneLibrary.discoveredCount) episodes verified")
                                .font(JoeyTheme.font(12)).foregroundStyle(.secondary)
                            Text(model.taxstoneLibrary.status).font(JoeyTheme.font(12)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName:"chevron.right")
                    }.padding(.vertical,16).contentShape(Rectangle())
                }.buttonStyle(.plain)
                Divider()
                JoeyPanel {
                    HStack {
                        Text("Joe Budden episodes").font(.headline)
                        Spacer()
                        Button(model.scanningJoe ? "Checking…":"Check Now") {model.scanJoe()}.disabled(model.scanningJoe)
                    }
                    Text(model.joeStatus).font(.callout).textSelection(.enabled)
                    if let episode = model.latestJoe {
                        Text(episode.title).font(.callout.bold())
                        Button("Use This Episode") {useEpisode(episode.url)}
                    }
                    if let error = model.joeAutomation.lastError {
                        Label(error,systemImage:"exclamationmark.triangle").font(.callout).foregroundStyle(.red).textSelection(.enabled)
                    }
                    HStack {
                        if model.joeAutomation.enabled {
                            Button("Pause Automatic Processing") {model.pauseJoe()}
                        } else {
                            Button(model.joeAutomation.afterEpisode == nil ? "Start Automatic Processing":"Resume Automatic Processing") {model.enableJoe()}
                                .disabled((model.latestJoe == nil && model.joeAutomation.afterEpisode == nil) || model.scanningJoe)
                        }
                        Text("\(model.joeAutomation.queue.count) episodes queued").font(.caption).foregroundStyle(.secondary)
                    }
                    Text("Checks on app opening, every 30 minutes while enabled, and Check Now. Once enabled, new numbered episodes process in the background while Joey stays open. The initial latest episode is not replayed. Sleep or Quit stops work; the saved queue resumes when Joey reopens. Only the 30 recent uploads are scanned.")
                        .font(.caption).foregroundStyle(.secondary)
                }

            }.padding(28)
        }
        .sheet(isPresented:$taxstone) {
            VStack(spacing:0) {
                HStack {Text("Taxstone").font(.headline);Spacer();Button("Done") {taxstone = false}}.padding()
                Divider()
                TaxstoneLibraryView(model:model)
            }.frame(width:760,height:680)
        }
    }
}
