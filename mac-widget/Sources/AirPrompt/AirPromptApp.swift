import AppKit
import SwiftUI

@main
struct AirPromptApp: App {
    @StateObject private var store = WidgetStore()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openWindow) private var openWindow

    private static let menuBarIcon: NSImage? = {
        guard let image = NSImage(named: "MenuBarTemplateIcon") else {
            return nil
        }

        image.isTemplate = true
        return image
    }()

    var body: some Scene {
        WindowGroup(id: "main") {
            WidgetView()
                .environmentObject(store)
                .onAppear { store.bootstrap() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        store.presentPairingIfIdle()
                    }
                }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 280, height: 360)

        MenuBarExtra {
            Button("Open Air Prompt") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        } label: {
            if let menuBarIcon = Self.menuBarIcon {
                Image(nsImage: menuBarIcon)
            } else {
                Image(systemName: "waveform")
            }
        }
    }
}
