import Observation

public enum EvaluationStatus: Equatable, Sendable {
    /// Readings (if any) describe the current text.
    case idle
    /// Waiting for the writer to pause.
    case pending
    /// An Evaluation is running.
    case evaluating
    case failed(EvaluationFailure)
}

/// The editor's view of ScribeCore: feed it text, cursor and Target; observe Readings.
@MainActor @Observable
public final class EditorSession {
    public static let pauseInterval: Duration = .seconds(2)

    public private(set) var text: String
    public private(set) var cursor: Int
    public private(set) var readings: Readings?
    public private(set) var status: EvaluationStatus = .idle
    public var target: Target

    public var wordCount: Int { MarkdownSegmenter.wordCount(of: text) }

    /// Replaceable, e.g. when the model setting changes.
    @ObservationIgnored public var model: any ModelClient
    @ObservationIgnored private let clock: any Clock<Duration>
    @ObservationIgnored private var task: Task<Void, Never>?

    public init(
        text: String = "",
        cursor: Int = 0,
        target: Target = BuiltInTargets.default,
        model: any ModelClient,
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.text = text
        self.cursor = cursor
        self.target = target
        self.model = model
        self.clock = clock
    }

    /// The writer edited the text. Schedules an Evaluation for when they pause.
    public func textDidChange(_ text: String, cursor: Int) {
        self.text = text
        self.cursor = cursor
        scheduleEvaluation()
    }

    public func cursorDidMove(to cursor: Int) {
        self.cursor = cursor
    }

    /// Evaluate what's under the cursor after a pause, e.g. when a Document is opened.
    public func scheduleEvaluation() {
        task?.cancel()
        status = .pending
        task = Task { [clock] in
            do {
                try await clock.sleep(for: Self.pauseInterval)
            } catch {
                return
            }
            await self.evaluateCurrentScope()
        }
    }

    private func evaluateCurrentScope() async {
        guard let paragraph = MarkdownSegmenter.paragraph(at: cursor, in: text) else {
            status = .idle
            return
        }
        status = .evaluating
        let prompt = PromptBuilder.evaluation(of: paragraph.text, target: target)
        do {
            let result = try await model.evaluate(prompt)
            guard !Task.isCancelled else { return }
            readings = result
            status = .idle
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            status = .failed(error as? EvaluationFailure ?? .other(String(describing: error)))
        }
    }
}
