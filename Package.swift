// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Sulfurcrest",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.15.0")
    ],
    targets: [
        .executableTarget(
            name: "Sulfurcrest",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio")
            ],
            path: "Sources/Sulfurcrest"
        )
    ]
)
