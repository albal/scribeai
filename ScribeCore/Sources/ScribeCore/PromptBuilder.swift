/// The text an Evaluation judges, by Scope.
public enum EvaluationUnit: Hashable, Sendable {
    /// A Sentence, judged with its Paragraph as context.
    case sentence(String, paragraph: String)
    case paragraph(String)
    case selection(String)

    public var text: String {
        switch self {
        case .sentence(let text, _), .paragraph(let text), .selection(let text): text
        }
    }
}

/// The messages sent to the model for one Evaluation.
public struct EvaluationPrompt: Equatable, Sendable {
    public let system: String
    public let user: String
}

public enum PromptBuilder {
    static let evaluationSystem = """
        You are an expert editor. You judge prose against a Style Brief and reply only with the requested JSON. \
        You never rewrite the text.
        """

    public static func evaluation(of unit: EvaluationUnit, target: Target) -> EvaluationPrompt {
        let tones = Tone.allCases.map(\.rawValue).joined(separator: ", ")
        let (noun, context): (String, String) = switch unit {
        case .sentence(_, let paragraph):
            ("sentence", """

                The sentence comes from this paragraph, given for context only. Score the sentence, not the paragraph:
                \"\"\"
                \(paragraph)
                \"\"\"

                """)
        case .paragraph: ("paragraph", "")
        case .selection: ("passage", "")
        }
        let user = """
            Target: \(target.name)
            Style Brief:
            \(target.styleBrief)
            \(context)
            Judge the \(noun) below against the Style Brief and score it:
            - alignment_score: 0–100, how closely the text matches the Style Brief.
            - concision: 0–100, where 100 is tight and 0 is bloated, judged relative to the Style Brief.
            - intensity: 0–100, where 0 is restrained and 100 is purple prose. Describe, don't judge.
            - tone: exactly one of \(tones).

            \(noun.capitalized):
            \"\"\"
            \(unit.text)
            \"\"\"
            """
        return EvaluationPrompt(system: evaluationSystem, user: user)
    }
}
