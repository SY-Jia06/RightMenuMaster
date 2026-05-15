import XCTest
@testable import RightMenuMaster

/// Preservation property tests that capture the CURRENT correct behavior of pure logic functions.
/// These tests PASS on unfixed code and MUST continue to PASS after the fix.
///
/// **Validates: Requirements 3.1, 3.6, 3.7**
///
/// Properties tested:
/// 1. FinderMonitorDirectories.urls() always includes required structural directories
/// 2. AuthorizedFolderStore.authorizedFolder(containing:in:) path matching uses longest prefix
///    with proper path boundary semantics
final class PreservationPropertyTests: XCTestCase {

    // MARK: - Test Data Generators

    /// Various home paths to test with (property-based style)
    private let homePaths: [URL] = [
        URL(fileURLWithPath: "/Users/tester", isDirectory: true),
        URL(fileURLWithPath: "/Users/alice", isDirectory: true),
        URL(fileURLWithPath: "/Users/bob-smith", isDirectory: true),
        URL(fileURLWithPath: "/Users/用户", isDirectory: true),
        URL(fileURLWithPath: "/Users/a", isDirectory: true),
        URL(fileURLWithPath: "/Users/developer.test", isDirectory: true),
    ]

    /// Various authorized folder grant sets to test with
    private func makeGrant(path: String) -> AuthorizedFolderGrant {
        AuthorizedFolderGrant(path: path, bookmarkData: Data("bookmark-\(path)".utf8))
    }

    private var authorizedFolderSets: [[AuthorizedFolderGrant]] {
        [
            // Empty
            [],
            // Single folder
            [makeGrant(path: "/Users/tester/Projects")],
            // Multiple folders
            [
                makeGrant(path: "/Users/tester/Projects"),
                makeGrant(path: "/Users/tester/Workspace"),
                makeGrant(path: "/Volumes/External/Data"),
            ],
            // Nested folders
            [
                makeGrant(path: "/Users/alice/Code"),
                makeGrant(path: "/Users/alice/Code/OpenSource"),
                makeGrant(path: "/Users/alice/Code/OpenSource/MyProject"),
            ],
            // Folders with special characters
            [
                makeGrant(path: "/Users/bob-smith/My Projects"),
                makeGrant(path: "/Volumes/Backup Drive/Archives"),
            ],
        ]
    }

    // MARK: - Property 1: FinderMonitorDirectories.urls() Structure

    /// For any valid home URL and any array of AuthorizedFolderGrant,
    /// the returned set ALWAYS includes the required structural directories.
    func testURLsAlwaysIncludesRootUsersAndVolumes() {
        for home in homePaths {
            for grants in authorizedFolderSets {
                let urls = FinderMonitorDirectories.urls(home: home, authorizedFolders: grants)
                let paths = urls.map(\.path)

                XCTAssertTrue(
                    paths.contains("/"),
                    "urls() must always include root '/' — home=\(home.path), grants=\(grants.count)"
                )
                XCTAssertTrue(
                    paths.contains("/Users"),
                    "urls() must always include '/Users' — home=\(home.path), grants=\(grants.count)"
                )
                XCTAssertTrue(
                    paths.contains("/Volumes"),
                    "urls() must always include '/Volumes' — home=\(home.path), grants=\(grants.count)"
                )
            }
        }
    }

    /// For any valid home URL, the returned set ALWAYS includes the home directory itself
    /// and its Desktop, Documents, Downloads subdirectories.
    func testURLsAlwaysIncludesHomeAndStandardSubdirectories() {
        for home in homePaths {
            for grants in authorizedFolderSets {
                let urls = FinderMonitorDirectories.urls(home: home, authorizedFolders: grants)
                let paths = urls.map(\.path)

                XCTAssertTrue(
                    paths.contains(home.path),
                    "urls() must include home '\(home.path)' — grants=\(grants.count)"
                )

                let expectedDesktop = home.appendingPathComponent("Desktop", isDirectory: true).path
                XCTAssertTrue(
                    paths.contains(expectedDesktop),
                    "urls() must include Desktop '\(expectedDesktop)' — grants=\(grants.count)"
                )

                let expectedDocuments = home.appendingPathComponent("Documents", isDirectory: true).path
                XCTAssertTrue(
                    paths.contains(expectedDocuments),
                    "urls() must include Documents '\(expectedDocuments)' — grants=\(grants.count)"
                )

                let expectedDownloads = home.appendingPathComponent("Downloads", isDirectory: true).path
                XCTAssertTrue(
                    paths.contains(expectedDownloads),
                    "urls() must include Downloads '\(expectedDownloads)' — grants=\(grants.count)"
                )
            }
        }
    }

