import Foundation

struct ParsedFilename: Equatable, Sendable {
    let fileName: String
    let stem: String
    let fileExtension: String?
    let recipe: FileRecipe
    let appliedRecipeExtension: Bool

    var contents: Data {
        Data(recipe.initialContent.utf8)
    }
}

enum SafeFilenameParser {
    static let maximumUTF8Length = 255

    static func parse(_ input: String, recipe: FileRecipe) throws -> ParsedFilename {
        try validateCharacters(in: input)

        let inputParts = splitExtension(in: input)
        let isExtensionlessDotfile = input.first == "."
            && !input.dropFirst().contains(".")
        let appliedRecipeExtension = inputParts.extension == nil
            && recipe.preferredExtension != nil
            && !isExtensionlessDotfile
        let finalName: String
        if let recipeExtension = recipe.preferredExtension, appliedRecipeExtension {
            finalName = input + "." + recipeExtension
        } else {
            finalName = input
        }

        try validateCharacters(in: finalName)
        let finalParts = splitExtension(in: finalName)
        return ParsedFilename(
            fileName: finalName,
            stem: finalParts.stem,
            fileExtension: finalParts.extension,
            recipe: recipe,
            appliedRecipeExtension: appliedRecipeExtension
        )
    }

    private static func validateCharacters(in candidate: String) throws {
        guard !candidate.isEmpty else {
            throw FilenameValidationError.empty
        }
        guard candidate != ".", candidate != ".." else {
            throw FilenameValidationError.relativeDirectoryMarker
        }
        guard candidate.utf8.count <= maximumUTF8Length else {
            throw FilenameValidationError.tooLong(maximumUTF8Length)
        }
        guard candidate.last != " ", candidate.last != "." else {
            throw FilenameValidationError.trailingSpaceOrPeriod
        }

        let forbidden = CharacterSet(charactersIn: "<>:\"/\\|?*")
        let bidiControls = CharacterSet(charactersIn: "\u{202A}\u{202B}\u{202C}\u{202D}\u{202E}\u{2066}\u{2067}\u{2068}\u{2069}")
        for scalar in candidate.unicodeScalars {
            if CharacterSet.controlCharacters.contains(scalar)
                || CharacterSet.illegalCharacters.contains(scalar)
                || bidiControls.contains(scalar) {
                throw FilenameValidationError.unsafeControlCharacter
            }
            if forbidden.contains(scalar) {
                throw FilenameValidationError.forbiddenCharacter(Character(String(scalar)))
            }
        }

        let firstComponent = candidate.split(
            separator: ".",
            maxSplits: 1,
            omittingEmptySubsequences: false
        ).first.map(String.init) ?? candidate
        let reservedStem = firstComponent.trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        let uppercasedStem = reservedStem.uppercased()
        let reservedNames: Set<String> = ["CON", "PRN", "AUX", "NUL"]
        let isNumberedDevice = (1...9).contains { number in
            uppercasedStem == "COM\(number)" || uppercasedStem == "LPT\(number)"
        }
        guard !reservedNames.contains(uppercasedStem), !isNumberedDevice else {
            throw FilenameValidationError.windowsReservedName(reservedStem)
        }
    }

    private static func splitExtension(in fileName: String) -> (stem: String, extension: String?) {
        guard let dot = fileName.lastIndex(of: "."),
              dot != fileName.startIndex,
              fileName.index(after: dot) != fileName.endIndex else {
            return (fileName, nil)
        }
        return (
            String(fileName[..<dot]),
            String(fileName[fileName.index(after: dot)...])
        )
    }
}

enum FilenameValidationError: Error, Equatable, LocalizedError {
    case empty
    case relativeDirectoryMarker
    case trailingSpaceOrPeriod
    case forbiddenCharacter(Character)
    case unsafeControlCharacter
    case windowsReservedName(String)
    case tooLong(Int)

    var errorDescription: String? {
        switch self {
        case .empty:
            return "Enter a filename."
        case .relativeDirectoryMarker:
            return "Use a filename other than . or ..."
        case .trailingSpaceOrPeriod:
            return "Remove the space or period at the end of the filename."
        case let .forbiddenCharacter(character):
            return "Remove the unsupported filename character: \(character)"
        case .unsafeControlCharacter:
            return "Remove control or bidirectional formatting characters from the filename."
        case let .windowsReservedName(name):
            return "Choose another filename; \(name) is reserved by Windows."
        case let .tooLong(limit):
            return "Shorten the filename to at most \(limit) UTF-8 bytes."
        }
    }
}

struct CreatedFile: Equatable, Sendable {
    let url: URL
    let parsedFilename: ParsedFilename
}

