// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VisionMeasure",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [.library(name: "RefractionCore", targets: ["RefractionCore"]),
               .executable(name: "VisionMeasureDesktop", targets: ["VisionMeasureDesktop"]),
               .executable(name: "RefractionBench", targets: ["RefractionBench"])],
    targets: [.target(name: "RefractionCore"),
              .executableTarget(name: "VisionMeasureDesktop", dependencies: ["RefractionCore"], path: "Sources/VisionMeasure"),
              .executableTarget(name: "RefractionBench", dependencies: ["RefractionCore"]),
              .testTarget(name: "RefractionCoreTests", dependencies: ["RefractionCore"])])
