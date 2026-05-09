// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Clipi",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Clipi",
            path: "Sources/Clipi"
        )
    ]
)
