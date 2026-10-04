// swift-tools-version: 6.2
import PackageDescription

// Everything except the app shell, so `swift build` and `swift test` work from
// the terminal. ScribeXCore is the logic the React app kept in plain TypeScript
// modules, plus the client for the Rust typesetting worker; ScribeXUI is the
// screens. The Xcode project in ../ScribeX.xcodeproj links both.
let package = Package(
    name: "ScribeXKit",
    // Tectonic's bundled Homebrew libraries are built for macOS 26 already.
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ScribeXCore", targets: ["ScribeXCore"]),
        .library(name: "ScribeXUI", targets: ["ScribeXUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/krzyzanowskim/STTextView", from: "2.4.1"),
    ],
    targets: [
        .target(name: "ScribeXCore"),
        .target(
            name: "ScribeXUI",
            dependencies: [
                "ScribeXCore",
                .product(name: "STTextView", package: "STTextView"),
            ],
            resources: [.copy("Fonts")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "ScribeXCoreTests", dependencies: ["ScribeXCore"]),
    ]
)
