import AppKit
import Foundation

struct SecurityScopedFolderGrant: Codable, Hashable, Identifiable, Sendable {
  let id: UUID
  let displayName: String
  let path: String
  fileprivate let bookmarkData: Data

  fileprivate init(id: UUID = UUID(), displayName: String, path: String, bookmarkData: Data) {
    self.id = id
    self.displayName = displayName
    self.path = path
    self.bookmarkData = bookmarkData
  }
}

enum SecurityScopedGrantError: LocalizedError {
  case selectionIsNotDirectory
  case selectionDoesNotContain(String)
  case noGrant(URL)
  case bookmarkUnavailable(String)
  case accessDenied(String)

  var errorDescription: String? {
    switch self {
    case .selectionIsNotDirectory:
      "Choose a folder, not a file."
    case .selectionDoesNotContain(let name):
      "Choose \(name) or one of its parent folders."
    case .noGrant(let url):
      "Access to \(url.lastPathComponent) has not been granted."
    case .bookmarkUnavailable(let name):
      "The saved permission for \(name) is no longer available. Choose the folder again."
    case .accessDenied(let name):
      "macOS denied access to \(name). Choose the folder again to repair permission."
    }
  }
}

/// Owns persistent security-scoped bookmarks selected with NSOpenPanel.
/// It never requests Accessibility, Full Disk Access, or administrator access.
@MainActor
final class SecurityScopedFolderGrantStore: ObservableObject {
  @Published private(set) var grants: [SecurityScopedFolderGrant] = []

  private let defaults: UserDefaults
  private let monitoredFoldersDefaults: UserDefaults?
  private let storageKey: String
  private let monitoredFoldersKey: String
  private let fileManager: FileManager

  init(
    defaults: UserDefaults = .standard,
    monitoredFoldersDefaults: UserDefaults? = UserDefaults(suiteName: Constants.appGroupID),
    storageKey: String = "v2.securityScopedFolderGrants",
    monitoredFoldersKey: String = Constants.v2MonitoredFolderPathsKey,
    fileManager: FileManager = .default
  ) {
    self.defaults = defaults
    self.monitoredFoldersDefaults = monitoredFoldersDefaults
    self.storageKey = storageKey
    self.monitoredFoldersKey = monitoredFoldersKey
    self.fileManager = fileManager
    load()
  }

  @discardableResult
  func authorize(_ folderURL: URL) throws -> SecurityScopedFolderGrant {
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: folderURL.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else {
      throw SecurityScopedGrantError.selectionIsNotDirectory
    }

    let canonicalURL = folderURL.standardizedFileURL
    let bookmark = try canonicalURL.bookmarkData(
      options: .withSecurityScope,
      includingResourceValuesForKeys: [.nameKey, .isDirectoryKey],
      relativeTo: nil
    )
    let resourceName = try? canonicalURL.resourceValues(forKeys: [.localizedNameKey]).localizedName
    let grant = SecurityScopedFolderGrant(
      displayName: resourceName ?? canonicalURL.lastPathComponent,
      path: canonicalURL.path,
      bookmarkData: bookmark
    )

    grants.removeAll { pathsAreEqual($0.path, grant.path) }
    grants.append(grant)
    grants.sort { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    try persist()
    return grant
  }

  func chooseAndAuthorizeFolder(
    language: V2Language = .system,
    attachedTo window: NSWindow? = nil
  ) async throws
    -> SecurityScopedFolderGrant?
  {
    try await chooseAndAuthorizeFolder(for: nil, language: language, attachedTo: window)
  }

  func chooseAndAuthorizeFolder(
    for requiredDirectory: URL?,
    language: V2Language = .system,
    attachedTo window: NSWindow? = nil
  ) async throws -> SecurityScopedFolderGrant? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = false
    panel.prompt = V2Presentation.text("Allow", "允许", language: language)
    if let requiredDirectory {
      panel.directoryURL = requiredDirectory
      panel.message = V2Presentation.text(
        "Choose \(requiredDirectory.lastPathComponent) or one of its parent folders to allow file creation there.",
        "选择 \(requiredDirectory.lastPathComponent) 或其上级文件夹，允许在其中创建文件。",
        language: language
      )
    } else {
      panel.message = V2Presentation.text(
        "Choose Home or a working folder where Right Click Master may create files.",
        "选择主文件夹或工作目录，允许 Right Click Master 在其中创建文件。",
        language: language
      )
    }

    let response: NSApplication.ModalResponse
    if let window {
      response = await withCheckedContinuation { continuation in
        panel.beginSheetModal(for: window) { continuation.resume(returning: $0) }
      }
    } else {
      response = panel.runModal()
    }

    guard response == .OK, let url = panel.url else { return nil }
    if let requiredDirectory,
      !isAncestorPath(url.path, ofComponents: requiredDirectory.standardizedFileURL.pathComponents)
    {
      throw SecurityScopedGrantError.selectionDoesNotContain(requiredDirectory.lastPathComponent)
    }
    return try authorize(url)
  }

