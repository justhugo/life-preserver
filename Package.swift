// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LifePreserver",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "LifePreserver", targets: ["LifePreserver"])],
    targets: [
        .target(name: "LifePreserverCore"),
        .target(name: "LifePreserverSync", dependencies: ["LifePreserverCore"]),
        .executableTarget(name: "LifePreserver", dependencies: ["LifePreserverCore", "LifePreserverSync"], resources: [.copy("Assets")]),
        .testTarget(name: "LifePreserverCoreTests", dependencies: ["LifePreserverCore"]),
        .testTarget(name: "LifePreserverSyncTests", dependencies: ["LifePreserverSync", "LifePreserverCore"])
    ],
    swiftLanguageModes: [.v5]
)
