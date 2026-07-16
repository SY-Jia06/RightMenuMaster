import AppKit
import Foundation
import OSLog
import SwiftUI

private let coordinatorLog = Logger(
  subsystem: Bundle.main.bundleIdentifier ?? "io.github.syjia06.rightclickmaster",
  category: "Coordinator"
)

enum RootDestination {
  case onboarding
  case settings
}

enum SettingsDestination: String, CaseIterable, Identifiable {
  case actions
  case applications
  case system

  var id: String { rawValue }

  var systemImage: String {
    switch self {
    case .actions: "list.bullet.rectangle"
    case .applications: "app.badge.checkmark"
    case .system: "gearshape"
    }
  }

  func title(language: V2Language) -> String {
    switch self {
    case .actions: V2Presentation.text("Actions", "操作", language: language)
    case .applications: V2Presentation.text("Applications", "应用", language: language)
    case .system: V2Presentation.text("System", "系统", language: language)
    }
  }
}

@MainActor
final class AppCoordinator: ObservableObject {
  @Published private(set) var config: V2Config
  @Published var rootDestination: RootDestination
  @Published var settingsDestination: SettingsDestination = .actions
  @Published var newFileSession: NewFileSession?
  @Published var errorMessage: String?

  let applicationCatalog: ApplicationCatalog
  let folderGrants: SecurityScopedFolderGrantStore
  let integrationHealth: IntegrationHealthService

  private let configurationStore: V2ConfigurationStore
  private let requestStore: ActionRequestStore?
  private let fileCreator: ExclusiveFileCreator
  private let applicationLauncher: NativeApplicationLauncher
  private lazy var commandConsumer = AppCommandConsumer(
    requestStore: requestStore,
    coordinator: self
  )

  init(
    configurationStore: V2ConfigurationStore = V2ConfigurationStore(),
    applicationCatalog: ApplicationCatalog? = nil,
    folderGrants: SecurityScopedFolderGrantStore? = nil,
    requestStore: ActionRequestStore? = try? ActionRequestStore.appGroup(
      identifier: Constants.appGroupID),
    fileCreator: ExclusiveFileCreator = ExclusiveFileCreator(),
    applicationLauncher: NativeApplicationLauncher? = nil
  ) {
    let resolvedCatalog = applicationCatalog ?? ApplicationCatalog()
    let resolvedFolderGrants = folderGrants ?? SecurityScopedFolderGrantStore()
    self.configurationStore = configurationStore
    self.applicationCatalog = resolvedCatalog
    self.folderGrants = resolvedFolderGrants
    self.requestStore = requestStore
    self.fileCreator = fileCreator
    self.applicationLauncher = applicationLauncher ?? NativeApplicationLauncher()

    let loaded = configurationStore.load()
    config = loaded
    rootDestination = loaded.onboardingStep < 4 ? .onboarding : .settings
    integrationHealth = IntegrationHealthService(
      requestStore: requestStore,
      fileCreator: fileCreator
    )
    resolvedCatalog.refresh(
      including: loaded.preferredTerminal,
      preferredEditor: loaded.preferredEditor
    )
  }

  var language: V2Language { config.language }
  var onboardingStep: Int { config.onboardingStep }

  func updateConfig(_ mutation: (inout V2Config) -> Void) {
    var updated = config
    mutation(&updated)
    updated = updated.normalized()
    do {
      try configurationStore.save(updated)
      config = updated
      applicationCatalog.refresh(
        including: updated.preferredTerminal,
        preferredEditor: updated.preferredEditor
      )
    } catch {
      errorMessage = V2Presentation.errorMessage(error, language: language)
    }
  }

  func setAction(_ action: ProductAction, enabled: Bool) {
    updateConfig { config in
      if enabled {
        if !config.enabledActions.contains(action) { config.enabledActions.append(action) }
      } else {
        config.enabledActions.removeAll { $0 == action }
      }
    }
  }

  func moveAction(from source: IndexSet, to destination: Int) {
    var order = config.actionOrder
    order.move(fromOffsets: source, toOffset: destination)
    updateConfig { $0.actionOrder = order }
  }

  func moveAction(_ action: ProductAction, by offset: Int) {
    guard let source = config.actionOrder.firstIndex(of: action) else { return }
    let destination = source + offset
    guard config.actionOrder.indices.contains(destination) else { return }
    var order = config.actionOrder
    order.swapAt(source, destination)
    updateConfig { $0.actionOrder = order }
  }

  func chooseApplication(for role: ApplicationRole) async {
    guard
      let application = await applicationCatalog.chooseApplication(
        for: role,
        language: language
      )
    else { return }
    updateConfig { config in
      switch role {
      case .terminal: config.preferredTerminal = application
      case .editor: config.preferredEditor = application
      }
    }
  }

  func setPreferredApplication(_ application: PreferredApplication?, for role: ApplicationRole) {
    updateConfig { config in
      switch role {
      case .terminal: config.preferredTerminal = application
      case .editor: config.preferredEditor = application
      }
    }
  }

  func authorizeFolder() async {
    do {
      _ = try await folderGrants.chooseAndAuthorizeFolder(language: language)
    } catch {
      errorMessage = V2Presentation.errorMessage(error, language: language)
    }
  }

  func revokeFolder(_ grant: SecurityScopedFolderGrant) {
    do {
      try folderGrants.revoke(grant)
    } catch {
      errorMessage = V2Presentation.errorMessage(error, language: language)
    }
  }

  func chooseSuggestedToolsIfNeeded() {
    updateConfig { config in
      if config.preferredTerminal == nil {
        config.preferredTerminal = applicationCatalog.terminals.first
      }
      if config.preferredEditor == nil { config.preferredEditor = applicationCatalog.editors.first }
    }
  }

