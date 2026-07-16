import Foundation

enum InvocationKind: String, Codable, Hashable, Sendable {
    case container
    case items
}

struct InvocationContext: Equatable, Sendable {
    static let maximumSubjectCount = 512

    var kind: InvocationKind
    var subjects: [URL]

    init(kind: InvocationKind, subjects: [URL]) {
        self.kind = kind
        self.subjects = subjects
    }

    init(containerURL: URL) {
        self.init(kind: .container, subjects: [containerURL])
    }

    init(selectedURLs: [URL]) {
        self.init(kind: .items, subjects: selectedURLs)
    }
}

enum InvocationShape: Equatable, Sendable {
    case container(directory: URL)
    case singleFile(file: URL, parent: URL)
    case singleFolder(directory: URL)
    case sameParentSelection(parent: URL, subjects: [URL])
    case mixedParentSelection(subjects: [URL])
}

struct EditorCapabilities: Equatable, Sendable {
    var supportsMultipleItems: Bool
    var supportsMixedParentItems: Bool

    init(supportsMultipleItems: Bool, supportsMixedParentItems: Bool) {
        self.supportsMultipleItems = supportsMultipleItems
        self.supportsMixedParentItems = supportsMultipleItems && supportsMixedParentItems
    }

    static let singleItemOnly = EditorCapabilities(
        supportsMultipleItems: false,
        supportsMixedParentItems: false
    )
    static let sameParentItems = EditorCapabilities(
        supportsMultipleItems: true,
        supportsMixedParentItems: false
    )
    static let mixedParentItems = EditorCapabilities(
        supportsMultipleItems: true,
        supportsMixedParentItems: true
    )
}

enum ActionTarget: Equatable, Sendable {
    case directory(URL)
    case subjects([URL])
}

enum ActionDisabledReason: Equatable, Sendable {
    case mixedParentSelection
    case editorDoesNotSupportMultipleItems
    case editorDoesNotSupportMixedParentItems
}

struct ActionResolution: Equatable, Sendable {
    let action: ProductAction
    let target: ActionTarget?
    let disabledReason: ActionDisabledReason?

    var isEnabled: Bool {
        target != nil && disabledReason == nil
    }

    static func enabled(_ action: ProductAction, target: ActionTarget) -> ActionResolution {
        ActionResolution(action: action, target: target, disabledReason: nil)
    }

    static func disabled(
        _ action: ProductAction,
        reason: ActionDisabledReason
    ) -> ActionResolution {
        ActionResolution(action: action, target: nil, disabledReason: reason)
    }
}

struct ContextResolver {
    typealias DirectoryProbe = (URL) throws -> Bool

    private let isDirectory: DirectoryProbe

    init(isDirectory: @escaping DirectoryProbe = ContextResolver.fileSystemDirectoryProbe) {
        self.isDirectory = isDirectory
    }

    func classify(_ context: InvocationContext) throws -> InvocationShape {
        try validate(context)

        switch context.kind {
        case .container:
            let directory = context.subjects[0]
            guard try isDirectory(directory) else {
                throw ContextResolutionError.containerIsNotDirectory(directory)
            }
            return .container(directory: directory)

        case .items:
            if context.subjects.count == 1 {
                let subject = context.subjects[0]
                if try isDirectory(subject) {
                    return .singleFolder(directory: subject)
                }
                return .singleFile(file: subject, parent: subject.deletingLastPathComponent())
            }

            // Probe every item. The default probe also proves each physical path exists.
            for subject in context.subjects {
                _ = try isDirectory(subject)
            }

            let firstParent = context.subjects[0].deletingLastPathComponent()
            let hasOneParent = context.subjects.dropFirst().allSatisfy {
                $0.deletingLastPathComponent().path == firstParent.path
            }
            if hasOneParent {
                return .sameParentSelection(parent: firstParent, subjects: context.subjects)
            }
            return .mixedParentSelection(subjects: context.subjects)
        }
    }

