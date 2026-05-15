import XCTest
@testable import RightMenuMaster

final class MenuActionTests: XCTestCase {

    func testDefaultInitialization() {
        let action = MenuAction(title: "Test", type: .copyPath)
        XCTAssertEqual(action.title, "Test")
        XCTAssertEqual(action.type, .copyPath)
        XCTAssertTrue(action.isEnabled)
        XCTAssertEqual(action.sortOrder, 0)
        XCTAssertNil(action.scriptContent)
    }

    func testCustomScriptAction() {
        let action = MenuAction(
            title: "My Script",
            type: .customScript,
            isEnabled: true,
            sortOrder: 5,
            scriptContent: "echo hello"
        )
        XCTAssertEqual(action.type, .customScript)
        XCTAssertEqual(action.scriptContent, "echo hello")
        XCTAssertEqual(action.sortOrder, 5)
    }

    func testCodableRoundTrip() throws {
        let action = MenuAction(title: "Copy", type: .copyPath, sortOrder: 3)
        let encoded = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(MenuAction.self, from: encoded)
        XCTAssertEqual(decoded.title, "Copy")
        XCTAssertEqual(decoded.type, .copyPath)
        XCTAssertEqual(decoded.sortOrder, 3)
    }

    func testEquatable() {
        let a = MenuAction(id: UUID(), title: "A", type: .newFile)
        let b = MenuAction(id: UUID(), title: "A", type: .newFile)
        XCTAssertNotEqual(a, b) // different IDs
        XCTAssertEqual(a, a)    // same instance
    }

    func testActionTypeDefaultTitles() {
        XCTAssertEqual(ActionType.newFile.defaultTitle, "New File")
        XCTAssertEqual(ActionType.copyPath.defaultTitle, "Copy File Path")
        XCTAssertEqual(ActionType.copyName.defaultTitle, "Copy File Name")
        XCTAssertEqual(ActionType.openTerminal.defaultTitle, "Open Terminal Here")
    }

    func testRequiresFileSelection() {
        XCTAssertFalse(ActionType.newFile.requiresFileSelection)
        XCTAssertFalse(ActionType.openTerminal.requiresFileSelection)
        XCTAssertTrue(ActionType.copyPath.requiresFileSelection)
        XCTAssertTrue(ActionType.deleteFile.requiresFileSelection)
    }
}
