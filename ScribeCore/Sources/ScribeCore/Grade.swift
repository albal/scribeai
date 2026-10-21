/// The letter shown for an Alignment Score, derived by fixed bands.
/// The model never produces a Grade.
public struct Grade: Equatable, Sendable, CustomStringConvertible {
    public let letter: String

    /// Lower bound of each band, highest first.
    static let bands: [(minimum: Int, letter: String)] = [
        (97, "A+"), (93, "A"), (90, "A−"),
        (87, "B+"), (83, "B"), (80, "B−"),
        (77, "C+"), (73, "C"), (70, "C−"),
        (67, "D+"), (63, "D"), (60, "D−"),
        (0, "F"),
    ]

    public init(score: Int) {
        letter = Self.bands.first { score >= $0.minimum }?.letter ?? "F"
    }

    public var description: String { letter }
}
