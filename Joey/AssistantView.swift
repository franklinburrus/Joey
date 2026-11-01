import SwiftUI

struct AssistantView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var conversation = AssistantConversation()
    @StateObject private var service = LocalAssistantService()
    let mediaBusy: Bool
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            HStack {
                Text("Local assistant").font(.title.bold())
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("Conversation, writing, summaries, planning and coding questions. Uses the installed qwen3:4b on this Mac.")
                .foregroundStyle(.secondary)
            Text("Only text you send here and this conversation’s replies are shared with local Ollama. No files, accounts or media jobs are accessed. Replies cannot run commands or publish content.")
                .font(.caption)
            HStack {
                Button("Start local Ollama") { Task { await service.start() } }
                    .disabled(service.starting || service.owned || mediaBusy || conversation.busy)
                Button("Stop Ollama") {
                    conversation.stop()
                    Task { await service.stop() }
                }.disabled(!service.owned && !service.starting)
                if service.starting { ProgressView().controlSize(.small) }
                Text(service.status).font(.caption).foregroundStyle(.secondary)
            }
            Text("Start may create Ollama’s local identity pair. No API key or sign-in. Joey starts it with cloud and external networking disabled; closing stops a service Joey owns.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment:.leading,spacing:16) {
                        if conversation.messages.isEmpty {
                            Text("Type or paste text below, then choose Send. Nothing is sent automatically.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(Array(conversation.messages.enumerated()),id:\.offset) { index, message in
                            VStack(alignment:.leading,spacing:6) {
                                Text(message.role == .user ? "You":"Local assistant").font(.headline)
                                Text(verbatim:message.content).textSelection(.enabled)
                            }.frame(maxWidth:.infinity,alignment:.leading)
                                .padding().background(.quaternary,in:RoundedRectangle(cornerRadius:10)).id(index)
                        }
                    }.frame(maxWidth:.infinity,alignment:.leading)
                }.onChange(of:conversation.messages.count) { _, count in
                    if count > 0 { proxy.scrollTo(count - 1,anchor:.bottom) }
                }
            }
            if let error = conversation.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            if mediaBusy { Text("Assistant requests are paused while Joey processes media.").foregroundStyle(.orange) }
            TextEditor(text:$conversation.draft)
                .font(.body).frame(height:110).border(.quaternary)
                .accessibilityLabel("Message to local assistant")
                .disabled(conversation.busy)
            HStack {
                Button("Clear conversation") { conversation.clear() }
                Text("Memory only · 6,000-byte conversation limit · 8K model context")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if conversation.busy {
                    ProgressView().controlSize(.small)
                    Button("Stop response") { conversation.stop() }
                } else {
                    Button("Send") { conversation.send() }.buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return,modifiers:.command)
                        .disabled(mediaBusy || service.starting || conversation.draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                }
            }
            Text("Review answers before using them. Closing clears this conversation; accepted media and production status are unchanged.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(minWidth:720,idealWidth:820,minHeight:650,idealHeight:740)
            .onChange(of:mediaBusy) { _, busy in
                if busy { conversation.stop(); Task { await service.stop() } }
            }
            .onDisappear { conversation.clear(); Task { await service.stop() } }
    }
}
