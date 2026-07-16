import AppKit
import Foundation
import UniformTypeIdentifiers

enum ApplicationRole: String, Sendable {
  case terminal
  case editor
}

/// Detects a small, explicit allow-list of native applications without scanning
/// the user's Applications folders.
@MainActor
final class ApplicationCatalog: ObservableObject {
  @Published private(set) var terminals: [PreferredApplication] = []
  @Published private(set) var editors: [PreferredApplication] = []

  private struct Candidate {
    let bundleIdentifier: String
    let fallbackName: String
  }

  private static let terminalCandidates = [
    Candidate(bundleIdentifier: "com.mitchellh.ghostty", fallbackName: "Ghostty"),
    Candidate(bundleIdentifier: "com.googlecode.iterm2", fallbackName: "iTerm2"),
    Candidate(bundleIdentifier: "dev.warp.Warp-Stable", fallbackName: "Warp"),
    Candidate(bundleIdentifier: "com.github.wez.wezterm", fallbackName: "WezTerm"),
    Candidate(bundleIdentifier: "net.kovidgoyal.kitty", fallbackName: "kitty"),
    Candidate(bundleIdentifier: "org.alacritty", fallbackName: "Alacritty"),
    Candidate(bundleIdentifier: "com.apple.Terminal", fallbackName: "Terminal"),
  ]

  private static let editorCandidates = [
    Candidate(bundleIdentifier: "com.coteditor.CotEditor", fallbackName: "CotEditor"),
    Candidate(bundleIdentifier: "dev.zed.Zed", fallbackName: "Zed"),
    Candidate(bundleIdentifier: "com.microsoft.VSCode", fallbackName: "Visual Studio Code"),
    Candidate(bundleIdentifier: "com.todesktop.230313mzl4w4u92", fallbackName: "Cursor"),
    Candidate(bundleIdentifier: "com.sublimetext.4", fallbackName: "Sublime Text"),
    Candidate(bundleIdentifier: "com.barebones.bbedit", fallbackName: "BBEdit"),
    Candidate(bundleIdentifier: "com.apple.TextEdit", fallbackName: "TextEdit"),
  ]

  private let workspace: NSWorkspace

  init(workspace: NSWorkspace = .shared) {
    self.workspace = workspace
    refresh()
  }

  func refresh(
    including preferredTerminal: PreferredApplication? = nil,
    preferredEditor: PreferredApplication? = nil
  ) {
    terminals = detectedApplications(from: Self.terminalCandidates, including: preferredTerminal)
    editors = detectedApplications(from: Self.editorCandidates, including: preferredEditor)
  }

  func applications(for role: ApplicationRole) -> [PreferredApplication] {
    switch role {
    case .terminal: terminals
    case .editor: editors
    }
  }

  func makePreferredApplication(for applicationURL: URL) -> PreferredApplication? {
    guard applicationURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame else {
      return nil
    }

    let bundle = Bundle(url: applicationURL)
    let identifier = bundle?.bundleIdentifier ?? applicationURL.standardizedFileURL.path
    let displayName =
      (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
      ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
      ?? FileManager.default.displayName(atPath: applicationURL.path)

    return PreferredApplication(
      id: identifier,
      displayName: displayName,
      applicationPath: applicationURL.standardizedFileURL.path
    )
  }

  /// Uses a native application picker. Selection is persisted by the caller.
  func chooseApplication(
    for role: ApplicationRole,
    language: V2Language = .system,
    attachedTo window: NSWindow? = nil
  ) async -> PreferredApplication? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowsMultipleSelection = false
    panel.resolvesAliases = true
    panel.allowedContentTypes = [.applicationBundle]
    panel.prompt = V2Presentation.text("Choose", "选择", language: language)
    panel.message =
      role == .terminal
      ? V2Presentation.text(
        "Choose a terminal application. This does not change your system default.",
        "选择终端应用。此操作不会修改系统默认应用。",
        language: language
      )
      : V2Presentation.text(
        "Choose an editor application. This does not change your system default.",
        "选择编辑器应用。此操作不会修改系统默认应用。",
        language: language
      )

    let response: NSApplication.ModalResponse
    if let window {
      response = await withCheckedContinuation { continuation in
        panel.beginSheetModal(for: window) { continuation.resume(returning: $0) }
      }
    } else {
      response = panel.runModal()
    }

    guard response == .OK, let url = panel.url else { return nil }
    return makePreferredApplication(for: url)
  }

  private func detectedApplications(
    from candidates: [Candidate],
    including customApplication: PreferredApplication?
  ) -> [PreferredApplication] {
    var result: [PreferredApplication] = []
    var seen = Set<String>()

    if let customApplication,
      resolvedURL(for: customApplication) != nil
    {
      result.append(customApplication)
      seen.insert(customApplication.id)
    }

    for candidate in candidates {
      guard !seen.contains(candidate.bundleIdentifier),
        let url = workspace.urlForApplication(withBundleIdentifier: candidate.bundleIdentifier)
      else {
        continue
      }

      let detected =
        makePreferredApplication(for: url)
        ?? PreferredApplication(
          id: candidate.bundleIdentifier,
          displayName: candidate.fallbackName,
          applicationPath: url.standardizedFileURL.path
        )
      result.append(detected)
      seen.insert(candidate.bundleIdentifier)
    }

    return result
  }

  func resolvedURL(for application: PreferredApplication) -> URL? {
    if let applicationPath = application.applicationPath {
      let url = URL(fileURLWithPath: applicationPath, isDirectory: true)
      if FileManager.default.fileExists(atPath: url.path) {
        return url
      }
    }
    return workspace.urlForApplication(withBundleIdentifier: application.id)
  }

  func editorCapabilities(for application: PreferredApplication?) -> EditorCapabilities {
    guard let application else { return .singleItemOnly }
    let knownMultiItemEditors: Set<String> = [
      "com.coteditor.CotEditor",
      "dev.zed.Zed",
      "com.microsoft.VSCode",
      "com.todesktop.230313mzl4w4u92",
      "com.sublimetext.4",
      "com.barebones.bbedit",
      "com.apple.TextEdit",
    ]
    return knownMultiItemEditors.contains(application.id) ? .mixedParentItems : .singleItemOnly
  }
}
