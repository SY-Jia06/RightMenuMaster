import XCTest
@testable import RightMenuMaster

final class ContextResolverV2Tests: XCTestCase {
    private let root = URL(fileURLWithPath: "/Users/example/Projects/demo", isDirectory: true)

    func testContainerSemantics() throws {
        let resolver = resolver(directories: [root])
        let context = InvocationContext(containerURL: root)

        XCTAssertEqual(try resolver.classify(context), .container(directory: root))
        XCTAssertEqual(
            try resolver.resolve(.newFile, in: context).target,
            .directory(root)
        )
        XCTAssertEqual(
            try resolver.resolve(.copyPath, in: context).target,
            .subjects([root])
        )
        XCTAssertEqual(
            try resolver.resolve(.openTerminal, in: context).target,
            .directory(root)
        )
        XCTAssertEqual(
            try resolver.resolve(.openEditor, in: context).target,
            .subjects([root])
        )
    }

    func testSingleFileSemantics() throws {
        let file = root.appendingPathComponent("notes.md", isDirectory: false)
        let resolver = resolver(directories: [])
        let context = InvocationContext(selectedURLs: [file])

        XCTAssertEqual(
            try resolver.classify(context),
            .singleFile(file: file, parent: root)
        )
        XCTAssertEqual(try resolver.resolve(.newFile, in: context).target, .directory(root))
        XCTAssertEqual(try resolver.resolve(.copyPath, in: context).target, .subjects([file]))
        XCTAssertEqual(try resolver.resolve(.openTerminal, in: context).target, .directory(root))
        XCTAssertEqual(try resolver.resolve(.openEditor, in: context).target, .subjects([file]))
    }

    func testSingleFolderSemantics() throws {
        let folder = root.appendingPathComponent("Sources", isDirectory: true)
        let resolver = resolver(directories: [folder])
        let context = InvocationContext(selectedURLs: [folder])

        XCTAssertEqual(try resolver.classify(context), .singleFolder(directory: folder))
        XCTAssertEqual(try resolver.resolve(.newFile, in: context).target, .directory(folder))
        XCTAssertEqual(try resolver.resolve(.copyPath, in: context).target, .subjects([folder]))
        XCTAssertEqual(try resolver.resolve(.openTerminal, in: context).target, .directory(folder))
        XCTAssertEqual(try resolver.resolve(.openEditor, in: context).target, .subjects([folder]))
    }

    func testSameParentSelectionSemantics() throws {
        let first = root.appendingPathComponent("one.txt")
        let second = root.appendingPathComponent("two.txt")
        let subjects = [first, second]
        let resolver = resolver(directories: [])
        let context = InvocationContext(selectedURLs: subjects)

        XCTAssertEqual(
            try resolver.classify(context),
            .sameParentSelection(parent: root, subjects: subjects)
        )
        XCTAssertEqual(try resolver.resolve(.newFile, in: context).target, .directory(root))
        XCTAssertEqual(try resolver.resolve(.copyPath, in: context).target, .subjects(subjects))
        XCTAssertEqual(try resolver.resolve(.openTerminal, in: context).target, .directory(root))

        let unsupported = try resolver.resolve(.openEditor, in: context)
        XCTAssertFalse(unsupported.isEnabled)
        XCTAssertEqual(unsupported.disabledReason, .editorDoesNotSupportMultipleItems)

        XCTAssertEqual(
            try resolver.resolve(
                .openEditor,
                in: context,
                editorCapabilities: .sameParentItems
            ).target,
            .subjects(subjects)
        )
    }

    func testMixedParentSelectionSemantics() throws {
        let first = root.appendingPathComponent("one.txt")
        let otherParent = URL(fileURLWithPath: "/Users/example/Downloads", isDirectory: true)
        let second = otherParent.appendingPathComponent("two.txt")
        let subjects = [first, second]
        let resolver = resolver(directories: [])
        let context = InvocationContext(selectedURLs: subjects)

        XCTAssertEqual(try resolver.classify(context), .mixedParentSelection(subjects: subjects))
        XCTAssertEqual(try resolver.resolve(.copyPath, in: context).target, .subjects(subjects))

        for action in [ProductAction.newFile, .openTerminal] {
            let resolution = try resolver.resolve(action, in: context)
            XCTAssertFalse(resolution.isEnabled)
            XCTAssertEqual(resolution.disabledReason, .mixedParentSelection)
        }

        XCTAssertEqual(
            try resolver.resolve(
                .openEditor,
                in: context,
                editorCapabilities: .sameParentItems
            ).disabledReason,
            .editorDoesNotSupportMixedParentItems
        )
        XCTAssertEqual(
            try resolver.resolve(
                .openEditor,
                in: context,
                editorCapabilities: .mixedParentItems
            ).target,
            .subjects(subjects)
        )
    }

    func testInvalidAndVirtualContextsAreRejected() {
        let resolver = resolver(directories: [])

        XCTAssertThrowsError(try resolver.classify(InvocationContext(selectedURLs: []))) {
            XCTAssertEqual($0 as? ContextResolutionError, .emptyItemSelection)
        }
        XCTAssertThrowsError(
            try resolver.classify(InvocationContext(kind: .container, subjects: [root, root]))
        ) { error in
            XCTAssertEqual(error as? ContextResolutionError, .invalidContainerSubjectCount(2))
        }

        let virtual = URL(string: "search://smart-folder")!
        XCTAssertThrowsError(
            try resolver.classify(InvocationContext(selectedURLs: [virtual]))
        ) { error in
            XCTAssertEqual(error as? ContextResolutionError, .nonPhysicalSubject(virtual))
        }
    }

    func testContainerMustProbeAsDirectory() {
        let resolver = resolver(directories: [])
        XCTAssertThrowsError(try resolver.classify(InvocationContext(containerURL: root))) {
            XCTAssertEqual($0 as? ContextResolutionError, .containerIsNotDirectory(root))
        }
    }

    private func resolver(directories: Set<URL>) -> ContextResolver {
        ContextResolver { directories.contains($0) }
    }
}
