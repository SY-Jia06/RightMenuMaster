import XCTest
@testable import RightMenuMaster

final class ActionRequestV2Tests: XCTestCase {
    func testStructuredRequestJSONUsesPhysicalPathsAndISO8601Timestamp() throws {
        let id = UUID(uuidString: "AF96C7A7-D74F-4E1D-8A1E-3359B2E1A100")!
        let date = Date(timeIntervalSince1970: 1_700_000_000.125)
        let request = try ActionRequest(
            id: id,
            action: .copyPath,
            invocationKind: .items,
            subjects: ["/Users/example/a.txt", "/Users/example/b.txt"],
            createdAt: date
        )

        let data = try JSONEncoder().encode(request)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
        XCTAssertEqual(object["action"] as? String, "copyPath")
        XCTAssertEqual(object["invocationKind"] as? String, "items")
        XCTAssertEqual(
            object["subjects"] as? [String],
            ["/Users/example/a.txt", "/Users/example/b.txt"]
        )
        XCTAssertFalse((object["subjects"] as? [String])?.first?.hasPrefix("file:") ?? true)
        XCTAssertNotNil(object["createdAt"] as? String)
        XCTAssertEqual(try JSONDecoder().decode(ActionRequest.self, from: data), request)
    }

    func testRequestConvertsToInvocationContextWithoutResolvingPaths() throws {
        let request = try ActionRequest(
            action: .newFile,
            context: InvocationContext(
                selectedURLs: [URL(fileURLWithPath: "/tmp/link/../lexical/file.txt")]
            )
        )

        let context = try request.invocationContext()
        XCTAssertEqual(context.kind, .items)
        XCTAssertEqual(context.subjects.map(\.path), request.subjects)
    }

    func testRequestRejectsInvalidSubjectShapesAndPaths() {
        XCTAssertThrowsError(
            try ActionRequest(
                action: .newFile,
                invocationKind: .container,
                subjects: ["/tmp/one", "/tmp/two"]
            )
        ) { error in
            XCTAssertEqual(
                error as? ActionRequestValidationError,
                .invalidContainerSubjectCount(2)
            )
        }

        XCTAssertThrowsError(
            try ActionRequest(
                action: .copyPath,
                invocationKind: .items,
                subjects: []
            )
        ) { error in
            XCTAssertEqual(error as? ActionRequestValidationError, .emptyItemSelection)
        }

        XCTAssertThrowsError(
            try ActionRequest(
                action: .copyPath,
                invocationKind: .items,
                subjects: ["relative/file.txt"]
            )
        ) { error in
            XCTAssertEqual(
                error as? ActionRequestValidationError,
                .invalidPhysicalPath("relative/file.txt")
            )
        }
    }

    func testRequestDecoderRejectsUnknownVersion() throws {
        let request = try ActionRequest(
            action: .openTerminal,
            invocationKind: .container,
            subjects: ["/tmp"]
        )
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
        )
        object["schemaVersion"] = 2
        let data = try JSONSerialization.data(withJSONObject: object)

