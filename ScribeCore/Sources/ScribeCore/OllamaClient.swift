import Foundation

/// Talks to a local Ollama server.
public struct OllamaClient: ModelClient {
    public static let defaultBaseURL = URL(string: "http://localhost:11434")!
    public static let defaultModel = "llama3.1:8b"

    public let baseURL: URL
    public let model: String
    let session: URLSession

    public init(baseURL: URL = defaultBaseURL, model: String = defaultModel, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.model = model
        self.session = session
    }

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
            "options": ["temperature": 0.2],
            "messages": [
                ["role": "system", "content": prompt.system],
                ["role": "user", "content": prompt.user],
            ],
        ]
        var request = URLRequest(url: baseURL.appending(path: "api/chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw OllamaError.httpStatus(http.statusCode)
        }
        let chat = try JSONDecoder().decode(ChatResponse.self, from: data)
        return try Self.readings(fromContent: chat.message.content)
    }

    static func readings(fromContent content: String) throws -> Readings {
        guard let raw = try? JSONDecoder().decode(RawReadings.self, from: Data(content.utf8)),
              let tone = Tone(rawValue: raw.tone.lowercased())
        else { throw OllamaError.invalidOutput }
        do {
            return try Readings(alignmentScore: raw.alignment_score, concision: raw.concision, intensity: raw.intensity, tone: tone)
        } catch {
            throw OllamaError.invalidOutput
        }
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
}

public enum OllamaError: Error, Equatable {
    case httpStatus(Int)
    case invalidOutput
}
