import Cocoa
import FinderSync

final class ActionDispatcher: NSObject {

    static let shared = ActionDispatcher()

    private let fileCreator = FileCreator()
    private let pathCopier = PathCopier()
    private let scriptRunner = ScriptRunner()

    // MARK: - Core dispatch

    func dispatch(
        _ action: MenuAction,
        selectedURLs: [URL]? = nil,
        targetURL: URL? = nil,
        isContainerMenu: Bool = false
    ) {
        NSLog("[RightMenu] dispatch: \(action.type.rawValue)")
        switch action.type {
        case .copyPath:   pathCopier.copyPath()
        case .copyName:   pathCopier.copyName()
        case .openTerminal: openTerminal(targetURL: targetURL, selectedURLs: selectedURLs, isContainerMenu: isContainerMenu)
        case .openITerm:  openITerm(targetURL: targetURL, selectedURLs: selectedURLs, isContainerMenu: isContainerMenu)
        case .deleteFile: trashSelectedItems(selectedURLs: selectedURLs)
        case .lockFile:   lockSelectedItems()
        case .showInfo:   showFileInfo()
        case .makeAlias:  makeDesktopAlias()
        case .qrShare:    showQRCode()
        case .setFolderIcon: openColorPanel()
        default: break
        }
    }

    func createFile(
        from template: FileTemplate,
        targetURL cachedTargetURL: URL? = nil,
        selectedURLs cachedSelectedURLs: [URL]? = nil,
        isContainerMenu: Bool = false
    ) {
        let url = cachedTargetURL ?? FIFinderSyncController.default().targetedURL()
        let selectedURLs = cachedSelectedURLs ?? FIFinderSyncController.default().selectedItemURLs() ?? []
        NSLog("[RightMenu] createFile targetedURL: \(url?.path ?? "nil"), selected=\(selectedURLs.map { $0.path }), isContainerMenu=\(isContainerMenu)")
        guard let targetURL = url else { return }
        let directoryURL = FinderTargetResolver.creationDirectory(
            targetURL: targetURL,
            selectedURLs: selectedURLs,
            isContainerMenu: isContainerMenu
        )
        NSLog("[RightMenu] createFile directoryURL: \(directoryURL.path)")
        fileCreator.createFile(from: template, at: directoryURL)
    }

    func runScript(action: MenuAction, targetURL cachedTargetURL: URL? = nil) {
        guard let script = action.scriptContent,
              let targetURL = cachedTargetURL ?? FIFinderSyncController.default().targetedURL() else { return }
        scriptRunner.run(script: script, at: targetURL)
    }

    func moveItems(to destination: String) {
        for url in FIFinderSyncController.default().selectedItemURLs() ?? [] {
            try? FileManager.default.moveItem(
                at: url,
                to: URL(fileURLWithPath: destination).appendingPathComponent(url.lastPathComponent)
            )
        }
    }

    func copyItems(to destination: String) {
        for url in FIFinderSyncController.default().selectedItemURLs() ?? [] {
            try? FileManager.default.copyItem(
                at: url,
                to: URL(fileURLWithPath: destination).appendingPathComponent(url.lastPathComponent)
            )
        }
    }

    // MARK: - Terminal

    private func openTerminal(
        targetURL cachedTargetURL: URL? = nil,
        selectedURLs cachedSelectedURLs: [URL]? = nil,
        isContainerMenu: Bool = false
    ) {
        guard let targetURL = cachedTargetURL ?? FIFinderSyncController.default().targetedURL() else {
            NSLog("[RightMenu] openTerminal: missing targetURL")
            return
        }
        openDirectoryInApp(
            targetURL,
            selectedURLs: cachedSelectedURLs ?? FIFinderSyncController.default().selectedItemURLs() ?? [],
            isContainerMenu: isContainerMenu,
            command: .openTerminal,
            appName: "Terminal"
        )
    }

    private func openITerm(
        targetURL cachedTargetURL: URL? = nil,
        selectedURLs cachedSelectedURLs: [URL]? = nil,
        isContainerMenu: Bool = false
    ) {
        guard let targetURL = cachedTargetURL ?? FIFinderSyncController.default().targetedURL() else {
            NSLog("[RightMenu] openITerm: missing targetURL")
            return
        }
        openDirectoryInApp(
            targetURL,
            selectedURLs: cachedSelectedURLs ?? FIFinderSyncController.default().selectedItemURLs() ?? [],
            isContainerMenu: isContainerMenu,
            command: .openITerm,
            appName: "iTerm"
        )
    }

