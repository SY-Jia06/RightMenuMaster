import Foundation

struct AppConfig: Codable {
    var enabledActions: [MenuAction]
    var customTemplates: [FileTemplate]
    var moveToFolders: [String]
    var copyToFolders: [String]

    static let `default` = AppConfig(
        enabledActions: [
            MenuAction(title: ActionType.newFile.defaultTitle, type: .newFile, sortOrder: 0),
            MenuAction(title: ActionType.copyPath.defaultTitle, type: .copyPath, sortOrder: 2),
            MenuAction(title: ActionType.copyName.defaultTitle, type: .copyName, sortOrder: 3),
            MenuAction(title: ActionType.openTerminal.defaultTitle, type: .openTerminal, sortOrder: 4),
            MenuAction(title: ActionType.copyTo.defaultTitle, type: .copyTo, sortOrder: 5),
            MenuAction(title: ActionType.moveTo.defaultTitle, type: .moveTo, sortOrder: 6),
            MenuAction(title: ActionType.deleteFile.defaultTitle, type: .deleteFile, sortOrder: 7),
        ],
        customTemplates: [],
        moveToFolders: [],
        copyToFolders: []
    )

    func sortedActions() -> [MenuAction] {
        enabledActions
            .filter { $0.isEnabled }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    func allTemplates() -> [FileTemplate] {
        Constants.defaultTemplates + customTemplates
    }
}
