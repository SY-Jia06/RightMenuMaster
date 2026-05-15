import Foundation
import Darwin

enum Constants {
    static let appGroupID = "group.com.rightmenu.master"
    static let configKey = "menu_config"
    static let templatesKey = "custom_templates"
    static let enabledActionsKey = "enabled_actions"
    static let authorizedFoldersKey = "authorized_folders"
    static let pendingFileCreationRequestsKey = "pending_file_creation_requests"
    static let authorizedFoldersChangedNotificationName = "com.rightmenu.master.authorized-folders-changed"

    static let defaultTemplates: [FileTemplate] = [
        FileTemplate(name: "Plain Text", ext: "txt", content: ""),
        FileTemplate(name: "Markdown", ext: "md", content: "# \n\n"),
        FileTemplate(name: "Swift File", ext: "swift", content: "import Foundation\n\n"),
        FileTemplate(name: "Python File", ext: "py", content: "#!/usr/bin/env python3\n\n\ndef main():\n    pass\n\n\nif __name__ == \"__main__\":\n    main()\n"),
        FileTemplate(name: "JavaScript File", ext: "js", content: "#!/usr/bin/env node\n\n"),
        FileTemplate(name: "Shell Script", ext: "sh", content: "#!/bin/bash\n\nset -euo pipefail\n\n"),
    ]
}

enum RealHomeDirectory {
    static var url: URL {
        if let pw = getpwuid(getuid()), let homeDir = pw.pointee.pw_dir {
            let homePath = String(cString: homeDir)
            return URL(fileURLWithPath: homePath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }
}

enum FinderMonitorDirectories {
    static func urls(
        home: URL = RealHomeDirectory.url,
        authorizedFolders: [AuthorizedFolderGrant]
    ) -> Set<URL> {
        var directoryURLs: Set<URL> = [
            URL(fileURLWithPath: "/", isDirectory: true),
            URL(fileURLWithPath: "/Users", isDirectory: true),
            URL(fileURLWithPath: "/Volumes", isDirectory: true),
            home,
            home.appendingPathComponent("Desktop", isDirectory: true),
            home.appendingPathComponent("Documents", isDirectory: true),
            home.appendingPathComponent("Downloads", isDirectory: true),
            home.appendingPathComponent("Library", isDirectory: true),
            home.appendingPathComponent("Library/Mobile Documents", isDirectory: true),
            home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true),
        ]

        for grant in authorizedFolders {
            directoryURLs.insert(URL(fileURLWithPath: grant.path, isDirectory: true))
        }

        return directoryURLs
    }
}

enum AppCommand: String {
    case openTerminal = "open-terminal"
    case openITerm = "open-iterm"
    case rename = "rename"
    case authorizeCreateFile = "authorize-create-file"
    case trashFile = "trash-file"
}

enum AppCommandURL {
    static let scheme = "rightmenumaster"

    static func url(
        command: AppCommand,
        path: String,
        queryItems extraQueryItems: [URLQueryItem] = []
    ) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = command.rawValue
        components.queryItems = [
            URLQueryItem(name: "path", value: path),
        ] + extraQueryItems
        return components.url
    }
}

struct PendingFileCreationRequest: Codable, Equatable, Identifiable {
    var id: UUID
    var directoryPath: String
    var template: FileTemplate

    init(id: UUID = UUID(), directoryPath: String, template: FileTemplate) {
        self.id = id
        self.directoryPath = URL(fileURLWithPath: directoryPath).standardizedFileURL.path
        self.template = template
    }
}

final class PendingFileCreationStore {
    static let shared = PendingFileCreationStore()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .shared) {
        self.defaults = defaults
    }

    func save(_ request: PendingFileCreationRequest) {
        var requests = load().filter { $0.id != request.id }
        requests.append(request)
        saveAll(requests)
    }

    func load(id: UUID) -> PendingFileCreationRequest? {
        load().first { $0.id == id }
    }

    func remove(id: UUID) {
        saveAll(load().filter { $0.id != id })
    }

    private func load() -> [PendingFileCreationRequest] {
        guard let data = defaults.data(forKey: Constants.pendingFileCreationRequestsKey),
              let requests = try? JSONDecoder().decode([PendingFileCreationRequest].self, from: data) else {
            return []
        }
        return requests
    }

    private func saveAll(_ requests: [PendingFileCreationRequest]) {
        guard let data = try? JSONEncoder().encode(requests) else { return }
        defaults.set(data, forKey: Constants.pendingFileCreationRequestsKey)
    }
}

enum FileCreationPlanner {
    static func nextFileURL(
        in directoryURL: URL,
        template: FileTemplate,
        fileExists: (String) -> Bool = FileManager.default.fileExists(atPath:)
    ) -> URL {
        let baseName = "untitled"
        let ext = template.ext
        var fileName = "\(baseName).\(ext)"
        var counter = 1

        while fileExists(directoryURL.appendingPathComponent(fileName).path) {
            fileName = "\(baseName) \(counter).\(ext)"
            counter += 1
        }

        return directoryURL.appendingPathComponent(fileName)
    }
}

struct AuthorizedFolderGrant: Codable, Equatable, Identifiable {
    var id: UUID
    var path: String
    var bookmarkData: Data

    init(id: UUID = UUID(), path: String, bookmarkData: Data) {
        self.id = id
        self.path = URL(fileURLWithPath: path).standardizedFileURL.path
        self.bookmarkData = bookmarkData
    }

    var displayName: String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}

