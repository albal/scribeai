import Foundation

/// A span of a Document's text. Offsets are UTF-16, matching the editor's selection.
public struct TextSpan: Equatable, Sendable {
    public let range: Range<Int>
    public let text: String

    public init(range: Range<Int>, text: String) {
        self.range = range
        self.text = text
    }
}

/// Splits Markdown text into the units that can be evaluated.
public enum MarkdownSegmenter {
    /// Blank-line-separated blocks of text.
    public static func paragraphs(in text: String) -> [TextSpan] {
        let ns = text as NSString
        var spans: [TextSpan] = []
        var start: Int?
        var end = 0

        func flush() {
            if let s = start {
                let range = NSRange(location: s, length: end - s)
                let trimmed = ns.substring(with: range).trimmingCharacters(in: .newlines)
                spans.append(TextSpan(range: s..<(s + (trimmed as NSString).length), text: trimmed))
            }
            start = nil
        }

        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byLines) { line, lineRange, enclosingRange, _ in
            if (line ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
                flush()
            } else {
                if start == nil { start = lineRange.location }
                end = NSMaxRange(lineRange)
            }
        }
        flush()
        return spans
    }

    /// The Paragraph containing `offset`, including a cursor resting just after its last character.
    public static func paragraph(at offset: Int, in text: String) -> TextSpan? {
        paragraphs(in: text).first { $0.range.contains(offset) || $0.range.upperBound == offset }
    }

    public static func wordCount(of text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }
}
