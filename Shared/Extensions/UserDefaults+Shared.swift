import Foundation

extension UserDefaults {
    static var shared: UserDefaults {
        UserDefaults(suiteName: Constants.appGroupID) ?? .standard
    }

    func loadConfig() -> AppConfig {
        guard let data = data(forKey: Constants.configKey),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data) else {
            return .default
        }
        return config
    }

    func saveConfig(_ config: AppConfig) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        set(data, forKey: Constants.configKey)
        synchronize()
    }

    func loadTemplates() -> [FileTemplate] {
        guard let data = data(forKey: Constants.templatesKey),
              let templates = try? JSONDecoder().decode([FileTemplate].self, from: data) else {
            return []
        }
        return templates
    }

    func saveTemplates(_ templates: [FileTemplate]) {
        guard let data = try? JSONEncoder().encode(templates) else { return }
        set(data, forKey: Constants.templatesKey)
        synchronize()
    }
}