    private func openDirectoryInApp(
        _ targetURL: URL,
        selectedURLs: [URL],
        isContainerMenu: Bool,
        command: AppCommand,
        appName: String
    ) {
        let directoryURL = FinderTargetResolver.creationDirectory(
            targetURL: targetURL,
            selectedURLs: selectedURLs,
            isContainerMenu: isContainerMenu
        )

        NSLog("[RightMenu] request open \(appName) at \(directoryURL.path)")
        guard let commandURL = AppCommandURL.url(command: command, path: directoryURL.path) else {
            NSLog("[RightMenu] open \(appName) command URL build failed: \(directoryURL.path)")
            return
        }
        NSWorkspace.shared.open(commandURL)
    }

    // MARK: - File Operations

    private func trashSelectedItems(selectedURLs cachedSelectedURLs: [URL]? = nil) {
        let urls = cachedSelectedURLs ?? FIFinderSyncController.default().selectedItemURLs() ?? []
        guard !urls.isEmpty else {
            NSLog("[RightMenu] trashSelectedItems: no selected URLs")
            return
        }

        NSLog("[RightMenu] trashSelectedItems: \(urls.map { $0.path })")
        for url in urls {
            do {
                var trashedURL: NSURL?
                try FileManager.default.trashItem(at: url, resultingItemURL: &trashedURL)
                NSLog("[RightMenu] trashed item: \(url.path)")
            } catch {
                NSLog("[RightMenu] trash failed: \(error.localizedDescription), path: \(url.path)")
            }
        }
    }

    private func lockSelectedItems() {
        for url in FIFinderSyncController.default().selectedItemURLs() ?? [] {
            var mutableURL = url
            var values = URLResourceValues()
            values.isUserImmutable = true
            try? mutableURL.setResourceValues(values)
        }
    }

    private func showFileInfo() {
        guard let first = FIFinderSyncController.default().selectedItemURLs()?.first else { return }
        NSWorkspace.shared.activateFileViewerSelecting([first])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSAppleScript(source: """
            tell application "Finder"
                activate
                tell front window to open information window
            end tell
            """)?.executeAndReturnError(nil)
        }
    }

    private func makeDesktopAlias() {
        let desktop = RealHomeDirectory.url
            .appendingPathComponent("Desktop")
        for url in FIFinderSyncController.default().selectedItemURLs() ?? [] {
            let aliasURL = desktop.appendingPathComponent("\(url.lastPathComponent) alias")
            try? FileManager.default.createSymbolicLink(at: aliasURL, withDestinationURL: url)
        }
    }

    // MARK: - QR Code

    private func showQRCode() {
        guard let first = FIFinderSyncController.default().selectedItemURLs()?.first,
              let filter = CIFilter(name: "CIQRCodeGenerator") else { return }
        filter.setValue(Data(first.absoluteString.utf8), forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")
        guard let ciImage = filter.outputImage else { return }

        let rep = NSCIImageRep(ciImage: ciImage)
        let nsImage = NSImage(size: rep.size)
        nsImage.addRepresentation(rep)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        window.title = "QR Code - \(first.lastPathComponent)"
        window.center()
        let imageView = NSImageView(frame: NSRect(x: 10, y: 10, width: 280, height: 280))
        imageView.image = nsImage
        imageView.imageScaling = .scaleProportionallyUpOrDown
        window.contentView?.addSubview(imageView)
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - Folder Icon Color

    private func openColorPanel() {
        let panel = NSColorPanel.shared
        panel.setTarget(self)
        panel.setAction(#selector(applyColor(_:)))
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func applyColor(_ sender: NSColorPanel) {
        let color = sender.color
        for url in FIFinderSyncController.default().selectedItemURLs() ?? [] where url.hasDirectoryPath {
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.lockFocus()
            color.setFill()
            NSGraphicsContext.current?.cgContext.fill(CGRect(x: 0, y: 0, width: icon.size.width, height: icon.size.height))
            icon.unlockFocus()
            NSWorkspace.shared.setIcon(icon, forFile: url.path)
        }
    }

}
