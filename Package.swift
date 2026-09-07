// swift-tools-version:5.9
import PackageDescription
let package = Package(
    name: "Chimtu",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Chimtu", path: "Sources/Chimtu")
    ]
)
