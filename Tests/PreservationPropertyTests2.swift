import XCTest
@testable import RightMenuMaster

/// Preservation property tests for FileCreationPlanner, AppCommandURL, and PendingFileCreationStore.
/// These tests PASS on unfixed code and MUST continue to PASS after the fix.
///
/// **Validates: Requirements 3.1, 3.6, 3.7**
///
/// Properties tested:
/// 1. FileCreationPlanner.nextFileURL always returns a URL inside the given directory
/// 2. FileCreationPlanner.nextFileURL follows the naming pattern `untitled.{ext}` or `untitled {n}.{ext}`
/// 3. AppCommandURL.url produces URLs with correct scheme, host, and query parameters
/// 4. PendingFileCreationStore round-trips requests correctly
final class PreservationPropertyTests2: XCTestCase {

    // MARK: - Test Data Generators

    private let testTemplates: [FileTemplate] = [
        FileTemplate(name: "Plain Text", ext: "txt", content: ""),
        FileTemplate(name: "Markdown", ext: "md", content: "# "),
        FileTemplate(name: "Swift File", ext: "swift", content: "import Foundation\n"),
        FileTemplate(name: "Python File", ext: "py", content: "#!/usr/bin/env python3\n"),
        FileTemplate(name: "JavaScript File", ext: "js", content: ""),
        FileTemplate(name: "Shell Script", ext: "sh", content: "#!/bin/bash\n"),
    ]

    private let testDirectoryPaths: [String] = [
        "/Users/j/Desktop",
        "/Users/j/Documents",
        "/Users/j/Downloads",
        "/Users/j/Projects",
        "/Users/j/Projects/MyApp/Sources",
        "/tmp/scratch",
        "/Volumes/External/Work",
        "/Users/alice/Code/OpenSource",
        "/Users/用户/文档",
        "/Users/bob smith/My Projects",
    ]

    private let testPaths: [String] = [
        "/Users/j/Desktop",
        "/Users/j/Documents/report.pdf",
        "/tmp/file.txt",
        "/Users/j/Projects/My App/Sources/main.swift",
        "/Users/j/工作区/Projects/claude",
        "/Volumes/Backup Drive/Archives/2024",
        "/Users/bob smith/Downloads/file (1).zip",
        "/Users/j/path with spaces/and (parens)/file.txt",
    ]

    // MARK: - Property 1: FileCreationPlanner.nextFileURL — URL is inside directory

    /// For any valid directory URL and FileTemplate, the returned URL is always inside the given directory.
    func testNextFileURLAlwaysInsideDirectory() {
        for dirPath in testDirectoryPaths {
            let dirURL = URL(fileURLWithPath: dirPath, isDirectory: true)
            for template in testTemplates {
                let result = FileCreationPlanner.nextFileURL(
                    in: dirURL,
                    template: template,
                    fileExists: { _ in false }
                )

                XCTAssertEqual(
                    result.deletingLastPathComponent().standardizedFileURL.path,
                    dirURL.standardizedFileURL.path,
                    "nextFileURL must return a URL inside '\(dirPath)' for template '\(template.ext)'"
                )
            }
        }
    }

    // MARK: - Property 2: FileCreationPlanner.nextFileURL — Naming pattern

    /// The returned filename follows the pattern `untitled.{ext}` or `untitled {n}.{ext}` where n >= 1.
    func testNextFileURLFollowsNamingPattern() {
        for template in testTemplates {
            let dirURL = URL(fileURLWithPath: "/tmp/test", isDirectory: true)

            // Test with no existing files
            let result0 = FileCreationPlanner.nextFileURL(
                in: dirURL, template: template, fileExists: { _ in false }
            )
            XCTAssertEqual(
                result0.lastPathComponent, "untitled.\(template.ext)",
                "When no files exist, should return 'untitled.\(template.ext)'"
            )

            // Test with untitled.{ext} existing
            let result1 = FileCreationPlanner.nextFileURL(
                in: dirURL, template: template,
                fileExists: { path in
                    path == dirURL.appendingPathComponent("untitled.\(template.ext)").path
                }
            )
            XCTAssertEqual(
                result1.lastPathComponent, "untitled 1.\(template.ext)",
                "When 'untitled.\(template.ext)' exists, should return 'untitled 1.\(template.ext)'"
            )

            // Test with untitled.{ext} and untitled 1.{ext} existing
            let result2 = FileCreationPlanner.nextFileURL(
                in: dirURL, template: template,
                fileExists: { path in
                    let existingFiles: Set<String> = [
                        dirURL.appendingPathComponent("untitled.\(template.ext)").path,
                        dirURL.appendingPathComponent("untitled 1.\(template.ext)").path,
                    ]
                    return existingFiles.contains(path)
                }
            )
            XCTAssertEqual(
                result2.lastPathComponent, "untitled 2.\(template.ext)",
                "When 'untitled.\(template.ext)' and 'untitled 1.\(template.ext)' exist, should return 'untitled 2.\(template.ext)'"
            )
        }
    }

