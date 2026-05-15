import Cocoa

final class FileCreator {

    func createFile(from template: FileTemplate, at directoryURL: URL) {
        let baseName = "untitled"
        let ext = template.ext
        var fileName = "\(baseName).\(ext)"
        var counter = 1

        while FileManager.default.fileExists(atPath: directoryURL.appendingPathComponent(fileName).path) {
            fileName = "\(baseName) \(counter).\(ext)"
            counter += 1
        }

        let fileURL = directoryURL.appendingPathComponent(fileName)
        FileManager.default.createFile(
            atPath: fileURL.path,
            contents: template.content.data(using: .utf8),
            attributes: [.creationDate: Date()]
        )

        selectAndRename(fileURL)
    }

    private func selectAndRename(_ fileURL: URL) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let path = fileURL.path.replacingOccurrences(of: "\"", with: "\\\"")
            let script = """
            tell application "Finder"
                activate
                select POSIX file "\(path)"
                tell application "System Events"
                    tell process "Finder"
                        keystroke return
                    end tell
                end tell
            end tell
            """
            NSAppleScript(source: script)?.executeAndReturnError(nil)
        }
    }
}
