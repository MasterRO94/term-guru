// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TermGuru",
    platforms: [.macOS("26.0")],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .target(name: "GuruCore"),
        .executableTarget(name: "GuruApp", dependencies: ["GuruCore"]),
        .executableTarget(
            name: "tgr",
            dependencies: ["GuruCore", .product(name: "ArgumentParser", package: "swift-argument-parser")]
        ),
        .testTarget(name: "GuruCoreTests", dependencies: ["GuruCore"]),
    ],
    swiftLanguageModes: [.v5]
)
