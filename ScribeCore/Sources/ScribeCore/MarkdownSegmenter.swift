import Foundation
import NaturalLanguage

/// A span of a Document's text. Offsets are UTF-16, matching the editor's selection.
public struct TextSpan: Equatable, Sendable {
    /// Where the span sits in the Document, Markdown markers included.
    public let range: Range<Int>
    /// The prose itself, with Markdown markers (`>`, list bullets) removed.
    public let text: String

    public init(range: Range<Int>, text: String) {
        self.range = range
        self.text = text
    }

    /// Whether a cursor at `offset` is in this span, including just after its last character.
    func holds(_ offset: Int) -> Bool {
        range.contains(offset) || range.upperBound == offset
    }
}

/// Splits Markdown text into the units that can be evaluated.
///
/// A Paragraph is a blank-line-separated block of prose; each list item and blockquote is also a
/// Paragraph. Headings, code blocks, horizontal rules and front matter are never prose.
public enum MarkdownSegmenter {
    public static let minimumSentenceWords = 4
    public static let minimumParagraphWords = 15

    public static func paragraphs(in text: String) -> [TextSpan] {
        let ns = text as NSString
        var spans: [TextSpan] = []
        var block: (start: Int, end: Int, kind: BlockKind)?
        var lineIndex = 0
        var inFrontMatter = false
        var fence: String?

        func flush() {
            if let current = block {
                let range = current.start..<current.end
                let prose = clean(ns.substring(with: NSRange(location: range.lowerBound, length: range.count)))
                if !prose.isEmpty { spans.append(TextSpan(range: range, text: prose)) }
            }
            block = nil
        }

        func extend(_ lineRange: NSRange, as kind: BlockKind) {
            if block == nil { block = (lineRange.location, NSMaxRange(lineRange), kind) }
            block?.end = NSMaxRange(lineRange)
        }

        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byLines) { line, lineRange, _, _ in
            defer { lineIndex += 1 }
            let trimmed = (line ?? "").trimmingCharacters(in: .whitespaces)

            if lineIndex == 0, trimmed == "---" {
                inFrontMatter = true
                return
            }
            if inFrontMatter {
                if trimmed == "---" || trimmed == "..." { inFrontMatter = false }
                return
            }
            if let marker = fence {
                if trimmed.hasPrefix(marker) { fence = nil }
                return
            }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flush()
                fence = String(trimmed.prefix(3))
                return
            }
            if trimmed.isEmpty || isHeading(trimmed) || isRule(trimmed) {
                flush()
                return
            }
            if trimmed.hasPrefix(">") {
                if stripQuote(trimmed).isEmpty {
                    flush()
                    return
                }
                if block?.kind != .quote { flush() }
                extend(lineRange, as: .quote)
                return
            }
            if listMarker(in: trimmed) != nil {
                flush()
                extend(lineRange, as: .listItem)
                return
            }
            if block?.kind == .quote { flush() }
            extend(lineRange, as: block?.kind ?? .prose)
        }
        flush()
        return spans
    }

    public static func paragraph(at offset: Int, in text: String) -> TextSpan? {
        paragraphs(in: text).first { $0.holds(offset) }
    }

    /// The Sentences of `paragraph`, which must come from `paragraphs(in: text)`.
    public static func sentences(in paragraph: TextSpan, of text: String) -> [TextSpan] {
        let ns = text as NSString
        let source = ns.substring(with: NSRange(location: paragraph.range.lowerBound, length: paragraph.range.count))
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = source

        var ranges: [Range<Int>] = []
        for token in tokenizer.tokens(for: source.startIndex..<source.endIndex) {
            let local = NSRange(token, in: source)
            let range = (paragraph.range.lowerBound + local.location)..<(paragraph.range.lowerBound + NSMaxRange(local))
            let piece = clean(String(source[token]))
            // The tokenizer splits after a quoted exclamation ("'Stop!' and left."); a piece starting
            // in lowercase continues the previous Sentence.
            if let previous = ranges.last, piece.first?.isLowercase == true {
                ranges[ranges.count - 1] = previous.lowerBound..<range.upperBound
            } else {
                ranges.append(range)
            }
        }
        return ranges.compactMap { range in
            let prose = clean(ns.substring(with: NSRange(location: range.lowerBound, length: range.count)))
            return prose.isEmpty ? nil : TextSpan(range: range, text: prose)
        }
    }

    public static func sentence(at offset: Int, in text: String) -> (sentence: TextSpan, paragraph: TextSpan)? {
        guard let paragraph = paragraph(at: offset, in: text) else { return nil }
        let sentences = sentences(in: paragraph, of: text)
        guard let sentence = sentences.first(where: { $0.range.contains(offset) }) ?? sentences.last(where: { $0.holds(offset) })
        else { return nil }
        return (sentence, paragraph)
    }

    public static func wordCount(of text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    // MARK: Markdown syntax

    private enum BlockKind {
        case prose, quote, listItem
    }

    private static func isHeading(_ line: String) -> Bool {
        line.wholeMatch(of: /#{1,6}(\s.*)?/) != nil
    }

    private static func isRule(_ line: String) -> Bool {
        line.wholeMatch(of: /([-*_])(\s*\1){2,}/) != nil
    }

    private static func listMarker(in line: String) -> Range<String.Index>? {
        line.prefixMatch(of: /([-*+]|\d{1,9}[.)])\s+/)?.range
    }

    private static func stripQuote(_ line: String) -> String {
        var rest = Substring(line)
        while rest.first == ">" {
            rest = rest.dropFirst().drop { $0 == " " }
        }
        return String(rest)
    }

    /// Removes block markers from each line and joins the lines into running prose.
    static func clean(_ source: String) -> String {
        source
            .split(whereSeparator: \.isNewline)
            .map { line -> String in
                var content = stripQuote(line.trimmingCharacters(in: .whitespaces))
                if let marker = listMarker(in: content) { content.removeSubrange(marker) }
                return content.trimmingCharacters(in: .whitespaces)
            }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
