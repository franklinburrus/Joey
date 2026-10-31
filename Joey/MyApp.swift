import SwiftUI

@main enum JoeyMain {
    @MainActor static func main() {
        if ProcessSupervisor.handleInvocation() {return}
        MyApp.main()
    }
}

struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
