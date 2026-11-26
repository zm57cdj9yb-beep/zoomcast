// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ZoomCast",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "ZoomCastCore", targets: ["ZoomCastCore"]),
        .executable(name: "ZoomCast", targets: ["ZoomCast"]),
        .executable(name: "ZoomCastBench", targets: ["ZoomCastBench"])
    ],
    targets: [
        .target(
            name: "ZoomCastCore",
            path: "Sources/ZoomCastCore",
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreImage"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("ImageIO"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("UniformTypeIdentifiers")
            ]
        ),
        .executableTarget(
            name: "ZoomCast",
            dependencies: ["ZoomCastCore"],
            path: "Sources/ZoomCast"
        ),
        .executableTarget(
            name: "ZoomCastBench",
            dependencies: ["ZoomCastCore"],
            path: "Sources/ZoomCastBench"
        ),
        .testTarget(
            name: "ZoomCastCoreTests",
            dependencies: ["ZoomCastCore"],
            path: "Tests/ZoomCastCoreTests"
        )
    ]
)
