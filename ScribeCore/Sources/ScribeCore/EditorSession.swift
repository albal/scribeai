import Observation

public enum EvaluationStatus: Equatable, Sendable {
    /// Readings (if any) describe the text under the cursor.
    case idle
    /// Waiting for the writer to pause; any Readings shown are stale.
    case pending
    /// An Evaluation is running; any Readings shown are stale.
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

    /// Identifies an Evaluation: the same text against the same Target always gets the same Readings.
    private struct EvaluationKey: Hashable {
        let text: String
        let target: Target
    }

    @ObservationIgnored private var cache: [EvaluationKey: Readings] = [:]
    /// What the shown Readings describe.
    @ObservationIgnored private var shownKey: EvaluationKey?
    /// What is waiting for a pause or being evaluated.
    @ObservationIgnored private var pendingKey: EvaluationKey?

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

    /// The writer edited the text.
    public func textDidChange(_ text: String, cursor: Int) {
        self.text = text
        self.cursor = cursor
        refresh()
    }

    /// The Gauges follow the cursor to whatever text it's in.
    public func cursorDidMove(to cursor: Int) {
        self.cursor = cursor
        refresh()
    }

    /// Evaluate what's under the cursor, e.g. when a Document is opened or the model changes.
    public func scheduleEvaluation() {
        pendingKey = nil
        shownKey = nil
        refresh()
    }

    private var currentKey: EvaluationKey? {
        MarkdownSegmenter.paragraph(at: cursor, in: text).map { EvaluationKey(text: $0.text, target: target) }
    }

    private func refresh() {
        guard let key = currentKey else {
            cancelPending()
            status = .idle
            return
        }
        if key == shownKey, status == .idle { return }
        if let cached = cache[key] {
            cancelPending()
            show(cached, for: key)
            return
        }
        if key == pendingKey { return }
        schedule(key)
    }

    private func schedule(_ key: EvaluationKey) {
        task?.cancel()
        pendingKey = key
        status = .pending
        let sleep = pause(on: clock, for: Self.pauseInterval)
        task = Task {
            do {
                try await sleep()
            } catch {
                return
            }
            await self.evaluate(key)
        }
    }

    private func cancelPending() {
        task?.cancel()
        task = nil
        pendingKey = nil
    }

    private func show(_ readings: Readings, for key: EvaluationKey) {
        self.readings = readings
        shownKey = key
        status = .idle
    }

    private func evaluate(_ key: EvaluationKey) async {
        status = .evaluating
        let prompt = PromptBuilder.evaluation(of: key.text, target: key.target)
        do {
            let result = try await model.evaluate(prompt)
            guard !Task.isCancelled else { return }
            cache[key] = result
            pendingKey = nil
            show(result, for: key)
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            pendingKey = nil
            status = .failed(error as? EvaluationFailure ?? .other(String(describing: error)))
        }
    }
}
