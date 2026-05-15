import Cocoa
import FinderSync

final class PathCopier {

    func copyPath() {
        let items = selectedOrTargetedURLs()
        NSLog("[RightMenu] PathCopier.copyPath, items: \(items.map { $0.path })")
        copyToPasteboard(items.map { $0.path }.joined(separator: "\n"))
    }

    func copyName() {
        let items = selectedOrTargetedURLs()
        copyToPasteboard(items.map { $0.lastPathComponent }.joined(separator: "\n"))
    }

    private func copyToPasteboard(_ string: String) {
        guard !string.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    private func selectedOrTargetedURLs() -> [URL] {
        if let selected = FIFinderSyncController.default().selectedItemURLs(),
           !selected.isEmpty {
            return selected
        }
        if let targeted = FIFinderSyncController.default().targetedURL() {
            return [targeted]
        }
        return []
    }
}
