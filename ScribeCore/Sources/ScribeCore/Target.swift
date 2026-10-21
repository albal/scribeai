/// The writing standard a Document is judged against.
public struct Target: Identifiable, Equatable, Hashable, Sendable, Codable {
    public enum Kind: String, Sendable, Codable {
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

    public var isBuiltIn: Bool { kind != .custom }
}

/// The Levels and Publications shipped with ScribeAI. Their Style Briefs are read-only.
public enum BuiltInTargets {
    public static let middleGrade = Target(
        id: "level.middle-grade",
        name: "Middle Grade",
        kind: .level,
        styleBrief: """
            Fiction for readers aged 8–12. Short, clear sentences (often under 15 words) with simple syntax; \
            dialogue carries much of the story. Concrete, familiar vocabulary, with the occasional rich word \
            whose meaning is clear from context. A close, energetic narrative voice; feelings are named plainly. \
            Brisk pacing with short paragraphs and frequent scene breaks. Avoid: long descriptive passages, \
            irony that depends on adult experience, abstract reflection, mature content, and condescension.
            """
    )

    public static let youngAdult = Target(
        id: "level.young-adult",
        name: "Young Adult",
        kind: .level,
        styleBrief: """
            Fiction for readers aged 13–18, usually told close to a teenage narrator, often in first person \
            and present tense. Immediate, voice-driven prose with emotional honesty and urgency. Sentences vary \
            but stay readable; contemporary but not slang-heavy vocabulary. Interior thought is frequent and \
            direct. Fast pacing; every scene raises stakes. Avoid: adult nostalgia looking back on youth, \
            moralising, dated slang, lengthy exposition, and over-ornate description.
            """
    )

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

    public static let academic = Target(
        id: "level.academic",
        name: "Academic",
        kind: .level,
        styleBrief: """
            Scholarly prose for specialist readers. Precise, formal register; claims are qualified and \
            supported, and terms are used consistently once defined. Longer sentences are acceptable when \
            they carry logical structure (because, therefore, whereas). Impersonal or measured first person. \
            Paragraphs open with a claim and develop it. Avoid: colloquialisms, contractions, emotive or \
            sensational language, unsupported generalisations, rhetorical flourish, and vague hedging that \
            commits to nothing.
            """
    )

    public static let literaryFiction = Target(
        id: "level.literary-fiction",
        name: "High Literary Fiction",
        kind: .level,
        styleBrief: """
            Ambitious literary prose in which language is itself a subject. Sentences may be long and \
            rhythmically complex, or pointedly spare; every word is chosen. Original, precise imagery; \
            subtext over statement; a distinctive narrative voice and close attention to consciousness. \
            Ambiguity is welcome when deliberate. Avoid: cliché and stock phrases, telling the reader what \
            to feel, genre shortcuts, filler, and ornament that doesn't earn its place.
            """
    )

    public static let economist = Target(
        id: "publication.economist",
        name: "The Economist",
        kind: .publication,
        styleBrief: """
            Crisp, authoritative analysis written in an anonymous, collective voice ("we" for the paper's \
            view). Short words and short sentences; plain English over jargon; numbers used to make points. \
            Dry wit and the occasional pun are welcome; confident argument with a clear line. British spelling. \
            Avoid: the first-person "I", hype, clichés, unexplained acronyms, needless qualifiers, the passive \
            voice where the active will do, and any word longer than it needs to be.
            """
    )

    public static let wired = Target(
        id: "publication.wired",
        name: "Wired",
        kind: .publication,
        styleBrief: """
            Smart, energetic writing about technology and its effect on culture, business and people. \
            Conversational yet informed; vivid, specific detail and scene-setting ledes. Technical ideas \
            explained through concrete examples and analogies without dumbing down. Strong verbs, a point of \
            view, a sense of what's at stake for the future. American spelling. Avoid: press-release tone, \
            unexplained jargon, breathless hype without evidence, dry academic hedging, and long throat-clearing \
            intros.
            """
    )

    public static let newYorker = Target(
        id: "publication.new-yorker",
        name: "The New Yorker",
        kind: .publication,
        styleBrief: """
            Elegant, literate long-form prose with a curious, discursive, often wry voice. Sentences are \
            polished and varied, rich in precise detail and reported observation; digressions are welcome \
            when they illuminate. Sophisticated vocabulary used exactly, never for show. Formal punctuation \
            and grammar; understatement over emphasis. Avoid: colloquial shorthand, slang, exclamation marks, \
            listicle structure, overt opinion-shouting, and anything that reads as rushed.
            """
    )

    public static let nature = Target(
        id: "publication.nature",
        name: "Nature",
        kind: .publication,
        styleBrief: """
            Clear, concise scientific writing for a broad scientific readership beyond the specialist field. \
            State the finding first, then the evidence and its significance. Short sentences, active voice \
            ("we show"), precise quantitative claims with appropriate caution. Define technical terms and \
            abbreviations at first use. Avoid: overstatement ("prove", "breakthrough"), unexplained jargon, \
            long nested clauses, rhetorical or literary flourish, and speculation presented as result.
            """
    )

    public static let levels: [Target] = [middleGrade, youngAdult, accessibleMainstream, academic, literaryFiction]
    public static let publications: [Target] = [economist, wired, newYorker, nature]
    public static let all: [Target] = levels + publications

    public static let `default` = accessibleMainstream
}

/// Every Target available to a Document, and resolution of a stored Target id.
public struct TargetCatalog: Sendable {
    public var custom: [Target]

    public init(custom: [Target] = []) {
        self.custom = custom
    }

    public var all: [Target] { BuiltInTargets.all + custom }

    public func target(id: String) -> Target? {
        all.first { $0.id == id }
    }

    public struct Resolution: Equatable, Sendable {
        public let target: Target
        /// Set when a stored id matched no Target and the default was used instead.
        public let unknownID: String?
    }

    /// The Target for a Document whose front matter names `storedID`, falling back to the default.
    public func resolve(storedID: String?, defaultID: String?) -> Resolution {
        let fallback = defaultID.flatMap(target(id:)) ?? BuiltInTargets.default
        guard let storedID else { return Resolution(target: fallback, unknownID: nil) }
        if let found = target(id: storedID) { return Resolution(target: found, unknownID: nil) }
        return Resolution(target: fallback, unknownID: storedID)
    }
}