    /// For any number of existing files (0..10), the returned filename matches the expected pattern.
    func testNextFileURLCounterIncrements() {
        let template = FileTemplate(name: "Test", ext: "txt", content: "")
        let dirURL = URL(fileURLWithPath: "/tmp/test", isDirectory: true)

        for existingCount in 0..<10 {
            var existingFiles = Set<String>()
            if existingCount > 0 {
                existingFiles.insert(dirURL.appendingPathComponent("untitled.txt").path)
                for i in 1..<existingCount {
                    existingFiles.insert(dirURL.appendingPathComponent("untitled \(i).txt").path)
                }
            }

            let result = FileCreationPlanner.nextFileURL(
                in: dirURL, template: template,
                fileExists: { existingFiles.contains($0) }
            )

            let expectedName: String
            if existingCount == 0 {
                expectedName = "untitled.txt"
            } else {
                expectedName = "untitled \(existingCount).txt"
            }

            XCTAssertEqual(
                result.lastPathComponent, expectedName,
                "With \(existingCount) existing files, expected '\(expectedName)'"
            )
        }
    }

    /// The returned filename always has the correct extension matching the template.
    func testNextFileURLAlwaysHasCorrectExtension() {
        for dirPath in testDirectoryPaths {
            let dirURL = URL(fileURLWithPath: dirPath, isDirectory: true)
            for template in testTemplates {
                // Test with various fileExists scenarios
                for existCount in 0...3 {
                    var existingFiles = Set<String>()
                    if existCount > 0 {
                        existingFiles.insert(dirURL.appendingPathComponent("untitled.\(template.ext)").path)
                        for i in 1..<existCount {
                            existingFiles.insert(dirURL.appendingPathComponent("untitled \(i).\(template.ext)").path)
                        }
                    }

                    let result = FileCreationPlanner.nextFileURL(
                        in: dirURL, template: template,
                        fileExists: { existingFiles.contains($0) }
                    )

                    XCTAssertEqual(
                        result.pathExtension, template.ext,
                        "Extension must be '\(template.ext)' — dir=\(dirPath), existCount=\(existCount)"
                    )
                }
            }
        }
    }

    // MARK: - Property 3: AppCommandURL.url — Scheme, Host, and Query

    /// For all AppCommand cases and valid paths, produces a URL with scheme `rightmenumaster`.
    func testAppCommandURLAlwaysHasCorrectScheme() {
        let commands: [AppCommand] = [.openTerminal, .openITerm, .rename, .authorizeCreateFile]

        for command in commands {
            for path in testPaths {
                let url = AppCommandURL.url(command: command, path: path)
                XCTAssertNotNil(url, "URL should not be nil for command=\(command.rawValue), path=\(path)")
                XCTAssertEqual(
                    url?.scheme, "rightmenumaster",
                    "Scheme must be 'rightmenumaster' for command=\(command.rawValue)"
                )
            }
        }
    }

    /// The host matches the command's rawValue.
    func testAppCommandURLHostMatchesCommandRawValue() {
        let commands: [AppCommand] = [.openTerminal, .openITerm, .rename, .authorizeCreateFile]

        for command in commands {
            for path in testPaths {
                let url = AppCommandURL.url(command: command, path: path)
                XCTAssertEqual(
                    url?.host, command.rawValue,
                    "Host must be '\(command.rawValue)' for path=\(path)"
                )
            }
        }
    }

