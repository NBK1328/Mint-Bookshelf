// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KindleManager",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "KindleManager", targets: ["KindleManager"]),
    ],
    targets: [
        .target(
            name: "KindleManagerSupport",
            path: "Sources/KindleManagerSupport"
        ),
        .executableTarget(
            name: "KindleManager",
            dependencies: ["KindleManagerSupport"],
            path: "Sources/KindleManager",
            linkerSettings: [
                .unsafeFlags(["-L", "../build"]),
                .linkedLibrary("kindlecore"),
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
        .testTarget(
            name: "KindleManagerSupportTests",
            dependencies: ["KindleManagerSupport"],
            path: "Tests/KindleManagerSupportTests"
        ),
    ]
)
