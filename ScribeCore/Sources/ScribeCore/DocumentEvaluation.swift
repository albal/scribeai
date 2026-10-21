/// The state of an on-request Evaluation of the whole Document.
public struct DocumentEvaluation: Equatable, Sendable {
    public internal(set) var completedChunks = 0
    public let totalChunks: Int
    public internal(set) var readings: Readings?
    public internal(set) var failure: EvaluationFailure?
    /// The text and Target the Readings describe.
    let evaluatedText: String
    let evaluatedTarget: Target

    public var isRunning: Bool { readings == nil && failure == nil }
}

/// Splits a Document into chunks for Document Scope and combines their Readings.
public enum DocumentChunker {
    /// Comfortably inside an 8k-token context once the prompt and Style Brief are added.
    public static let maximumWords = 1200

    /// Consecutive Paragraphs grouped up to `maximumWords`. A Paragraph is never split, so one longer
    /// than the limit becomes a chunk on its own.
    public static func chunks(of text: String, maximumWords: Int = maximumWords) -> [String] {
        var chunks: [String] = []
        var current: [String] = []
        var words = 0
        for paragraph in MarkdownSegmenter.paragraphs(in: text) {
            let count = MarkdownSegmenter.wordCount(of: paragraph.text)
            if !current.isEmpty, words + count > maximumWords {
                chunks.append(current.joined(separator: "\n\n"))
                current = []
                words = 0
            }
            current.append(paragraph.text)
            words += count
        }
        if !current.isEmpty { chunks.append(current.joined(separator: "\n\n")) }
        return chunks
    }

    /// Word-weighted averages for the scored Gauges; the Tone covering the most words, with ties
    /// going to whichever Tone appears first in the Document.
    public static func combine(_ parts: [(readings: Readings, words: Int)]) -> Readings? {
        let total = parts.reduce(0) { $0 + $1.words }
        guard total > 0 else { return nil }

        func average(_ value: (Readings) -> Int) -> Int {
            let weighted = parts.reduce(0.0) { $0 + Double(value($1.readings) * $1.words) }
            return Int((weighted / Double(total)).rounded())
        }

        var toneWords: [Tone: Int] = [:]
        var firstSeen: [Tone] = []
        for part in parts {
            if toneWords[part.readings.tone] == nil { firstSeen.append(part.readings.tone) }
            toneWords[part.readings.tone, default: 0] += part.words
        }
        let most = toneWords.values.max() ?? 0
        let tone = firstSeen.first { toneWords[$0] == most } ?? .neutral

        return try? Readings(
            alignmentScore: average(\.alignmentScore),
            concision: average(\.concision),
            intensity: average(\.intensity),
            tone: tone
        )
    }
}
