// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AirPrompt",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AirPrompt", targets: ["AirPrompt"]),
        .executable(name: "AirPromptLauncher", targets: ["AirPromptLauncher"])
    ],
    targets: [
        .executableTarget(
            name: "AirPrompt",
            path: "Sources/AirPrompt"
        ),
        .executableTarget(
            name: "AirPromptLauncher",
            path: "Sources/AirPromptLauncher"
        )
    ]
)
