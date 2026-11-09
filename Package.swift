// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "Joey", platforms: [.macOS(.v14)], products: [
    .library(name: "JoeyCore", targets: ["JoeyCore"]),
    .executable(name: "joey-run", targets: ["JoeyRunner"])
], targets: [
    .target(name: "JoeyCore", path: "Joey/Core", resources: [.copy("Resources/transcribe_source.py"), .copy("Resources/mail_intake.py")]),
    .executableTarget(name: "JoeyRunner", dependencies: ["JoeyCore"], path: "Tools/JoeyRunner",
        sources: ["main.swift"]),
    .target(name: "JoeyInterface", dependencies: ["JoeyCore"], path: "Joey",
        exclude: ["Core", "Assets.xcassets", "AssistantView.swift", "BufferView.swift", "ContentView.swift",
                  "JobDetailView.swift", "JoeySettingsView.swift", "EmailSettingsView.swift", "MyApp.swift", "ShowsView.swift", "TaxstoneLibraryView.swift"],
        sources: ["JobModel.swift", "EmailIntakeModel.swift", "NewJobView.swift", "ProductionSetupView.swift", "JoeyTheme.swift"]),
    .testTarget(name: "JoeyCoreTests", dependencies: ["JoeyCore", "JoeyInterface"], path: "Tests/JoeyCoreTests")
], swiftLanguageModes: [.v5])
