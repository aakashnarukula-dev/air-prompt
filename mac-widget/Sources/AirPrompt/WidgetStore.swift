import AppKit
import AVFoundation
import Combine
import CoreImage.CIFilterBuiltins
import Foundation

@MainActor
final class WidgetStore: ObservableObject {
    static let defaultPrompt = "Tap mic to talk."

    @Published var sessionId: String = "default"
    @Published var joinURL = ""
    @Published var state = "idle"
    @Published var liveText = defaultPrompt
    @Published var lastText = ""
    @Published var copiedShareLink = false
    @Published var mobileConnected = false
    @Published var showQRCode = false
    @Published var isRecording = false
    @Published var micPermissionDenied = false

    private var socket: URLSessionWebSocketTask?
    private var config = AppConfigLoader.load()
    private var currentBackendBase = ""
    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?

    func bootstrap() {
        let mobileBase = config?.mobileURL
            ?? ProcessInfo.processInfo.environment["AIR_PROMPT_MOBILE_URL"]
            ?? "http://\(ProcessInfo.processInfo.hostName):5173"
        currentBackendBase = config?.backendURL
            ?? ProcessInfo.processInfo.environment["AIR_PROMPT_BACKEND_URL"]
            ?? "http://\(ProcessInfo.processInfo.hostName):8787"
        showQRCode = false
        mobileConnected = false
        liveText = Self.defaultPrompt
        state = "connecting"
        joinURL = mobileBase
        connect()
    }

    func presentPairingIfIdle() {
        guard state != "receiving" else { return }
        if liveText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || liveText == lastText {
            liveText = Self.defaultPrompt
        }
    }

    func connect() {
        config = AppConfigLoader.load()
        let backendBase = config?.backendURL
            ?? ProcessInfo.processInfo.environment["AIR_PROMPT_BACKEND_URL"]
            ?? "http://\(ProcessInfo.processInfo.hostName):8787"
        currentBackendBase = backendBase
        // Refresh joinURL from config only if the current one is a localhost
        // placeholder (i.e. we never got a real public URL). This prevents a
        // good ngrok URL being replaced by a localhost fallback on reconnect.
        if joinURL.contains("localhost") || joinURL.isEmpty {
            let mobileBase = config?.mobileURL
                ?? ProcessInfo.processInfo.environment["AIR_PROMPT_MOBILE_URL"]
                ?? "http://\(ProcessInfo.processInfo.hostName):5173"
            joinURL = mobileBase
        }
        let wsBase = backendBase.replacingOccurrences(of: "http", with: "ws", options: .anchored, range: nil)
        guard let url = URL(string: wsBase) else { return }
        socket?.cancel()
        socket = URLSession.shared.webSocketTask(with: url)
        socket?.resume()
        send(["type": "pair", "sessionId": sessionId, "device": "mac"])
        state = "idle"
        receive()
    }

    func pasteLast() {
        guard !lastText.isEmpty else { return }
        AccessibilityService.shared.copy(lastText)
        let ok = attemptPaste()
        state = ok ? "ready" : "clipboard"
    }