    /// For any authorized folder grants, all grant paths appear in the returned URL set.
    func testURLsAlwaysIncludesAllAuthorizedFolderPaths() {
        for home in homePaths {
            for grants in authorizedFolderSets {
                let urls = FinderMonitorDirectories.urls(home: home, authorizedFolders: grants)
                let paths = urls.map(\.path)

                for grant in grants {
                    let grantURL = URL(fileURLWithPath: grant.path, isDirectory: true)
                    XCTAssertTrue(
                        paths.contains(grantURL.path),
                        "urls() must include authorized folder '\(grant.path)' — home=\(home.path)"
                    )
                }
            }
        }
    }

    /// The minimum size of the returned set is 7 (root, /Users, /Volumes, home, Desktop,
    /// Documents, Downloads) plus the number of unique authorized folder paths.
    func testURLsMinimumSetSize() {
        for home in homePaths {
            for grants in authorizedFolderSets {
                let urls = FinderMonitorDirectories.urls(home: home, authorizedFolders: grants)

                // At minimum: /, /Users, /Volumes, home, Desktop, Documents, Downloads = 7
                XCTAssertGreaterThanOrEqual(
                    urls.count, 7,
                    "urls() must return at least 7 URLs — home=\(home.path), grants=\(grants.count)"
                )
            }
        }
    }

    // MARK: - Property 2: AuthorizedFolderStore.authorizedFolder(containing:in:) Path Matching

    /// For a URL inside an authorized folder, returns the grant with the longest matching path prefix.
    func testPathMatchingReturnsLongestPrefixMatch() {
        let folders = [
            makeGrant(path: "/Users/j"),
            makeGrant(path: "/Users/j/Projects"),
            makeGrant(path: "/Users/j/Projects/MyApp"),
        ]

        // File deep inside the most specific folder
        let result = AuthorizedFolderStore.authorizedFolder(
            containing: URL(fileURLWithPath: "/Users/j/Projects/MyApp/Sources/main.swift"),
            in: folders
        )
        XCTAssertEqual(result?.path, "/Users/j/Projects/MyApp")

        // File inside Projects but not MyApp
        let result2 = AuthorizedFolderStore.authorizedFolder(
            containing: URL(fileURLWithPath: "/Users/j/Projects/OtherApp/file.txt"),
            in: folders
        )
        XCTAssertEqual(result2?.path, "/Users/j/Projects")

        // File inside home but not Projects
        let result3 = AuthorizedFolderStore.authorizedFolder(
            containing: URL(fileURLWithPath: "/Users/j/Documents/note.txt"),
            in: folders
        )
        XCTAssertEqual(result3?.path, "/Users/j")
    }

    /// For a URL NOT inside any authorized folder, returns nil.
    func testPathMatchingReturnsNilForUnmatchedPaths() {
        let folders = [
            makeGrant(path: "/Users/j/Downloads"),
            makeGrant(path: "/Users/j/Projects"),
        ]

        // Completely unrelated path
        XCTAssertNil(
            AuthorizedFolderStore.authorizedFolder(
                containing: URL(fileURLWithPath: "/tmp/scratch/file.txt"),
                in: folders
            )
        )

        // Different user
        XCTAssertNil(
            AuthorizedFolderStore.authorizedFolder(
                containing: URL(fileURLWithPath: "/Users/other/Downloads/file.txt"),
                in: folders
            )
        )

        // Empty folders array
        XCTAssertNil(
            AuthorizedFolderStore.authorizedFolder(
                containing: URL(fileURLWithPath: "/Users/j/Downloads/file.txt"),
                in: []
            )
        )
    }

