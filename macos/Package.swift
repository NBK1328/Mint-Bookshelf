// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KindleManager",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "KindleManager", targets: ["KindleManager"]),
    ],
    targets: [
        .executableTarget(
            name: "KindleManager",
            path: "Sources/KindleManager",
            linkerSettings: [
                .unsafeFlags(["-L", "../build"]),
                .linkedLibrary("kindlecore"),
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
    ]
)
