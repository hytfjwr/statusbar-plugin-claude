// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ClaudeCodePlugin",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ClaudeCodePlugin", type: .dynamic, targets: ["ClaudeCodePlugin"]),
    ],
    dependencies: [
        .package(url: "https://github.com/hytfjwr/StatusBarKit", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "ClaudeCodePlugin",
            dependencies: [
                .product(name: "StatusBarKit", package: "StatusBarKit"),
            ]
        ),
    ]
)
