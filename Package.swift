// swift-tools-version: 5.9
// package-version: 0.0.2
import PackageDescription

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
                "Libass",
                "Libunibreak",
                "Libfreetype",
                "Libfribidi",
                "Libharfbuzz",
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
            dependencies: ["Libass"],
            path: "Sources/CAssKit",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("libass-headers"),
            ]
        ),
        .binaryTarget(name: "Libunibreak", path: "Vendor/Libunibreak.xcframework"),
        .binaryTarget(name: "Libfreetype", path: "Vendor/Libfreetype.xcframework"),
        .binaryTarget(name: "Libfribidi", path: "Vendor/Libfribidi.xcframework"),
        .binaryTarget(name: "Libharfbuzz", path: "Vendor/Libharfbuzz.xcframework"),
        .binaryTarget(name: "Libass", path: "Vendor/Libass.xcframework"),
        .testTarget(
            name: "AssKitTests",
            dependencies: ["AssKit"],
            path: "Tests/AssKitTests"
        ),
    ]
)