    func copyShareLink() {
        guard !joinURL.isEmpty else { return }
        DemoControl.copy(joinURL)
        copiedShareLink = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            self.copiedShareLink = false
        }
    }

    func stopDemo() {
        DemoControl.stopDemo()
    }

    func revealQRCode() {
        showQRCode = true
    }

    func hideQRCode() {
        showQRCode = false
    }

    func toggleQRCode() {
        showQRCode.toggle()
    }

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        showQRCode = false
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            beginRecording()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    if granted { self.beginRecording() }
                    else { self.micPermissionDenied = true }
                }
            }
        default:
            micPermissionDenied = true
            liveText = "Enable mic in System Settings > Privacy."
        }
    }

    private func beginRecording() {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("airprompt-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
        do {
            let recorder = try AVAudioRecorder(url: tmp, settings: settings)
            recorder.prepareToRecord()
            guard recorder.record() else {
                liveText = "Could not start mic."
                return
            }
            audioRecorder = recorder
            recordingURL = tmp
            isRecording = true
            state = "receiving"
            liveText = "Listening…"
        } catch {
            liveText = "Mic error: \(error.localizedDescription)"
        }
    }

    func stopRecording() {
        guard let recorder = audioRecorder, let url = recordingURL else { return }
        recorder.stop()
        audioRecorder = nil
        recordingURL = nil
        isRecording = false
        state = "processing"
        liveText = "Transcribing…"
        Task { await uploadRecording(url: url) }
    }

    private func uploadRecording(url: URL) async {
        defer { try? FileManager.default.removeItem(at: url) }
        guard !currentBackendBase.isEmpty,
              var components = URLComponents(string: "\(currentBackendBase)/mac-transcribe") else {
            liveText = "Backend URL missing."
            state = "error"
            return
        }
        components.queryItems = [
            URLQueryItem(name: "sessionId", value: sessionId),
            URLQueryItem(name: "mode", value: "raw")
        ]
        guard let endpoint = components.url else { return }
        guard let data = try? Data(contentsOf: url) else {
            liveText = "Recording read failed."
            state = "error"
            return
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("audio/mp4", forHTTPHeaderField: "Content-Type")
        do {
            let (_, response) = try await URLSession.shared.upload(for: request, from: data)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                liveText = "Transcribe failed (\(http.statusCode))."
                state = "error"
            }
            // Final result arrives via WS `final` handler.
        } catch {
            liveText = "Upload error: \(error.localizedDescription)"
            state = "error"
        }
    }

    private func receive() {
        socket?.receive { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .failure:
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.connect() }
                case .success(let message):
                    if case let .string(text) = message {
                        self.handle(text: text)
                    }
                    self.receive()
                }
            }
        }
    }

    private func handle(text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }
        switch type {
        case "session":
            if let sessionId = json["sessionId"] as? String {
                self.sessionId = sessionId
            }
            // Only accept the server's joinUrl if we don't already have one set
            // locally from demo-config.json. The server may fall back to
            // "http://localhost:5173" (no APP_BASE_URL) which is useless on mobile.
            if let serverJoinURL = json["joinUrl"] as? String,
               !serverJoinURL.isEmpty,
               !serverJoinURL.contains("localhost") {
                self.joinURL = serverJoinURL
            }
        case "paired":
            let connected = json["peerConnected"] as? Bool ?? false
            self.mobileConnected = connected
            if !connected {
                self.state = "ready"
            }
            if connected, self.state != "error" {
                self.state = "ready"
            }
        case "state":
            self.state = json["value"] as? String ?? self.state
            if self.state == "receiving" {
                self.showQRCode = false
            }
        case "partial":
            self.liveText = json["text"] as? String ?? self.liveText
            self.showQRCode = false
        case "error":
            self.state = "error"
            self.liveText = json["message"] as? String ?? self.liveText
        case "final":
            let value = json["text"] as? String ?? ""
            let replayed = json["replayed"] as? Bool ?? false
            if replayed {
                self.lastText = value
                self.state = "ready"
            } else {
                self.liveText = value
                self.lastText = value
                self.showQRCode = false
                AccessibilityService.shared.copy(value)
                self.state = attemptPaste() ? "ready" : "clipboard"
            }
            if let deliveryId = json["deliveryId"] as? String {
                self.send(["type": "ack", "deliveryId": deliveryId])
            }
        default:
            break
        }
    }

    private func send(_ payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else { return }
        socket?.send(.string(text)) { _ in }
    }

    private func attemptPaste() -> Bool {
        if AccessibilityService.shared.isTrusted() {
            return AccessibilityService.shared.focusedTextInput() ? AccessibilityService.shared.paste() : false
        }
        _ = AccessibilityService.shared.requestIfNeeded()
        return AccessibilityService.shared.isTrusted() && AccessibilityService.shared.focusedTextInput()
            ? AccessibilityService.shared.paste()
            : false
    }

}

enum QRCode {
    static func make(from text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)) else { return nil }
        let context = CIContext()
        guard let cgImage = context.createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: 200, height: 200))
    }
}