    /// The query contains a `path` parameter with the given path value.
    func testAppCommandURLQueryContainsPath() {
        let commands: [AppCommand] = [.openTerminal, .openITerm, .rename, .authorizeCreateFile]

        for command in commands {
            for path in testPaths {
                let url = AppCommandURL.url(command: command, path: path)
                guard let url = url,
                      let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                    XCTFail("Failed to parse URL for command=\(command.rawValue), path=\(path)")
                    continue
                }

                let pathItem = components.queryItems?.first { $0.name == "path" }
                XCTAssertNotNil(pathItem, "Query must contain 'path' item")
                XCTAssertEqual(
                    pathItem?.value, path,
                    "Query 'path' value must equal '\(path)' for command=\(command.rawValue)"
                )
            }
        }
    }

    /// Extra query items are appended correctly.
    func testAppCommandURLExtraQueryItems() {
        let extraItems = [
            URLQueryItem(name: "id", value: "abc-123"),
            URLQueryItem(name: "template", value: "swift"),
        ]

        let url = AppCommandURL.url(
            command: .authorizeCreateFile,
            path: "/Users/j/Projects",
            queryItems: extraItems
        )

        guard let url = url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            XCTFail("Failed to parse URL with extra query items")
            return
        }

        // Should have path + 2 extra items = 3 total
        XCTAssertEqual(components.queryItems?.count, 3)

        let idItem = components.queryItems?.first { $0.name == "id" }
        XCTAssertEqual(idItem?.value, "abc-123")

        let templateItem = components.queryItems?.first { $0.name == "template" }
        XCTAssertEqual(templateItem?.value, "swift")
    }

    /// Paths with spaces and special characters are properly encoded and round-trip correctly.
    func testAppCommandURLHandlesSpecialCharacters() {
        let specialPaths = [
            "/Users/j/My Documents/file.txt",
            "/Users/j/工作区/Projects",
            "/Users/j/path (copy)/test",
            "/Volumes/Backup Drive/2024 Archive",
            "/Users/j/a&b=c?d#e/file",
        ]

        for path in specialPaths {
            let url = AppCommandURL.url(command: .openTerminal, path: path)
            XCTAssertNotNil(url, "URL must not be nil for special path: \(path)")

            guard let url = url,
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                continue
            }

            let pathItem = components.queryItems?.first { $0.name == "path" }
            XCTAssertEqual(
                pathItem?.value, path,
                "Path must round-trip correctly through URL encoding: \(path)"
            )
        }
    }

    // MARK: - Property 4: PendingFileCreationStore Round-Trip

    override func setUp() {
        super.setUp()
        UserDefaults.shared.removeObject(forKey: Constants.pendingFileCreationRequestsKey)
    }

    override func tearDown() {
        UserDefaults.shared.removeObject(forKey: Constants.pendingFileCreationRequestsKey)
        super.tearDown()
    }

    /// Save a request, load by ID, verify equality.
    func testPendingFileCreationStoreRoundTrip() {
        let store = PendingFileCreationStore(defaults: .shared)

        for template in testTemplates {
            for dirPath in testDirectoryPaths {
                let request = PendingFileCreationRequest(
                    directoryPath: dirPath,
                    template: template
                )

                store.save(request)
                let loaded = store.load(id: request.id)

                XCTAssertEqual(
                    loaded, request,
                    "Round-trip failed for template=\(template.ext), dir=\(dirPath)"
                )

                // Clean up
                store.remove(id: request.id)
            }
        }
    }

    /// Remove a request, verify it's gone.
    func testPendingFileCreationStoreRemove() {
        let store = PendingFileCreationStore(defaults: .shared)

        let request = PendingFileCreationRequest(
            directoryPath: "/Users/j/Desktop",
            template: FileTemplate(name: "Test", ext: "txt", content: "")
        )

        store.save(request)
        XCTAssertNotNil(store.load(id: request.id))

        store.remove(id: request.id)
        XCTAssertNil(
            store.load(id: request.id),
            "After removal, load should return nil"
        )
    }

    /// Multiple requests can coexist.
    func testPendingFileCreationStoreMultipleRequests() {
        let store = PendingFileCreationStore(defaults: .shared)

        let requests = testTemplates.prefix(4).enumerated().map { index, template in
            PendingFileCreationRequest(
                directoryPath: testDirectoryPaths[index],
                template: template
            )
        }

        // Save all
        for request in requests {
            store.save(request)
        }

        // Verify all can be loaded
        for request in requests {
            let loaded = store.load(id: request.id)
            XCTAssertEqual(
                loaded, request,
                "Request with id=\(request.id) should be loadable when multiple requests exist"
            )
        }

        // Remove one and verify others still exist
        store.remove(id: requests[1].id)
        XCTAssertNil(store.load(id: requests[1].id))
        XCTAssertNotNil(store.load(id: requests[0].id))
        XCTAssertNotNil(store.load(id: requests[2].id))
        XCTAssertNotNil(store.load(id: requests[3].id))

        // Clean up
        for request in requests {
            store.remove(id: request.id)
        }
    }

    /// Test with various directory paths including those with special characters.
    func testPendingFileCreationStoreSpecialPaths() {
        let store = PendingFileCreationStore(defaults: .shared)
        let template = FileTemplate(name: "Test", ext: "txt", content: "hello")

        let specialDirPaths = [
            "/Users/j/工作区/Projects",
            "/Users/bob smith/My Projects",
            "/Volumes/Backup Drive/Archives",
            "/Users/j/path (copy)",
            "/tmp/a&b",
        ]

        for dirPath in specialDirPaths {
            let request = PendingFileCreationRequest(
                directoryPath: dirPath,
                template: template
            )

            store.save(request)
            let loaded = store.load(id: request.id)

            XCTAssertEqual(
                loaded, request,
                "Round-trip failed for special path: \(dirPath)"
            )

            store.remove(id: request.id)
        }
    }
}
