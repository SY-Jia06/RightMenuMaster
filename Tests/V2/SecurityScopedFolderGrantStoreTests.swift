import Foundation
import XCTest

@testable import RightMenuMaster

@MainActor
final class SecurityScopedFolderGrantStoreTests: XCTestCase {
  func testTopLevelGrantStaysActiveAcrossNestedOperations() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let nested = root.appendingPathComponent("one/two/three", isDirectory: true)
    try fileManager.createDirectory(at: nested, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: root) }

    let suiteName = "RightMenuMaster.SecurityScopeTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    var startCount = 0
    var stopCount = 0
    let store = SecurityScopedFolderGrantStore(
      defaults: defaults,
      monitoredFoldersDefaults: nil,
      storageKey: "grants",
      fileManager: fileManager,
      startAccessing: { _ in
        startCount += 1
        return true
      },
      stopAccessing: { _ in stopCount += 1 }
    )

    let grant = try store.authorize(root)
    XCTAssertEqual(store.grant(containing: nested)?.id, grant.id)
    XCTAssertEqual(startCount, 1)

    try store.withAccess(to: nested) { _ in }
    try store.withAccess(to: nested.appendingPathComponent("file.txt")) { _ in }
    XCTAssertEqual(startCount, 1, "Nested operations must reuse the active top-level scope")

    try store.revoke(grant)
    XCTAssertEqual(stopCount, 1)
  }
}
