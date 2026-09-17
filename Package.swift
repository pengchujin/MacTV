// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "MacTV", defaultLocalization: "en", platforms: [.macOS(.v13)], products: [.library(name: "CECCore", targets: ["CECCore"])], targets: [.target(name: "CECCore", resources: [.process("Resources")]), .testTarget(name: "CECCoreTests", dependencies: ["CECCore"])])
