// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MintBookshelf",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MintBookshelf", targets: ["MintBookshelf"]),
    ],
    targets: [
        .target(
            name: "MintBookshelfSupport",
            path: "Sources/MintBookshelfSupport"
        ),
        .executableTarget(
            name: "MintBookshelf",
            dependencies: ["MintBookshelfSupport"],
            path: "Sources/MintBookshelf",
            linkerSettings: [
                .unsafeFlags(["-L", "../build"]),
                .linkedLibrary("kindlecore"),
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
        .testTarget(
            name: "MintBookshelfSupportTests",
            dependencies: ["MintBookshelfSupport"],
            path: "Tests/MintBookshelfSupportTests"
        ),
    ]
)
