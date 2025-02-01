import AppKit
import Foundation

@MainActor
final class LauncherStore: ObservableObject {
    private var didStart = false
    private var process: Process?
    private var capturedOutput = ""

    func start() {
        guard !didStart else { return }
        didStart = true

        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = ["/Users/aakashnarukula/Developer/Air Prompt/.airprompt/start-demo.sh"]
        task.currentDirectoryURL = URL(fileURLWithPath: "/Users/aakashnarukula/Developer/Air Prompt")
        task.standardOutput = pipe
        task.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                guard let self else { return }
                self.capturedOutput += text
            }
        }

        task.terminationHandler = { [weak self] process in
            Task { @MainActor in
                guard let self else { return }
                pipe.fileHandleForReading.readabilityHandler = nil
                if process.terminationStatus == 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        NSApplication.shared.terminate(nil)
                    }
                } else {
                    NSLog("Air Prompt launcher failed with status %d. Output: %@", process.terminationStatus, self.capturedOutput)
                }
            }
        }

        do {
            try task.run()
            process = task
        } catch {
            NSLog("Air Prompt launcher could not start: %@", error.localizedDescription)
        }
    }
}
