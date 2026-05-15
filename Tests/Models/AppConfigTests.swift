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
}
