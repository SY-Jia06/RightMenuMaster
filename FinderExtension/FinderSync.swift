import Cocoa
import FinderSync

class FinderSync: FIFinderSync {

    private let menuBuilder = MenuBuilder()
    private let fileCreator = FileCreator()
    private let pathCopier = PathCopier()
    private let scriptRunner = ScriptRunner()

    override init() {
        super.init()
        let defaultFolders = Set([URL(fileURLWithPath: "/")])
        FIFinderSyncController.default().directoryURLs = defaultFolders
    }

    // MARK: - Menu

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems ||
              menuKind == .contextualMenuForContainer else {
            return nil
        }

        let menu = NSMenu(title: "RightMenu Master")
        let config = UserDefaults.shared.loadConfig()
        let actions = config.sortedActions()

        for action in actions {
            let item = menuItem(for: action)
            menu.addItem(item)
        }

        return menu
    }

    private func menuItem(for action: MenuAction) -> NSMenuItem {
        switch action.type {
        case .newFile:
            return buildNewFileMenu(action: action)
        case .moveTo:
            return buildMoveToMenu(action: action)
        case .copyTo:
            return buildCopyToMenu(action: action)
        case .customScript:
            let item = NSMenuItem(
                title: action.title,
                action: #selector(runCustomScript(_:)),
                keyEquivalent: ""
            )
            item.representedObject = action
            item.target = self
            return item
        default:
            let item = NSMenuItem(
                title: action.title,
                action: #selector(handleStandardAction(_:)),
                keyEquivalent: ""
            )
            item.representedObject = action
            item.target = self
            return item
        }
    }

    // MARK: - Submenus

    private func buildNewFileMenu(action: MenuAction) -> NSMenuItem {
        let item = NSMenuItem(title: action.title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "New File")
        let config = UserDefaults.shared.loadConfig()

        for template in config.allTemplates() {
            let templateItem = NSMenuItem(
                title: template.displayName,
                action: #selector(createNewFileFromTemplate(_:)),
                keyEquivalent: ""
            )
            templateItem.representedObject = template
            templateItem.target = self
            submenu.addItem(templateItem)
        }

        item.submenu = submenu
        return item
    }

    private func buildMoveToMenu(action: MenuAction) -> NSMenuItem {
        let item = NSMenuItem(title: action.title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Move To")
        let config = UserDefaults.shared.loadConfig()

        for folder in config.moveToFolders {
            let folderURL = URL(fileURLWithPath: folder)
            let folderItem = NSMenuItem(
                title: folderURL.lastPathComponent,
                action: #selector(moveSelectedItems(_:)),
                keyEquivalent: ""
            )
            folderItem.representedObject = folder
            folderItem.target = self
            folderItem.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
            submenu.addItem(folderItem)
        }

        if config.moveToFolders.isEmpty {
            let emptyItem = NSMenuItem(title: "No folders configured", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            submenu.addItem(emptyItem)
        }

        item.submenu = submenu
        return item
    }

    private func buildCopyToMenu(action: MenuAction) -> NSMenuItem {
        let item = NSMenuItem(title: action.title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Copy To")
        let config = UserDefaults.shared.loadConfig()

        for folder in config.copyToFolders {
            let folderURL = URL(fileURLWithPath: folder)
            let folderItem = NSMenuItem(
                title: folderURL.lastPathComponent,
                action: #selector(copySelectedItems(_:)),
                keyEquivalent: ""
            )
            folderItem.representedObject = folder
            folderItem.target = self
            folderItem.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
            submenu.addItem(folderItem)
        }

        if config.copyToFolders.isEmpty {
            let emptyItem = NSMenuItem(title: "No folders configured", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            submenu.addItem(emptyItem)
        }

        item.submenu = submenu
        return item
    }

    // MARK: - Actions

    @objc private func handleStandardAction(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? MenuAction else { return }

        switch action.type {
        case .copyPath:
            pathCopier.copyPath()
        case .copyName:
            pathCopier.copyName()
        case .openTerminal:
            openTerminal()
        case .openITerm:
            openITerm()
        case .deleteFile:
            deleteSelectedItems()
        case .lockFile:
            lockSelectedItems()
        case .showInfo:
            showFileInfo()
        case .makeAlias:
            makeAlias()
        case .qrShare:
            qrShare()
        case .setFolderIcon:
            setFolderIcon()
        default:
            break
        }
    }

    @objc private func createNewFileFromTemplate(_ sender: NSMenuItem) {
        guard let template = sender.representedObject as? FileTemplate,
              let targetURL = FIFinderSyncController.default().targetedURL() else { return }

        fileCreator.createFile(from: template, at: targetURL)
    }

    @objc private func runCustomScript(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? MenuAction,
              let script = action.scriptContent,
              let targetURL = FIFinderSyncController.default().targetedURL() else { return }

        scriptRunner.run(script: script, at: targetURL)
    }

    @objc private func moveSelectedItems(_ sender: NSMenuItem) {
        guard let destination = sender.representedObject as? String else { return }
        let items = FIFinderSyncController.default().selectedItemURLs() ?? []
        for url in items {
            try? FileManager.default.moveItem(
                at: url,
                to: URL(fileURLWithPath: destination).appendingPathComponent(url.lastPathComponent)
            )
        }
    }

    @objc private func copySelectedItems(_ sender: NSMenuItem) {
        guard let destination = sender.representedObject as? String else { return }
        let items = FIFinderSyncController.default().selectedItemURLs() ?? []
        for url in items {
            try? FileManager.default.copyItem(
                at: url,
                to: URL(fileURLWithPath: destination).appendingPathComponent(url.lastPathComponent)
            )
        }
    }

    // MARK: - Utility Actions

    private func openTerminal() {
        guard let targetURL = FIFinderSyncController.default().targetedURL() else { return }
        NSWorkspace.shared.open(
            [URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")],
            withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
            configuration: NSWorkspace.OpenConfiguration()
        ) { _, _ in }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let script = """
            tell application "Terminal"
                activate
                do script "cd \(targetURL.path.replacingOccurrences(of: "\"", with: "\\\""))"
            end tell
            """
            NSAppleScript(source: script)?.executeAndReturnError(nil)
        }
    }

    private func openITerm() {
        guard let targetURL = FIFinderSyncController.default().targetedURL() else { return }
        let path = targetURL.path.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "iTerm"
            if it is running then
                tell current window
                    create tab with default profile
                    tell current session
                        write text "cd \\"\(path)\\"; clear"
                    end tell
                end tell
            else
                tell current window
                    tell current session
                        write text "cd \\"\(path)\\"; clear"
                    end tell
                end tell
            end if
            activate
        end tell
        """
        NSAppleScript(source: script)?.executeAndReturnError(nil)
    }

    private func deleteSelectedItems() {
        let items = FIFinderSyncController.default().selectedItemURLs() ?? []
        for url in items {
            try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
    }

    private func lockSelectedItems() {
        let items = FIFinderSyncController.default().selectedItemURLs() ?? []
        for url in items {
            var url = url
            var resourceValues = URLResourceValues()
            resourceValues.isUserImmutable = true
            try? url.setResourceValues(resourceValues)
        }
    }

    private func showFileInfo() {
        let items = FIFinderSyncController.default().selectedItemURLs() ?? []
        guard let first = items.first else { return }
        NSWorkspace.shared.activateFileViewerSelecting([first])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let script = """
            tell application "Finder"
                activate
                tell front window
                    open information window
                end tell
            end tell
            """
            NSAppleScript(source: script)?.executeAndReturnError(nil)
        }
    }

    private func makeAlias() {
        let items = FIFinderSyncController.default().selectedItemURLs() ?? []
        let desktop = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop")
        for url in items {
            let aliasURL = desktop.appendingPathComponent("\(url.lastPathComponent) alias")
            try? FileManager.default.createSymbolicLink(at: aliasURL, withDestinationURL: url)
        }
    }

    private func qrShare() {
        let items = FIFinderSyncController.default().selectedItemURLs() ?? []
        guard let first = items.first else { return }
        // Generate QR code from file URL
        let urlString = first.absoluteString
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return }
        let data = Data(urlString.utf8)
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")
        guard let ciImage = filter.outputImage else { return }

        let rep = NSCIImageRep(ciImage: ciImage)
        let nsImage = NSImage(size: rep.size)
        nsImage.addRepresentation(rep)

        // Show preview window with QR code
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "QR Code - \(first.lastPathComponent)"
        window.center()

        let imageView = NSImageView(frame: NSRect(x: 10, y: 10, width: 280, height: 280))
        imageView.image = nsImage
        imageView.imageScaling = .scaleProportionallyUpOrDown
        window.contentView?.addSubview(imageView)
        window.makeKeyAndOrderFront(nil)
    }

    private func setFolderIcon() {
        let panel = NSColorPanel.shared
        panel.setTarget(self)
        panel.setAction(#selector(colorSelected(_:)))
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func colorSelected(_ sender: NSColorPanel) {
        let items = FIFinderSyncController.default().selectedItemURLs() ?? []
        let color = sender.color
        for url in items where url.hasDirectoryPath {
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.lockFocus()
            color.setFill()
            NSGraphicsContext.current?.cgContext.fill(CGRect(x: 0, y: 0, width: icon.size.width, height: icon.size.height))
            icon.unlockFocus()
            NSWorkspace.shared.setIcon(icon, forFile: url.path)
        }
    }
}
