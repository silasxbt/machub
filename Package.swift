// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "mac+",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "mac+", targets: ["MacPlus"])
    ],
    targets: [
        .executableTarget(
            name: "MacPlus",
            path: "Sources/MacPlus",
            linkerSettings: [
                .linkedFramework("SafariServices")
            ]
        ),
        .testTarget(
            name: "MacPlusTests",
            dependencies: ["MacPlus"],
            path: "Tests/MacPlusTests"
        )
    ]
)
