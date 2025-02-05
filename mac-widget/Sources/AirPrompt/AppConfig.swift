import Foundation

struct AppConfig: Decodable {
    let mobileURL: String
    let backendURL: String

    static var backendBaseURL: String {
        if let loaded = AppConfigLoader.load()?.backendURL, !loaded.isEmpty {
            return loaded
        }
        if let env = ProcessInfo.processInfo.environment["AIR_PROMPT_BACKEND_URL"], !env.isEmpty {
            return env
        }
        return "https://airprompt.fly.dev"
    }
}

enum AppConfigLoader {
    static let path = "/Users/aakashnarukula/Developer/Air Prompt/.run/demo-config.json"

    static func load() -> AppConfig? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return try? JSONDecoder().decode(AppConfig.self, from: data)
    }
}

