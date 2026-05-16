import SwiftUI
import AppKit
import ApplicationServices

@main
struct RightMenuMasterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = SettingsViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .frame(minWidth: 640, minHeight: 500)
                .onAppear {
                    checkAndRequestInitialPermissions()
                }
        }
        .handlesExternalEvents(matching: ["settings"])
        .windowResizability(.contentSize)
        .defaultSize(width: 700, height: 600)

        Settings {
            ContentView()
                .environmentObject(viewModel)
                .frame(minWidth: 640, minHeight: 500)
        }
    }
    
    private func checkAndRequestInitialPermissions() {
        // Disabled auto-prompt during development to avoid blocking the UI.
        // Users can manually click "Enable Everywhere" in the Permissions tab.
        NSLog("[RightMenu] App launched. Authorized folders: \(AuthorizedFolderStore.shared.load().map(\.path))")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )

        setupMenuBarIcon()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    private func setupMenuBarIcon() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "contextualmenu.and.cursorarrow", accessibilityDescription: "RightMenu Master")
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit RightMenu Master", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.title.contains("RightMenu") || $0.contentView != nil }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            // Open settings window via external event
            if let url = URL(string: "rightmenumaster://settings") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    @objc func handleGetURLEvent(
        _ event: NSAppleEventDescriptor,
        withReplyEvent replyEvent: NSAppleEventDescriptor
    ) {
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: urlString) else {
            NSLog("[RightMenu] Ignored malformed URL apple event")
            return
        }

        AppCommandHandler.shared.handle(url)
    }
}

final class AppCommandHandler {
    static let shared = AppCommandHandler()

    private let authorizedFolderStore = AuthorizedFolderStore.shared
    private let pendingFileCreationStore = PendingFileCreationStore.shared

    func handle(_ url: URL) {
        guard url.scheme == AppCommandURL.scheme,
              let command = AppCommand(rawValue: url.host ?? "") else {
            NSLog("[RightMenu] Ignored app command URL: \(url.absoluteString)")
            return
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard let path = components?
            .queryItems?
            .first(where: { $0.name == "path" })?
            .value else {
            NSLog("[RightMenu] Ignored app command URL without path: \(url.absoluteString)")
            return
        }

        let fileURL = URL(fileURLWithPath: path)
        NSLog("[RightMenu] MainApp command \(command.rawValue): \(fileURL.path)")

        switch command {
        case .openTerminal:
            openTerminal(at: fileURL, appName: "Terminal")
        case .openITerm:
            openTerminal(at: fileURL, appName: "iTerm")
        case .rename:
            selectAndBeginRename(fileURL)
        case .authorizeCreateFile:
            let requestIDString = components?
                .queryItems?
                .first(where: { $0.name == "requestID" })?
                .value
            authorizeAndCreateFile(at: fileURL, requestIDString: requestIDString)
        case .trashFile:
            trashFile(at: fileURL)
        }
    }

    private func openTerminal(at directoryURL: URL, appName: String) {
        do {
            try authorizedFolderStore.withAccess(to: directoryURL) {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                process.arguments = ["-a", appName, directoryURL.path]
                try process.run()
                NSLog("[RightMenu] MainApp opened \(appName) at \(directoryURL.path)")
            }
        } catch {
            NSLog("[RightMenu] MainApp open \(appName) failed: \(error.localizedDescription), path=\(directoryURL.path)")
        }
    }

    private func trashFile(at fileURL: URL) {
        let parentDirectory = fileURL.deletingLastPathComponent()
        do {
            try authorizedFolderStore.withAccess(to: parentDirectory) {
                var trashedURL: NSURL?
                try FileManager.default.trashItem(at: fileURL, resultingItemURL: &trashedURL)
                NSLog("[RightMenu] MainApp trashed file: \(fileURL.path)")
            }
        } catch {
            NSLog("[RightMenu] MainApp trash failed: \(error.localizedDescription), path=\(fileURL.path)")
        }
    }

    private func authorizeAndCreateFile(at directoryURL: URL, requestIDString: String?) {
        guard let requestIDString,
              let requestID = UUID(uuidString: requestIDString),
              let request = pendingFileCreationStore.load(id: requestID) else {
            NSLog("[RightMenu] Missing pending file creation request: \(requestIDString ?? "nil")")
            return
        }

        do {
            // Check if we need authorization
            if AuthorizedFolderStore.authorizedFolder(containing: directoryURL, in: authorizedFolderStore.load()) == nil {
                NSLog("[RightMenu] Requesting folder access for: \(directoryURL.path)")
                try requestFolderAccess(for: directoryURL)
                // Notify extension about new authorization
                postAuthorizedFoldersChangedNotification()
            }

            // Create the file with the (possibly newly) authorized access
            let createdURL = try createPendingFile(request)
            pendingFileCreationStore.remove(id: requestID)
            selectAndBeginRename(createdURL)
        } catch {
            NSLog("[RightMenu] MainApp authorize/create file failed: \(error.localizedDescription), path=\(directoryURL.path)")
            // Don't remove the pending request if it failed, so user can retry
        }
    }

    private func requestFolderAccess(for directoryURL: URL) throws {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = directoryURL.deletingLastPathComponent()
        panel.message = "Select \(directoryURL.lastPathComponent) or a parent folder to allow RightMenu Master to create files here."
        panel.prompt = "Allow"

        guard panel.runModal() == .OK,
              let selectedURL = panel.urls.first else {
            throw CocoaError(.userCancelled)
        }

        _ = try authorizedFolderStore.authorizeFolder(selectedURL)
        NSLog("[RightMenu] MainApp authorized folder: \(selectedURL.path)")
    }

    private func createPendingFile(_ request: PendingFileCreationRequest) throws -> URL {
        let directoryURL = URL(fileURLWithPath: request.directoryPath, isDirectory: true)
        let fileURL = FileCreationPlanner.nextFileURL(in: directoryURL, template: request.template)
        let data = request.template.content.data(using: .utf8) ?? Data()

        try authorizedFolderStore.withAccess(to: directoryURL) {
            try data.write(to: fileURL, options: .atomic)
        }

        NSLog("[RightMenu] MainApp created file: \(fileURL.path)")
        return fileURL
    }

    private func postAuthorizedFoldersChangedNotification() {
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(Constants.authorizedFoldersChangedNotificationName),
            object: Bundle.main.bundleIdentifier,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    private func selectAndBeginRename(_ fileURL: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        
        // Wait longer for Finder to fully select the file
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.pressReturnForRename()
        }
    }

    private func pressReturnForRename() {
        guard AXIsProcessTrusted() else {
            NSLog("[RightMenu] MainApp rename skipped: Accessibility permission is not granted")
            return
        }

        let source = CGEventSource(stateID: .hidSystemState)
        let returnKeyCode: CGKeyCode = 36
        
        // Press Return key to enter rename mode
        // Finder's default behavior should select only the filename without extension
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: returnKeyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: returnKeyCode, keyDown: false)
        
        keyDown?.post(tap: .cghidEventTap)
        usleep(50000) // 50ms delay between key down and up
        keyUp?.post(tap: .cghidEventTap)
        
        NSLog("[RightMenu] MainApp rename Return key posted")
    }
}
