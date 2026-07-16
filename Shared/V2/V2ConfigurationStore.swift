import Foundation

extension Constants {
  static let v2ConfigurationKey = "v2.configuration"
  static let v2MonitoredFolderPathsKey = "v2.monitoredFolderPaths"
  static let v2FinderExtensionHeartbeatKey = "v2.finderExtensionHeartbeat"
  static let v2FinderCommandReadyNotificationName =
    "io.github.syjia06.rightclickmaster.v2.finder-command-ready"
  static let v2MonitoredFoldersChangedNotificationName =
    "io.github.syjia06.rightclickmaster.v2.monitored-folders-changed"
}

final class V2ConfigurationStore {
  private let defaults: UserDefaults
  private let key: String

  init(
    defaults: UserDefaults = UserDefaults(suiteName: Constants.appGroupID) ?? .standard,
    key: String = Constants.v2ConfigurationKey
  ) {
    self.defaults = defaults
    self.key = key
  }

  func load() -> V2Config {
    guard let data = defaults.data(forKey: key),
      let decoded = try? JSONDecoder().decode(V2Config.self, from: data)
    else {
      return .default
    }
    return decoded.normalized()
  }

  func save(_ config: V2Config) throws {
    let normalized = config.normalized()
    try normalized.validate()

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    defaults.set(try encoder.encode(normalized), forKey: key)
  }
}
