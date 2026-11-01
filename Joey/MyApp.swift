import SwiftUI

@main enum JoeyMain {
    @MainActor static func main() {
        if ProcessSupervisor.handleInvocation() {return}
        MyApp.main()
    }
}

struct MyApp: App {
    @StateObject private var model = JobModel()
    var body: some Scene {
        WindowGroup {
            ContentView(model:model)
        }.defaultSize(width:1280,height:800)
    }
}
