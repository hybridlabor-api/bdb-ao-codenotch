// swift-tools-version:5.9
// BDB-only build path for machines with just the Command Line Tools (no Xcode,
// no xcodegen). Upstream builds from project.yml; this mirrors it. Asset
// catalog, string catalog and Info.plist are handled by Scripts/bdb-bundle.sh.
import PackageDescription

let package = Package(
    name: "Codenotch",
    platforms: [.macOS("15.0")],
    products: [.executable(name: "Codenotch", targets: ["Codenotch"])],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio", from: "2.102.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        // The vendored Zstandard decoder; Xcode sees it through a bridging
        // header, SwiftPM needs a module of its own.
        .target(
            name: "CZstd",
            path: "Sources/Vendor/zstd",
            exclude: ["README.md", "LICENSE"],
            sources: ["zstddeclib.c"],
            publicHeadersPath: ".",
            cSettings: [.unsafeFlags(["-w"])]
        ),
        .executableTarget(
            name: "Codenotch",
            dependencies: [
                "CZstd",
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
            ],
            path: "Sources",
            exclude: [
                "Vendor", "Assets.xcassets", "Resources", "Info.plist",
                "Localizable.xcstrings", "Codenotch-Bridging-Header.h",
            ]
        ),
        .testTarget(
            name: "CodenotchTests",
            dependencies: ["Codenotch"],
            path: "Tests"
        ),
    ],
    swiftLanguageVersions: [.v5]
)
