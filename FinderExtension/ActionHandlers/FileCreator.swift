import Cocoa

final class FileCreator {

    func createFile(from template: FileTemplate, at directoryURL: URL) {
        NSLog("[RightMenu] FileCreator.createFile at: \(directoryURL.path), template: \(template.displayName)")
        let fileURL = FileCreationPlanner.nextFileURL(in: directoryURL, template: template)
        do {
            let data = template.content.data(using: .utf8) ?? Data()
            try data.write(to: fileURL, options: .atomic)
            NSLog("[RightMenu] File created: true, path: \(fileURL.path)")
            selectAndBeginRename(fileURL)
        } catch {
            NSLog("[RightMenu] File create failed: \(error.localizedDescription), path: \(fileURL.path)")
        }
    }

    private func selectAndBeginRename(_ fileURL: URL) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard let commandURL = AppCommandURL.url(command: .rename, path: fileURL.path) else {
                NSLog("[RightMenu] Rename command URL build failed: \(fileURL.path)")
                return
            }
            NSWorkspace.shared.open(commandURL)
        }
    }
}
