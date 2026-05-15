import XCTest
@testable import RightMenuMaster

/// Bug condition exploration tests for sandbox permission sharing.
///
/// These tests demonstrate the three root causes of the bug:
/// 1. `FinderMonitorDirectories.urls()` with a container home path produces URLs
///    containing `/Library/Containers/` path segments.
/// 2. `AppCommand` enum does NOT have a `trashFile` case — no trash fallback exists.
/// 3. `AuthorizedFolderStore` uses `relativeTo: nil` — bookmarks are app-scoped
///    and cannot be shared across processes.
///
/// **Validates: Requirements 1.1, 1.2, 1.3, 1.4, 1.5**
///
/// Structure:
/// - Tests confirming CURRENT buggy state → PASS on unfixed code
/// - Tests encoding EXPECTED fixed state → FAIL on unfixed code
/// - Overall test suite is EXPECTED TO FAIL, confirming the bug exists
final class SandboxPermissionBugTests: XCTestCase {

    // MARK: - Helpers

    private func repoRoot() -> URL {
        let testFile = URL(fileURLWithPath: #filePath)
        return testFile
            .deletingLastPathComponent() // BugCondition/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // repo root
    }

    private func constantsSource() throws -> String {
        try String(contentsOf: repoRoot()
            .appendingPathComponent("Shared")
            .appendingPathComponent("Constants.swift"))
    }

    private func actionDispatcherSource() throws -> String {
        try String(contentsOf: repoRoot()
            .appendingPathComponent("FinderExtension")
            .appendingPathComponent("ActionHandlers")
            .appendingPathComponent("ActionDispatcher.swift"))
    }

    // MARK: - Bug Condition 1: Containerized Home Path

    /// Confirms the bug: when `FinderMonitorDirectories.urls()` is called with a simulated
    /// container home path (like the one returned by `FileManager.default.homeDirectoryForCurrentUser`
    /// in the Finder extension sandbox), the resulting URLs contain `/Library/Containers/` segments.
    ///
    /// This test PASSES on unfixed code — it demonstrates the buggy behavior.
    func testContainerHomePathProducesContainerizedURLs() {
        // Simulate the container path that FileManager returns in the extension sandbox
        let containerHome = URL(fileURLWithPath:
            "/Users/j/Library/Containers/com.rightmenu.master.finder-extension/Data",
            isDirectory: true
        )

        let urls = FinderMonitorDirectories.urls(
            home: containerHome,
            authorizedFolders: []
        )

        // With a container home, Desktop/Documents/Downloads will contain container path segments
        let containerPaths = urls.filter { $0.path.contains("Library/Containers") }
        XCTAssertFalse(
            containerPaths.isEmpty,
            "With a container home path, FinderMonitorDirectories.urls() SHOULD produce " +
            "URLs containing 'Library/Containers' — this confirms the bug mechanism."
        )

        // Verify specific paths are containerized
        let desktopPath = containerHome.appendingPathComponent("Desktop", isDirectory: true)
        XCTAssertTrue(
            urls.contains(desktopPath),
            "Desktop URL should be based on container home path: \(desktopPath.path)"
        )

        let documentsPath = containerHome.appendingPathComponent("Documents", isDirectory: true)
        XCTAssertTrue(
            urls.contains(documentsPath),
            "Documents URL should be based on container home path: \(documentsPath.path)"
        )

        let downloadsPath = containerHome.appendingPathComponent("Downloads", isDirectory: true)
        XCTAssertTrue(
            urls.contains(downloadsPath),
            "Downloads URL should be based on container home path: \(downloadsPath.path)"
        )
    }

    /// Confirms the bug: the default `home` parameter in `FinderMonitorDirectories.urls()`
    /// uses `FileManager.default.homeDirectoryForCurrentUser` which returns the container
    /// path in the extension process.
    ///
    /// This test PASSES on unfixed code — it reads the source to confirm the buggy default.
    func testDefaultHomeParameterUsesFileManager() throws {
        let source = try constantsSource()

        // The default parameter currently uses FileManager.default.homeDirectoryForCurrentUser
        XCTAssertTrue(
            source.contains("FileManager.default.homeDirectoryForCurrentUser"),
            "FinderMonitorDirectories.urls() default home parameter should reference " +
            "FileManager.default.homeDirectoryForCurrentUser (confirming the bug mechanism)."
        )
    }

    // MARK: - Bug Condition 2: Missing Trash Fallback

    /// Confirms the fix: `AppCommand` enum now HAS a `trashFile` case.
    /// This provides the mechanism for the extension to delegate trash operations
    /// to the main app when permission errors occur.
    ///
    /// This test PASSES on fixed code — it confirms the fallback exists.
    func testAppCommandHasTrashFileFallback() throws {
        let source = try constantsSource()

        XCTAssertTrue(
            source.contains("trashFile") && source.contains("trash-file"),
            "AppCommand enum should contain 'trashFile' and 'trash-file' after the fix. " +
            "This confirms the trash delegation command exists."
        )
    }

    // MARK: - Bug Condition 3: App-Scope Bookmarks

    /// Confirms the bug: `AuthorizedFolderStore.authorizeFolder` uses `relativeTo: nil`
    /// when creating bookmarks, making them app-scoped. App-scoped bookmarks cannot be
    /// resolved by a different process (the Finder extension).
    ///
    /// This test PASSES on unfixed code — it confirms bookmarks are app-scoped.
    func testAuthorizedFolderStoreUsesAppScopedBookmarks() throws {
        let source = try constantsSource()

        // The authorizeFolder method uses relativeTo: nil (app-scoped)
        XCTAssertTrue(
            source.contains("relativeTo: nil"),
            "AuthorizedFolderStore should use 'relativeTo: nil' in bookmarkData() call, " +
            "confirming bookmarks are app-scoped and cannot be shared across processes."
        )
    }

    // MARK: - Expected Behavior Assertions (FAIL on unfixed code)

    /// Asserts that a `RealHomeDirectory` enum exists.
    /// On UNFIXED code, this FAILS because the helper doesn't exist yet.
    func testRealHomeDirectoryEnumExists() throws {
        let source = try constantsSource()

        XCTAssertTrue(
            source.contains("enum RealHomeDirectory"),
            "Constants.swift should contain 'enum RealHomeDirectory' helper that provides " +
            "the real home directory path via POSIX getpwuid(). Its absence confirms the bug: " +
            "no mechanism exists to bypass the sandbox container path."
        )
    }

    /// Asserts that `FinderMonitorDirectories.urls()` default parameter does NOT use
    /// `FileManager.default.homeDirectoryForCurrentUser`.
    /// On UNFIXED code, this FAILS because it still uses the FileManager API.
    func testDefaultHomeParameterDoesNotUseFileManager() throws {
        let source = try constantsSource()

        // Extract the FinderMonitorDirectories.urls function signature
        // After the fix, the default should use RealHomeDirectory.url instead
        let lines = source.components(separatedBy: "\n")
        let urlsFuncLines = lines.filter {
            $0.contains("home:") && $0.contains("FileManager.default.homeDirectoryForCurrentUser")
        }

        XCTAssertTrue(
            urlsFuncLines.isEmpty,
            "FinderMonitorDirectories.urls() default home parameter should NOT use " +
            "FileManager.default.homeDirectoryForCurrentUser. It should use " +
            "RealHomeDirectory.url instead. The presence of this default confirms the bug."
        )
    }

    /// Asserts that `AppCommand` has a `trashFile` case.
    /// On UNFIXED code, this FAILS because the case doesn't exist yet.
    func testAppCommandHasTrashFileCase() throws {
        let source = try constantsSource()

        XCTAssertTrue(
            source.contains("case trashFile") || source.contains("case trashFile ="),
            "AppCommand enum should have a 'trashFile' case for delegating trash operations " +
            "from the extension to the main app. Its absence confirms the bug: " +
            "no command exists for cross-process trash delegation."
        )
    }
}
