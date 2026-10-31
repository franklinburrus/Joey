// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "Joey", platforms: [.macOS(.v14)], products: [
    .library(name: "JoeyCore", targets: ["JoeyCore"]),
    .executable(name: "joey-run", targets: ["JoeyRunner"])
], targets: [
    .target(name: "JoeyCore", path: "Joey/Core", resources: [.copy("Resources/transcribe_source.py")]),
    .executableTarget(name: "JoeyRunner", dependencies: ["JoeyCore"], path: "Tools/JoeyRunner"),
    .testTarget(name: "JoeyCoreTests", dependencies: ["JoeyCore"], path: "Tests/JoeyCoreTests")
], swiftLanguageModes: [.v5])
