import Foundation
import Testing
@testable import ScribeCore

struct OllamaClientTests {
    static let validContent = #"{"alignment_score": 81, "concision": 70, "intensity": 30, "tone": "formal"}"#
    static let prompt = EvaluationPrompt(system: "system text", user: "user text")

    func client(model: String = "llama3.1:8b", _ handler: @escaping StubURLProtocol.Handler) -> (OllamaClient, URL) {
        let (session, baseURL) = StubURLProtocol.stub(handler)
        return (OllamaClient(baseURL: baseURL, model: model, session: session), baseURL)
    }

    // MARK: Parsing Readings

    @Test func validContentBecomesReadings() throws {
        let readings = try OllamaClient.readings(fromContent: Self.validContent)
        #expect(readings == (try Readings(alignmentScore: 81, concision: 70, intensity: 30, tone: .formal)))
    }

    @Test(arguments: [
        "not json",
        #"{"alignment_score": 81, "concision": 70, "intensity": 30, "tone": "wistful"}"#,
        #"{"alignment_score": 181, "concision": 70, "intensity": 30, "tone": "formal"}"#,
        #"{"alignment_score": 81, "concision": -4, "intensity": 30, "tone": "formal"}"#,
        #"{"alignment_score": 81, "tone": "formal"}"#,
    ])
    func invalidContentIsRejected(content: String) {
        #expect(throws: EvaluationFailure.invalidOutput) {
            try OllamaClient.readings(fromContent: content)
        }
    }

    // MARK: Evaluate

    @Test func evaluationRequestUsesChatWithTheReadingsSchema() async throws {
        let (client, baseURL) = client { _ in
            .response(status: 200, body: json(["message": ["role": "assistant", "content": Self.validContent]]))
        }
        _ = try await client.evaluate(Self.prompt)

        let request = try #require(StubURLProtocol.requests(to: baseURL).first)
        #expect(request.url?.path() == "/api/chat")
        #expect(request.httpMethod == "POST")
        let body = try #require(request.jsonBody)
        #expect(body["model"] as? String == "llama3.1:8b")
        #expect(body["stream"] as? Bool == false)
        let messages = try #require(body["messages"] as? [[String: String]])
        #expect(messages == [["role": "system", "content": "system text"], ["role": "user", "content": "user text"]])
        let format = try #require(body["format"] as? [String: Any])
        #expect(Set(format["required"] as? [String] ?? []) == ["alignment_score", "concision", "intensity", "tone"])
        let tone = try #require((format["properties"] as? [String: Any])?["tone"] as? [String: Any])
        #expect(tone["enum"] as? [String] == Tone.allCases.map(\.rawValue))
    }

    @Test func anUnreachableServerIsReportedAsOllamaNotRunning() async {
        let (client, _) = client { _ in .failure(.cannotConnectToHost) }
        await #expect(throws: EvaluationFailure.ollamaNotRunning) {
            try await client.evaluate(Self.prompt)
        }
    }

    @Test func aMissingModelIsReported() async {
        let (client, _) = client { _ in .response(status: 404, body: json(["error": "model not found"])) }
        await #expect(throws: EvaluationFailure.modelMissing) {
            try await client.evaluate(Self.prompt)
        }
    }

    @Test func aMalformedResponseIsInvalidOutput() async {
        let (client, _) = client { _ in .response(status: 200, body: Data("garbage".utf8)) }
        await #expect(throws: EvaluationFailure.invalidOutput) {
            try await client.evaluate(Self.prompt)
        }
    }

    @Test func cancellingAnEvaluationThrowsCancellation() async {
        let (client, baseURL) = client { _ in .hang }
        let task = Task { try await client.evaluate(Self.prompt) }
        while StubURLProtocol.requests(to: baseURL).isEmpty { await Task.yield() }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    // MARK: Critique

    @Test func critiqueStreamsChatContent() async throws {
        let lines = [
            ["message": ["role": "assistant", "content": "The register "], "done": false],
            ["message": ["role": "assistant", "content": "is too casual."], "done": false],
            ["message": ["role": "assistant", "content": ""], "done": true],
        ]
        let body = lines.map { String(decoding: json($0), as: UTF8.self) }.joined(separator: "\n")
        let (client, baseURL) = client { _ in .response(status: 200, body: Data(body.utf8)) }

        var chunks: [String] = []
        for try await chunk in client.critique(CritiquePrompt(system: "s", user: "u")) { chunks.append(chunk) }

        #expect(chunks == ["The register ", "is too casual."])
        let request = try #require(StubURLProtocol.requests(to: baseURL).first)
        #expect(request.url?.path() == "/api/chat")
        let requestBody = try #require(request.jsonBody)
        #expect(requestBody["stream"] as? Bool == true)
        #expect(requestBody["format"] == nil)
    }

    @Test func critiqueReportsAnUnreachableServer() async {
        let (client, _) = client { _ in .failure(.cannotConnectToHost) }
        await #expect(throws: EvaluationFailure.ollamaNotRunning) {
            for try await _ in client.critique(CritiquePrompt(system: "s", user: "u")) {}
        }
    }

    // MARK: Status

    @Test(arguments: [
        ("llama3.1:8b", ["llama3.1:8b"], ModelStatus.ready),
        ("llama3.2", ["llama3.2:latest"], .ready),
        ("llama3.1:8b", ["llama3.2:latest", "qwen3:8b"], .modelMissing),
        ("llama3.1:8b", [], .modelMissing),
    ])
    func statusReportsWhetherTheModelIsPresent(model: String, installed: [String], expected: ModelStatus) async {
        let (client, baseURL) = client(model: model) { _ in
            .response(status: 200, body: json(["models": installed.map { ["name": $0] }]))
        }
        #expect(await client.status() == expected)
        #expect(StubURLProtocol.requests(to: baseURL).first?.url?.path() == "/api/tags")
    }

    @Test func statusReportsAnUnreachableServer() async {
        let (client, _) = client { _ in .failure(.cannotConnectToHost) }
        #expect(await client.status() == .ollamaNotRunning)
    }

    // MARK: Pull

    @Test func pullStreamsProgressAcrossLayers() async throws {
        let lines = [
            ["status": "pulling manifest"],
            ["status": "pulling a", "digest": "a", "total": 300, "completed": 0],
            ["status": "pulling a", "digest": "a", "total": 300, "completed": 150],
            ["status": "pulling b", "digest": "b", "total": 100, "completed": 100],
            ["status": "verifying sha256 digest"],
            ["status": "success"],
        ]
        let body = lines.map { String(decoding: json($0), as: UTF8.self) }.joined(separator: "\n")
        let (client, baseURL) = client { _ in .response(status: 200, body: Data(body.utf8)) }

        var progress: [PullProgress] = []
        for try await event in client.pull() { progress.append(event) }

        #expect(progress.map(\.fraction) == [nil, 0, 0.5, 0.625, 0.625, 1])
        #expect(progress.last?.status == "success")
        let request = try #require(StubURLProtocol.requests(to: baseURL).first)
        #expect(request.url?.path() == "/api/pull")
        #expect(request.jsonBody?["model"] as? String == "llama3.1:8b")
    }

    @Test func pullSurfacesAnErrorFromOllama() async {
        let body = String(decoding: json(["error": "pull model manifest: file does not exist"]), as: UTF8.self)
        let (client, _) = client { _ in .response(status: 200, body: Data(body.utf8)) }
        await #expect(throws: OllamaError.pullFailed("pull model manifest: file does not exist")) {
            for try await _ in client.pull() {}
        }
    }
}
