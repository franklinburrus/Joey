import SwiftUI

@main enum JoeyMain {
    @MainActor static func main() {
        if ProcessSupervisor.handleInvocation() {return}
        MyApp.main()
    }
}

struct MyApp: App {
    @StateObject private var model = JobModel()
    @AppStorage("joey.interfaceScale") private var interfaceScale = 1.0
    @AppStorage("joey.sidebarCollapsed") private var sidebarCollapsed = false
    var body: some Scene {
        WindowGroup {
            ContentView(model:model)
        }.defaultSize(width:1440,height:900)
            .commands {
                CommandGroup(after:.sidebar) {
                    Button(sidebarCollapsed ? "Show Sidebar" : "Hide Sidebar") {sidebarCollapsed.toggle()}
                        .keyboardShortcut("s",modifiers:[.command,.control])
                    Divider()
                    Button("Increase Interface Size") {interfaceScale = JoeyInterfaceSize.increased(interfaceScale)}
                        .keyboardShortcut("+",modifiers:.command)
                        .disabled(JoeyInterfaceSize.normalized(interfaceScale) >= 2)
                    Button("Decrease Interface Size") {interfaceScale = JoeyInterfaceSize.decreased(interfaceScale)}
                        .keyboardShortcut("-",modifiers:.command)
                        .disabled(JoeyInterfaceSize.normalized(interfaceScale) <= 0.8)
                    Button("Actual Interface Size") {interfaceScale = 1}
                        .keyboardShortcut("0",modifiers:.command)
                    Menu("Alternate Sizing Shortcuts") {
                        Button("Increase with Command-Equals") {interfaceScale = JoeyInterfaceSize.increased(interfaceScale)}
                            .keyboardShortcut("=",modifiers:.command)
                        Button("Increase with Control-Plus") {interfaceScale = JoeyInterfaceSize.increased(interfaceScale)}
                            .keyboardShortcut("+",modifiers:.control)
                        Button("Increase with Control-Equals") {interfaceScale = JoeyInterfaceSize.increased(interfaceScale)}
                            .keyboardShortcut("=",modifiers:.control)
                        Button("Decrease with Control-Minus") {interfaceScale = JoeyInterfaceSize.decreased(interfaceScale)}
                            .keyboardShortcut("-",modifiers:.control)
                        Button("Reset with Control-Zero") {interfaceScale = 1}
                            .keyboardShortcut("0",modifiers:.control)
                    }
                }
            }
    }
}
