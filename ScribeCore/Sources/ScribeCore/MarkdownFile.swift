import Foundation

/// A Document as stored on disk: optional YAML front matter, then the Markdown body.
///
/// The editor shows only the body, so front matter is never evaluated. Front matter keys other
/// than the Target are preserved exactly.
public struct MarkdownFile: Equatable, Sendable {
    public static let targetKey = "scribeai-target"

    /// Raw lines between the `---` delimiters; empty when the file has no front matter.
    public private(set) var frontMatter: [String]
    public var body: String

    public init(body: String = "", targetID: String? = nil) {
        frontMatter = []
        self.body = body
        self.targetID = targetID
    }

    public init(parsing text: String) {
        frontMatter = []
        body = text
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.first.map(Self.trimmed) == "---",
              let close = lines.dropFirst().firstIndex(where: { ["---", "..."].contains(Self.trimmed($0)) })
        else { return }
        frontMatter = lines[1..<close].map { String($0.hasSuffix("\r") ? $0.dropLast() : $0) }
        body = lines[(close + 1)...].joined(separator: "\n")
    }

    public var rendered: String {
        frontMatter.isEmpty ? body : (["---"] + frontMatter + ["---"]).joined(separator: "\n") + "\n" + body
    }

    public var targetID: String? {
        get {
            frontMatter.lazy.compactMap(Self.targetValue).first
        }
        set {
            let index = frontMatter.firstIndex { Self.targetValue(in: $0) != nil }
            switch (index, newValue) {
            case let (index?, id?): frontMatter[index] = "\(Self.targetKey): \(id)"
            case let (index?, nil): frontMatter.remove(at: index)
            case let (nil, id?): frontMatter.append("\(Self.targetKey): \(id)")
            case (nil, nil): break
            }
        }
    }

    private static func targetValue(in line: String) -> String? {
        guard let match = line.wholeMatch(of: /\s*scribeai-target\s*:\s*(.*?)\s*/) else { return nil }
        let value = match.1.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        return value.isEmpty ? nil : value
    }

    private static func trimmed(_ line: Substring) -> String {
        line.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
