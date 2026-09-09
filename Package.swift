// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Chimtu",
    platforms: [.macOS(.v13)],
    targets: [
        // Pure behaviour: state selection, reaction gating, mood, persistence, phrases.
        // Foundation only, so it is unit-testable and mirrors windows/chimtu_core.py.
        .target(name: "ChimtuCore", path: "Sources/ChimtuCore"),
        .executableTarget(name: "Chimtu", dependencies: ["ChimtuCore"], path: "Sources/Chimtu"),
        // Tests as a plain executable: XCTest/Testing are not available with Command Line Tools alone.
        // Run with `swift run ChimtuCoreChecks`; exits non-zero on any failure.
        .executableTarget(name: "ChimtuCoreChecks", dependencies: ["ChimtuCore"], path: "Sources/ChimtuCoreChecks"),
    ]
)