    func resolve(
        _ action: ProductAction,
        in context: InvocationContext,
        editorCapabilities: EditorCapabilities = .singleItemOnly
    ) throws -> ActionResolution {
        let shape = try classify(context)

        switch shape {
        case let .container(directory), let .singleFolder(directory):
            switch action {
            case .newFile, .openTerminal:
                return .enabled(action, target: .directory(directory))
            case .copyPath, .openEditor:
                return .enabled(action, target: .subjects([directory]))
            }

        case let .singleFile(file, parent):
            switch action {
            case .newFile, .openTerminal:
                return .enabled(action, target: .directory(parent))
            case .copyPath, .openEditor:
                return .enabled(action, target: .subjects([file]))
            }

        case let .sameParentSelection(parent, subjects):
            switch action {
            case .newFile, .openTerminal:
                return .enabled(action, target: .directory(parent))
            case .copyPath:
                return .enabled(action, target: .subjects(subjects))
            case .openEditor:
                guard editorCapabilities.supportsMultipleItems else {
                    return .disabled(action, reason: .editorDoesNotSupportMultipleItems)
                }
                return .enabled(action, target: .subjects(subjects))
            }

        case let .mixedParentSelection(subjects):
            switch action {
            case .copyPath:
                return .enabled(action, target: .subjects(subjects))
            case .openEditor:
                guard editorCapabilities.supportsMultipleItems else {
                    return .disabled(action, reason: .editorDoesNotSupportMultipleItems)
                }
                guard editorCapabilities.supportsMixedParentItems else {
                    return .disabled(action, reason: .editorDoesNotSupportMixedParentItems)
                }
                return .enabled(action, target: .subjects(subjects))
            case .newFile, .openTerminal:
                return .disabled(action, reason: .mixedParentSelection)
            }
        }
    }

    static func fileSystemDirectoryProbe(_ url: URL) throws -> Bool {
        do {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            guard let isDirectory = values.isDirectory else {
                throw ContextResolutionError.cannotDetermineItemType(url)
            }
            return isDirectory
        } catch let error as ContextResolutionError {
            throw error
        } catch {
            throw ContextResolutionError.inaccessibleSubject(url)
        }
    }

    private func validate(_ context: InvocationContext) throws {
        switch context.kind {
        case .container where context.subjects.count != 1:
            throw ContextResolutionError.invalidContainerSubjectCount(context.subjects.count)
        case .items where context.subjects.isEmpty:
            throw ContextResolutionError.emptyItemSelection
        default:
            break
        }

        guard context.subjects.count <= InvocationContext.maximumSubjectCount else {
            throw ContextResolutionError.tooManySubjects(context.subjects.count)
        }

        for subject in context.subjects {
            guard subject.isFileURL,
                  !subject.path.isEmpty,
                  !subject.path.contains("\0"),
                  (subject.path as NSString).isAbsolutePath else {
                throw ContextResolutionError.nonPhysicalSubject(subject)
            }
        }
    }
}

enum ContextResolutionError: Error, Equatable, LocalizedError {
    case invalidContainerSubjectCount(Int)
    case emptyItemSelection
    case tooManySubjects(Int)
    case nonPhysicalSubject(URL)
    case containerIsNotDirectory(URL)
    case inaccessibleSubject(URL)
    case cannotDetermineItemType(URL)

    var errorDescription: String? {
        switch self {
        case let .invalidContainerSubjectCount(count):
            return "A container invocation must contain exactly one directory; received \(count)."
        case .emptyItemSelection:
            return "An item invocation must contain at least one physical path."
        case let .tooManySubjects(count):
            return "An invocation may contain at most \(InvocationContext.maximumSubjectCount) paths; received \(count)."
        case let .nonPhysicalSubject(url):
            return "Invocation subject is not an absolute local file URL: \(url.absoluteString)"
        case let .containerIsNotDirectory(url):
            return "Container invocation subject is not a directory: \(url.path)"
        case let .inaccessibleSubject(url):
            return "Invocation subject is missing or inaccessible: \(url.path)"
        case let .cannotDetermineItemType(url):
            return "Cannot determine whether invocation subject is a directory: \(url.path)"
        }
    }
}
