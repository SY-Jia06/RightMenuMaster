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
      usesSecurityScopedAccess: true,
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

  func testHomeGrantExpandsFinderMonitoringWithoutLibraryOrHiddenFolders() throws {
    let fileManager = FileManager.default
    let home = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let work = home.appendingPathComponent("Work", isDirectory: true)
    let library = home.appendingPathComponent("Library", isDirectory: true)
    let hidden = home.appendingPathComponent(".private", isDirectory: true)
    try fileManager.createDirectory(at: work, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: library, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: hidden, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: home) }

    let grantsSuite = "RightMenuMaster.HomeGrantTests.\(UUID().uuidString)"
    let monitorSuite = "RightMenuMaster.HomeMonitorTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: grantsSuite))
    let monitoredDefaults = try XCTUnwrap(UserDefaults(suiteName: monitorSuite))
    defer {
      defaults.removePersistentDomain(forName: grantsSuite)
      monitoredDefaults.removePersistentDomain(forName: monitorSuite)
    }

    let store = SecurityScopedFolderGrantStore(
      defaults: defaults,
      monitoredFoldersDefaults: monitoredDefaults,
      storageKey: "grants",
      monitoredFoldersKey: "monitored",
      fileManager: fileManager,
      homeDirectoryURL: home,
      usesSecurityScopedAccess: true,
      startAccessing: { _ in true },
      stopAccessing: { _ in }
    )
    _ = try store.authorize(home)

    let monitored = try XCTUnwrap(monitoredDefaults.stringArray(forKey: "monitored"))
    XCTAssertTrue(monitored.contains(home.path))
    XCTAssertTrue(monitored.contains(work.path))
    XCTAssertFalse(monitored.contains(library.path))
    XCTAssertFalse(monitored.contains(hidden.path))
  }
}
