import Cocoa
import FinderSync

final class FinderSync: FIFinderSync {

    private var cachedActions: [MenuAction] = []
    private var cachedTemplates: [FileTemplate] = []
    private var cachedMoveFolders: [String] = []
    private var cachedCopyFolders: [String] = []
    private var cachedTargetURL: URL?
    private var cachedSelectedURLs: [URL] = []
    private var cachedMenuIsContainer = false

    override init() {
        super.init()
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(authorizedFoldersDidChange(_:)),
            name: Notification.Name(Constants.authorizedFoldersChangedNotificationName),
            object: nil
        )
        configureMonitoredDirectories()
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    private func configureMonitoredDirectories() {
        let directoryURLs = FinderMonitorDirectories.urls(
            authorizedFolders: AuthorizedFolderStore.shared.load()
        )
        FIFinderSyncController.default().directoryURLs = directoryURLs
        NSLog("[RightMenu] monitored directories=\(directoryURLs.map { $0.path }.sorted())")
    }

    @objc private func authorizedFoldersDidChange(_ notification: Notification) {
        NSLog("[RightMenu] authorized folders changed; refreshing monitored directories")
        configureMonitoredDirectories()
    }

    // MARK: - Menu

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems ||
              menuKind == .contextualMenuForContainer else { return nil }

        configureMonitoredDirectories()

        let config = UserDefaults.shared.loadConfig()
        let actions = config.sortedActions()
        let templates = config.allTemplates()

        cachedActions = actions
        cachedTemplates = templates
        cachedMoveFolders = config.moveToFolders
        cachedCopyFolders = config.copyToFolders
        cachedTargetURL = FIFinderSyncController.default().targetedURL()
        cachedSelectedURLs = FIFinderSyncController.default().selectedItemURLs() ?? []
        cachedMenuIsContainer = menuKind == .contextualMenuForContainer
        NSLog("[RightMenu] menu kind=\(menuKind.rawValue), target=\(cachedTargetURL?.path ?? "nil"), selected=\(cachedSelectedURLs.map { $0.path })")

        let menu = NSMenu(title: "RightMenu Master")
        for (index, action) in actions.enumerated() {
            menu.addItem(menuItem(for: action, tag: index))
        }
        return menu
    }

    private func menuItem(for action: MenuAction, tag: Int) -> NSMenuItem {
        switch action.type {
        case .newFile:  return buildNewFileSubmenu(action)
        case .moveTo:   return buildMoveToSubmenu(action)
        case .copyTo:   return buildCopyToSubmenu(action)
        case .customScript: return buildScriptItem(action, tag: tag)
        default:        return buildStandardItem(action, tag: tag)
        }
    }

    private func buildStandardItem(_ action: MenuAction, tag: Int) -> NSMenuItem {
        let item = NSMenuItem(
            title: action.title,
            action: #selector(handleAction(_:)),
            keyEquivalent: ""
        )
        item.tag = tag
        return item
    }

    private func buildScriptItem(_ action: MenuAction, tag: Int) -> NSMenuItem {
        let item = NSMenuItem(
            title: action.title,
            action: #selector(runScriptAction(_:)),
            keyEquivalent: ""
        )
        item.tag = tag
        return item
    }

    // MARK: - Submenus

    private func buildNewFileSubmenu(_ action: MenuAction) -> NSMenuItem {
        let templates = UserDefaults.shared.loadConfig().allTemplates()
        
        // Find Markdown template index (default to first template if not found)
        let markdownIndex = templates.firstIndex { $0.ext.lowercased() == "md" } ?? 0
        
        // Main menu item creates Markdown by default
        let item = NSMenuItem(
            title: action.title,
            action: #selector(createFileAction(_:)),
            keyEquivalent: ""
        )
        item.tag = markdownIndex
        
        // Submenu for other templates
        let submenu = NSMenu(title: "New File")
        for (index, template) in templates.enumerated() {
            let t = NSMenuItem(
                title: template.displayName,
                action: #selector(createFileAction(_:)),
                keyEquivalent: ""
            )
            t.tag = index
            submenu.addItem(t)
        }
        item.submenu = submenu
        return item
    }

    private func buildMoveToSubmenu(_ action: MenuAction) -> NSMenuItem {
        let folders = UserDefaults.shared.loadConfig().moveToFolders
        return buildFolderSubmenu(title: action.title, title2: "Move To", folders: folders,
                                  selector: #selector(moveItemsAction(_:)))
    }

    private func buildCopyToSubmenu(_ action: MenuAction) -> NSMenuItem {
        let folders = UserDefaults.shared.loadConfig().copyToFolders
        return buildFolderSubmenu(title: action.title, title2: "Copy To", folders: folders,
                                  selector: #selector(copyItemsAction(_:)))
    }

    private func buildFolderSubmenu(title: String, title2: String, folders: [String],
                                     selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: title2)
        if folders.isEmpty {
            let empty = NSMenuItem(title: "No folders configured", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
        } else {
            for (index, folder) in folders.enumerated() {
                let f = NSMenuItem(
                    title: URL(fileURLWithPath: folder).lastPathComponent,
                    action: selector,
                    keyEquivalent: ""
                )
                f.tag = index
                f.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
                submenu.addItem(f)
            }
        }
        item.submenu = submenu
        return item
    }

    // MARK: - Menu Actions

    @objc func handleAction(_ sender: NSMenuItem) {
        NSLog("[RightMenu] FinderSync.handleAction tag=\(sender.tag)")
        guard cachedActions.indices.contains(sender.tag) else {
            NSLog("[RightMenu] FAILED: tag \(sender.tag) out of bounds (actions=\(cachedActions.count))")
            return
        }
        ActionDispatcher.shared.dispatch(
            cachedActions[sender.tag],
            selectedURLs: cachedSelectedURLs,
            targetURL: cachedTargetURL,
            isContainerMenu: cachedMenuIsContainer
        )
    }

    @objc func createFileAction(_ sender: NSMenuItem) {
        NSLog("[RightMenu] FinderSync.createFileAction tag=\(sender.tag)")
        guard cachedTemplates.indices.contains(sender.tag) else {
            NSLog("[RightMenu] FAILED: tag \(sender.tag) out of bounds (templates=\(cachedTemplates.count))")
            return
        }
        ActionDispatcher.shared.createFile(
            from: cachedTemplates[sender.tag],
            targetURL: cachedTargetURL,
            selectedURLs: cachedSelectedURLs,
            isContainerMenu: cachedMenuIsContainer
        )
    }

    @objc func runScriptAction(_ sender: NSMenuItem) {
        guard cachedActions.indices.contains(sender.tag) else { return }
        ActionDispatcher.shared.runScript(action: cachedActions[sender.tag], targetURL: cachedTargetURL)
    }

    @objc func moveItemsAction(_ sender: NSMenuItem) {
        guard cachedMoveFolders.indices.contains(sender.tag) else { return }
        ActionDispatcher.shared.moveItems(to: cachedMoveFolders[sender.tag])
    }

    @objc func copyItemsAction(_ sender: NSMenuItem) {
        guard cachedCopyFolders.indices.contains(sender.tag) else { return }
        ActionDispatcher.shared.copyItems(to: cachedCopyFolders[sender.tag])
    }
}
