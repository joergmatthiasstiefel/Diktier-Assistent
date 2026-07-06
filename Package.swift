// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DiktierAssistent",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "DiktierAssistent",
            path: "Sources/DiktierAssistent"
        )
    ]
)
