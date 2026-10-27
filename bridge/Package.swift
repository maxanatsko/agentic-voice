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
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.12.1"),
        // Voxtral 4B TTS on MLX. Pinned: speech-swift has no releases to follow.
        .package(url: "https://github.com/soniqo/speech-swift", revision: "cbad3be29480825707890490f446b19d7288be2d")
    ],
    targets: [
        // Synthesis server, model preparation, voice installation and cloning, shared by the
        // TTSBridge command-line executable and the Agentic Voice app.
        .target(
            name: "TTSBridgeCore",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "VoxtralTTS", package: "speech-swift"),
                .product(name: "AudioCommon", package: "speech-swift")
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
        // Thinking-orbs geometry (MIT, libraries.dev/orbs), from visual-explainer's VECore/OrbEngine.swift.
        .target(name: "OrbKit"),
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
            dependencies: ["OrbKit"]
        )
    ]
)