  func advanceOnboarding() {
    if config.onboardingStep == 1 { chooseSuggestedToolsIfNeeded() }
    guard config.onboardingStep < 4 else {
      rootDestination = .settings
      return
    }
    updateConfig { $0.onboardingStep += 1 }
    if config.onboardingStep == 4 { rootDestination = .settings }
  }

  func retreatOnboarding() {
    guard config.onboardingStep > 0 else { return }
    updateConfig { $0.onboardingStep -= 1 }
  }

  func restartOnboarding() {
    updateConfig { $0.onboardingStep = 0 }
    rootDestination = .onboarding
  }

  func applicationDidBecomeActive() {
    try? folderGrants.refreshMonitoredFolders()
    applicationCatalog.refresh(
      including: config.preferredTerminal,
      preferredEditor: config.preferredEditor
    )
    integrationHealth.refreshExtensionState()
  }

  @discardableResult
  func consumeExternalURL(_ url: URL) -> Bool {
    commandConsumer.consume(url)
  }

  @discardableResult
  func consumeExternalRequest(id: UUID) -> Bool {
    commandConsumer.consume(requestID: id)
  }

  func consumePendingExternalRequests() -> Int {
    commandConsumer.consumePendingRequests()
  }

  func hasPendingExternalRequests() -> Bool {
    commandConsumer.hasPendingRequests()
  }

  func presentNewFile(in directory: URL) {
    newFileSession = NewFileSession(directory: directory, recipe: config.defaultRecipe)
    NSApp.activate(ignoringOtherApps: true)
  }

  func dismissNewFile() {
    newFileSession = nil
  }

  func createFile(filename: String, recipe: FileRecipe, in directory: URL) async throws
    -> CreatedFile
  {
    if folderGrants.grant(containing: directory) == nil {
      guard
        try await folderGrants.chooseAndAuthorizeFolder(for: directory, language: language) != nil
      else {
        throw CocoaError(.userCancelled)
      }
    }
    return try folderGrants.withAccess(to: directory) { authorizedDirectory in
      try fileCreator.create(filename: filename, recipe: recipe, in: authorizedDirectory)
    }
  }

  func performPostCreate(for fileURL: URL, openInPreferredEditor: Bool) async throws {
    let configuredBehavior = config.postCreateBehavior
    let behavior: PostCreateBehavior =
      openInPreferredEditor
      ? .openPreferredEditor
      : (configuredBehavior == .openPreferredEditor ? .reveal : configuredBehavior)

    switch behavior {
    case .reveal:
      NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    case .openPreferredEditor:
      guard let editor = config.preferredEditor else {
        throw NativeApplicationLaunchError.applicationNotSelected
      }
      try await folderGrants.withAsyncAccess(to: [fileURL]) { urls in
        try await applicationLauncher.open(urls, with: editor, catalog: applicationCatalog)
      }
    case .openSystemAssociation:
      try await folderGrants.withAsyncAccess(to: fileURL) { authorizedURL in
        guard NSWorkspace.shared.open(authorizedURL) else {
          throw NativeApplicationLaunchError.activationFailed
        }
      }
    }
  }

  func dispatch(_ request: ActionRequest) {
    coordinatorLog.notice("Dispatching \(request.action.rawValue, privacy: .public)")
    guard config.enabledActions.contains(request.action) else {
      reportError(
        V2Presentation.text(
          "This action is disabled in Settings.",
          "此操作已在设置中停用。",
          language: language
        ))
      return
    }

    do {
      let context = try request.invocationContext()
      let resolver = ContextResolver { [folderGrants] url in
        try folderGrants.withAccess(to: url) { try ContextResolver.fileSystemDirectoryProbe($0) }
      }
      let resolution = try resolver.resolve(
        request.action,
        in: context,
        editorCapabilities: applicationCatalog.editorCapabilities(for: config.preferredEditor)
      )
      guard let target = resolution.target, resolution.isEnabled else {
        throw AppCommandConsumerError.actionUnavailable
      }

      switch (request.action, target) {
      case (.newFile, .directory(let directory)):
        coordinatorLog.notice("Presenting New File panel")
        presentNewFile(in: directory)
      case (.copyPath, .subjects(let subjects)):
        let paths = subjects.map(\.path).joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(paths, forType: .string)
      case (.openTerminal, .directory(let directory)):
        guard let terminal = config.preferredTerminal else {
          throw NativeApplicationLaunchError.applicationNotSelected
        }
        Task {
          do {
            try await folderGrants.withAsyncAccess(to: [directory]) { urls in
              try await applicationLauncher.open(urls, with: terminal, catalog: applicationCatalog)
            }
          } catch { reportError(V2Presentation.errorMessage(error, language: language)) }
        }
      case (.openEditor, .subjects(let subjects)):
        guard let editor = config.preferredEditor else {
          throw NativeApplicationLaunchError.applicationNotSelected
        }
        Task {
          do {
            try await folderGrants.withAsyncAccess(to: subjects) { urls in
              try await applicationLauncher.open(urls, with: editor, catalog: applicationCatalog)
            }
          } catch { reportError(V2Presentation.errorMessage(error, language: language)) }
        }
      default:
        throw AppCommandConsumerError.actionUnavailable
      }
    } catch {
      coordinatorLog.error(
        "Dispatch for \(request.action.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .public)"
      )
      reportError(V2Presentation.errorMessage(error, language: language))
    }
  }

  func clearError() {
    errorMessage = nil
  }

  func reportError(_ message: String) {
    errorMessage = message
  }

  func openSafeTestFolder() {
    do {
      let folder = try integrationHealth.makeTestFolder()
      NSWorkspace.shared.open(folder)
    } catch {
      errorMessage = V2Presentation.errorMessage(error, language: language)
    }
  }
}
