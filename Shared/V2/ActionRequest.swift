import Foundation

struct ActionRequest: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1
    static let maximumPathUTF8Length = 32_768

    let schemaVersion: Int
    let id: UUID
    let action: ProductAction
    let invocationKind: InvocationKind
    let subjects: [String]
    let createdAt: Date

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case id
        case action
        case invocationKind
        case subjects
        case createdAt
    }

    init(
        id: UUID = UUID(),
        action: ProductAction,
        invocationKind: InvocationKind,
        subjects: [String],
        createdAt: Date = Date()
    ) throws {
        schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.action = action
        self.invocationKind = invocationKind
        self.subjects = subjects
        self.createdAt = Self.normalizedTimestamp(createdAt)
        try validate()
    }

    init(
        id: UUID = UUID(),
        action: ProductAction,
        context: InvocationContext,
        createdAt: Date = Date()
    ) throws {
        try self.init(
            id: id,
            action: action,
            invocationKind: context.kind,
            subjects: context.subjects.map(\.path),
            createdAt: createdAt
        )
    }

    func invocationContext() throws -> InvocationContext {
        try validate()
        return InvocationContext(
            kind: invocationKind,
            subjects: subjects.map { URL(fileURLWithPath: $0) }
        )
    }

    func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ActionRequestValidationError.unsupportedSchemaVersion(schemaVersion)
        }
        switch invocationKind {
        case .container where subjects.count != 1:
            throw ActionRequestValidationError.invalidContainerSubjectCount(subjects.count)
        case .items where subjects.isEmpty:
            throw ActionRequestValidationError.emptyItemSelection
        default:
            break
        }
        guard subjects.count <= InvocationContext.maximumSubjectCount else {
            throw ActionRequestValidationError.tooManySubjects(subjects.count)
        }
        guard createdAt.timeIntervalSinceReferenceDate.isFinite else {
            throw ActionRequestValidationError.invalidTimestamp
        }
        for path in subjects {
            guard !path.isEmpty,
                  !path.contains("\0"),
                  (path as NSString).isAbsolutePath else {
                throw ActionRequestValidationError.invalidPhysicalPath(path)
            }
            guard path.utf8.count <= Self.maximumPathUTF8Length else {
                throw ActionRequestValidationError.pathTooLong
            }
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        id = try container.decode(UUID.self, forKey: .id)
        action = try container.decode(ProductAction.self, forKey: .action)
        invocationKind = try container.decode(InvocationKind.self, forKey: .invocationKind)
        subjects = try container.decode([String].self, forKey: .subjects)

        let dateString = try container.decode(String.self, forKey: .createdAt)
        guard let decodedDate = Self.date(from: dateString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .createdAt,
                in: container,
                debugDescription: "createdAt must be an ISO 8601 timestamp."
            )
        }
        createdAt = Self.normalizedTimestamp(decodedDate)
        try validate()
    }

    func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(id, forKey: .id)
        try container.encode(action, forKey: .action)
        try container.encode(invocationKind, forKey: .invocationKind)
        try container.encode(subjects, forKey: .subjects)
        try container.encode(Self.string(from: createdAt), forKey: .createdAt)
    }

    private static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func normalizedTimestamp(_ date: Date) -> Date {
        let milliseconds = (date.timeIntervalSince1970 * 1_000).rounded(.towardZero)
        return Date(timeIntervalSince1970: milliseconds / 1_000)
    }

    private static func date(from string: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: string) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

enum ActionRequestValidationError: Error, Equatable, LocalizedError {
    case unsupportedSchemaVersion(Int)
    case invalidContainerSubjectCount(Int)
    case emptyItemSelection
    case tooManySubjects(Int)
    case invalidPhysicalPath(String)
    case pathTooLong
    case invalidTimestamp

    var errorDescription: String? {
        switch self {
        case let .unsupportedSchemaVersion(version):
            return "Unsupported action request schema version: \(version)"
        case let .invalidContainerSubjectCount(count):
            return "A container request must contain exactly one path; received \(count)."
        case .emptyItemSelection:
            return "An item request must contain at least one path."
        case let .tooManySubjects(count):
            return "An action request may contain at most \(InvocationContext.maximumSubjectCount) paths; received \(count)."
        case let .invalidPhysicalPath(path):
            return "Action request path must be an absolute physical path: \(path)"
        case .pathTooLong:
            return "Action request path is too long."
        case .invalidTimestamp:
            return "Action request timestamp is invalid."
        }
    }
}
