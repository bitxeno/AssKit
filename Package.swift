// swift-tools-version: 5.9
// package-version: 0.0.3
import PackageDescription

// The vendored frameworks ship under an `AssKit` prefix. SwiftPM target names
// are unique across the whole dependency graph, and other players packaged for
// Apple platforms (FFmpegKit and forks, KSPlayer, mpv builds, MobileVLCKit)
// commonly declare targets named Libass or Libfreetype. Sharing those names
// made this package unresolvable next to any of them. The prefix also keeps
// the framework bundles distinct inside App.app/Frameworks/.
let package = Package(
    name: "AssKit",
    platforms: [
        .iOS(.v14),
        .tvOS(.v14),
        .macOS(.v11),
    ],
    products: [
        .library(name: "AssKit", targets: ["AssKit"]),
    ],
    targets: [
        .target(
            name: "AssKit",
            dependencies: [
                "CAssKit",
                "AssKitLibass",
                "AssKitUnibreak",
                "AssKitFreetype",
                "AssKitFribidi",
                "AssKitHarfbuzz",
            ],
            path: "Sources/AssKit",
            linkerSettings: [
                .linkedFramework("CoreText"),
                .linkedLibrary("z"),
                .linkedLibrary("iconv"),
            ]
        ),
        .target(
            name: "CAssKit",
            dependencies: ["AssKitLibass"],
            path: "Sources/CAssKit",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("libass-headers"),
            ]
        ),
        .binaryTarget(name: "AssKitUnibreak", path: "Vendor/AssKitUnibreak.xcframework"),
        .binaryTarget(name: "AssKitFreetype", path: "Vendor/AssKitFreetype.xcframework"),
        .binaryTarget(name: "AssKitFribidi", path: "Vendor/AssKitFribidi.xcframework"),
        .binaryTarget(name: "AssKitHarfbuzz", path: "Vendor/AssKitHarfbuzz.xcframework"),
        .binaryTarget(name: "AssKitLibass", path: "Vendor/AssKitLibass.xcframework"),
        .testTarget(
            name: "AssKitTests",
            dependencies: ["AssKit"],
            path: "Tests/AssKitTests"
        ),
    ]
)
