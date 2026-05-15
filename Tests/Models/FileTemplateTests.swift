import XCTest
@testable import RightMenuMaster

final class FileTemplateTests: XCTestCase {

    func testDefaultInitialization() {
        let template = FileTemplate(name: "Test", ext: "txt", content: "hello")
        XCTAssertEqual(template.name, "Test")
        XCTAssertEqual(template.ext, "txt")
        XCTAssertEqual(template.content, "hello")
        XCTAssertFalse(template.isBuiltIn)
    }

    func testBuiltInFlag() {
        let template = FileTemplate(name: "Swift", ext: "swift", content: "", isBuiltIn: true)
        XCTAssertTrue(template.isBuiltIn)
    }

    func testFileName() {
        let template = FileTemplate(name: "Markdown", ext: "md", content: "")
        XCTAssertEqual(template.fileName, "untitled.md")
    }

    func testDisplayName() {
        let template = FileTemplate(name: "Python", ext: "py", content: "")
        XCTAssertEqual(template.displayName, "Python (.py)")
    }

    func testCodableRoundTrip() throws {
        let template = FileTemplate(name: "JSON", ext: "json", content: "{}")
        let encoded = try JSONEncoder().encode(template)
        let decoded = try JSONDecoder().decode(FileTemplate.self, from: encoded)
        XCTAssertEqual(decoded.name, "JSON")
        XCTAssertEqual(decoded.ext, "json")
        XCTAssertEqual(decoded.content, "{}")
    }

    func testHashable() {
        let a = FileTemplate(name: "A", ext: "txt", content: "")
        let b = FileTemplate(name: "A", ext: "txt", content: "")
        var set = Set<FileTemplate>()
        set.insert(a)
        set.insert(b)
        XCTAssertEqual(set.count, 2) // Different UUIDs
    }
}
