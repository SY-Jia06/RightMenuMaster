import Foundation

struct MenuAction: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var type: ActionType
    var isEnabled: Bool
    var sortOrder: Int
    var scriptContent: String?

    init(id: UUID = UUID(), title: String, type: ActionType, isEnabled: Bool = true, sortOrder: Int = 0, scriptContent: String? = nil) {
        self.id = id
        self.title = title
        self.type = type
        self.isEnabled = isEnabled
        self.sortOrder = sortOrder
        self.scriptContent = scriptContent
    }
}

enum ActionType: String, Codable, CaseIterable {
    case newFile = "new_file"
    case copyPath = "copy_path"
    case copyName = "copy_name"
    case openTerminal = "open_terminal"
    case openITerm = "open_iterm"
    case moveTo = "move_to"
    case copyTo = "copy_to"
    case deleteFile = "delete_file"
    case lockFile = "lock_file"
    case showInfo = "show_info"
    case makeAlias = "make_alias"
    case qrShare = "qr_share"
    case setFolderIcon = "set_folder_icon"
    case customScript = "custom_script"

    var defaultTitle: String {
        switch self {
        case .newFile: return "New File"
        case .copyPath: return "Copy File Path"
        case .copyName: return "Copy File Name"
        case .openTerminal: return "Open Terminal Here"
        case .openITerm: return "Open iTerm Here"
        case .moveTo: return "Move To..."
        case .copyTo: return "Copy To..."
        case .deleteFile: return "Quick Delete"
        case .lockFile: return "Lock File"
        case .showInfo: return "Show File Info"
        case .makeAlias: return "Make Alias"
        case .qrShare: return "Share via QR Code"
        case .setFolderIcon: return "Set Folder Icon Color"
        case .customScript: return "Run Script"
        }
    }

    var requiresFileSelection: Bool {
        switch self {
        case .newFile, .openTerminal, .openITerm:
            return false
        default:
            return true
        }
    }
}
