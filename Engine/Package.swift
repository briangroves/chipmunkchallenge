// swift-tools-version:5.9
import PackageDescription

/// ChipmunkEngine: the game's rules, timed simulation, level builder and solver, ported 1:1 from the
/// `<script id="engine">` block of web/chipmunk-challenge.html. Pure Swift, no UI, so it runs in the iOS app,
/// in macOS tests, and in command-line tools alike.
let package = Package(
    name: "ChipmunkEngine",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ChipmunkEngine", targets: ["ChipmunkEngine"]),
    ],
    targets: [
        .target(name: "ChipmunkEngine", resources: [.copy("Resources/levels.json")]),
        .testTarget(name: "ChipmunkEngineTests", dependencies: ["ChipmunkEngine"]),
    ]
)
