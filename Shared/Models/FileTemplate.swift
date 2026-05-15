import Foundation

struct FileTemplate: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var ext: String
    var content: String
    var isBuiltIn: Bool

    init(id: UUID = UUID(), name: String, ext: String, content: String, isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.ext = ext
        self.content = content
        self.isBuiltIn = isBuiltIn
    }

    var fileName: String {
        "untitled.\(ext)"
    }

    var displayName: String {
        "\(name) (.\(ext))"
    }
}
