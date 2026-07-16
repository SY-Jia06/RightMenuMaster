import XCTest
@testable import RightMenuMaster

final class SafeFileCreationV2Tests: XCTestCase {
    func testRecipeExtensionIsAppliedOnlyWhenInputHasNoExtension() throws {
        let markdown = try SafeFilenameParser.parse("notes", recipe: .markdown)
        XCTAssertEqual(markdown.fileName, "notes.md")
        XCTAssertEqual(markdown.stem, "notes")
        XCTAssertEqual(markdown.fileExtension, "md")
        XCTAssertTrue(markdown.appliedRecipeExtension)

        let explicit = try SafeFilenameParser.parse("notes.txt", recipe: .markdown)
        XCTAssertEqual(explicit.fileName, "notes.txt")
        XCTAssertEqual(explicit.fileExtension, "txt")
        XCTAssertFalse(explicit.appliedRecipeExtension)
    }

    func testExtensionlessDotfilesNeverReceiveRecipeExtension() throws {
        for recipe in [FileRecipe.blank, .text, .markdown] {
            let parsed = try SafeFilenameParser.parse(".env", recipe: recipe)
            XCTAssertEqual(parsed.fileName, ".env")
            XCTAssertEqual(parsed.stem, ".env")
            XCTAssertNil(parsed.fileExtension)
            XCTAssertFalse(parsed.appliedRecipeExtension)
        }

        let dottedDotfile = try SafeFilenameParser.parse(".env.local", recipe: .markdown)
        XCTAssertEqual(dottedDotfile.fileName, ".env.local")
        XCTAssertEqual(dottedDotfile.fileExtension, "local")
    }

    func testUnsafeAndCrossPlatformInvalidNamesAreRejected() {
        let cases: [(String, FilenameValidationError)] = [
            ("", .empty),
            (".", .relativeDirectoryMarker),
            ("..", .relativeDirectoryMarker),
            ("bad/name", .forbiddenCharacter("/")),
            ("bad:name", .forbiddenCharacter(":")),
            ("bad\nname", .unsafeControlCharacter),
            ("report\u{202E}fdp.exe", .unsafeControlCharacter),
            ("CON.txt", .windowsReservedName("CON")),
            ("lpt9.md", .windowsReservedName("lpt9")),
            ("trailing.", .trailingSpaceOrPeriod),
            ("trailing ", .trailingSpaceOrPeriod),
        ]

        for (name, expectedError) in cases {
            XCTAssertThrowsError(try SafeFilenameParser.parse(name, recipe: .blank), name) {
                XCTAssertEqual($0 as? FilenameValidationError, expectedError, name)
            }
        }
    }

    func testFinalFilenameByteLimitIncludesRecipeExtension() {
        let longName = String(repeating: "a", count: 253)
        XCTAssertThrowsError(try SafeFilenameParser.parse(longName, recipe: .markdown)) {
            XCTAssertEqual($0 as? FilenameValidationError, .tooLong(255))
        }
    }

    func testCreatorWritesRecipeContentAndReturnsExactLexicalURL() throws {
        let directory = try makeTemporaryDirectory()
        let result = try ExclusiveFileCreator().create(
            filename: "README",
            recipe: .markdown,
            in: directory
        )

        XCTAssertEqual(result.url.path, directory.appendingPathComponent("README.md").path)
        XCTAssertEqual(try String(contentsOf: result.url), "# \n\n")
    }

    func testCollisionNeverOverwritesAndSuggestsNextAvailableName() throws {
        let directory = try makeTemporaryDirectory()
        let existing = directory.appendingPathComponent("notes.md")
        let occupiedSuggestion = directory.appendingPathComponent("notes 2.md")
        try Data("do-not-change".utf8).write(to: existing)
        try Data("also-existing".utf8).write(to: occupiedSuggestion)

        XCTAssertThrowsError(
            try ExclusiveFileCreator().create(
                filename: "notes.md",
                recipe: .blank,
                in: directory
            )
        ) { error in
            XCTAssertEqual(
                error as? FileCreationError,
                .collision(existing: existing, suggestedFilename: "notes 3.md")
            )
        }
        XCTAssertEqual(try String(contentsOf: existing), "do-not-change")
        XCTAssertEqual(try String(contentsOf: occupiedSuggestion), "also-existing")
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("notes 3.md").path
        ))
    }

    func testCollisionSuggestionContinuesExistingNumericSuffix() throws {
        let directory = try makeTemporaryDirectory()
        let existing = directory.appendingPathComponent("notes 7.txt")
        try Data().write(to: existing)

        XCTAssertThrowsError(
            try ExclusiveFileCreator().create(
                filename: "notes 7.txt",
                recipe: .blank,
                in: directory
            )
        ) { error in
            XCTAssertEqual(
                error as? FileCreationError,
                .collision(existing: existing, suggestedFilename: "notes 8.txt")
            )
        }
    }

    func testDanglingSymlinkCountsAsCollision() throws {
        let directory = try makeTemporaryDirectory()
        let link = directory.appendingPathComponent("notes.txt")
        try FileManager.default.createSymbolicLink(
            at: link,
            withDestinationURL: directory.appendingPathComponent("missing-target")
        )

        XCTAssertThrowsError(
            try ExclusiveFileCreator().create(
                filename: "notes.txt",
                recipe: .blank,
                in: directory
            )
        ) { error in
            XCTAssertEqual(
                error as? FileCreationError,
                .collision(existing: link, suggestedFilename: "notes 2.txt")
            )
        }
    }

    func testConcurrentCreationHasExactlyOneWinnerAndNeverOverwrites() throws {
        let directory = try makeTemporaryDirectory()
        let lock = NSLock()
        var successes = [CreatedFile]()
        var collisions = 0
        var unexpectedErrors = [Error]()

        DispatchQueue.concurrentPerform(iterations: 32) { _ in
            do {
                let result = try ExclusiveFileCreator().create(
                    filename: "race.md",
                    recipe: .markdown,
                    in: directory
                )
                lock.lock()
                successes.append(result)
                lock.unlock()
            } catch FileCreationError.collision {
                lock.lock()
                collisions += 1
                lock.unlock()
            } catch {
                lock.lock()
                unexpectedErrors.append(error)
                lock.unlock()
            }
        }

        XCTAssertEqual(successes.count, 1)
        XCTAssertEqual(collisions, 31)
        XCTAssertTrue(unexpectedErrors.isEmpty, "Unexpected errors: \(unexpectedErrors)")
        XCTAssertEqual(
            try String(contentsOf: directory.appendingPathComponent("race.md")),
            "# \n\n"
        )
    }

    func testMissingAndNonDirectoryTargetsReturnSpecificErrors() throws {
        let parent = try makeTemporaryDirectory()
        let missing = parent.appendingPathComponent("missing", isDirectory: true)
        XCTAssertThrowsError(
            try ExclusiveFileCreator().create(filename: "file", recipe: .blank, in: missing)
        ) {
            XCTAssertEqual($0 as? FileCreationError, .directoryMissing(missing))
        }

        let file = parent.appendingPathComponent("ordinary-file")
        try Data().write(to: file)
        XCTAssertThrowsError(
            try ExclusiveFileCreator().create(filename: "file", recipe: .blank, in: file)
        ) {
            XCTAssertEqual($0 as? FileCreationError, .notDirectory(file))
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RightMenuMasterFileTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
