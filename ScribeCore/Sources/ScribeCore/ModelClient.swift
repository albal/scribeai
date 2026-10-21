/// The single boundary between ScribeCore and the LLM. Tests replace it with a fake.
public protocol ModelClient: Sendable {
    func evaluate(_ prompt: EvaluationPrompt) async throws -> Readings
}
