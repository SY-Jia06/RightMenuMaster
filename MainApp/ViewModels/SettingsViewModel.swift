import SwiftUI
import UniformTypeIdentifiers

final class SettingsViewModel: ObservableObject {
    @Published var selectedTab = 0
    @Published var config: AppConfig {
        didSet { save() }
    }
    @Published var customTemplates: [FileTemplate] {
        didSet { saveTemplates() }
    }

    init() {
        let loaded = UserDefaults.shared.loadConfig()
        self.config = loaded
        self.customTemplates = UserDefaults.shared.loadTemplates()
    }

    private func save() {
        UserDefaults.shared.saveConfig(config)
    }

    private func saveTemplates() {
        UserDefaults.shared.saveTemplates(customTemplates)
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
