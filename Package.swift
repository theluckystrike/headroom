// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Headroom",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Headroom", targets: ["Headroom"]),
        .executable(name: "headroom-cli", targets: ["headroom-cli"]),
        .library(name: "HeadroomCore", targets: ["HeadroomCore"]),
    ],
    targets: [
        // Pure Swift, no Darwin imports: builds and tests on Linux too.
        .target(name: "HeadroomCore"),
        // Darwin probes (libproc, mach, sysctl). macOS only.
        .target(name: "HeadroomMac", dependencies: ["HeadroomCore"]),
        // Menu bar app (AppKit).
        .executableTarget(name: "Headroom", dependencies: ["HeadroomCore", "HeadroomMac"]),
        // CLI: `headroom`, `headroom --json`, `headroom --line` (tmux / Claude Code statusline).
        .executableTarget(name: "headroom-cli", dependencies: ["HeadroomCore", "HeadroomMac"]),
        .testTarget(name: "HeadroomCoreTests", dependencies: ["HeadroomCore"]),
    ]
)
