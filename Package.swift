// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FeedbackKit",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(
            name: "FeedbackKit",
            targets: ["FeedbackKit"]),
    ],
    targets: [
        .target(name: "FeedbackKit"),
        .testTarget(
            name: "FeedbackKitTests",
            dependencies: ["FeedbackKit"]),
    ])
