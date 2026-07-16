import XCTest
@testable import RightMenuMaster

final class ProductModelsV2Tests: XCTestCase {
    func testProductActionsAreExactlyVersionTwoScope() {
        XCTAssertEqual(
            ProductAction.allCases,
            [.newFile, .copyPath, .openTerminal, .openEditor]
        )
    }

    func testFileRecipeMetadata() {
        XCTAssertNil(FileRecipe.blank.preferredExtension)
        XCTAssertEqual(FileRecipe.text.preferredExtension, "txt")
        XCTAssertEqual(FileRecipe.markdown.preferredExtension, "md")
        XCTAssertEqual(FileRecipe.markdown.initialContent, "# \n\n")
    }

    func testPreferredApplicationValidationAndURL() throws {
        let application = PreferredApplication(
            id: "com.coteditor.CotEditor",
            displayName: "CotEditor",
            applicationPath: "/Applications/CotEditor.app"
        )

        XCTAssertNoThrow(try application.validate())
        XCTAssertEqual(application.applicationURL?.path, "/Applications/CotEditor.app")
        XCTAssertThrowsError(
            try PreferredApplication(id: "", displayName: "Editor").validate()
        ) { error in
            XCTAssertEqual(error as? PreferredApplicationValidationError, .emptyIdentifier)
        }
        XCTAssertThrowsError(
            try PreferredApplication(
                id: "editor",
                displayName: "Editor",
                applicationPath: "Applications/Editor.app"
            ).validate()
        ) { error in
            XCTAssertEqual(
                error as? PreferredApplicationValidationError,
                .invalidApplicationPath("Applications/Editor.app")
            )
        }
    }

    func testDefaultConfigurationIsCompleteAndValid() throws {
        let config = V2Config.default

        XCTAssertEqual(config.schemaVersion, 2)
        XCTAssertEqual(config.enabledActions, ProductAction.allCases)
        XCTAssertEqual(config.actionOrder, ProductAction.allCases)
        XCTAssertEqual(config.language, .system)
        XCTAssertEqual(config.onboardingStep, 0)
        XCTAssertNoThrow(try config.validate())
    }

    func testConfigurationRoundTripUsesSchemaValues() throws {
        let config = V2Config(
            enabledActions: [.newFile, .copyPath],
            actionOrder: [.copyPath, .newFile, .openEditor, .openTerminal],
            preferredTerminal: PreferredApplication(id: "com.mitchellh.ghostty", displayName: "Ghostty"),
            preferredEditor: PreferredApplication(id: "com.coteditor.CotEditor", displayName: "CotEditor"),
            language: .simplifiedChinese,
            defaultRecipe: .markdown,
            postCreateBehavior: .openPreferredEditor,
            onboardingStep: 3
        )

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(V2Config.self, from: data)
        XCTAssertEqual(decoded, config)
    }

    func testConfigurationNormalizationRemovesDuplicatesAndAppendsMissingActions() throws {
        let config = V2Config(
            enabledActions: [.copyPath, .copyPath, .newFile],
            actionOrder: [.openEditor, .openEditor, .newFile],
            onboardingStep: 99
        ).normalized()

        XCTAssertEqual(config.enabledActions, [.copyPath, .newFile])
        XCTAssertEqual(config.actionOrder, [.openEditor, .newFile, .copyPath, .openTerminal])
        XCTAssertEqual(config.onboardingStep, 4)
        XCTAssertNoThrow(try config.validate())
    }

    func testConfigurationDecoderRejectsUnknownMajorVersion() {
        let json = """
        {
          "schemaVersion": 3,
          "enabledActions": ["newFile"],
          "actionOrder": ["newFile", "copyPath", "openTerminal", "openEditor"],
          "language": "system",
          "defaultRecipe": "blank",
          "postCreateBehavior": "reveal"
        }
        """

        XCTAssertThrowsError(try JSONDecoder().decode(V2Config.self, from: Data(json.utf8))) {
            XCTAssertEqual(
                $0 as? V2ConfigValidationError,
                .unsupportedSchemaVersion(3)
            )
        }
    }

    func testConfigurationRejectsDuplicateAndIncompleteOrder() {
        XCTAssertThrowsError(
            try V2Config(actionOrder: [.newFile, .newFile]).validate()
        ) { error in
            XCTAssertEqual(error as? V2ConfigValidationError, .duplicateOrderedAction)
        }

        XCTAssertThrowsError(
            try V2Config(actionOrder: [.newFile, .copyPath]).validate()
        ) { error in
            XCTAssertEqual(error as? V2ConfigValidationError, .incompleteActionOrder)
        }
    }

    func testSharedConfigurationStoreSavesNormalizedConfig() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = V2ConfigurationStore(defaults: defaults)
        let input = V2Config(
            enabledActions: [.copyPath, .copyPath],
            actionOrder: [.openEditor, .newFile],
            onboardingStep: 9
        )

        try store.save(input)
        let loaded = store.load()
        XCTAssertEqual(loaded.enabledActions, [.copyPath])
        XCTAssertEqual(loaded.actionOrder, [.openEditor, .newFile, .copyPath, .openTerminal])
        XCTAssertEqual(loaded.onboardingStep, 4)
        XCTAssertNotNil(defaults.data(forKey: Constants.v2ConfigurationKey))
    }

    func testSharedConfigurationStoreUsesDefaultForMissingOrCorruptData() {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = V2ConfigurationStore(defaults: defaults)

        XCTAssertEqual(store.load(), .default)
        defaults.set(Data("not-json".utf8), forKey: Constants.v2ConfigurationKey)
        XCTAssertEqual(store.load(), .default)
        XCTAssertEqual(Constants.v2MonitoredFolderPathsKey, "v2.monitoredFolderPaths")
    }

    private func makeIsolatedDefaults() -> (UserDefaults, String) {
        let suiteName = "RightMenuMaster.V2ConfigTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }
}
