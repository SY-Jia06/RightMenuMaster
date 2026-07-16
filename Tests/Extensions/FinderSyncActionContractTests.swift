import XCTest

final class FinderSyncActionContractTests: XCTestCase {
  func testFinderExtensionExposesOnlyV2ActionsAndStructuredHandoff() throws {
    let source = try read("FinderExtension/FinderSync.swift")

    XCTAssertTrue(source.contains("case .newFile"))
    XCTAssertTrue(source.contains("case .copyPath"))
    XCTAssertTrue(source.contains("case .openTerminal"))
    XCTAssertTrue(source.contains("case .openEditor"))
    XCTAssertTrue(source.contains("ActionRequest(action: action, context: context)"))
    XCTAssertTrue(source.contains("ActionRequestStore.appGroup"))
    XCTAssertTrue(source.contains("URLQueryItem(name: \"id\""))
    XCTAssertTrue(source.contains("FIFinderSyncController.default().open(commandURL)"))
    XCTAssertTrue(source.contains("DistributedNotificationCenter.default().postNotificationName"))

    XCTAssertFalse(source.contains("ActionDispatcher"))
    XCTAssertFalse(source.contains("ScriptRunner"))
    XCTAssertFalse(source.contains("trashItem"))
    XCTAssertFalse(source.contains("Process()"))
    XCTAssertFalse(source.contains("NSWorkspace.shared.open(commandURL)"))
    XCTAssertFalse(source.contains("URLQueryItem(name: \"path\""))
  }

  func testFinderExtensionEntitlementsHaveNoFilesystemException() throws {
    let entitlements = try plist("FinderExtension/FinderExtension.entitlements")
    XCTAssertEqual(entitlements["com.apple.security.app-sandbox"] as? Bool, true)
    XCTAssertNotNil(entitlements["com.apple.security.application-groups"])

    let keys = Set(entitlements.keys)
    XCTAssertEqual(
      keys,
      [
        "com.apple.security.app-sandbox",
        "com.apple.security.application-groups",
      ]
    )
  }

  func testMainAppEntitlementsStayInsideV2Boundary() throws {
    let entitlements = try plist("MainApp/RightMenuMaster.entitlements")
    XCTAssertEqual(entitlements["com.apple.security.app-sandbox"] as? Bool, true)
    XCTAssertEqual(entitlements["com.apple.security.files.bookmarks.app-scope"] as? Bool, true)
    XCTAssertEqual(entitlements["com.apple.security.files.user-selected.read-write"] as? Bool, true)

    let serialized = String(
      decoding: try data("MainApp/RightMenuMaster.entitlements"), as: UTF8.self)
    XCTAssertFalse(serialized.contains("temporary-exception"))
    XCTAssertFalse(serialized.contains("get-task-allow"))
    XCTAssertFalse(serialized.contains("apple-events"))
  }

  func testLegacyRiskySourcesAreNotCompiledIntoV2Targets() throws {
    let project = try read("project.yml")
    XCTAssertTrue(project.contains("- path: FinderExtension/FinderSync.swift"))
    XCTAssertTrue(project.contains("- path: Shared/V2"))
    XCTAssertFalse(project.contains("- path: Shared\n"))
    XCTAssertFalse(project.contains("- path: FinderExtension\n"))
    XCTAssertTrue(project.contains("- Services"))
    XCTAssertTrue(project.contains("- ViewModels"))
    XCTAssertTrue(project.contains("- Views"))
    XCTAssertTrue(project.contains("- ContentView.swift"))
  }

  func testGeneratedFinderSourcesBuildPhaseMatchesV2Allowlist() throws {
    let project = try read("RightMenuMaster.xcodeproj/project.pbxproj")
    let nativeTargets = try section(
      in: project,
      beginning: "/* Begin PBXNativeTarget section */",
      ending: "/* End PBXNativeTarget section */"
    )
    let targetPattern =
      #"[A-F0-9]+ /\* FinderExtension \*/ = \{.*?buildPhases = \(\s*([A-F0-9]+) /\* Sources \*/"#
    let sourcePhaseID = try firstCapture(in: nativeTargets, pattern: targetPattern)
    let sourcePhases = try section(
      in: project,
      beginning: "/* Begin PBXSourcesBuildPhase section */",
      ending: "/* End PBXSourcesBuildPhase section */"
    )
    let phasePattern =
      NSRegularExpression.escapedPattern(for: sourcePhaseID)
      + #" /\* Sources \*/ = \{.*?files = \((.*?)\);"#
    let sourceList = try firstCapture(in: sourcePhases, pattern: phasePattern)
    let filenames = try allCaptures(
      in: sourceList,
      pattern: #"/\* ([^*]+\.swift) in Sources \*/"#
    )

    XCTAssertEqual(
      Set(filenames),
      [
        "ActionRequest.swift",
        "ActionRequestStore.swift",
        "ContextResolver.swift",
        "FinderSync.swift",
        "ProductModels.swift",
        "V2ConfigurationStore.swift",
        "V2Constants.swift",
      ]
    )

    for forbidden in [
      "ActionDispatcher.swift",
      "AppCommandURL.swift",
      "Constants.swift",
      "FileCreator.swift",
      "MenuBuilder.swift",
      "PendingFileCreationStore.swift",
      "ScriptRunner.swift",
      "TemplateService.swift",
    ] {
      XCTAssertFalse(project.contains("/* \(forbidden) */"), forbidden)
    }
  }

