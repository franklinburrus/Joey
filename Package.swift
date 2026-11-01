// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "Joey", platforms: [.macOS(.v14)], products: [
    .library(name: "JoeyCore", targets: ["JoeyCore"]),
    .executable(name: "joey-run", targets: ["JoeyRunner"])
], targets: [
    .target(name: "JoeyCore", path: "Joey/Core", resources: [.copy("Resources/transcribe_source.py")]),
    .executableTarget(name: "JoeyRunner", dependencies: ["JoeyCore"], path: "Tools/JoeyRunner"),
    .target(name: "JoeyInterface", dependencies: ["JoeyCore"], path: "Joey",
        exclude: ["Core", "Assets.xcassets", "AssistantView.swift", "BufferView.swift", "ContentView.swift",
                  "JobDetailView.swift", "JoeySettingsView.swift", "MyApp.swift", "ShowsView.swift", "TaxstoneLibraryView.swift"],
        sources: ["JobModel.swift", "NewJobView.swift", "ProductionSetupView.swift", "JoeyTheme.swift"]),
    .testTarget(name: "JoeyCoreTests", dependencies: ["JoeyCore", "JoeyInterface", "JoeyRunner"], path: "Tests/JoeyCoreTests")
], swiftLanguageModes: [.v5])
