import Cocoa
import FinderSync

final class FinderSync: FIFinderSync {

    private let menuBuilder = MenuBuilder()
    private let dispatcher = ActionDispatcher()

    override init() {
        super.init()
        FIFinderSyncController.default().directoryURLs = Set([URL(fileURLWithPath: "/")])
    }

    // MARK: - Menu

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems ||
              menuKind == .contextualMenuForContainer else { return nil }

        let menu = NSMenu(title: "RightMenu Master")
        for action in UserDefaults.shared.loadConfig().sortedActions() {
            menu.addItem(menuItem(for: action))
        }
        return menu
    }

    private func menuItem(for action: MenuAction) -> NSMenuItem {
        switch action.type {
        case .newFile:  return buildNewFileSubmenu(action)
        case .moveTo:   return buildMoveToSubmenu(action)
        case .copyTo:   return buildCopyToSubmenu(action)
        default:        return buildStandardItem(action)
        }
    }

    private func buildStandardItem(_ action: MenuAction) -> NSMenuItem {
        let selector: Selector = action.type == .customScript
            ? #selector(runScriptAction(_:))
            : #selector(handleAction(_:))
        let item = NSMenuItem(title: action.title, action: selector, keyEquivalent: "")
        item.representedObject = action
        item.target = self
        return item
    }

    // MARK: - Submenus

    private func buildNewFileSubmenu(_ action: MenuAction) -> NSMenuItem {
        let item = NSMenuItem(title: action.title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "New File")
        for template in UserDefaults.shared.loadConfig().allTemplates() {
            let t = NSMenuItem(title: template.displayName,
                               action: #selector(createFileAction(_:)),
                               keyEquivalent: "")
            t.representedObject = template
            t.target = self
            submenu.addItem(t)
        }
        item.submenu = submenu
        return item
    }

    private func buildMoveToSubmenu(_ action: MenuAction) -> NSMenuItem {
        return buildFolderSubmenu(title: action.title, title2: "Move To",
                                   folders: UserDefaults.shared.loadConfig().moveToFolders,
                                   selector: #selector(moveItemsAction(_:)))
    }

    private func buildCopyToSubmenu(_ action: MenuAction) -> NSMenuItem {
        return buildFolderSubmenu(title: action.title, title2: "Copy To",
                                   folders: UserDefaults.shared.loadConfig().copyToFolders,
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
            for folder in folders {
                let f = NSMenuItem(title: URL(fileURLWithPath: folder).lastPathComponent,
                                   action: selector, keyEquivalent: "")
                f.representedObject = folder
                f.target = self
                f.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
                submenu.addItem(f)
            }
        }
        item.submenu = submenu
        return item
    }

    // MARK: - Selectors → Dispatcher

    @objc private func handleAction(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? MenuAction else { return }
        dispatcher.dispatch(action)
    }

    @objc private func createFileAction(_ sender: NSMenuItem) {
        guard let template = sender.representedObject as? FileTemplate else { return }
        dispatcher.createFile(from: template)
    }

    @objc private func runScriptAction(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? MenuAction else { return }
        dispatcher.runScript(action: action)
    }

    @objc private func moveItemsAction(_ sender: NSMenuItem) {
        guard let destination = sender.representedObject as? String else { return }
        dispatcher.moveItems(to: destination)
    }

    @objc private func copyItemsAction(_ sender: NSMenuItem) {
        guard let destination = sender.representedObject as? String else { return }
        dispatcher.copyItems(to: destination)
    }
}
