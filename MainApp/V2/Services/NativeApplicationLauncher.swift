import AppKit
import Foundation

enum NativeApplicationLaunchError: LocalizedError {
  case applicationNotSelected
  case applicationUnavailable(String)
  case activationFailed

  var errorDescription: String? {
    switch self {
    case .applicationNotSelected:
      "Choose an application in Settings and retry."
    case .applicationUnavailable(let name):
      "\(name) is unavailable. Choose another installed application in Settings."
    case .activationFailed:
      "macOS could not open the item. The file was not changed."
    }
  }
}

@MainActor
final class NativeApplicationLauncher {
  private let workspace: NSWorkspace

  init(workspace: NSWorkspace = .shared) {
    self.workspace = workspace
  }

  func open(
    _ urls: [URL],
    with application: PreferredApplication,
    catalog: ApplicationCatalog
  ) async throws {
    guard let applicationURL = catalog.resolvedURL(for: application) else {
      throw NativeApplicationLaunchError.applicationUnavailable(application.displayName)
    }

    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    configuration.addsToRecentItems = true

    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      workspace.open(
        urls,
        withApplicationAt: applicationURL,
        configuration: configuration
      ) { _, error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume()
        }
      }
    }
  }
}
