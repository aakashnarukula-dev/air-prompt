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
            path: "Sources/AirPrompt",
            exclude: ["Info.plist"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/AirPrompt/Info.plist"
                ])
            ]
        ),
        .executableTarget(
            name: "AirPromptLauncher",
            path: "Sources/AirPromptLauncher"
        )
    ]
)
