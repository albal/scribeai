/// The single boundary between ScribeCore and the LLM. Tests replace it with a fake.
public protocol ModelClient: Sendable {
    /// The model this client evaluates with.
    var model: String { get }
    /// Whether the model server is reachable and the model is present.
    func status() async -> ModelStatus
    /// Downloads the model, reporting progress until it completes.
    func pull() -> AsyncThrowingStream<PullProgress, any Error>
    func evaluate(_ prompt: EvaluationPrompt) async throws -> Readings
    /// Streams a Critique's text as the model writes it.
    func critique(_ prompt: CritiquePrompt) -> AsyncThrowingStream<String, any Error>
}

public enum ModelStatus: Equatable, Sendable {
    case ready
    case ollamaNotRunning
    case modelMissing
}

public struct PullProgress: Equatable, Sendable {
    /// What Ollama says it's doing, e.g. "pulling manifest".
    public let status: String
    /// 0–1 across all layers, or nil before sizes are known.
    public let fraction: Double?

    public init(status: String, fraction: Double?) {
        self.status = status
        self.fraction = fraction
    }
}

/// Why an Evaluation produced no Readings.
public enum EvaluationFailure: Error, Equatable, Sendable {
    case ollamaNotRunning
    case modelMissing
    case invalidOutput
    case other(String)

    public var message: String {
        switch self {
        case .ollamaNotRunning: "Ollama isn't running."
        case .modelMissing: "The model isn't downloaded."
        case .invalidOutput: "The model returned an unusable answer. It will try again when you next pause."
        case .other(let detail): "The Evaluation failed: \(detail)"
        }
    }
}
