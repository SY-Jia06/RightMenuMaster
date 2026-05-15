import Cocoa

final class ScriptRunner {

    func run(script: String, at directoryURL: URL) {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("rightmenu_script_\(UUID().uuidString.prefix(8)).sh")

        defer { try? FileManager.default.removeItem(at: tempURL) }

        guard let data = script.data(using: .utf8) else { return }
        FileManager.default.createFile(atPath: tempURL.path, contents: data)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempURL.path)

        let safePath = directoryURL.path.replacingOccurrences(of: "\"", with: "\\\"")
        let scriptPath = tempURL.path.replacingOccurrences(of: "\"", with: "\\\"")

        let appleScript = """
        tell application "Terminal"
            if it is running then
                do script "cd \\"\(safePath)\\" && bash \\"\(scriptPath)\\""
            else
                do script "cd \\"\(safePath)\\" && bash \\"\(scriptPath)\\"" in front window
            end if
            activate
        end tell
        """

        let scriptObject = NSAppleScript(source: appleScript)
        var error: NSDictionary?
        scriptObject?.executeAndReturnError(&error)

        if let error = error {
            NSLog("ScriptRunner error: \(error)")
        }
    }
}
