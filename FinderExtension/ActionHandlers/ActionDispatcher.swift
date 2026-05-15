import Cocoa
import FinderSync

final class ActionDispatcher {

    private let fileCreator = FileCreator()
    private let pathCopier = PathCopier()
    private let scriptRunner = ScriptRunner()

    func dispatch(_ action: MenuAction) {
        switch action.type {
        case .copyPath:   pathCopier.copyPath()
        case .copyName:   pathCopier.copyName()
        case .openTerminal: openTerminal()
        case .openITerm:  openITerm()
        case .deleteFile: trashSelectedItems()
        case .lockFile:   lockSelectedItems()
        case .showInfo:   showFileInfo()
        case .makeAlias:  makeDesktopAlias()
        case .qrShare:    showQRCode()
        case .setFolderIcon: openColorPanel()
        default: break
        }
    }

    func createFile(from template: FileTemplate) {
        guard let targetURL = FIFinderSyncController.default().targetedURL() else { return }
        fileCreator.createFile(from: template, at: targetURL)
    }

    func runScript(action: MenuAction) {
        guard let script = action.scriptContent,
              let targetURL = FIFinderSyncController.default().targetedURL() else { return }
        scriptRunner.run(script: script, at: targetURL)
    }

    func moveItems(to destination: String) {
        let items = FIFinderSyncController.default().selectedItemURLs() ?? []
        for url in items {
            try? FileManager.default.moveItem(
                at: url,
                to: URL(fileURLWithPath: destination).appendingPathComponent(url.lastPathComponent)
            )
        }
    }

    func copyItems(to destination: String) {
        let items = FIFinderSyncController.default().selectedItemURLs() ?? []
        for url in items {
            try? FileManager.default.copyItem(
                at: url,
                to: URL(fileURLWithPath: destination).appendingPathComponent(url.lastPathComponent)
            )
        }
    }

    // MARK: - Terminal

    private func openTerminal() {
        guard let targetURL = FIFinderSyncController.default().targetedURL() else { return }
        NSWorkspace.shared.open(
            [URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")],
            withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
            configuration: NSWorkspace.OpenConfiguration()
        ) { _, _ in }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let safePath = targetURL.path.replacingOccurrences(of: "\"", with: "\\\"")
            NSAppleScript(source: "tell application \"Terminal\"\nactivate\ndo script \"cd \(safePath)\"\nend tell")?
                .executeAndReturnError(nil)
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

    // MARK: - File Operations

    private func trashSelectedItems() {
        for url in FIFinderSyncController.default().selectedItemURLs() ?? [] {
            try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
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
        let desktop = FileManager.default.homeDirectoryForCurrentUser
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