struct ExclusiveFileCreator {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func create(
        filename: String,
        recipe: FileRecipe,
        in directory: URL
    ) throws -> CreatedFile {
        let parsedFilename: ParsedFilename
        do {
            parsedFilename = try SafeFilenameParser.parse(filename, recipe: recipe)
        } catch let error as FilenameValidationError {
            throw FileCreationError.invalidFilename(error)
        }

        try validateDirectory(directory)
        let destination = directory.appendingPathComponent(
            parsedFilename.fileName,
            isDirectory: false
        )

        do {
            // Foundation implements withoutOverwriting as an exclusive create. A competing
            // invocation can win, but this invocation can never replace its entry.
            try parsedFilename.contents.write(to: destination, options: .withoutOverwriting)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain
            && error.code == NSFileWriteFileExistsError {
            let suggestion = (try? nextAvailableFilename(
                after: parsedFilename,
                in: directory
            )) ?? fallbackSuggestion(after: parsedFilename)
            throw FileCreationError.collision(
                existing: destination,
                suggestedFilename: suggestion
            )
        } catch let error as NSError where error.domain == NSCocoaErrorDomain
            && (error.code == NSFileWriteNoPermissionError
                || error.code == NSFileWriteVolumeReadOnlyError) {
            throw FileCreationError.permissionDenied(directory)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain
            && error.code == NSFileNoSuchFileError {
            throw FileCreationError.directoryMissing(directory)
        } catch {
            throw FileCreationError.writeFailed(destination)
        }

        return CreatedFile(url: destination, parsedFilename: parsedFilename)
    }

    func nextAvailableFilename(
        after parsedFilename: ParsedFilename,
        in directory: URL
    ) throws -> String {
        try validateDirectory(directory)

        let numberedStem = splitNumberedSuffix(from: parsedFilename.stem)
        var number = numberedStem.nextNumber
        while number < 100_000 {
            let candidateStem = "\(numberedStem.base) \(number)"
            let candidate = joined(
                stem: candidateStem,
                extension: parsedFilename.fileExtension
            )
            let candidateURL = directory.appendingPathComponent(candidate, isDirectory: false)
            if try !entryExists(at: candidateURL) {
                return candidate
            }
            number += 1
        }
        throw FileCreationError.cannotSuggestAvailableName
    }

    private func validateDirectory(_ directory: URL) throws {
        guard directory.isFileURL,
              !directory.path.contains("\0"),
              (directory.path as NSString).isAbsolutePath else {
            throw FileCreationError.invalidDirectory(directory)
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory) else {
            throw FileCreationError.directoryMissing(directory)
        }
        guard isDirectory.boolValue else {
            throw FileCreationError.notDirectory(directory)
        }
    }

    private func entryExists(at url: URL) throws -> Bool {
        do {
            _ = try fileManager.attributesOfItem(atPath: url.path)
            return true
        } catch let error as NSError where error.domain == NSCocoaErrorDomain
            && (error.code == NSFileNoSuchFileError
                || error.code == NSFileReadNoSuchFileError) {
            return false
        } catch {
            throw FileCreationError.cannotInspectDirectory(url.deletingLastPathComponent())
        }
    }

    private func splitNumberedSuffix(from stem: String) -> (base: String, nextNumber: Int) {
        guard let space = stem.lastIndex(of: " ") else {
            return (stem, 2)
        }
        let suffixStart = stem.index(after: space)
        guard suffixStart != stem.endIndex,
              let value = Int(stem[suffixStart...]),
              value >= 1 else {
            return (stem, 2)
        }
        let base = String(stem[..<space])
        guard !base.isEmpty else { return (stem, 2) }
        return (base, value + 1)
    }

    private func joined(stem: String, extension fileExtension: String?) -> String {
        guard let fileExtension else { return stem }
        return stem + "." + fileExtension
    }

    private func fallbackSuggestion(after parsedFilename: ParsedFilename) -> String {
        let numberedStem = splitNumberedSuffix(from: parsedFilename.stem)
        return joined(
            stem: "\(numberedStem.base) \(numberedStem.nextNumber)",
            extension: parsedFilename.fileExtension
        )
    }
}

enum FileCreationError: Error, Equatable, LocalizedError {
    case invalidFilename(FilenameValidationError)
    case invalidDirectory(URL)
    case directoryMissing(URL)
    case notDirectory(URL)
    case permissionDenied(URL)
    case collision(existing: URL, suggestedFilename: String)
    case cannotInspectDirectory(URL)
    case cannotSuggestAvailableName
    case writeFailed(URL)

    var errorDescription: String? {
        switch self {
        case let .invalidFilename(error):
            return error.localizedDescription
        case .invalidDirectory:
            return "Choose a local working directory."
        case .directoryMissing:
            return "The working directory no longer exists. Choose another directory and retry."
        case .notDirectory:
            return "The selected working location is not a directory."
        case .permissionDenied:
            return "Right Click Master cannot write here. Choose a writable directory or grant access, then retry."
        case let .collision(_, suggestedFilename):
            return "A file with this name already exists. Try \(suggestedFilename)."
        case .cannotInspectDirectory:
            return "Right Click Master cannot inspect this directory for an available filename."
        case .cannotSuggestAvailableName:
            return "No available filename suggestion could be found."
        case .writeFailed:
            return "The file could not be created. The existing entry was not changed."
        }
    }
}
