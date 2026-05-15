import Foundation
import UniformTypeIdentifiers

final class TemplateService {

    func importTemplate(from url: URL) -> FileTemplate? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let name = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension.isEmpty ? "txt" : url.pathExtension
        return FileTemplate(name: name, ext: ext, content: content, isBuiltIn: false)
    }

    func exportTemplate(_ template: FileTemplate, to directory: URL) {
        let fileName = "\(template.name).\(template.ext)"
        let fileURL = directory.appendingPathComponent(fileName)
        try? template.content.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    func validateTemplate(name: String, ext: String) -> Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty,
              !ext.trimmingCharacters(in: .whitespaces).isEmpty,
              !ext.contains("/"),
              !ext.contains("."),
              ext.count <= 10,
              name.count <= 100 else { return false }
        return true
    }
}
