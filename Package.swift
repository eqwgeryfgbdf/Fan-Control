// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacminiContoral",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "MacminiContoral", targets: ["MacminiContoral"]),
        .executable(name: "MacminiHelper", targets: ["MacminiHelper"]),
        .executable(name: "MacminiProbe", targets: ["MacminiProbe"])
    ],
    targets: [
        .target(name: "FanCore", linkerSettings: [.linkedFramework("IOKit")]),
        .executableTarget(name: "MacminiContoral", dependencies: ["FanCore"]),
        .executableTarget(name: "MacminiHelper", dependencies: ["FanCore"]),
        .executableTarget(name: "MacminiProbe", dependencies: ["FanCore"]),
        .testTarget(name: "FanCoreTests", dependencies: ["FanCore"])
    ],
    swiftLanguageModes: [.v5]
)
