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
            swiftSettings: [
                // Swift 5 language mode: disables the Swift 6 strict-isolation
                // runtime checks that trap on legacy @Sendable callbacks
                // (SFSpeechRecognizer, AVCaptureDevice, URLSession via tccd XPC).
                .swiftLanguageMode(.v5)
            ],
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
