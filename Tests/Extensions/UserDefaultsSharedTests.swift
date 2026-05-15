import XCTest
@testable import RightMenuMaster

final class UserDefaultsSharedTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.shared.removeObject(forKey: Constants.configKey)
        UserDefaults.shared.removeObject(forKey: Constants.templatesKey)
        UserDefaults.shared.removeObject(forKey: Constants.authorizedFoldersKey)
        UserDefaults.shared.removeObject(forKey: Constants.pendingFileCreationRequestsKey)
    }

    override func tearDown() {
        UserDefaults.shared.removeObject(forKey: Constants.configKey)
        UserDefaults.shared.removeObject(forKey: Constants.templatesKey)
        UserDefaults.shared.removeObject(forKey: Constants.authorizedFoldersKey)
        UserDefaults.shared.removeObject(forKey: Constants.pendingFileCreationRequestsKey)
        super.tearDown()
    }

    func testLoadConfigReturnsDefaultWhenEmpty() {
        let config = UserDefaults.shared.loadConfig()
        XCTAssertFalse(config.enabledActions.isEmpty)
    }

    func testSaveAndLoadConfig() {
        var config = AppConfig.default
        config.enabledActions = [
            MenuAction(title: "OnlyAction", type: .newFile, sortOrder: 1)
        ]
        UserDefaults.shared.saveConfig(config)

        let loaded = UserDefaults.shared.loadConfig()
        XCTAssertEqual(loaded.enabledActions.count, 1)
        XCTAssertEqual(loaded.enabledActions.first?.title, "OnlyAction")
    }

    func testLoadTemplatesReturnsEmptyWhenNone() {
        let templates = UserDefaults.shared.loadTemplates()
        XCTAssertTrue(templates.isEmpty)
    }

    func testSaveAndLoadTemplates() {
        let templates = [
            FileTemplate(name: "Custom1", ext: "abc", content: "x"),
            FileTemplate(name: "Custom2", ext: "xyz", content: "y"),
        ]
        UserDefaults.shared.saveTemplates(templates)

        let loaded = UserDefaults.shared.loadTemplates()
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded.map(\.name).sorted(), ["Custom1", "Custom2"])
    }

    func testSaveAndLoadAuthorizedFolders() {
        let folders = [
            AuthorizedFolderGrant(path: "/Users/j/Downloads", bookmarkData: Data([1, 2, 3])),
        ]
        UserDefaults.shared.saveAuthorizedFolders(folders)

        let loaded = UserDefaults.shared.loadAuthorizedFolders()
        XCTAssertEqual(loaded, folders)
    }

    func testAuthorizedFolderMatchingUsesPathBoundaryAndLongestPrefix() {
        let folders = [
            AuthorizedFolderGrant(path: "/Users/j", bookmarkData: Data([1])),
            AuthorizedFolderGrant(path: "/Users/j/Downloads", bookmarkData: Data([2])),
        ]

        let matched = AuthorizedFolderStore.authorizedFolder(
            containing: URL(fileURLWithPath: "/Users/j/Downloads/example.txt"),
            in: folders
        )

        XCTAssertEqual(matched?.path, "/Users/j/Downloads")
        XCTAssertNil(
            AuthorizedFolderStore.authorizedFolder(
                containing: URL(fileURLWithPath: "/Users/j/Downloads-old/example.txt"),
                in: [folders[1]]
            )
        )
    }

    func testPendingFileCreationStoreRoundTripsRequests() {
        let store = PendingFileCreationStore(defaults: .shared)
        let request = PendingFileCreationRequest(
            directoryPath: "/Users/j/工作区/Projects/claude",
            template: FileTemplate(name: "Plain Text", ext: "txt", content: "")
        )

        store.save(request)

        XCTAssertEqual(store.load(id: request.id), request)
        store.remove(id: request.id)
        XCTAssertNil(store.load(id: request.id))
    }
}
