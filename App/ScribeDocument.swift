import ScribeCore
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let markdownText = UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
}

/// A Markdown file on disk. The editor sees only its body; the Target lives in front matter.
struct ScribeDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.markdownText, .plainText]
    static let writableContentTypes: [UTType] = [.markdownText]

    var file: MarkdownFile

    /// A new Document, using the app-wide default Target.
    init() {
        file = MarkdownFile(body: "", targetID: UserDefaults.standard.string(forKey: SettingsKey.defaultTargetID) ?? BuiltInTargets.default.id)
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8)
        else { throw CocoaError(.fileReadCorruptFile) }
        file = MarkdownFile(parsing: text)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(file.rendered.utf8))
    }
}
