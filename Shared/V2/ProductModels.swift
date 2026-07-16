import Foundation

enum ProductAction: String, Codable, CaseIterable, Hashable, Sendable {
    case newFile
    case copyPath
    case openTerminal
    case openEditor
}

struct PreferredApplication: Codable, Equatable, Hashable, Sendable {
    var id: String
    var displayName: String
    var applicationPath: String?

    init(id: String, displayName: String, applicationPath: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.applicationPath = applicationPath
    }

    var applicationURL: URL? {
        guard let applicationPath else { return nil }
        return URL(fileURLWithPath: applicationPath)
    }

    func validate() throws {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PreferredApplicationValidationError.emptyIdentifier
        }
        guard !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PreferredApplicationValidationError.emptyDisplayName
        }
        guard let applicationPath else { return }
        guard !applicationPath.isEmpty,
              !applicationPath.contains("\0"),
              (applicationPath as NSString).isAbsolutePath else {
            throw PreferredApplicationValidationError.invalidApplicationPath(applicationPath)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        applicationPath = try container.decodeIfPresent(String.self, forKey: .applicationPath)
        try validate()
    }
}

enum PreferredApplicationValidationError: Error, Equatable, LocalizedError {
    case emptyIdentifier
    case emptyDisplayName
    case invalidApplicationPath(String)

    var errorDescription: String? {
        switch self {
        case .emptyIdentifier:
            return "Application identifier cannot be empty."
        case .emptyDisplayName:
            return "Application display name cannot be empty."
        case let .invalidApplicationPath(path):
            return "Application path must be an absolute local path: \(path)"
        }
    }
}

enum FileRecipe: String, Codable, CaseIterable, Hashable, Sendable {
    case blank
    case text
    case markdown

    var preferredExtension: String? {
        switch self {
        case .blank:
            return nil
        case .text:
            return "txt"
        case .markdown:
            return "md"
        }
    }

    var initialContent: String {
        switch self {
        case .blank, .text:
            return ""
        case .markdown:
            return "# \n\n"
        }
    }
}

enum V2Language: String, Codable, CaseIterable, Hashable, Sendable {
    case system
    case simplifiedChinese = "zh-Hans"
    case english = "en"
}

enum PostCreateBehavior: String, Codable, CaseIterable, Hashable, Sendable {
    case reveal
    case openPreferredEditor
    case openSystemAssociation
}

struct V2Config: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 2

    let schemaVersion: Int
    var enabledActions: [ProductAction]
    var actionOrder: [ProductAction]
    var preferredTerminal: PreferredApplication?
    var preferredEditor: PreferredApplication?
    var language: V2Language
    var defaultRecipe: FileRecipe
    var postCreateBehavior: PostCreateBehavior
    var onboardingStep: Int

    init(
        enabledActions: [ProductAction] = ProductAction.allCases,
        actionOrder: [ProductAction] = ProductAction.allCases,
        preferredTerminal: PreferredApplication? = nil,
        preferredEditor: PreferredApplication? = nil,
        language: V2Language = .system,
        defaultRecipe: FileRecipe = .blank,
        postCreateBehavior: PostCreateBehavior = .reveal,
        onboardingStep: Int = 0
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.enabledActions = enabledActions
        self.actionOrder = actionOrder
        self.preferredTerminal = preferredTerminal
        self.preferredEditor = preferredEditor
        self.language = language
        self.defaultRecipe = defaultRecipe
        self.postCreateBehavior = postCreateBehavior
        self.onboardingStep = onboardingStep
    }

    static let `default` = V2Config()

    func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw V2ConfigValidationError.unsupportedSchemaVersion(schemaVersion)
        }
        guard Set(enabledActions).count == enabledActions.count else {
            throw V2ConfigValidationError.duplicateEnabledAction
        }
        guard Set(actionOrder).count == actionOrder.count else {
            throw V2ConfigValidationError.duplicateOrderedAction
        }
        guard Set(actionOrder) == Set(ProductAction.allCases),
              actionOrder.count == ProductAction.allCases.count else {
            throw V2ConfigValidationError.incompleteActionOrder
        }
        guard (0...4).contains(onboardingStep) else {
            throw V2ConfigValidationError.invalidOnboardingStep(onboardingStep)
        }
        try preferredTerminal?.validate()
        try preferredEditor?.validate()
    }

    func normalized() -> V2Config {
        var copy = self
        copy.enabledActions = enabledActions.removingDuplicates()

        var normalizedOrder = actionOrder.removingDuplicates()
        normalizedOrder.append(contentsOf: ProductAction.allCases.filter { !normalizedOrder.contains($0) })
        copy.actionOrder = normalizedOrder
        copy.onboardingStep = min(max(onboardingStep, 0), 4)
        return copy
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        enabledActions = try container.decode([ProductAction].self, forKey: .enabledActions)
        actionOrder = try container.decode([ProductAction].self, forKey: .actionOrder)
        preferredTerminal = try container.decodeIfPresent(PreferredApplication.self, forKey: .preferredTerminal)
        preferredEditor = try container.decodeIfPresent(PreferredApplication.self, forKey: .preferredEditor)
        language = try container.decode(V2Language.self, forKey: .language)
        defaultRecipe = try container.decode(FileRecipe.self, forKey: .defaultRecipe)
        postCreateBehavior = try container.decode(PostCreateBehavior.self, forKey: .postCreateBehavior)
        onboardingStep = try container.decodeIfPresent(Int.self, forKey: .onboardingStep) ?? 0
        try validate()
    }
}

enum V2ConfigValidationError: Error, Equatable, LocalizedError {
    case unsupportedSchemaVersion(Int)
    case duplicateEnabledAction
    case duplicateOrderedAction
    case incompleteActionOrder
    case invalidOnboardingStep(Int)

    var errorDescription: String? {
        switch self {
        case let .unsupportedSchemaVersion(version):
            return "Unsupported configuration schema version: \(version)"
        case .duplicateEnabledAction:
            return "Enabled actions must not contain duplicates."
        case .duplicateOrderedAction:
            return "Action order must not contain duplicates."
        case .incompleteActionOrder:
            return "Action order must contain every product action exactly once."
        case let .invalidOnboardingStep(step):
            return "Onboarding step must be between 0 and 4: \(step)"
        }
    }
}

private extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
