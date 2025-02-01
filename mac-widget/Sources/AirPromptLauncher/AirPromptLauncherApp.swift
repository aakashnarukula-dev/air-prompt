import AppKit
import SwiftUI

@main
struct AirPromptLauncherApp: App {
    @StateObject private var launcher = LauncherStore()

    var body: some Scene {
        WindowGroup {
            LauncherView()
                .onAppear { launcher.start() }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 56, height: 56)
    }
}