  func testHostHasNoAccessibilityOrResidentMenuBarCode() throws {
    let source = try read("MainApp/App.swift")
    XCTAssertFalse(source.contains("ApplicationServices"))
    XCTAssertFalse(source.contains("AXIsProcessTrusted"))
    XCTAssertFalse(source.contains("NSStatusItem"))
    XCTAssertTrue(source.contains("NSAppleEventManager"))
    XCTAssertTrue(source.contains("NSHostingController"))
  }

  func testExternalURLHasSingleAppDelegateConsumer() throws {
    let appSource = try read("MainApp/App.swift")
    let rootSource = try read("MainApp/V2/RootView.swift")

    XCTAssertTrue(appSource.contains("handleGetURLEvent"))
    XCTAssertTrue(appSource.contains("coordinator.consumeExternalURL(url)"))
    XCTAssertTrue(appSource.contains("handleFinderCommandReady"))
    XCTAssertTrue(appSource.contains("consumePendingExternalRequests"))
    XCTAssertFalse(rootSource.contains(".onOpenURL"))
  }

  func testActionRequestSchemaHasExactlyFourPublicActions() throws {
    let object =
      try JSONSerialization.jsonObject(
        with: data("Shared/contracts/action-request.schema.json")
      ) as? [String: Any]
    let properties = object?["properties"] as? [String: Any]
    let action = properties?["action"] as? [String: Any]
    let values = action?["enum"] as? [String]

    XCTAssertEqual(Set(values ?? []), ["newFile", "copyPath", "openTerminal", "openEditor"])
    XCTAssertEqual(values?.count, 4)
  }

  func testPublicReadmesNeverTeachSecurityBypass() throws {
    for path in ["README.md", "README_CN.md"] {
      let readme = try read(path)
      XCTAssertFalse(readme.contains("xattr -cr"))
      XCTAssertFalse(readme.contains("spctl --master-disable"))
    }
  }

  private var repositoryRoot: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  private func data(_ relativePath: String) throws -> Data {
    try Data(contentsOf: repositoryRoot.appendingPathComponent(relativePath))
  }

  private func read(_ relativePath: String) throws -> String {
    String(decoding: try data(relativePath), as: UTF8.self)
  }

  private func plist(_ relativePath: String) throws -> [String: Any] {
    let object = try PropertyListSerialization.propertyList(
      from: data(relativePath),
      options: [],
      format: nil
    )
    return try XCTUnwrap(object as? [String: Any])
  }

  private func firstCapture(in string: String, pattern: String) throws -> String {
    let expression = try NSRegularExpression(
      pattern: pattern,
      options: [.dotMatchesLineSeparators]
    )
    let fullRange = NSRange(string.startIndex..., in: string)
    let match = try XCTUnwrap(expression.firstMatch(in: string, range: fullRange))
    let range = try XCTUnwrap(Range(match.range(at: 1), in: string))
    return String(string[range])
  }

  private func allCaptures(in string: String, pattern: String) throws -> [String] {
    let expression = try NSRegularExpression(pattern: pattern)
    let fullRange = NSRange(string.startIndex..., in: string)
    return expression.matches(in: string, range: fullRange).map { match in
      let range = Range(match.range(at: 1), in: string)!
      return String(string[range])
    }
  }

  private func section(in string: String, beginning: String, ending: String) throws -> String {
    let start = try XCTUnwrap(string.range(of: beginning)?.upperBound)
    let end = try XCTUnwrap(string.range(of: ending, range: start..<string.endIndex)?.lowerBound)
    return String(string[start..<end])
  }
}
