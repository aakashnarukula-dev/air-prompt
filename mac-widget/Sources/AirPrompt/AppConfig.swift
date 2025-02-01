import Foundation

struct AppConfig: Decodable {
    let mobileURL: String
    let backendURL: String
}

enum AppConfigLoader {
    static let path = "/Users/aakashnarukula/Developer/Air Prompt/.run/demo-config.json"

    static func load() -> AppConfig? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return try? JSONDecoder().decode(AppConfig.self, from: data)
    }
}