    /// Path boundary: `/Users/j/Downloads-old/file.txt` does NOT match `/Users/j/Downloads`.
    /// The matching must respect path component boundaries (trailing slash).
    func testPathMatchingRespectsPathBoundaries() {
        let folders = [
            makeGrant(path: "/Users/j/Downloads"),
        ]

        // "Downloads-old" should NOT match "Downloads" — path boundary check
        XCTAssertNil(
            AuthorizedFolderStore.authorizedFolder(
                containing: URL(fileURLWithPath: "/Users/j/Downloads-old/file.txt"),
                in: folders
            )
        )

        // "Downloads2" should NOT match "Downloads"
        XCTAssertNil(
            AuthorizedFolderStore.authorizedFolder(
                containing: URL(fileURLWithPath: "/Users/j/Downloads2/file.txt"),
                in: folders
            )
        )

        // "DownloadsExtra" should NOT match "Downloads"
        XCTAssertNil(
            AuthorizedFolderStore.authorizedFolder(
                containing: URL(fileURLWithPath: "/Users/j/DownloadsExtra/file.txt"),
                in: folders
            )
        )
    }

    /// Exact match: `/Users/j/Downloads` matches `/Users/j/Downloads`.
    func testPathMatchingHandlesExactMatch() {
        let folders = [
            makeGrant(path: "/Users/j/Downloads"),
        ]

        let result = AuthorizedFolderStore.authorizedFolder(
            containing: URL(fileURLWithPath: "/Users/j/Downloads"),
            in: folders
        )
        XCTAssertEqual(result?.path, "/Users/j/Downloads")
    }

    /// Nested match: `/Users/j/Projects/sub/file.txt` matches `/Users/j/Projects` (not `/Users/j`).
    func testPathMatchingPicksMostSpecificNestedMatch() {
        let folders = [
            makeGrant(path: "/Users/j"),
            makeGrant(path: "/Users/j/Projects"),
        ]

        let result = AuthorizedFolderStore.authorizedFolder(
            containing: URL(fileURLWithPath: "/Users/j/Projects/sub/file.txt"),
            in: folders
        )
        XCTAssertEqual(
            result?.path, "/Users/j/Projects",
            "Should match the most specific (longest path) grant, not the broader one"
        )
    }

    /// Multiple grants: picks the most specific (longest path) match regardless of array order.
    func testPathMatchingIsOrderIndependent() {
        // Grants in reverse specificity order
        let foldersReversed = [
            makeGrant(path: "/Users/j/Projects/MyApp/Sources"),
            makeGrant(path: "/Users/j"),
            makeGrant(path: "/Users/j/Projects"),
            makeGrant(path: "/Users/j/Projects/MyApp"),
        ]

        let result = AuthorizedFolderStore.authorizedFolder(
            containing: URL(fileURLWithPath: "/Users/j/Projects/MyApp/Sources/main.swift"),
            in: foldersReversed
        )
        XCTAssertEqual(
            result?.path, "/Users/j/Projects/MyApp/Sources",
            "Should pick longest matching path regardless of array order"
        )
    }

    // MARK: - Property 3: Combined Property-Based Style Tests

