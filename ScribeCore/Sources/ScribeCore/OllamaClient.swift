import Foundation

/// Talks to a local Ollama server.
public struct OllamaClient: ModelClient {
    public static let defaultBaseURL = URL(string: "http://localhost:11434")!
    public static let defaultModel = "gemma3:12b"

    /// Large enough for a Document Scope chunk plus its prompt.
    static let contextWindow = 8192

    public let baseURL: URL
    public let model: String
    let session: URLSession

    public init(baseURL: URL = defaultBaseURL, model: String = defaultModel, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.model = model
        self.session = session
    }

    // MARK: Status

    public func status() async -> ModelStatus {
        do {
            let (data, _) = try await session.data(from: baseURL.appending(path: "api/tags"))
            let tags = try JSONDecoder().decode(TagsResponse.self, from: data)
            let wanted = Self.normalised(model)
            return tags.models.contains { Self.normalised($0.name) == wanted } ? .ready : .modelMissing
        } catch {
            return .ollamaNotRunning
        }
    }

    /// Ollama treats "llama3.2" and "llama3.2:latest" as the same model.
    static func normalised(_ name: String) -> String {
        name.contains(":") ? name : name + ":latest"
    }

    struct TagsResponse: Decodable {
        struct Model: Decodable { let name: String }
        let models: [Model]
    }

    // MARK: Pull

    public func pull() -> AsyncThrowingStream<PullProgress, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: baseURL.appending(path: "api/pull"))
                    request.httpMethod = "POST"
                    request.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "stream": true])
                    let (bytes, response) = try await session.bytes(for: request)
                    try Self.check(response)
                    var layers = PullLayers()
                    for try await line in bytes.lines where !line.isEmpty {
                        let event = try JSONDecoder().decode(PullEvent.self, from: Data(line.utf8))
                        if let error = event.error { throw OllamaError.pullFailed(error) }
                        if event.status == "success" {
                            continuation.yield(PullProgress(status: "success", fraction: 1))
                            break
                        }
                        layers.record(event)
                        continuation.yield(PullProgress(status: event.status ?? "", fraction: layers.fraction))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.mapCancellation(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    struct PullEvent: Decodable {
        let status: String?
        let digest: String?
        let total: Int64?
        let completed: Int64?
        let error: String?
    }

    /// Ollama reports progress per layer; the bar shows progress across all of them.
    struct PullLayers {
        private var totals: [String: Int64] = [:]
        private var completed: [String: Int64] = [:]

        mutating func record(_ event: PullEvent) {
            guard let digest = event.digest, let total = event.total else { return }
            totals[digest] = total
            completed[digest] = event.completed ?? completed[digest] ?? 0
        }

        var fraction: Double? {
            let total = totals.values.reduce(0, +)
            guard total > 0 else { return nil }
            return Double(completed.values.reduce(0, +)) / Double(total)
        }
    }

    // MARK: Evaluate

    /// JSON schema passed in `format` so Ollama constrains the output.
    static var readingsSchema: [String: Any] { [
        "type": "object",
        "properties": [
            "alignment_score": ["type": "integer", "minimum": 0, "maximum": 100],
            "concision": ["type": "integer", "minimum": 0, "maximum": 100],
            "intensity": ["type": "integer", "minimum": 0, "maximum": 100],
            "tone": ["type": "string", "enum": Tone.allCases.map(\.rawValue)],
        ],
        "required": ["alignment_score", "concision", "intensity", "tone"],
    ] }

    public func evaluate(_ prompt: EvaluationPrompt) async throws -> Readings {
        let body: [String: Any] = [
            "model": model,
            "stream": false,
            "format": Self.readingsSchema,
            "options": ["temperature": 0.2, "num_ctx": Self.contextWindow],
            "messages": [
                ["role": "system", "content": prompt.system],
                ["role": "user", "content": prompt.user],
            ],
        ]
        var request = URLRequest(url: baseURL.appending(path: "api/chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        do {
            let (body, response) = try await session.data(for: request)
            try Self.check(response)
            data = body
        } catch {
            throw Self.mapFailure(error)
        }
        guard let chat = try? JSONDecoder().decode(ChatResponse.self, from: data) else {
            throw EvaluationFailure.invalidOutput
        }
        return try Self.readings(fromContent: chat.message.content)
    }

    static func readings(fromContent content: String) throws(EvaluationFailure) -> Readings {
        guard let raw = try? JSONDecoder().decode(RawReadings.self, from: Data(content.utf8)),
              let tone = Tone(rawValue: raw.tone.lowercased()),
              let readings = try? Readings(
                  alignmentScore: raw.alignment_score, concision: raw.concision, intensity: raw.intensity, tone: tone
              )
        else { throw .invalidOutput }
        return readings
    }

    struct ChatResponse: Decodable {
        struct Message: Decodable { let content: String }
        let message: Message
    }

    struct RawReadings: Decodable {
        let alignment_score: Int
        let concision: Int
        let intensity: Int
        let tone: String
    }

    // MARK: Critique

    public func critique(_ prompt: CritiquePrompt) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let body: [String: Any] = [
                        "model": model,
                        "stream": true,
                        "options": ["temperature": 0.4, "num_ctx": Self.contextWindow],
                        "messages": [
                            ["role": "system", "content": prompt.system],
                            ["role": "user", "content": prompt.user],
                        ],
                    ]
                    var request = URLRequest(url: baseURL.appending(path: "api/chat"))
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)
                    let (bytes, response) = try await session.bytes(for: request)
                    try Self.check(response)
                    for try await line in bytes.lines where !line.isEmpty {
                        let chunk = try JSONDecoder().decode(ChatChunk.self, from: Data(line.utf8))
                        if let error = chunk.error { throw EvaluationFailure.other(error) }
                        if let content = chunk.message?.content, !content.isEmpty { continuation.yield(content) }
                        if chunk.done == true { break }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.mapFailure(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    struct ChatChunk: Decodable {
        struct Message: Decodable { let content: String }
        let message: Message?
        let done: Bool?
        let error: String?
    }

    // MARK: Errors

    static func check(_ response: URLResponse) throws {
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw OllamaError.httpStatus(http.statusCode)
        }
    }

    static func mapCancellation(_ error: any Error) -> any Error {
        (error as? URLError)?.code == .cancelled ? CancellationError() : error
    }

    static func mapFailure(_ error: any Error) -> any Error {
        if error is CancellationError || error is EvaluationFailure { return error }
        switch error {
        case let error as URLError where error.code == .cancelled:
            return CancellationError()
        case let error as URLError where [.cannotConnectToHost, .networkConnectionLost, .cannotFindHost, .timedOut].contains(error.code):
            return EvaluationFailure.ollamaNotRunning
        case OllamaError.httpStatus(404):
            return EvaluationFailure.modelMissing
        default:
            return EvaluationFailure.other(String(describing: error))
        }
    }
}

public enum OllamaError: Error, Equatable {
    case httpStatus(Int)
    case pullFailed(String)
}
