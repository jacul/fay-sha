// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FaySHA",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "FaySHA", targets: ["FaySHA"])],
    targets: [
        .target(name: "ChecksumCore"),
        .executableTarget(name: "FaySHA", dependencies: ["ChecksumCore"]),
        .testTarget(name: "ChecksumCoreTests", dependencies: ["ChecksumCore"])
    ]
)
