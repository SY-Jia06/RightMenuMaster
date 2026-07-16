import Cocoa
import FinderSync
import OSLog

private let finderCommandLog = Logger(
  subsystem: Bundle.main.bundleIdentifier ?? "io.github.syjia06.rightclickmaster.finder",
  category: "FinderCommand"
)

final class FinderSync: FIFinderSync {
  private static let knownMultiItemEditorIDs: Set<String> = [
    "com.coteditor.CotEditor",
    "dev.zed.Zed",
    "com.microsoft.VSCode",
    "com.todesktop.230313mzl4w4u92",
    "com.sublimetext.4",
    "com.barebones.bbedit",
    "com.apple.TextEdit",
  ]

  private let configurationStore = V2ConfigurationStore()
  private let requestStore: ActionRequestStore?
  private var cachedContext: InvocationContext?
  private var cachedActions: [ProductAction] = []

  override init() {
    requestStore = try? ActionRequestStore.appGroup(identifier: Constants.appGroupID)
    super.init()

    DistributedNotificationCenter.default().addObserver(
      self,
      selector: #selector(monitoredFoldersDidChange(_:)),
      name: Notification.Name(Constants.v2MonitoredFoldersChangedNotificationName),
      object: nil
    )
    configureMonitoredDirectories()
    recordHeartbeat()
  }

  deinit {
    DistributedNotificationCenter.default().removeObserver(self)
  }

  override func menu(for menuKind: FIMenuKind) -> NSMenu? {
    guard
      menuKind == .contextualMenuForContainer
        || menuKind == .contextualMenuForItems
    else {
      return nil
    }

    configureMonitoredDirectories()
    recordHeartbeat()

    guard let context = invocationContext(for: menuKind) else { return nil }
    let config = configurationStore.load()
    let orderedActions = config.actionOrder.filter(config.enabledActions.contains)
    guard !orderedActions.isEmpty else { return nil }

    cachedContext = context
    cachedActions = orderedActions

    let menu = NSMenu(title: "Right Click Master")
    let root = NSMenuItem(title: "Right Click Master", action: nil, keyEquivalent: "")
    root.image = NSImage(
      systemSymbolName: "contextualmenu.and.cursorarrow",
      accessibilityDescription: "Right Click Master"
    )

    let submenu = NSMenu(title: "Right Click Master")
    for (index, action) in orderedActions.enumerated() {
      submenu.addItem(
        actionMenuItem(
          action,
          tag: index,
          context: context,
          config: config
        )
      )
    }
    root.submenu = submenu
    menu.addItem(root)
    return menu
  }

  @objc private func performAction(_ sender: NSMenuItem) {
    guard cachedActions.indices.contains(sender.tag),
      let context = cachedContext
    else {
      return
    }

    let action = cachedActions[sender.tag]
    if action == .copyPath {
      copyPaths(from: context)
      return
    }

    do {
      guard let requestStore else {
        throw ActionRequestStoreError.appGroupUnavailable
      }
      let request = try ActionRequest(action: action, context: context)
      try requestStore.save(request)
      finderCommandLog.notice(
        "Stored request \(request.id.uuidString, privacy: .public) for \(action.rawValue, privacy: .public)"
      )
      DistributedNotificationCenter.default().postNotificationName(
        Notification.Name(Constants.v2FinderCommandReadyNotificationName),
        object: request.id.uuidString,
        userInfo: nil,
        deliverImmediately: true
      )
      guard let commandURL = commandURL(for: request.id) else {
        try? requestStore.remove(id: request.id)
        throw FinderHandoffError.hostActivationFailed
      }
      // Finder Sync is sandboxed. Its extension context is the supported
      // mechanism for asking macOS to open the containing app's URL scheme;
      // NSWorkspace.open may return false from an extension process.
      FIFinderSyncController.default().open(commandURL) { opened in
        finderCommandLog.notice(
          "Host activation for \(request.id.uuidString, privacy: .public): \(opened, privacy: .public)"
        )
        guard opened else {
          // Launch Services can report `false` even while it is asynchronously
          // delivering the URL. Keep the one-shot request for its short TTL so
          // the host can still claim it; a later save purges stale requests.
          finderCommandLog.warning(
            "Activation was not confirmed for \(request.id.uuidString, privacy: .public); retaining short-lived request"
          )
          return
        }
      }
    } catch {
      NSLog("[RightClickMaster] Finder handoff failed: %@", error.localizedDescription)
    }
  }

  @objc private func monitoredFoldersDidChange(_ notification: Notification) {
    configureMonitoredDirectories()
  }

  private func actionMenuItem(
    _ action: ProductAction,
    tag: Int,
    context: InvocationContext,
    config: V2Config
  ) -> NSMenuItem {
    let item = NSMenuItem(
      title: title(for: action, config: config),
      action: #selector(performAction(_:)),
      keyEquivalent: ""
    )
    item.target = self
    item.tag = tag
    item.image = NSImage(
      systemSymbolName: systemImageName(for: action),
      accessibilityDescription: title(for: action, config: config)
    )

    do {
      let resolution = try resolver(for: context).resolve(
        action,
        in: context,
        editorCapabilities: editorCapabilities(for: config.preferredEditor)
      )
      item.isEnabled = resolution.isEnabled
      if !resolution.isEnabled {
        item.toolTip = disabledReasonText(resolution.disabledReason, language: config.language)
      }
    } catch {
      item.isEnabled = false
      item.toolTip = error.localizedDescription
    }
    return item
  }

