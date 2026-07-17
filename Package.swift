// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "BooksTranslator",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
    ],
    products: [
        .library(name: "LookupCore", targets: ["LookupCore"]),
        .library(name: "ApplePlatformSupport", targets: ["ApplePlatformSupport"]),
    ],
    targets: [
        .target(
            name: "LookupCore",
            resources: [.process("Resources")]
        ),
        .target(
            name: "ApplePlatformSupport",
            dependencies: ["LookupCore"],
            resources: [.process("Resources")],
            linkerSettings: [.linkedFramework("Security")]
        ),
        .testTarget(
            name: "LookupCoreTests",
            dependencies: ["LookupCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "ApplePlatformSupportTests", dependencies: ["ApplePlatformSupport"]),
    ]
)
