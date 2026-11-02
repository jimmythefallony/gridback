// swift-tools-version:5.10
import PackageDescription

// Logic-only package. The Mac app target lives in GridBack.xcodeproj and
// links this product. Platforms are intentionally unset so `swift test` can
// run on non-Mac hosts; the app target pins macOS 26.
let package = Package(
    name: "GridBack",
    products: [
        .library(name: "GridBackCore", targets: ["GridBackCore"])
    ],
    targets: [
        .target(name: "GridBackCore"),
        .testTarget(
            name: "GridBackCoreTests",
            dependencies: ["GridBackCore"]
        )
    ]
)
