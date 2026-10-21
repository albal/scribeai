/// The writing standard a Document is judged against.
public struct Target: Identifiable, Equatable, Hashable, Sendable {
    public enum Kind: String, Sendable {
        case level, publication, custom
    }

    /// Stable identifier stored in a Document's front matter.
    public let id: String
    public var name: String
    public let kind: Kind
    public var styleBrief: String

    public init(id: String, name: String, kind: Kind, styleBrief: String) {
        self.id = id
        self.name = name
        self.kind = kind
        self.styleBrief = styleBrief
    }
}

public enum BuiltInTargets {
    public static let accessibleMainstream = Target(
        id: "level.accessible-mainstream",
        name: "Accessible/Mainstream",
        kind: .level,
        styleBrief: """
            Clear, engaging prose for a broad adult readership, as in bestselling commercial fiction \
            and general-interest non-fiction. Sentences average 12–20 words, varied but rarely complex. \
            Everyday vocabulary; specialist terms explained or avoided. Concrete images over abstraction. \
            Momentum matters more than ornament. Avoid: purple prose, long digressions, jargon, \
            stacked adjectives, and sentences that need rereading.
            """
    )

    public static let all: [Target] = [accessibleMainstream]

    public static let `default` = accessibleMainstream
}
