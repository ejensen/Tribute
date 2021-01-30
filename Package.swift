// swift-tools-version:5.1
import PackageDescription

let package = Package(
    name: "Tribute",
    platforms: [.macOS(.v10_13)],
    products: [
        .executable(name: "tribute", targets: ["TributeCLI"]),
        .library(name: "Tribute", targets: ["Tribute"]),
    ],
    targets: [
        .target(name: "Tribute"),
        .target(name: "TributeCLI", dependencies: ["Tribute"]),
        .testTarget(name: "TributeTests", dependencies: ["Tribute"], path: "Tests"),
    ]
)
