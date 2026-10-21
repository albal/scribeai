/// One of the four fixed at-a-glance indicators.
public enum Gauge: String, CaseIterable, Identifiable, Sendable {
    case alignment, concision, intensity, tone

    public var id: Self { self }
    public var name: String { rawValue.capitalized }

    /// Judging Gauges say good or bad relative to the Target; describing Gauges are neutral.
    public var isJudging: Bool { self == .alignment || self == .concision }

    /// The Reading this Gauge shows, in words the model and the writer both understand.
    public func describe(_ readings: Readings) -> String {
        switch self {
        case .alignment: "\(readings.alignmentScore)/100 (Grade \(readings.grade))"
        case .concision: "\(readings.concision)/100, where 100 is tight and 0 is bloated"
        case .intensity: "\(readings.intensity)/100, where 0 is restrained and 100 is purple"
        case .tone: readings.tone.name
        }
    }
}
