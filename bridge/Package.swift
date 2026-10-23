// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "TTSBridge",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "TTSBridge", targets: ["TTSBridge"]),
        .executable(name: "AgenticVoice", targets: ["AgenticVoice"])
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.110.0"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.4.0")
    ],
    targets: [
        // Synthesis server, model preparation and voice installation, shared by the
        // TTSBridge command-line executable and the Agentic Voice app.
        .target(
            name: "TTSBridgeCore",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "FluidAudio", package: "FluidAudio")
            ]
        ),
        .executableTarget(
            name: "TTSBridge",
            dependencies: ["TTSBridgeCore"]
        ),
        // The menu bar app; scripts/build-app.sh wraps it in "Agentic Voice.app".
        .executableTarget(
            name: "AgenticVoice",
            dependencies: ["TTSBridgeCore"]
        )
    ]
)
