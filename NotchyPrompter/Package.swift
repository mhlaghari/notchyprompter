// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NotchyPrompter",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "NotchyPrompter", targets: ["NotchyPrompter"]),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.18.0"),
    ],
    targets: [
        .executableTarget(
            name: "NotchyPrompter",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
            ],
            path: "Sources"
        ),
    ]
)
