// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TTSBridge",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "TTSBridge", targets: ["TTSBridge"])
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
        )
    ]
)