final class AuthorizedFolderStore {
    static let shared = AuthorizedFolderStore()

    private let defaults: UserDefaults
    private var hasMigrated = false

    static var appGroupContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Constants.appGroupID)
    }

    init(defaults: UserDefaults = .shared) {
        self.defaults = defaults
    }

    func migrateBookmarksIfNeeded() {
        guard !hasMigrated else { return }
        hasMigrated = true

        var folders = load()
        var didMigrate = false

        for (index, grant) in folders.enumerated() {
            var isStale = false
            // Try document-scope resolution first
            if let _ = try? URL(
                resolvingBookmarkData: grant.bookmarkData,
                options: [.withSecurityScope],
                relativeTo: Self.appGroupContainerURL,
                bookmarkDataIsStale: &isStale
            ) {
                continue // Already document-scoped
            }

            // Try app-scope resolution as fallback
            var appStale = false
            guard let folderURL = try? URL(
                resolvingBookmarkData: grant.bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &appStale
            ) else {
                NSLog("[RightMenu] Migration: bookmark for '\(grant.path)' could not be resolved with either scope")
                continue
            }

            // Re-create as document-scoped
            let didStart = folderURL.startAccessingSecurityScopedResource()
            defer { if didStart { folderURL.stopAccessingSecurityScopedResource() } }

            guard let newBookmarkData = try? folderURL.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: Self.appGroupContainerURL
            ) else {
                NSLog("[RightMenu] Migration: failed to re-create bookmark for '\(grant.path)'")
                continue
            }

            folders[index] = AuthorizedFolderGrant(id: grant.id, path: grant.path, bookmarkData: newBookmarkData)
            didMigrate = true
            NSLog("[RightMenu] Migration: migrated bookmark for '\(grant.path)' from app-scope to document-scope")
        }

        if didMigrate {
            save(folders)
            NSLog("[RightMenu] Migration: saved \(folders.count) migrated bookmarks")
        }
    }

    func load() -> [AuthorizedFolderGrant] {
        defaults.loadAuthorizedFolders()
    }

    func save(_ folders: [AuthorizedFolderGrant]) {
        defaults.saveAuthorizedFolders(folders)
    }

    @discardableResult
    func authorizeFolder(_ url: URL) throws -> AuthorizedFolderGrant {
        let folderURL = url.standardizedFileURL
        let bookmarkData = try folderURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: Self.appGroupContainerURL
        )
        let grant = AuthorizedFolderGrant(path: folderURL.path, bookmarkData: bookmarkData)

        var folders = load().filter { $0.path != grant.path }
        folders.append(grant)
        folders.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        save(folders)
        return grant
    }

    func remove(_ grant: AuthorizedFolderGrant) {
        save(load().filter { $0.id != grant.id })
    }

    func withAccess<T>(to url: URL, perform operation: () throws -> T) throws -> T {
        migrateBookmarksIfNeeded()

        guard let grant = Self.authorizedFolder(containing: url, in: load()) else {
            return try operation()
        }

        var isStale = false
        do {
            let folderURL = try URL(
                resolvingBookmarkData: grant.bookmarkData,
                options: [.withSecurityScope],
                relativeTo: Self.appGroupContainerURL,
                bookmarkDataIsStale: &isStale
            )
            let didStartAccessing = folderURL.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing {
                    folderURL.stopAccessingSecurityScopedResource()
                }
            }

            if isStale {
                NSLog("[RightMenu] Authorized folder bookmark is stale: \(grant.path)")
            }
            return try operation()
        } catch {
            NSLog("[RightMenu] Authorized folder bookmark failed: \(grant.path), \(error.localizedDescription)")
            return try operation()
        }
    }

    static func authorizedFolder(
        containing url: URL,
        in folders: [AuthorizedFolderGrant]
    ) -> AuthorizedFolderGrant? {
        let itemPath = url.standardizedFileURL.path
        return folders
            .filter { contains(itemPath: itemPath, folderPath: $0.path) }
            .max { $0.path.count < $1.path.count }
    }

    private static func contains(itemPath: String, folderPath: String) -> Bool {
        let folderPath = URL(fileURLWithPath: folderPath).standardizedFileURL.path
        if itemPath == folderPath {
            return true
        }

        let folderPrefix = folderPath.hasSuffix("/") ? folderPath : "\(folderPath)/"
        return itemPath.hasPrefix(folderPrefix)
    }
}

enum FinderTargetResolver {
    static func creationDirectory(
        targetURL: URL,
        selectedURLs: [URL],
        isContainerMenu: Bool,
        isDirectory: (URL) -> Bool = FinderTargetResolver.fileSystemDirectoryCheck
    ) -> URL {
        if isContainerMenu {
            return creationDirectory(for: targetURL, isDirectory: isDirectory)
        }

        if let selectedURL = selectedURLs.first {
            return creationDirectory(for: selectedURL, isDirectory: isDirectory)
        }

        return creationDirectory(for: targetURL, isDirectory: isDirectory)
    }

    static func creationDirectory(
        for targetURL: URL,
        isDirectory: (URL) -> Bool = FinderTargetResolver.fileSystemDirectoryCheck
    ) -> URL {
        isDirectory(targetURL) ? targetURL : targetURL.deletingLastPathComponent()
    }

    private static func fileSystemDirectoryCheck(_ url: URL) -> Bool {
        if url.hasDirectoryPath { return true }

        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        return values?.isDirectory == true
    }
}
