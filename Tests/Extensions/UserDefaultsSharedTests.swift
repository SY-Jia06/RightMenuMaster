import XCTest
@testable import RightMenuMaster

final class UserDefaultsSharedTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.shared.removeObject(forKey: Constants.configKey)
        UserDefaults.shared.removeObject(forKey: Constants.templatesKey)
    }

    override func tearDown() {
        UserDefaults.shared.removeObject(forKey: Constants.configKey)
        UserDefaults.shared.removeObject(forKey: Constants.templatesKey)
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
}
