import Foundation

// Beta storage: UserDefaults plist under ~/Library/Preferences/, user-readable only (600).
// Not Keychain — Keychain prompts every rebuild on unsigned SwiftPM binaries.
// Revisit after proper code signing (V2 Tauri + Apple Developer cert).
struct TokenStore {
    private static let key = "airprompt.idToken"

    static func save(_ token: String) {
        UserDefaults.standard.set(token, forKey: key)
    }

    static func load() -> String? {
        UserDefaults.standard.string(forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
