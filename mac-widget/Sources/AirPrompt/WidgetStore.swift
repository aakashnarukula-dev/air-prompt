import AppKit
import AVFoundation
import Combine
import CoreImage.CIFilterBuiltins
import Foundation
import Speech

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

    @Published var idToken: String? = TokenStore.load()
    @Published var isLoginPresented: Bool = false
    @Published var pollState: String?

    private var pollTimer: Timer?

    func beginLogin() {
        let state = UUID().uuidString
        self.pollState = state
        let backendBase = currentBackendBase.isEmpty
            ? (AppConfigLoader.load()?.backendURL ?? "http://localhost:8787")
            : currentBackendBase
        let urlStr = "\(backendBase)/login.html?state=\(state)&widget=1"
        if let url = URL(string: urlStr) {
            NSWorkspace.shared.open(url)
        }
        startPollingForToken()
    }

    private func startPollingForToken() {
        pollTimer?.invalidate()
        let started = Date()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let state = self.pollState else { return }
                if Date().timeIntervalSince(started) > 300 {
                    self.pollTimer?.invalidate()
                    self.pollTimer = nil
                    self.pollState = nil
                    return
                }
                self.pollTokenOnce(state: state) { [weak self] token in
                    Task { @MainActor in
                        guard let self, let token else { return }
                        self.pollTimer?.invalidate()
                        self.pollTimer = nil
                        self.pollState = nil
                        self.completeLogin(token: token)
                    }
                }
            }
        }
    }

    private func pollTokenOnce(state: String, onToken: @Sendable @escaping (String?) -> Void) {
        let backendBase = currentBackendBase.isEmpty
            ? (AppConfigLoader.load()?.backendURL ?? "http://localhost:8787")
            : currentBackendBase
        guard let url = URL(string: "\(backendBase)/auth/poll?state=\(state)") else {
            onToken(nil); return
        }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = obj["idToken"] as? String else {
                onToken(nil); return
            }
            onToken(token)
        }.resume()
    }

    func completeLogin(token: String) {
        self.idToken = token
        TokenStore.save(token)
        self.isLoginPresented = false
        // Reconnect so the v2 hello carries the new token.
        self.connect()
    }

    func signOut() {
        TokenStore.clear()
        self.idToken = nil
    }

    private var socket: URLSessionWebSocketTask?
    private var config = AppConfigLoader.load()
    private var currentBackendBase = ""
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var currentSeq: Int = 0

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
        // Require auth before opening a WS — prevents unauth reconnect loop.
        guard self.idToken != nil else {
            self.state = "needs_login"
            self.isLoginPresented = true
            return
        }
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

        // v2 protocol: send hello, then create_session.
        let hello: [String: Any] = [
            "type": "hello",
            "protocolVersion": "2",
            "idToken": self.idToken ?? "",
            "device": "mac"
        ]
        if let data = try? JSONSerialization.data(withJSONObject: hello) {
            self.socket?.send(.string(String(data: data, encoding: .utf8) ?? "")) { _ in }
        }

        let createMsg: [String: Any] = [
            "type": "create_session",
            "protocolVersion": "2"
        ]
        if let data = try? JSONSerialization.data(withJSONObject: createMsg) {
            self.socket?.send(.string(String(data: data, encoding: .utf8) ?? "")) { _ in }
        }

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
        Self.log("toggleRecording called, isRecording=\(isRecording), idToken=\(idToken == nil ? "nil" : "present")")
        liveText = "mic clicked: \(Date().timeIntervalSince1970)"
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private static func log(_ msg: String) {
        let line = "\(Date()) \(msg)\n"
        if let data = line.data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: "/tmp/airprompt.log")) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: URL(fileURLWithPath: "/tmp/airprompt.log"))
            }
        }
    }

    func startRecording() {
        Self.log("startRecording called")
        showQRCode = false
        guard idToken != nil else {
            Self.log("no idToken, showing login")
            state = "needs_login"
            isLoginPresented = true
            return
        }
        Task { @MainActor in
            let status = await Self.requestSpeechAuth()
            Self.log("speech auth status = \(status.rawValue)")
            self.handleSpeechAuth(status: status)
        }
    }

    private nonisolated static func requestSpeechAuth() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status)
            }
        }
    }

    private nonisolated static func requestMicAccess() async -> Bool {
        await withCheckedContinuation { cont in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                cont.resume(returning: granted)
            }
        }
    }

    private func handleSpeechAuth(status: SFSpeechRecognizerAuthorizationStatus) {
        guard status == .authorized else {
            self.micPermissionDenied = true
            self.liveText = "Enable Speech Recognition in System Settings > Privacy."
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            self.beginRecognition()
        case .notDetermined:
            Task { @MainActor in
                let granted = await Self.requestMicAccess()
                self.handleMicAuth(granted: granted)
            }
        default:
            self.micPermissionDenied = true
            self.liveText = "Enable mic in System Settings > Privacy."
        }
    }

    private func handleMicAuth(granted: Bool) {
        if granted {
            self.beginRecognition()
        } else {
            self.micPermissionDenied = true
            self.liveText = "Enable mic in System Settings > Privacy."
        }
    }

    private func beginRecognition() {
        Self.log("beginRecognition")
        // Try current locale first (handles en-IN, etc.), fall back to en-US.
        let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        guard let recognizer else {
            Self.log("recognizer nil for locale \(Locale.current.identifier)")
            state = "error"
            liveText = "Speech recognizer unavailable for your locale."
            return
        }
        Self.log("recognizer locale=\(recognizer.locale.identifier) available=\(recognizer.isAvailable) onDevice=\(recognizer.supportsOnDeviceRecognition)")
        guard recognizer.isAvailable else {
            Self.log("recognizer unavailable — dictation likely disabled")
            state = "error"
            liveText = "Enable Dictation in System Settings > Keyboard, then try again."
            return
        }
        self.speechRecognizer = recognizer

        recognitionTask?.cancel()
        recognitionTask = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        // Let Apple pick on-device vs server. Forcing on-device fails if the model
        // isn't downloaded for the user's locale.
        self.recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        // Guard: installTap crashes on invalid format (sample rate 0 or 0 channels).
        guard format.sampleRate > 0, format.channelCount > 0 else {
            state = "error"
            liveText = "No microphone input available."
            return
        }
        inputNode.removeTap(onBus: 0)
        var tapBufferCount = 0
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            tapBufferCount += 1
            if tapBufferCount == 1 || tapBufferCount % 50 == 0 {
                Self.log("tap buffer #\(tapBufferCount), frames=\(buffer.frameLength)")
            }
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            state = "error"
            liveText = "Mic error: \(error.localizedDescription)"
            inputNode.removeTap(onBus: 0)
            return
        }

        isRecording = true
        state = "receiving"
        liveText = "Listening…"

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let errMsg = error?.localizedDescription
            let errDomain = (error as NSError?)?.domain ?? ""
            let errCode = (error as NSError?)?.code ?? 0
            Self.log("recognitionTask callback: text=\(text ?? "nil"), isFinal=\(isFinal), err=\(errMsg ?? "nil") [\(errDomain) \(errCode)]")
            // Map common errors to actionable UI strings.
            let uiError: String? = {
                guard let error = error as NSError? else { return nil }
                // kLSRErrorDomain 201 = "Siri and Dictation are disabled"
                if error.domain == "kLSRErrorDomain" && error.code == 201 {
                    return "Enable Dictation in System Settings > Keyboard > Dictation, then try again."
                }
                // kAFAssistantErrorDomain 1700/1101 = speech service unreachable
                if error.domain == "kAFAssistantErrorDomain" && (error.code == 1700 || error.code == 1101) {
                    return "Speech service unreachable. Check your internet or enable Dictation."
                }
                return "Speech error: \(error.localizedDescription)"
            }()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self = self else { return }
                    if let text = text, !text.isEmpty {
                        self.liveText = text
                        if isFinal {
                            self.sendTranscript(text: text)
                            self.lastText = text
                        }
                    }
                    if let uiError = uiError {
                        self.liveText = uiError
                        self.finalizeRecording()
                    } else if isFinal {
                        self.finalizeRecording()
                    }
                    _ = errMsg; _ = errDomain; _ = errCode
                }
            }
        }
        Self.log("recognitionTask installed, audioEngine.isRunning=\(audioEngine.isRunning), format=\(format)")
    }

    func stopRecording() {
        guard isRecording else { return }
        audioEngine.stop()
        recognitionRequest?.endAudio()
        isRecording = false
        // Recognition task will fire final result, then finalizeRecording.
    }

    private func finalizeRecording() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.finish()
        recognitionTask = nil
        isRecording = false
        if state == "receiving" { state = "idle" }
        Self.log("recording finalized")
    }

    private func sendTranscript(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        currentSeq += 1
        let msg: [String: Any] = [
            "type": "transcript",
            "protocolVersion": "2",
            "text": trimmed,
            "mode": "prompt",
            "seq": currentSeq
        ]
        if let data = try? JSONSerialization.data(withJSONObject: msg),
           let str = String(data: data, encoding: .utf8) {
            socket?.send(.string(str)) { _ in }
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
        case "session_created":
            if let sessionId = json["sessionId"] as? String {
                self.sessionId = sessionId
            }
            if let serverJoinURL = json["joinUrl"] as? String,
               !serverJoinURL.isEmpty,
               !serverJoinURL.contains("localhost") {
                self.joinURL = serverJoinURL
            }
            // Rebuild QR by nudging showQRCode flag state consumers observe joinURL directly.
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
