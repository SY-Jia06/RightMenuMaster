import Foundation

final class ActionRequestStore {
    static let maximumPayloadSize = 256 * 1_024
    static let defaultMaximumAge: TimeInterval = 30

    private let rootDirectory: URL
    private let requestDirectory: URL
    private let fileManager: FileManager

    init(rootDirectory: URL, fileManager: FileManager = .default) {
        self.rootDirectory = rootDirectory
        self.requestDirectory = rootDirectory.appendingPathComponent(
            "ActionRequests",
            isDirectory: true
        )
        self.fileManager = fileManager
    }

    static func appGroup(
        identifier: String = Constants.appGroupID,
        fileManager: FileManager = .default
    ) throws -> ActionRequestStore {
        guard let container = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: identifier
        ) else {
            throw ActionRequestStoreError.appGroupUnavailable
        }
        return ActionRequestStore(rootDirectory: container, fileManager: fileManager)
    }

    func save(_ request: ActionRequest) throws {
        try request.validate()
        try prepareRequestDirectory()
        try purgeExpiredRequests()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let payload = try encoder.encode(request)
        guard payload.count <= Self.maximumPayloadSize else {
            throw ActionRequestStoreError.payloadTooLarge
        }

        let destination = fileURL(for: request.id)
        do {
            try payload.write(to: destination, options: .withoutOverwriting)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain
            && error.code == NSFileWriteFileExistsError {
            throw ActionRequestStoreError.duplicateIdentifier(request.id)
        } catch {
            throw ActionRequestStoreError.writeFailed
        }

        do {
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: destination.path
            )
        } catch {
            // Do not leave a request containing user paths with unintended permissions.
            try? fileManager.removeItem(at: destination)
            throw ActionRequestStoreError.permissionHardeningFailed
        }
    }

    func load(id: UUID) throws -> ActionRequest? {
        try decodeRequest(at: fileURL(for: id), expectedID: id)
    }

    func consume(
        id: UUID,
        now: Date = Date(),
        maxAge: TimeInterval = ActionRequestStore.defaultMaximumAge
    ) throws -> ActionRequest? {
        guard maxAge.isFinite, maxAge > 0 else {
            throw ActionRequestStoreError.invalidMaximumAge
        }
        try prepareRequestDirectory()

        let source = fileURL(for: id)
        let claim = requestDirectory.appendingPathComponent(
            id.uuidString.lowercased() + ".consuming-" + UUID().uuidString.lowercased(),
            isDirectory: false
        )
        do {
            // Same-directory rename is atomic. Exactly one concurrent consumer can claim source.
            try fileManager.moveItem(at: source, to: claim)
        } catch let error as NSError where isNoSuchFile(error) {
            return nil
        } catch {
            throw ActionRequestStoreError.claimFailed
        }
        defer { try? fileManager.removeItem(at: claim) }

        guard let request = try decodeRequest(at: claim, expectedID: id) else {
            return nil
        }
        let age = now.timeIntervalSince(request.createdAt)
        guard age >= 0 else {
            throw ActionRequestStoreError.requestCreatedInFuture
        }
        guard age <= maxAge else {
            throw ActionRequestStoreError.requestExpired
        }
        return request
    }

    private func decodeRequest(at source: URL, expectedID id: UUID) throws -> ActionRequest? {

        let values: URLResourceValues
        do {
            values = try source.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .fileSizeKey,
            ])
        } catch {
            if isNoSuchFile(error as NSError) {
                return nil
            }
            throw ActionRequestStoreError.readFailed
        }

        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw ActionRequestStoreError.unsafeRequestFile
        }
        guard (values.fileSize ?? Self.maximumPayloadSize + 1) <= Self.maximumPayloadSize else {
            throw ActionRequestStoreError.payloadTooLarge
        }

        let payload: Data
        do {
            payload = try Data(contentsOf: source, options: .uncached)
        } catch {
            if isNoSuchFile(error as NSError) {
                return nil
            }
            throw ActionRequestStoreError.readFailed
        }
        guard payload.count <= Self.maximumPayloadSize else {
            throw ActionRequestStoreError.payloadTooLarge
        }

        let request: ActionRequest
        do {
            request = try JSONDecoder().decode(ActionRequest.self, from: payload)
        } catch {
            throw ActionRequestStoreError.corruptPayload
        }
        guard request.id == id else {
            throw ActionRequestStoreError.identifierMismatch
        }
        return request
    }

    func remove(id: UUID) throws {
        let source = fileURL(for: id)
        do {
            try fileManager.removeItem(at: source)
        } catch let error as NSError where isNoSuchFile(error) {
            return
        } catch {
            throw ActionRequestStoreError.removeFailed
        }
    }

    /// Removes only expired, regular JSON request files from the private store.
    /// Unknown files and symlinks are never followed or deleted.
    func purgeExpiredRequests(
        now: Date = Date(),
        maxAge: TimeInterval = ActionRequestStore.defaultMaximumAge
    ) throws {
        guard maxAge.isFinite, maxAge > 0 else {
            throw ActionRequestStoreError.invalidMaximumAge
        }
        try prepareRequestDirectory()

        let candidates: [URL]
        do {
            candidates = try fileManager.contentsOfDirectory(
                at: requestDirectory,
                includingPropertiesForKeys: [
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                    .contentModificationDateKey,
                ],
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw ActionRequestStoreError.readFailed
        }

        for candidate in candidates where candidate.pathExtension == "json" {
            let values: URLResourceValues
            do {
                values = try candidate.resourceValues(forKeys: [
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                    .contentModificationDateKey,
                ])
            } catch {
                continue
            }
            guard values.isRegularFile == true,
                  values.isSymbolicLink != true,
                  let modifiedAt = values.contentModificationDate,
                  now.timeIntervalSince(modifiedAt) > maxAge else {
                continue
            }
            do {
                try fileManager.removeItem(at: candidate)
            } catch {
                throw ActionRequestStoreError.removeFailed
            }
        }
    }

    /// Returns fresh, regular request-file identifiers in creation order.
    /// This lets a cold-launched host recover a user command even when Launch
    /// Services activates the app without forwarding its custom URL event.
    func pendingRequestIDs(
        now: Date = Date(),
        maxAge: TimeInterval = ActionRequestStore.defaultMaximumAge
    ) throws -> [UUID] {
        try purgeExpiredRequests(now: now, maxAge: maxAge)

        let candidates: [URL]
        do {
            candidates = try fileManager.contentsOfDirectory(
                at: requestDirectory,
                includingPropertiesForKeys: [
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                    .contentModificationDateKey,
                ],
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw ActionRequestStoreError.readFailed
        }

        return candidates.compactMap { candidate -> (UUID, Date)? in
            guard candidate.pathExtension == "json",
                  let id = UUID(uuidString: candidate.deletingPathExtension().lastPathComponent),
                  let values = try? candidate.resourceValues(forKeys: [
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                    .contentModificationDateKey,
                  ]),
                  values.isRegularFile == true,
                  values.isSymbolicLink != true else {
                return nil
            }
            return (id, values.contentModificationDate ?? .distantPast)
        }
        .sorted { lhs, rhs in
            if lhs.1 == rhs.1 { return lhs.0.uuidString < rhs.0.uuidString }
            return lhs.1 < rhs.1
        }
        .suffix(64)
        .map { $0.0 }
    }

    private func prepareRequestDirectory() throws {
        guard rootDirectory.isFileURL,
              (rootDirectory.path as NSString).isAbsolutePath else {
            throw ActionRequestStoreError.invalidRootDirectory
        }

        do {
            try fileManager.createDirectory(
                at: requestDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let values = try requestDirectory.resourceValues(forKeys: [
                .isDirectoryKey,
                .isSymbolicLinkKey,
            ])
            guard values.isDirectory == true, values.isSymbolicLink != true else {
                throw ActionRequestStoreError.unsafeStoreDirectory
            }
            try fileManager.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: requestDirectory.path
            )
        } catch let error as ActionRequestStoreError {
            throw error
        } catch {
            throw ActionRequestStoreError.cannotPrepareStore
        }
    }

    private func fileURL(for id: UUID) -> URL {
        requestDirectory.appendingPathComponent(
            id.uuidString.lowercased() + ".json",
            isDirectory: false
        )
    }

    private func isNoSuchFile(_ error: NSError) -> Bool {
        error.domain == NSCocoaErrorDomain
            && (error.code == NSFileNoSuchFileError
                || error.code == NSFileReadNoSuchFileError)
    }
}

enum ActionRequestStoreError: Error, Equatable, LocalizedError {
    case appGroupUnavailable
    case invalidRootDirectory
    case cannotPrepareStore
    case unsafeStoreDirectory
    case duplicateIdentifier(UUID)
    case invalidMaximumAge
    case payloadTooLarge
    case writeFailed
    case permissionHardeningFailed
    case readFailed
    case unsafeRequestFile
    case corruptPayload
    case identifierMismatch
    case removeFailed
    case claimFailed
    case requestCreatedInFuture
    case requestExpired

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            return "The shared App Group container is unavailable."
        case .invalidRootDirectory:
            return "The action request store requires an absolute local directory."
        case .cannotPrepareStore:
            return "The action request store could not be prepared."
        case .unsafeStoreDirectory:
            return "The action request store is not a safe physical directory."
        case .duplicateIdentifier:
            return "An action request with this identifier already exists."
        case .invalidMaximumAge:
            return "Action request lifetime must be greater than zero."
        case .payloadTooLarge:
            return "The action request exceeds the size limit."
        case .writeFailed:
            return "The action request could not be saved."
        case .permissionHardeningFailed:
            return "The action request could not be protected with private permissions."
        case .readFailed:
            return "The action request could not be read."
        case .unsafeRequestFile:
            return "The stored action request is not a regular file."
        case .corruptPayload:
            return "The stored action request is invalid."
        case .identifierMismatch:
            return "The stored action request identifier does not match its reference."
        case .removeFailed:
            return "The stored action request could not be removed."
        case .claimFailed:
            return "The action request could not be claimed for one-time use."
        case .requestCreatedInFuture:
            return "The action request timestamp is in the future."
        case .requestExpired:
            return "The action request expired before it could be used."
        }
    }
}
