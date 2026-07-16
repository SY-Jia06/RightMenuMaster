import Foundation
import OSLog

private let commandLog = Logger(
  subsystem: Bundle.main.bundleIdentifier ?? "io.github.syjia06.rightclickmaster",
  category: "FinderCommand"
)

enum AppCommandConsumerError: LocalizedError {
  case invalidURL
  case sharedStoreUnavailable
  case requestMissing
  case actionUnavailable

  var errorDescription: String? {
    switch self {
    case .invalidURL:
      "The Finder request URL is invalid."
    case .sharedStoreUnavailable:
      "The shared App Group is unavailable. Check app and extension signing."
    case .requestMissing:
      "The Finder request is missing or was already consumed."
    case .actionUnavailable:
      "This action is not available for the current Finder selection."
    }
  }
}

/// Consumes one-shot Finder handoff URLs. URL payload is only a UUID; physical
/// paths remain inside the private App Group request file.
@MainActor
final class AppCommandConsumer {
  private let requestStore: ActionRequestStore?
  private weak var coordinator: AppCoordinator?

  init(requestStore: ActionRequestStore?, coordinator: AppCoordinator) {
    self.requestStore = requestStore
    self.coordinator = coordinator
  }

  @discardableResult
  func consume(_ url: URL) -> Bool {
    guard url.scheme == Constants.urlScheme,
      let requestID = requestIdentifier(from: url)
    else {
      return false
    }

    do {
      guard let requestStore else { throw AppCommandConsumerError.sharedStoreUnavailable }
      guard let request = try requestStore.consume(id: requestID) else {
        // The custom URL and distributed notification intentionally race.
        // A missing request normally means the other channel already claimed it.
        commandLog.notice(
          "Request \(requestID.uuidString, privacy: .public) was already consumed"
        )
        return true
      }
      commandLog.notice(
        "Consumed request \(requestID.uuidString, privacy: .public) for \(request.action.rawValue, privacy: .public)"
      )
      coordinator?.dispatch(request)
    } catch {
      commandLog.error(
        "Request \(requestID.uuidString, privacy: .public) failed: \(error.localizedDescription, privacy: .public)"
      )
      if let coordinator {
        coordinator.reportError(V2Presentation.errorMessage(error, language: coordinator.language))
      }
    }
    return true
  }

  @discardableResult
  func consume(requestID: UUID) -> Bool {
    guard let url = URL(string: "\(Constants.urlScheme)://command?id=\(requestID.uuidString)")
    else {
      coordinator?.reportError(AppCommandConsumerError.invalidURL.localizedDescription)
      return false
    }
    return consume(url)
  }

  /// Replays fresh one-shot requests after a Launch Services cold start.
  /// The store enforces TTL, regular-file checks, and atomic consumption.
  func consumePendingRequests() -> Int {
    guard let requestStore else {
      coordinator?.reportError(AppCommandConsumerError.sharedStoreUnavailable.localizedDescription)
      return 0
    }
    do {
      let ids = try requestStore.pendingRequestIDs()
      guard let latest = ids.last else { return 0 }
      // A cold launch has one presentation surface. If multiple clicks raced
      // before launch, honor the newest explicit action and remove older ones.
      for superseded in ids.dropLast() {
        try? requestStore.remove(id: superseded)
      }
      _ = consume(requestID: latest)
      return 1
    } catch {
      commandLog.error(
        "Pending request recovery failed: \(error.localizedDescription, privacy: .public)"
      )
      if let coordinator {
        coordinator.reportError(V2Presentation.errorMessage(error, language: coordinator.language))
      }
      return 0
    }
  }

  func hasPendingRequests() -> Bool {
    guard let requestStore else { return false }
    return ((try? requestStore.pendingRequestIDs())?.isEmpty == false)
  }

  private func requestIdentifier(from url: URL) -> UUID? {
    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    if let value = components?.queryItems?.first(where: {
      $0.name == "id" || $0.name == "requestID"
    })?.value,
      let id = UUID(uuidString: value)
    {
      return id
    }
    if let lastComponent = url.pathComponents.last,
      let id = UUID(uuidString: lastComponent)
    {
      return id
    }
    if let host = url.host, let id = UUID(uuidString: host) {
      return id
    }
    return nil
  }
}
