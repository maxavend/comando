// swift-tools-version:5.9
// SwiftTerm 1.11.2 (b1262db), vendored with one fix: Pty.fork prepares
// everything before forking, so the child only calls async-signal-safe
// functions. See README-COMANDO.md.

import PackageDescription

let package = Package(
    name: "SwiftTerm",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "SwiftTerm", targets: ["SwiftTerm"]),
    ],
    targets: [
        .target(
            name: "SwiftTerm",
            path: "Sources/SwiftTerm",
            exclude: ["Mac/README.md"]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