    /// Generate several different home paths and authorized folder arrays,
    /// verify all invariants hold for all combinations.
    func testPropertyBasedCombinations() {
        let homes: [URL] = [
            URL(fileURLWithPath: "/Users/test1", isDirectory: true),
            URL(fileURLWithPath: "/Users/test2", isDirectory: true),
            URL(fileURLWithPath: "/Users/longusername", isDirectory: true),
        ]

        let grantSets: [[AuthorizedFolderGrant]] = [
            [],
            [makeGrant(path: "/Users/test1/Work")],
            [
                makeGrant(path: "/Users/test2/A"),
                makeGrant(path: "/Users/test2/B"),
                makeGrant(path: "/Users/test2/C"),
            ],
        ]

        for home in homes {
            for grants in grantSets {
                let urls = FinderMonitorDirectories.urls(home: home, authorizedFolders: grants)
                let paths = Set(urls.map(\.path))

                // Invariant 1: Always contains structural directories
                XCTAssertTrue(paths.contains("/"))
                XCTAssertTrue(paths.contains("/Users"))
                XCTAssertTrue(paths.contains("/Volumes"))

                // Invariant 2: Always contains home-relative directories
                XCTAssertTrue(paths.contains(home.path))
                XCTAssertTrue(paths.contains(home.appendingPathComponent("Desktop").path))
                XCTAssertTrue(paths.contains(home.appendingPathComponent("Documents").path))
                XCTAssertTrue(paths.contains(home.appendingPathComponent("Downloads").path))

                // Invariant 3: All grant paths are included
                for grant in grants {
                    let grantURL = URL(fileURLWithPath: grant.path, isDirectory: true)
                    XCTAssertTrue(
                        paths.contains(grantURL.path),
                        "Grant path '\(grant.path)' missing from urls() result"
                    )
                }

                // Invariant 4: No duplicate URLs (Set guarantees this, but verify count)
                XCTAssertEqual(urls.count, paths.count, "URL set should have no duplicates")
            }
        }
    }

    /// Property: path matching with generated inputs always respects path boundaries.
    func testPropertyPathBoundaryWithGeneratedInputs() {
        // Generate folder paths and test that similar-but-different paths don't match
        let basePaths = ["/Users/j/Downloads", "/Users/j/Projects", "/Users/j/Documents"]
        let suffixes = ["-old", "2", "Extra", "-backup", "_copy"]

        for basePath in basePaths {
            let folders = [makeGrant(path: basePath)]

            for suffix in suffixes {
                let nonMatchingPath = "\(basePath)\(suffix)/file.txt"
                XCTAssertNil(
                    AuthorizedFolderStore.authorizedFolder(
                        containing: URL(fileURLWithPath: nonMatchingPath),
                        in: folders
                    ),
                    "'\(nonMatchingPath)' should NOT match '\(basePath)' — path boundary violation"
                )
            }

            // But actual children SHOULD match
            let matchingPath = "\(basePath)/subdir/file.txt"
            let result = AuthorizedFolderStore.authorizedFolder(
                containing: URL(fileURLWithPath: matchingPath),
                in: folders
            )
            XCTAssertEqual(
                result?.path, basePath,
                "'\(matchingPath)' SHOULD match '\(basePath)'"
            )
        }
    }

    /// Property: for any file URL inside an authorized folder, the matched grant's path
    /// is always a prefix of the file URL's path (with proper boundary).
    func testPropertyMatchedGrantIsAlwaysPrefix() {
        let folders = [
            makeGrant(path: "/Users/j"),
            makeGrant(path: "/Users/j/Projects"),
            makeGrant(path: "/Users/j/Projects/App"),
            makeGrant(path: "/Volumes/External"),
        ]

        let testURLs = [
            "/Users/j/file.txt",
            "/Users/j/Projects/readme.md",
            "/Users/j/Projects/App/main.swift",
            "/Users/j/Projects/App/Tests/test.swift",
            "/Volumes/External/data.bin",
            "/Volumes/External/sub/deep/file.txt",
        ]

        for urlPath in testURLs {
            let url = URL(fileURLWithPath: urlPath)
            let result = AuthorizedFolderStore.authorizedFolder(containing: url, in: folders)

            if let matched = result {
                // The matched grant's path must be a proper prefix of the URL path
                let folderPrefix = matched.path.hasSuffix("/") ? matched.path : "\(matched.path)/"
                XCTAssertTrue(
                    urlPath == matched.path || urlPath.hasPrefix(folderPrefix),
                    "Matched grant '\(matched.path)' must be a path prefix of '\(urlPath)'"
                )
            }
        }
    }
}