  func revoke(_ grant: SecurityScopedFolderGrant) throws {
    grants.removeAll { $0.id == grant.id }
    try persist()
  }

  func grant(containing url: URL) -> SecurityScopedFolderGrant? {
    let targetComponents = url.standardizedFileURL.pathComponents
    return
      grants
      .filter { isAncestorPath($0.path, ofComponents: targetComponents) }
      .max { $0.pathComponents.count < $1.pathComponents.count }
  }

  func withAccess<T>(to url: URL, operation: (URL) throws -> T) throws -> T {
    guard let grant = grant(containing: url) else {
      throw SecurityScopedGrantError.noGrant(url)
    }
    let grantedURL = try resolve(grant)
    guard grantedURL.startAccessingSecurityScopedResource() else {
      throw SecurityScopedGrantError.accessDenied(grant.displayName)
    }
    defer { grantedURL.stopAccessingSecurityScopedResource() }
    return try operation(url)
  }

  func withAsyncAccess<T>(to url: URL, operation: (URL) async throws -> T) async throws -> T {
    guard let grant = grant(containing: url) else {
      throw SecurityScopedGrantError.noGrant(url)
    }
    let grantedURL = try resolve(grant)
    guard grantedURL.startAccessingSecurityScopedResource() else {
      throw SecurityScopedGrantError.accessDenied(grant.displayName)
    }
    defer { grantedURL.stopAccessingSecurityScopedResource() }
    return try await operation(url)
  }

  func withAsyncAccess<T>(to urls: [URL], operation: ([URL]) async throws -> T) async throws -> T {
    var uniqueGrants: [SecurityScopedFolderGrant] = []
    for url in urls {
      guard let grant = grant(containing: url) else {
        throw SecurityScopedGrantError.noGrant(url)
      }
      if !uniqueGrants.contains(where: { $0.id == grant.id }) {
        uniqueGrants.append(grant)
      }
    }

    var accessedURLs: [URL] = []
    for grant in uniqueGrants {
      let grantedURL = try resolve(grant)
      guard grantedURL.startAccessingSecurityScopedResource() else {
        for accessedURL in accessedURLs {
          accessedURL.stopAccessingSecurityScopedResource()
        }
        throw SecurityScopedGrantError.accessDenied(grant.displayName)
      }
      accessedURLs.append(grantedURL)
    }
    defer {
      for accessedURL in accessedURLs {
        accessedURL.stopAccessingSecurityScopedResource()
      }
    }
    return try await operation(urls)
  }

  func resolve(_ grant: SecurityScopedFolderGrant) throws -> URL {
    var isStale = false
    let url: URL
    do {
      url = try URL(
        resolvingBookmarkData: grant.bookmarkData,
        options: [.withSecurityScope, .withoutUI],
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      )
    } catch {
      throw SecurityScopedGrantError.bookmarkUnavailable(grant.displayName)
    }

    if isStale {
      _ = try authorize(url)
    }
    return url
  }

  private func load() {
    guard let data = defaults.data(forKey: storageKey),
      let decoded = try? JSONDecoder().decode([SecurityScopedFolderGrant].self, from: data)
    else {
      grants = []
      return
    }
    grants = decoded
  }

  private func persist() throws {
    defaults.set(try JSONEncoder().encode(grants), forKey: storageKey)
    // Finder extension receives only lexical paths needed for directoryURLs.
    // Security-scoped bookmark bytes remain private to the host application.
    monitoredFoldersDefaults?.set(grants.map(\.path).sorted(), forKey: monitoredFoldersKey)
    DistributedNotificationCenter.default().postNotificationName(
      Notification.Name(Constants.v2MonitoredFoldersChangedNotificationName),
      object: Bundle.main.bundleIdentifier,
      userInfo: nil,
      deliverImmediately: true
    )
  }

  private func pathsAreEqual(_ lhs: String, _ rhs: String) -> Bool {
    URL(fileURLWithPath: lhs).standardizedFileURL.pathComponents
      == URL(fileURLWithPath: rhs).standardizedFileURL.pathComponents
  }

  private func isAncestorPath(_ path: String, ofComponents target: [String]) -> Bool {
    let ancestor = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.pathComponents
    guard ancestor.count <= target.count else { return false }
    return Array(target.prefix(ancestor.count)) == ancestor
  }
}

extension SecurityScopedFolderGrant {
  fileprivate var pathComponents: [String] {
    URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.pathComponents
  }
}
