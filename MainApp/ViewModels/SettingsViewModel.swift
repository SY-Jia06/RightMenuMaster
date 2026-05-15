import SwiftUI
import AppKit
import ApplicationServices
import UniformTypeIdentifiers

final class SettingsViewModel: ObservableObject {
    @Published var selectedTab = 0
    @Published var config: AppConfig {
        didSet { save() }
    }
    @Published var customTemplates: [FileTemplate] {
        didSet { saveTemplates() }
    }
    @Published var authorizedFolders: [AuthorizedFolderGrant] {
        didSet { saveAuthorizedFolders() }
    }
    @Published var permissionErrorMessage: String?
    @Published var accessibilityTrusted: Bool

    init() {
        let loaded = UserDefaults.shared.loadConfig()
        self.config = loaded
        self.customTemplates = UserDefaults.shared.loadTemplates()
        self.authorizedFolders = UserDefaults.shared.loadAuthorizedFolders()
        self.accessibilityTrusted = AXIsProcessTrusted()
    }

    private func save() {
        UserDefaults.shared.saveConfig(config)
    }

    private func saveTemplates() {
        UserDefaults.shared.saveTemplates(customTemplates)
    }

    private func saveAuthorizedFolders() {
        UserDefaults.shared.saveAuthorizedFolders(authorizedFolders)
    }

    // MARK: - Menu Actions

    func toggleAction(_ action: MenuAction) {
        guard let index = config.enabledActions.firstIndex(where: { $0.id == action.id }) else { return }
        config.enabledActions[index].isEnabled.toggle()
    }

    func moveAction(from source: IndexSet, to destination: Int) {
        config.enabledActions.move(fromOffsets: source, toOffset: destination)
        for (index, _) in config.enabledActions.enumerated() {
            config.enabledActions[index].sortOrder = index
        }
    }

    func addAction(type: ActionType) {
        let action = MenuAction(
            title: type.defaultTitle,
            type: type,
            sortOrder: config.enabledActions.count
        )
        config.enabledActions.append(action)
    }

    func removeAction(_ action: MenuAction) {
        config.enabledActions.removeAll { $0.id == action.id }
    }

    func updateActionTitle(_ action: MenuAction, title: String) {
        guard let index = config.enabledActions.firstIndex(where: { $0.id == action.id }) else { return }
        config.enabledActions[index].title = title
    }

    // MARK: - Templates

    func addTemplate(_ template: FileTemplate) {
        customTemplates.append(template)
    }

    func removeTemplate(_ template: FileTemplate) {
        customTemplates.removeAll { $0.id == template.id }
    }

    func updateTemplate(_ template: FileTemplate) {
        guard let index = customTemplates.firstIndex(where: { $0.id == template.id }) else { return }
        customTemplates[index] = template
    }

    // MARK: - Scripts

    func updateScript(for action: MenuAction, content: String) {
        guard let index = config.enabledActions.firstIndex(where: { $0.id == action.id }) else { return }
        config.enabledActions[index].scriptContent = content
    }

    // MARK: - Folders

    func addMoveToFolder(_ path: String) {
        if !config.moveToFolders.contains(path) {
            config.moveToFolders.append(path)
        }
    }

    func removeMoveToFolder(_ path: String) {
        config.moveToFolders.removeAll { $0 == path }
    }

    func addCopyToFolder(_ path: String) {
        if !config.copyToFolders.contains(path) {
            config.copyToFolders.append(path)
        }
    }

    func removeCopyToFolder(_ path: String) {
        config.copyToFolders.removeAll { $0 == path }
    }

    // MARK: - Permissions

    func addAuthorizedFolder() {
        authorizeFolders(
            message: "Choose folders RightMenu Master can modify from Finder.",
            prompt: "Authorize"
        )
    }

    func authorizeHomeFolder() {
        let home = RealHomeDirectory.url
        NSLog("[RightMenu] authorizeHomeFolder: home=\(home.path)")
        authorizeFolders(
            message: "RightMenu Master needs access to your home folder to work everywhere in Finder.\n\nThis is a one-time setup. Please select your home folder (\(home.path)).",
            prompt: "Grant Access",
            directoryURL: home.deletingLastPathComponent(),
            allowsMultipleSelection: false
        )
    }
    
    func authorizeCommonFolders() {
        let home = RealHomeDirectory.url
        let commonPaths = [
            home.appendingPathComponent("工作区"),
            home.appendingPathComponent("Documents"),
            home.appendingPathComponent("Desktop"),
            home.appendingPathComponent("Downloads"),
        ].filter { FileManager.default.fileExists(atPath: $0.path) }
        
        guard !commonPaths.isEmpty else {
            authorizeHomeFolder()
            return
        }
        
        authorizeFolders(
            message: "Select common folders you want RightMenu Master to access (工作区, Documents, Desktop, Downloads).",
            prompt: "Authorize Selected",
            directoryURL: home,
            allowsMultipleSelection: true
        )
    }

    private func authorizeFolders(
        message: String,
        prompt: String,
        directoryURL: URL? = nil,
        allowsMultipleSelection: Bool = true
    ) {
        permissionErrorMessage = nil

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = allowsMultipleSelection
        panel.directoryURL = directoryURL
        panel.message = message
        panel.prompt = prompt

        NSLog("[RightMenu] Opening folder picker, directoryURL=\(directoryURL?.path ?? "nil")")
        guard panel.runModal() == .OK else {
            NSLog("[RightMenu] User cancelled folder selection")
            return
        }

        NSLog("[RightMenu] User selected folders: \(panel.urls.map { $0.path })")
        
        do {
            var updatedFolders = authorizedFolders
            for url in panel.urls {
                NSLog("[RightMenu] Authorizing folder: \(url.path)")
                let grant = try AuthorizedFolderStore.shared.authorizeFolder(url)
                NSLog("[RightMenu] Created grant: path=\(grant.path)")
                updatedFolders.removeAll { $0.path == grant.path }
                updatedFolders.append(grant)
            }
            updatedFolders.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
            authorizedFolders = updatedFolders  // Trigger didSet
            NSLog("[RightMenu] Updated authorizedFolders count: \(authorizedFolders.count)")
            NSLog("[RightMenu] Authorized paths: \(authorizedFolders.map { $0.path })")
            postAuthorizedFoldersChangedNotification()
        } catch {
            NSLog("[RightMenu] Authorization failed: \(error.localizedDescription)")
            permissionErrorMessage = error.localizedDescription
        }
    }

    func removeAuthorizedFolder(_ grant: AuthorizedFolderGrant) {
        authorizedFolders.removeAll { $0.id == grant.id }
        AuthorizedFolderStore.shared.save(authorizedFolders)
        postAuthorizedFoldersChangedNotification()
    }

    private func postAuthorizedFoldersChangedNotification() {
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(Constants.authorizedFoldersChangedNotificationName),
            object: Bundle.main.bundleIdentifier,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    func requestAccessibilityPermission() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        accessibilityTrusted = AXIsProcessTrustedWithOptions(options)
    }

    func refreshAccessibilityPermission() {
        accessibilityTrusted = AXIsProcessTrusted()
    }

    // MARK: - Export/Import

    func exportConfig() -> URL? {
        guard let data = try? JSONEncoder().encode(config) else { return nil }
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RightMenuMaster_Config.json")
        try? data.write(to: tempURL)
        return tempURL
    }

    func importConfig(from url: URL) {
        guard let data = try? Data(contentsOf: url),
              let imported = try? JSONDecoder().decode(AppConfig.self, from: data) else { return }
        config = imported
    }
}
