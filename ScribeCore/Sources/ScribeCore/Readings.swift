/// The perceived register of a passage. Always exactly one of a fixed set,
/// so the model can't drift between near-synonyms.
public enum Tone: String, CaseIterable, Codable, Sendable {
    case academic, casual, formal, suspenseful, humorous, melancholic, urgent, neutral

    public var name: String { rawValue.capitalized }

    public var symbol: String {
        switch self {
        case .academic: "🧐"
        case .casual: "🤠"
        case .formal: "🎩"
        case .suspenseful: "🕵️"
        case .humorous: "😄"
        case .melancholic: "🌧️"
        case .urgent: "⏰"
        case .neutral: "😐"
        }
    }
}

/// One Reading per Gauge, produced by a single Evaluation.
public struct Readings: Equatable, Sendable {
    public static let range = 0...100

    /// How closely the text matches its Target (judging).
    public let alignmentScore: Int
    /// 100 is tight, 0 is bloated, relative to the Target (judging).
    public let concision: Int
    /// 0 is restrained, 100 is purple (describing).
    public let intensity: Int
    /// Describing.
    public let tone: Tone

    /// Fails if any value lies outside 0–100, so out-of-range model output
    /// can never be shown as a Reading.
    public init(alignmentScore: Int, concision: Int, intensity: Int, tone: Tone) throws(ReadingsError) {
        for value in [alignmentScore, concision, intensity] where !Self.range.contains(value) {
            throw .outOfRange(value)
        }
        self.alignmentScore = alignmentScore
        self.concision = concision
        self.intensity = intensity
        self.tone = tone
    }

    public var grade: Grade { Grade(score: alignmentScore) }
}

public enum ReadingsError: Error, Equatable {
    case outOfRange(Int)
}
