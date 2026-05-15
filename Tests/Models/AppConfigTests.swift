import XCTest
@testable import RightMenuMaster

final class AppConfigTests: XCTestCase {

    func testDefaultConfigHasActions() {
        let config = AppConfig.default
        XCTAssertFalse(config.enabledActions.isEmpty)
        XCTAssertTrue(config.customTemplates.isEmpty)
        XCTAssertTrue(config.moveToFolders.isEmpty)
    }

    func testSortedActionsBySortOrder() {
        var config = AppConfig.default
        config.enabledActions = [
            MenuAction(title: "Third", type: .copyPath, sortOrder: 3),
            MenuAction(title: "First", type: .newFile, sortOrder: 0),
            MenuAction(title: "Second", type: .copyName, sortOrder: 2),
        ]
        let sorted = config.sortedActions()
        XCTAssertEqual(sorted.map(\.title), ["First", "Second", "Third"])
        XCTAssertEqual(sorted.map(\.sortOrder), [0, 2, 3])
    }

    func testSortedActionsFiltersDisabled() {
        var config = AppConfig.default
        config.enabledActions = [
            MenuAction(title: "Enabled", type: .newFile, isEnabled: true, sortOrder: 0),
            MenuAction(title: "Disabled", type: .copyPath, isEnabled: false, sortOrder: 1),
        ]
        let sorted = config.sortedActions()
        XCTAssertEqual(sorted.count, 1)
        XCTAssertEqual(sorted.first?.title, "Enabled")
    }

    func testCodableRoundTrip() throws {
        let config = AppConfig.default
        let encoded = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: encoded)
        XCTAssertEqual(decoded.enabledActions.count, config.enabledActions.count)
        XCTAssertEqual(decoded.moveToFolders.count, config.moveToFolders.count)
    }

    func testAllTemplatesIncludesDefaults() {
        let config = AppConfig.default
        let all = config.allTemplates()
        XCTAssertEqual(all.count, Constants.defaultTemplates.count)
        XCTAssertTrue(all.contains { $0.ext == "swift" })
        XCTAssertTrue(all.contains { $0.ext == "md" })
    }

    func testAllTemplatesIncludesCustom() {
        var config = AppConfig.default
        config.customTemplates = [
            FileTemplate(name: "Custom", ext: "xyz", content: "custom", isBuiltIn: false)
        ]
        let all = config.allTemplates()
        XCTAssertEqual(all.count, Constants.defaultTemplates.count + 1)
        XCTAssertTrue(all.contains { $0.name == "Custom" })
    }

    func testCreationDirectoryUsesTargetWhenTargetIsDirectory() {
        let target = URL(fileURLWithPath: "/tmp/example-folder", isDirectory: true)
        let directory = FinderTargetResolver.creationDirectory(for: target) { _ in true }

        XCTAssertEqual(directory.path, "/tmp/example-folder")
    }

    func testCreationDirectoryUsesParentWhenTargetIsFile() {
        let target = URL(fileURLWithPath: "/tmp/example-folder/file.txt", isDirectory: false)
        let directory = FinderTargetResolver.creationDirectory(for: target) { _ in false }

        XCTAssertEqual(directory.path, "/tmp/example-folder")
    }

    func testContainerMenuCreationDirectoryIgnoresStaleSelection() {
        let target = URL(fileURLWithPath: "/tmp/projects", isDirectory: true)
        let selectedFolder = URL(fileURLWithPath: "/tmp/projects/.vscode", isDirectory: true)

        let directory = FinderTargetResolver.creationDirectory(
            targetURL: target,
            selectedURLs: [selectedFolder],
            isContainerMenu: true
        ) { url in
            url.path != "/tmp/projects/file.txt"
        }

        XCTAssertEqual(directory.path, "/tmp/projects")
    }

    func testItemMenuCreationDirectoryUsesSelectedFileParent() {
        let target = URL(fileURLWithPath: "/tmp/downloads", isDirectory: true)
        let selectedFile = URL(fileURLWithPath: "/tmp/downloads/image.jpg", isDirectory: false)

        let directory = FinderTargetResolver.creationDirectory(
            targetURL: target,
            selectedURLs: [selectedFile],
            isContainerMenu: false
        ) { url in
            url.hasDirectoryPath
        }

        XCTAssertEqual(directory.path, "/tmp/downloads")
    }

    func testMonitoredDirectoriesIncludeHomeCommonFoldersAndAuthorizedFolders() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let grant = AuthorizedFolderGrant(
            path: "/Users/tester/Workspace",
            bookmarkData: Data("bookmark".utf8)
        )

        let directories = FinderMonitorDirectories.urls(
            home: home,
            authorizedFolders: [grant]
        ).map(\.path)

        XCTAssertTrue(directories.contains("/Users/tester"))
        XCTAssertTrue(directories.contains("/Users/tester/Desktop"))
        XCTAssertTrue(directories.contains("/Users/tester/Documents"))
        XCTAssertTrue(directories.contains("/Users/tester/Downloads"))
        XCTAssertTrue(directories.contains("/Users/tester/Workspace"))
    }

    func testFileCreationPlannerChoosesNextUntitledName() {
        let directory = URL(fileURLWithPath: "/tmp/example", isDirectory: true)
        let template = FileTemplate(name: "Plain Text", ext: "txt", content: "")
        let existingPaths: Set<String> = [
            "/tmp/example/untitled.txt",
            "/tmp/example/untitled 1.txt",
        ]

        let url = FileCreationPlanner.nextFileURL(in: directory, template: template) { path in
            existingPaths.contains(path)
        }

        XCTAssertEqual(url.path, "/tmp/example/untitled 2.txt")
    }
}
