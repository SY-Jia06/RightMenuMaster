import Cocoa
import FinderSync

final class PathCopier {

    func copyPath() {
        let items = FIFinderSyncController.default().selectedItemURLs()
        copyToPasteboard(items?.map { $0.path }.joined(separator: "\n") ?? "")
    }

    func copyName() {
        let items = FIFinderSyncController.default().selectedItemURLs()
        copyToPasteboard(items?.map { $0.lastPathComponent }.joined(separator: "\n") ?? "")
    }

    private func copyToPasteboard(_ string: String) {
        guard !string.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }
}
