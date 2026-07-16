import AppKit
import FinderSync
import Foundation

enum IntegrationHealthLevel: String, Sendable {
  case checking
  case healthy
  case attention
  case failed
}

struct IntegrationCheck: Identifiable, Equatable, Sendable {
  let id: String
  let title: String
  let detail: String
  let level: IntegrationHealthLevel

  var systemImage: String {
    switch level {
    case .checking: "clock"
    case .healthy: "checkmark.circle.fill"
    case .attention: "exclamationmark.triangle.fill"
    case .failed: "xmark.octagon.fill"
    }
  }
}

struct IntegrationHealthSnapshot: Equatable, Sendable {
  var checks: [IntegrationCheck]
  var lastCheckedAt: Date?

  static let checking = IntegrationHealthSnapshot(
    checks: [
      IntegrationCheck(
        id: "extension",
        title: "Finder integration",
        detail: "Checking extension state…",
        level: .checking
      )
    ],
    lastCheckedAt: nil
  )

  var isHealthy: Bool {
    !checks.isEmpty && checks.allSatisfy { $0.level == .healthy }
  }
}

/// Read-only integration checks. It never reads user folders, changes the
/// clipboard, or launches another application.
@MainActor
final class IntegrationHealthService: ObservableObject {
  static let heartbeatMaximumAge: TimeInterval = 120

  @Published private(set) var snapshot: IntegrationHealthSnapshot = .checking

  private let requestStore: ActionRequestStore?
  private let fileManager: FileManager
  private let fileCreator: ExclusiveFileCreator
  private let appGroupDefaults: UserDefaults?

  init(
    requestStore: ActionRequestStore?,
    fileManager: FileManager = .default,
    fileCreator: ExclusiveFileCreator = ExclusiveFileCreator(),
    appGroupDefaults: UserDefaults? = UserDefaults(suiteName: Constants.appGroupID)
  ) {
    self.requestStore = requestStore
    self.fileManager = fileManager
    self.fileCreator = fileCreator
    self.appGroupDefaults = appGroupDefaults
    refreshExtensionState()
  }

  var isExtensionEnabled: Bool {
    FIFinderSyncController.isExtensionEnabled
  }

  func showExtensionManagement() {
    FIFinderSyncController.showExtensionManagementInterface()
  }

  func refreshExtensionState() {
    let extensionEnabled = FIFinderSyncController.isExtensionEnabled
    let extensionCheck = IntegrationCheck(
      id: "extension",
      title: "Finder integration",
      detail: extensionEnabled
        ? "Finder extension is enabled."
        : "Enable Right Click Master in Login Items & Extensions.",
      level: extensionEnabled ? .healthy : .attention
    )
    var checks = snapshot.checks
    if let index = checks.firstIndex(where: { $0.id == extensionCheck.id }) {
      checks[index] = extensionCheck
    } else {
      checks.insert(extensionCheck, at: 0)
    }
    let heartbeat = heartbeatCheck(extensionEnabled: extensionEnabled, now: Date())
    if let index = checks.firstIndex(where: { $0.id == heartbeat.id }) {
      checks[index] = heartbeat
    } else {
      checks.insert(heartbeat, at: min(1, checks.count))
    }
    snapshot = IntegrationHealthSnapshot(
      checks: checks,
      lastCheckedAt: Date()
    )
  }

  /// Verifies shared request storage plus an exclusive create/remove cycle in
  /// app-owned temporary storage. All test artifacts are removed immediately.
  @discardableResult
  func runVerification() -> IntegrationHealthSnapshot {
    var checks: [IntegrationCheck] = []
    let extensionEnabled = FIFinderSyncController.isExtensionEnabled
    checks.append(
      IntegrationCheck(
        id: "extension",
        title: "Finder integration",
        detail: extensionEnabled
          ? "Finder extension is enabled." : "Finder extension is not enabled yet.",
        level: extensionEnabled ? .healthy : .attention
      )
    )

    checks.append(heartbeatCheck(extensionEnabled: extensionEnabled, now: Date()))

    checks.append(checkRequestRoundTrip())
    checks.append(checkTemporaryFileCycle())
    let result = IntegrationHealthSnapshot(checks: checks, lastCheckedAt: Date())
    snapshot = result
    return result
  }

  func makeTestFolder() throws -> URL {
    let folder = fileManager.temporaryDirectory
      .appendingPathComponent("Right Click Master Test", isDirectory: true)
    try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
  }

  private func checkRequestRoundTrip() -> IntegrationCheck {
    guard let requestStore else {
      return IntegrationCheck(
        id: "handoff",
        title: "Extension handoff",
        detail: "Shared App Group storage is unavailable. Check signing and entitlements.",
        level: .failed
      )
    }

    let testDirectory = fileManager.temporaryDirectory
    do {
      let request = try ActionRequest(
        action: .copyPath,
        context: InvocationContext(containerURL: testDirectory)
      )
      try requestStore.save(request)
      defer { try? requestStore.remove(id: request.id) }
      guard try requestStore.load(id: request.id) == request else {
        throw IntegrationHealthError.requestMismatch
      }
      try requestStore.remove(id: request.id)
      return IntegrationCheck(
        id: "handoff",
        title: "Extension handoff",
        detail: "Shared request storage passed a write/read/remove cycle.",
        level: .healthy
      )
    } catch {
      return IntegrationCheck(
        id: "handoff",
        title: "Extension handoff",
        detail: "Shared request storage failed. Check App Group entitlements.",
        level: .failed
      )
    }
  }

  private func heartbeatCheck(extensionEnabled: Bool, now: Date) -> IntegrationCheck {
    guard extensionEnabled else {
      return IntegrationCheck(
        id: "heartbeat",
        title: "Finder handshake",
        detail: "Enable the Finder extension first.",
        level: .attention
      )
    }
    guard
      let heartbeat = appGroupDefaults?.object(forKey: Constants.v2FinderExtensionHeartbeatKey)
        as? Date
    else {
      return IntegrationCheck(
        id: "heartbeat",
        title: "Finder handshake",
        detail: "After enabling, open Finder and right-click once.",
        level: .attention
      )
    }

    let age = now.timeIntervalSince(heartbeat)
    guard age >= 0, age <= Self.heartbeatMaximumAge else {
      return IntegrationCheck(
        id: "heartbeat",
        title: "Finder handshake",
        detail: "Open Finder and right-click once to refresh the handshake.",
        level: .attention
      )
    }
    return IntegrationCheck(
      id: "heartbeat",
      title: "Finder handshake",
      detail: "Finder extension recently reached shared storage.",
      level: .healthy
    )
  }

  private func checkTemporaryFileCycle() -> IntegrationCheck {
    let directory = fileManager.temporaryDirectory
      .appendingPathComponent("RightClickMaster-Health-\(UUID().uuidString)", isDirectory: true)
    do {
      try fileManager.createDirectory(at: directory, withIntermediateDirectories: false)
      defer { try? fileManager.removeItem(at: directory) }
      let created = try fileCreator.create(
        filename: "health-check",
        recipe: .blank,
        in: directory
      )
      try fileManager.removeItem(at: created.url)
      return IntegrationCheck(
        id: "creation",
        title: "Safe file creation",
        detail: "Exclusive create/remove cycle passed in app-owned temporary storage.",
        level: .healthy
      )
    } catch {
      return IntegrationCheck(
        id: "creation",
        title: "Safe file creation",
        detail: "The app could not complete its temporary create/remove check.",
        level: .failed
      )
    }
  }
}

private enum IntegrationHealthError: Error {
  case requestMismatch
}
