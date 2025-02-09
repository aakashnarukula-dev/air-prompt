import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        return .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
struct AirPromptApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
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
                NSApp.terminate(nil)
                // Fallback if terminate is intercepted for any reason.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { exit(0) }
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
