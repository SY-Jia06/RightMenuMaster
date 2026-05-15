import XCTest

final class FinderSyncActionContractTests: XCTestCase {

    func testFinderSyncPrincipalClassProvidesCopyPathAndNewFileActions() throws {
        let source = try finderSyncSource()

        XCTAssertTrue(
            source.contains("@objc func handleAction"),
            "Finder Sync menu item actions must be implemented by the extension principal class."
        )
        XCTAssertTrue(
            source.contains("@objc func createFileAction"),
            "New File submenu actions must be implemented by the extension principal class."
        )
        XCTAssertFalse(
            source.contains(".target = ActionDispatcher.shared"),
            "Finder Sync does not reliably preserve custom NSMenuItem targets across its XPC menu boundary."
        )
    }

    func testFinderExtensionUsesPersistentFolderBookmarksWithoutHomeWideTemporaryException() throws {
        let entitlements = try plist(at: repoRoot()
            .appendingPathComponent("FinderExtension")
            .appendingPathComponent("FinderExtension.entitlements"))

        XCTAssertEqual(entitlements["com.apple.security.app-sandbox"] as? Bool, true)
        XCTAssertEqual(entitlements["com.apple.security.application-groups"] as? [String], ["group.com.rightmenu.master"])
        XCTAssertEqual(entitlements["com.apple.security.files.user-selected.read-write"] as? Bool, true)
        XCTAssertEqual(entitlements["com.apple.security.files.bookmarks.app-scope"] as? Bool, true)
        XCTAssertNil(entitlements["com.apple.security.temporary-exception.files.home-relative-path.read-write"])
    }

    func testMainAppCanCreatePersistentFolderBookmarks() throws {
        let entitlements = try plist(at: repoRoot()
            .appendingPathComponent("MainApp")
            .appendingPathComponent("RightMenuMaster.entitlements"))

        XCTAssertEqual(entitlements["com.apple.security.app-sandbox"] as? Bool, true)
        XCTAssertEqual(entitlements["com.apple.security.application-groups"] as? [String], ["group.com.rightmenu.master"])
        XCTAssertEqual(entitlements["com.apple.security.files.user-selected.read-write"] as? Bool, true)
        XCTAssertEqual(entitlements["com.apple.security.files.bookmarks.app-scope"] as? Bool, true)
    }

    func testOpenTerminalDelegatesToMainAppBridge() throws {
        let source = try String(contentsOf: repoRoot()
            .appendingPathComponent("FinderExtension")
            .appendingPathComponent("ActionHandlers")
            .appendingPathComponent("ActionDispatcher.swift"))

        XCTAssertTrue(source.contains("command: .openTerminal"))
        XCTAssertTrue(source.contains("AppCommandURL.url(command: command"))
        XCTAssertFalse(source.contains("withApplicationAt: appURL"))
    }

    func testRenameModeDelegatesToMainAppBridge() throws {
        let source = try String(contentsOf: repoRoot()
            .appendingPathComponent("FinderExtension")
            .appendingPathComponent("ActionHandlers")
            .appendingPathComponent("FileCreator.swift"))

        XCTAssertTrue(source.contains("AppCommandURL.url(command: .rename"))
        XCTAssertFalse(source.contains("AXIsProcessTrusted()"))
        XCTAssertFalse(source.contains("System Events"))
    }

    func testNewFilePermissionFailureRequestsMainAppAuthorizationAndRetry() throws {
        let fileCreatorSource = try String(contentsOf: repoRoot()
            .appendingPathComponent("FinderExtension")
            .appendingPathComponent("ActionHandlers")
            .appendingPathComponent("FileCreator.swift"))
        let appSource = try String(contentsOf: repoRoot()
            .appendingPathComponent("MainApp")
            .appendingPathComponent("App.swift"))

        XCTAssertTrue(fileCreatorSource.contains("PendingFileCreationRequest"))
        XCTAssertTrue(fileCreatorSource.contains("command: .authorizeCreateFile"))
        XCTAssertTrue(fileCreatorSource.contains("requestID"))
        XCTAssertTrue(appSource.contains("case .authorizeCreateFile"))
        XCTAssertTrue(appSource.contains("requestFolderAccess"))
        XCTAssertTrue(appSource.contains("createPendingFile"))
    }

    func testMainAppRegistersCommandURLScheme() throws {
        let info = try plist(at: repoRoot()
            .appendingPathComponent("MainApp")
            .appendingPathComponent("Info.plist"))

        let urlTypes = try XCTUnwrap(info["CFBundleURLTypes"] as? [[String: Any]])
        let schemes = urlTypes.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        XCTAssertTrue(schemes.contains("rightmenumaster"))
    }

    func testMainAppHandlesCommandURLsWithoutOpeningSwiftUIWindow() throws {
        let appSource = try String(contentsOf: repoRoot()
            .appendingPathComponent("MainApp")
            .appendingPathComponent("App.swift"))

        XCTAssertTrue(appSource.contains("NSApplicationDelegateAdaptor"))
        XCTAssertTrue(appSource.contains("NSAppleEventManager.shared().setEventHandler"))
        XCTAssertTrue(appSource.contains("handleGetURLEvent"))
        XCTAssertTrue(appSource.contains(".handlesExternalEvents(matching: [\"settings\"])"))
        XCTAssertFalse(appSource.contains(".onOpenURL"))
    }

    func testFinderSyncRefreshesMonitoredDirectoriesWhenPermissionsChange() throws {
        let source = try finderSyncSource()

        XCTAssertTrue(source.contains("DistributedNotificationCenter.default().addObserver"))
        XCTAssertTrue(source.contains("authorizedFoldersDidChange"))
        XCTAssertTrue(source.contains("authorizedFoldersChangedNotificationName"))
    }

    func testMainAppPostsPermissionChangeNotificationAndOffersHomeAuthorization() throws {
        let viewModelSource = try String(contentsOf: repoRoot()
            .appendingPathComponent("MainApp")
            .appendingPathComponent("ViewModels")
            .appendingPathComponent("SettingsViewModel.swift"))
        let contentViewSource = try String(contentsOf: repoRoot()
            .appendingPathComponent("MainApp")
            .appendingPathComponent("ContentView.swift"))

        XCTAssertTrue(viewModelSource.contains("authorizeHomeFolder"))
        XCTAssertTrue(viewModelSource.contains("authorizedFoldersChangedNotificationName"))
        XCTAssertTrue(viewModelSource.contains("DistributedNotificationCenter.default().post"))
        XCTAssertTrue(contentViewSource.contains("Enable Everywhere"))
    }

    private func finderSyncSource() throws -> String {
        let sourceURL = repoRoot()
            .appendingPathComponent("FinderExtension")
            .appendingPathComponent("FinderSync.swift")
        return try String(contentsOf: sourceURL)
    }

    private func repoRoot() -> URL {
        let testFile = URL(fileURLWithPath: #filePath)
        return testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func plist(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try XCTUnwrap(plist as? [String: Any])
    }
}
