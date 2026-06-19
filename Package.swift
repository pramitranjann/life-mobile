// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PRLifeKit",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "PRLifeKit", targets: ["PRLifeKit"])
    ],
    targets: [
        .target(name: "PRLifeKit"),
        .testTarget(name: "PRLifeKitTests", dependencies: ["PRLifeKit"])
    ]
)
