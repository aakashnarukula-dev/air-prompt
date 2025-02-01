import AppKit
import Foundation

enum DemoControl {
    static let root = "/Users/aakashnarukula/Developer/Air Prompt"
    static let stopScript = "/Users/aakashnarukula/Developer/Air Prompt/.airprompt/stop-demo.sh"

    static func copy(_ text: String) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(text, forType: .string)
    }

    static func stopDemo() {
        run(script: stopScript)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            NSApplication.shared.terminate(nil)
        }
    }

    private static func run(script: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = [script]
        task.currentDirectoryURL = URL(fileURLWithPath: root)
        try? task.run()
    }
}
