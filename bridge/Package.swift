// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "TTSBridge",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "TTSBridge", targets: ["TTSBridge"]),
        .executable(name: "AgenticVoice", targets: ["AgenticVoice"]),
        .executable(name: "agentic-voice", targets: ["AgenticVoiceCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.110.0"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.4.0"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.12.1")
    ],
    targets: [
        // Synthesis server, model preparation, voice installation and cloning, shared by the
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
        // Speaking, the bridge startup protocol and client installation, shared by the
        // agentic-voice command and the app. Free of Vapor and FluidAudio: it reaches the
        // bridge only over HTTP.
        .target(name: "AgenticVoiceKit"),
        // The agentic-voice command: the MCP server, the speak CLI and the client installer.
        .executableTarget(
            name: "AgenticVoiceCLI",
            dependencies: [
                "AgenticVoiceKit",
                .product(name: "MCP", package: "swift-sdk")
            ]
        ),
        // Thinking-orbs geometry (MIT, libraries.dev/orbs), copied unchanged from visual-explainer's
        // VECore/OrbEngine.swift, so it keeps that code's Swift 5 language mode.
        .target(
            name: "OrbKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // The menu bar app; scripts/build-app.sh wraps it in "Agentic Voice.app".
        .executableTarget(
            name: "AgenticVoice",
            dependencies: ["TTSBridgeCore", "AgenticVoiceKit", "OrbKit"]
        ),
        .testTarget(
            name: "AgenticVoiceKitTests",
            dependencies: ["AgenticVoiceKit"]
        ),
        .testTarget(
            name: "TTSBridgeCoreTests",
            dependencies: ["TTSBridgeCore"]
        ),
        .testTarget(
            name: "OrbKitTests",
            dependencies: ["OrbKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