  private func invocationContext(for menuKind: FIMenuKind) -> InvocationContext? {
    let controller = FIFinderSyncController.default()
    if menuKind == .contextualMenuForContainer {
      guard let target = controller.targetedURL(), isPhysical(target) else { return nil }
      return InvocationContext(containerURL: target)
    }

    let selected = (controller.selectedItemURLs() ?? []).filter(isPhysical)
    guard !selected.isEmpty else { return nil }
    return InvocationContext(selectedURLs: selected)
  }

  private func resolver(for context: InvocationContext) -> ContextResolver {
    let knownContainer = context.kind == .container ? context.subjects.first?.path : nil
    return ContextResolver { url in
      if url.path == knownContainer || url.hasDirectoryPath {
        return true
      }

      var isDirectory: ObjCBool = false
      if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
        return isDirectory.boolValue
      }
      // Host revalidates under its security-scoped grant. Treat an item
      // without directory evidence as a file; never infer a writable path.
      return false
    }
  }

  private func copyPaths(from context: InvocationContext) {
    let paths = context.subjects.map(\.path).joined(separator: "\n")
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    guard pasteboard.setString(paths, forType: .string) else {
      NSLog("[RightClickMaster] Copy Path failed")
      return
    }
  }

  private func commandURL(for requestID: UUID) -> URL? {
    var components = URLComponents()
    components.scheme = Constants.urlScheme
    components.host = "command"
    components.queryItems = [URLQueryItem(name: "id", value: requestID.uuidString)]
    return components.url
  }

  private func configureMonitoredDirectories() {
    let defaults = UserDefaults(suiteName: Constants.appGroupID)
    let paths = defaults?.stringArray(forKey: Constants.v2MonitoredFolderPathsKey) ?? []
    let directories = paths.compactMap { path -> URL? in
      guard !path.isEmpty,
        !path.contains("\0"),
        (path as NSString).isAbsolutePath
      else {
        return nil
      }
      return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    }
    FIFinderSyncController.default().directoryURLs = Set(directories)
  }

  private func recordHeartbeat() {
    UserDefaults(suiteName: Constants.appGroupID)?.set(
      Date(),
      forKey: Constants.v2FinderExtensionHeartbeatKey
    )
  }

  private func isPhysical(_ url: URL) -> Bool {
    url.isFileURL
      && !url.path.isEmpty
      && !url.path.contains("\0")
      && (url.path as NSString).isAbsolutePath
  }

  private func editorCapabilities(for application: PreferredApplication?) -> EditorCapabilities {
    guard let application,
      Self.knownMultiItemEditorIDs.contains(application.id)
    else {
      return .singleItemOnly
    }
    return .mixedParentItems
  }

  private func title(for action: ProductAction, config: V2Config) -> String {
    let chinese = usesChinese(config.language)
    switch action {
    case .newFile:
      return chinese ? "新建文件…" : "New File…"
    case .copyPath:
      return chinese ? "复制路径" : "Copy Path"
    case .openTerminal:
      let name = config.preferredTerminal?.displayName ?? (chinese ? "终端" : "Terminal")
      return chinese ? "在 \(name) 中打开" : "Open in \(name)"
    case .openEditor:
      let name = config.preferredEditor?.displayName ?? (chinese ? "编辑器" : "Editor")
      return chinese ? "用 \(name) 打开" : "Open with \(name)"
    }
  }

  private func systemImageName(for action: ProductAction) -> String {
    switch action {
    case .newFile: "doc.badge.plus"
    case .copyPath: "doc.on.doc"
    case .openTerminal: "apple.terminal"
    case .openEditor: "square.and.pencil"
    }
  }

  private func disabledReasonText(
    _ reason: ActionDisabledReason?,
    language: V2Language
  ) -> String {
    let chinese = usesChinese(language)
    switch reason {
    case .mixedParentSelection:
      return chinese ? "所选项目不在同一文件夹" : "Selected items are in different folders."
    case .editorDoesNotSupportMultipleItems:
      return chinese ? "当前编辑器不支持同时打开多个项目" : "The selected editor does not support multiple items."
    case .editorDoesNotSupportMixedParentItems:
      return chinese
        ? "当前编辑器不支持跨文件夹选择" : "The selected editor does not support items from different folders."
    case nil:
      return chinese ? "此操作在当前选择中不可用" : "This action is unavailable for the current selection."
    }
  }

  private func usesChinese(_ language: V2Language) -> Bool {
    switch language {
    case .simplifiedChinese:
      return true
    case .english:
      return false
    case .system:
      return Locale.preferredLanguages.first?.hasPrefix("zh") == true
    }
  }
}

private enum FinderHandoffError: LocalizedError {
  case hostActivationFailed

  var errorDescription: String? {
    "Right Click Master could not be opened."
  }
}
