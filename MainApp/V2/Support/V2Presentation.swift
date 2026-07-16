import Foundation
import SwiftUI

enum V2Presentation {
  static func text(_ english: String, _ chinese: String, language: V2Language) -> String {
    switch language {
    case .english:
      return english
    case .simplifiedChinese:
      return chinese
    case .system:
      return Locale.preferredLanguages.first?.hasPrefix("zh") == true ? chinese : english
    }
  }

  static func errorMessage(_ error: Error, language: V2Language) -> String {
    guard resolvedLanguage(language) == .simplifiedChinese else {
      return error.localizedDescription
    }

    if let error = error as? FilenameValidationError {
      switch error {
      case .empty: return "请输入文件名。"
      case .relativeDirectoryMarker: return "文件名不能是 . 或 ..。"
      case .trailingSpaceOrPeriod: return "请移除文件名末尾的空格或句点。"
      case .forbiddenCharacter(let character): return "请移除不支持的字符：\(character)"
      case .unsafeControlCharacter: return "请移除控制字符或双向文本格式字符。"
      case .windowsReservedName(let name): return "\(name) 是 Windows 保留名称，请更换文件名。"
      case .tooLong(let limit): return "请将文件名缩短至 \(limit) 个 UTF-8 字节以内。"
      }
    }

    if let error = error as? FileCreationError {
      switch error {
      case .invalidFilename(let filenameError):
        return errorMessage(filenameError, language: language)
      case .invalidDirectory: return "请选择本地工作目录。"
      case .directoryMissing: return "工作目录已不存在，请选择其他目录后重试。"
      case .notDirectory: return "所选位置不是文件夹。"
      case .permissionDenied: return "无法写入此处，请授权可写目录后重试。"
      case .collision(_, let suggestion): return "同名文件已存在，可尝试 \(suggestion)。"
      case .cannotInspectDirectory: return "无法检查此目录中的可用文件名。"
      case .cannotSuggestAvailableName: return "找不到可用的文件名建议。"
      case .writeFailed: return "文件创建失败，现有项目未被修改。"
      }
    }

    if let error = error as? SecurityScopedGrantError {
      switch error {
      case .selectionIsNotDirectory: return "请选择文件夹，而不是文件。"
      case .selectionDoesNotContain(let name): return "请选择 \(name) 或其上级文件夹。"
      case .noGrant(let url): return "尚未授权访问 \(url.lastPathComponent)。"
      case .bookmarkUnavailable(let name): return "\(name) 的权限已失效，请重新选择该文件夹。"
      case .accessDenied(let name): return "macOS 拒绝访问 \(name)，请重新授权。"
      }
    }

    if let error = error as? NativeApplicationLaunchError {
      switch error {
      case .applicationNotSelected: return "请先在设置中选择应用，然后重试。"
      case .applicationUnavailable(let name): return "\(name) 不可用，请选择其他已安装应用。"
      case .activationFailed: return "macOS 无法打开此项目，文件未被修改。"
      }
    }

    if let error = error as? AppCommandConsumerError {
      switch error {
      case .invalidURL: return "Finder 请求 URL 无效。"
      case .sharedStoreUnavailable: return "共享 App Group 不可用，请检查签名与权限。"
      case .requestMissing: return "Finder 请求不存在或已被处理。"
      case .actionUnavailable: return "此操作不适用于当前 Finder 选择。"
      }
    }

    return "操作失败：\(error.localizedDescription)"
  }

  private static func resolvedLanguage(_ language: V2Language) -> V2Language {
    if language == .system {
      return Locale.preferredLanguages.first?.hasPrefix("zh") == true
        ? .simplifiedChinese : .english
    }
    return language
  }
}

extension ProductAction: Identifiable {
  var id: String { rawValue }

  var systemImage: String {
    switch self {
    case .newFile: "doc.badge.plus"
    case .copyPath: "doc.on.doc"
    case .openTerminal: "apple.terminal"
    case .openEditor: "square.and.pencil"
    }
  }

  func title(language: V2Language) -> String {
    switch self {
    case .newFile: V2Presentation.text("New File", "新建文件", language: language)
    case .copyPath: V2Presentation.text("Copy Path", "复制路径", language: language)
    case .openTerminal: V2Presentation.text("Open in Terminal", "在终端中打开", language: language)
    case .openEditor: V2Presentation.text("Open with Editor", "用编辑器打开", language: language)
    }
  }

  func detail(language: V2Language) -> String {
    switch self {
    case .newFile:
      V2Presentation.text(
        "Create a blank, text, or Markdown file.", "创建空白、文本或 Markdown 文件。", language: language)
    case .copyPath:
      V2Presentation.text("Copy one or more physical paths.", "复制一个或多个实际路径。", language: language)
    case .openTerminal:
      V2Presentation.text(
        "Open the relevant folder in your chosen terminal.", "在选定终端中打开对应文件夹。", language: language)
    case .openEditor:
      V2Presentation.text(
        "Open selected items in your chosen editor.", "用选定编辑器打开所选项目。", language: language)
    }
  }
}

extension FileRecipe: Identifiable {
  var id: String { rawValue }

  func title(language: V2Language) -> String {
    switch self {
    case .blank: V2Presentation.text("Blank", "空白", language: language)
    case .text: V2Presentation.text("Text (.txt)", "文本（.txt）", language: language)
    case .markdown: V2Presentation.text("Markdown (.md)", "Markdown（.md）", language: language)
    }
  }
}

extension V2Language: Identifiable {
  var id: String { rawValue }

  var title: String {
    switch self {
    case .system: "System"
    case .simplifiedChinese: "简体中文"
    case .english: "English"
    }
  }
}

extension PostCreateBehavior: Identifiable {
  var id: String { rawValue }

  func title(language: V2Language) -> String {
    switch self {
    case .reveal:
      V2Presentation.text("Reveal in Finder", "在 Finder 中显示", language: language)
    case .openPreferredEditor:
      V2Presentation.text("Open in preferred editor", "用首选编辑器打开", language: language)
    case .openSystemAssociation:
      V2Presentation.text("Open with system association", "用系统关联应用打开", language: language)
    }
  }
}

extension View {
  func v2Card() -> some View {
    padding(16)
      .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
  }
}
