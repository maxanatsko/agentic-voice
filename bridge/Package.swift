// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TTSBridge",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.110.0"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.4.0")
    ],
    targets: [
        .executableTarget(
            name: "TTSBridge",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "FluidAudio", package: "FluidAudio")
            ]
        )
    ]
)
