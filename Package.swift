// swift-tools-version: 5.9

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
                .linkedFramework("CoreText", .when(platforms: [.iOS, .tvOS, .macOS])),
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
        .binaryTarget(name: "Libunibreak", path: "Sources/Libunibreak.xcframework"),
        .binaryTarget(name: "Libfreetype", path: "Sources/Libfreetype.xcframework"),
        .binaryTarget(name: "Libfribidi", path: "Sources/Libfribidi.xcframework"),
        .binaryTarget(name: "Libharfbuzz", path: "Sources/Libharfbuzz.xcframework"),
        .binaryTarget(name: "Libass", path: "Sources/Libass.xcframework"),
        .testTarget(
            name: "AssKitTests",
            dependencies: ["AssKit"],
            path: "Tests/AssKitTests"
        ),
    ]
)