        XCTAssertThrowsError(try JSONDecoder().decode(ActionRequest.self, from: data)) {
            XCTAssertEqual(
                $0 as? ActionRequestValidationError,
                .unsupportedSchemaVersion(2)
            )
        }
    }

    func testStoreSaveLoadRemoveAndPrivatePermissions() throws {
        let root = try makeTemporaryDirectory()
        let store = ActionRequestStore(rootDirectory: root)
        let request = try ActionRequest(
            action: .openEditor,
            invocationKind: .items,
            subjects: ["/Users/example/notes.md"]
        )

        try store.save(request)
        XCTAssertEqual(try store.load(id: request.id), request)

        let file = requestFile(root: root, id: request.id)
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
        XCTAssertEqual(permissions.intValue & 0o777, 0o600)
        let directoryAttributes = try FileManager.default.attributesOfItem(
            atPath: file.deletingLastPathComponent().path
        )
        let directoryPermissions = try XCTUnwrap(
            directoryAttributes[.posixPermissions] as? NSNumber
        )
        XCTAssertEqual(directoryPermissions.intValue & 0o777, 0o700)

        try store.remove(id: request.id)
        XCTAssertNil(try store.load(id: request.id))
        XCTAssertNoThrow(try store.remove(id: request.id))
    }

    func testStoreDuplicateSaveNeverReplacesFirstPayload() throws {
        let root = try makeTemporaryDirectory()
        let store = ActionRequestStore(rootDirectory: root)
        let id = UUID()
        let first = try ActionRequest(
            id: id,
            action: .copyPath,
            invocationKind: .items,
            subjects: ["/tmp/first"]
        )
        let replacement = try ActionRequest(
            id: id,
            action: .openEditor,
            invocationKind: .items,
            subjects: ["/tmp/replacement"]
        )

        try store.save(first)
        XCTAssertThrowsError(try store.save(replacement)) { error in
            XCTAssertEqual(error as? ActionRequestStoreError, .duplicateIdentifier(id))
        }
        XCTAssertEqual(try store.load(id: id), first)
    }

    func testStoreRejectsSymlinkAndIdentifierMismatch() throws {
        let root = try makeTemporaryDirectory()
        let requestDirectory = root.appendingPathComponent("ActionRequests", isDirectory: true)
        try FileManager.default.createDirectory(
            at: requestDirectory,
            withIntermediateDirectories: true
        )
        let store = ActionRequestStore(rootDirectory: root)

        let symlinkID = UUID()
        let target = root.appendingPathComponent("target.json")
        try Data("{}".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(
            at: requestFile(root: root, id: symlinkID),
            withDestinationURL: target
        )
        XCTAssertThrowsError(try store.load(id: symlinkID)) {
            XCTAssertEqual($0 as? ActionRequestStoreError, .unsafeRequestFile)
        }

        let requestedID = UUID()
        let payload = try ActionRequest(
            id: UUID(),
            action: .copyPath,
            invocationKind: .items,
            subjects: ["/tmp/file"]
        )
        try JSONEncoder().encode(payload).write(to: requestFile(root: root, id: requestedID))
        XCTAssertThrowsError(try store.load(id: requestedID)) {
            XCTAssertEqual($0 as? ActionRequestStoreError, .identifierMismatch)
        }
    }

    func testStoreRejectsCorruptPayload() throws {
        let root = try makeTemporaryDirectory()
        let directory = root.appendingPathComponent("ActionRequests", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let id = UUID()
        try Data("not-json".utf8).write(to: requestFile(root: root, id: id))

        XCTAssertThrowsError(try ActionRequestStore(rootDirectory: root).load(id: id)) {
            XCTAssertEqual($0 as? ActionRequestStoreError, .corruptPayload)
        }
    }

    func testConsumeIsFreshOneShotAndRemovesStoredRequest() throws {
        let root = try makeTemporaryDirectory()
        let store = ActionRequestStore(rootDirectory: root)
        let now = Date(timeIntervalSince1970: 1_700_000_100)
        let request = try ActionRequest(
            action: .newFile,
            invocationKind: .container,
            subjects: ["/tmp"],
            createdAt: now.addingTimeInterval(-10)
        )
        try store.save(request)

        XCTAssertEqual(try store.consume(id: request.id, now: now), request)
        XCTAssertNil(try store.consume(id: request.id, now: now))
        XCTAssertNil(try store.load(id: request.id))
    }

    func testConsumeRejectsAndRemovesExpiredRequest() throws {
        let root = try makeTemporaryDirectory()
        let store = ActionRequestStore(rootDirectory: root)
        let now = Date(timeIntervalSince1970: 1_700_000_100)
        let request = try ActionRequest(
            action: .copyPath,
            invocationKind: .items,
            subjects: ["/tmp/file"],
            createdAt: now.addingTimeInterval(-31)
        )
        try store.save(request)

        XCTAssertThrowsError(try store.consume(id: request.id, now: now)) {
            XCTAssertEqual($0 as? ActionRequestStoreError, .requestExpired)
        }
        XCTAssertNil(try store.consume(id: request.id, now: now))
    }

    func testConsumeRejectsAndRemovesFutureDatedRequest() throws {
        let root = try makeTemporaryDirectory()
        let store = ActionRequestStore(rootDirectory: root)
        let now = Date(timeIntervalSince1970: 1_700_000_100)
        let request = try ActionRequest(
            action: .openEditor,
            invocationKind: .items,
            subjects: ["/tmp/file"],
            createdAt: now.addingTimeInterval(1)
        )
        try store.save(request)

        XCTAssertThrowsError(try store.consume(id: request.id, now: now)) {
            XCTAssertEqual($0 as? ActionRequestStoreError, .requestCreatedInFuture)
        }
        XCTAssertNil(try store.consume(id: request.id, now: now))
    }

    func testConsumeRemovesCorruptPayload() throws {
        let root = try makeTemporaryDirectory()
        let requestDirectory = root.appendingPathComponent("ActionRequests", isDirectory: true)
        try FileManager.default.createDirectory(
            at: requestDirectory,
            withIntermediateDirectories: true
        )
        let id = UUID()
        try Data("not-json".utf8).write(to: requestFile(root: root, id: id))
        let store = ActionRequestStore(rootDirectory: root)

        XCTAssertThrowsError(try store.consume(id: id)) {
            XCTAssertEqual($0 as? ActionRequestStoreError, .corruptPayload)
        }
        XCTAssertNil(try store.consume(id: id))
    }

    func testPendingRequestLimitRetainsNewestRequests() throws {
        let root = try makeTemporaryDirectory()
        let store = ActionRequestStore(rootDirectory: root)
        let now = Date()
        var identifiers: [UUID] = []

        for index in 0..<70 {
            let request = try ActionRequest(
                action: .copyPath,
                invocationKind: .items,
                subjects: ["/tmp/item-\(index)"],
                createdAt: now
            )
            try store.save(request)
            try FileManager.default.setAttributes(
                [.modificationDate: now.addingTimeInterval(-20 + Double(index) / 10)],
                ofItemAtPath: requestFile(root: root, id: request.id).path
            )
            identifiers.append(request.id)
        }

        let pending = try store.pendingRequestIDs(now: now)
        XCTAssertEqual(pending.count, 64)
        XCTAssertEqual(pending.first, identifiers[6])
        XCTAssertEqual(pending.last, identifiers[69])
    }

    func testConcurrentConsumeHasExactlyOneWinner() throws {
        let root = try makeTemporaryDirectory()
        let store = ActionRequestStore(rootDirectory: root)
        let now = Date(timeIntervalSince1970: 1_700_000_100)
        let request = try ActionRequest(
            action: .openTerminal,
            invocationKind: .container,
            subjects: ["/tmp"],
            createdAt: now
        )
        try store.save(request)

        let lock = NSLock()
        var consumed = [ActionRequest]()
        var emptyResults = 0
        var errors = [Error]()
        DispatchQueue.concurrentPerform(iterations: 32) { _ in
            do {
                let result = try store.consume(id: request.id, now: now)
                lock.lock()
                if let result {
                    consumed.append(result)
                } else {
                    emptyResults += 1
                }
                lock.unlock()
            } catch {
                lock.lock()
                errors.append(error)
                lock.unlock()
            }
        }

        XCTAssertEqual(consumed, [request])
        XCTAssertEqual(emptyResults, 31)
        XCTAssertTrue(errors.isEmpty, "Unexpected consume errors: \(errors)")
        XCTAssertNil(try store.load(id: request.id))
    }

    func testConsumeRejectsInvalidTTLWithoutClaimingRequest() throws {
        let root = try makeTemporaryDirectory()
        let store = ActionRequestStore(rootDirectory: root)
        let request = try ActionRequest(
            action: .copyPath,
            invocationKind: .items,
            subjects: ["/tmp/file"]
        )
        try store.save(request)

        XCTAssertThrowsError(try store.consume(id: request.id, maxAge: 0)) {
            XCTAssertEqual($0 as? ActionRequestStoreError, .invalidMaximumAge)
        }
        XCTAssertEqual(try store.load(id: request.id), request)
    }

    func testPurgeRemovesOnlyExpiredRegularJSONRequests() throws {
        let root = try makeTemporaryDirectory()
        let store = ActionRequestStore(rootDirectory: root)
        let expired = try ActionRequest(
            action: .newFile,
            invocationKind: .container,
            subjects: ["/tmp"]
        )
        let fresh = try ActionRequest(
            action: .openTerminal,
            invocationKind: .container,
            subjects: ["/tmp"]
        )
        try store.save(expired)
        try store.save(fresh)

        let now = Date()
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-31)],
            ofItemAtPath: requestFile(root: root, id: expired.id).path
        )
        let requestDirectory = root.appendingPathComponent("ActionRequests", isDirectory: true)
        let symlink = requestDirectory.appendingPathComponent("untrusted.json")
        let target = root.appendingPathComponent("target")
        try Data("keep".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: target)

        try store.purgeExpiredRequests(now: now)

        XCTAssertNil(try store.load(id: expired.id))
        XCTAssertEqual(try store.load(id: fresh.id), fresh)
        XCTAssertEqual(try store.pendingRequestIDs(now: now), [fresh.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: symlink.path))
        XCTAssertEqual(try Data(contentsOf: target), Data("keep".utf8))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RightMenuMasterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func requestFile(root: URL, id: UUID) -> URL {
        root.appendingPathComponent("ActionRequests", isDirectory: true)
            .appendingPathComponent(id.uuidString.lowercased() + ".json")
    }
}
