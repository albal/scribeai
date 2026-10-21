import Foundation
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

/// How much text the writer wants evaluated. A Selection of two or more words overrides it.
public enum Scope: String, CaseIterable, Identifiable, Sendable {
    case sentence, paragraph, document

    public var id: Self { self }
    public var name: String { rawValue.capitalized }
}

/// The editor's view of ScribeCore: feed it text, cursor and Target; observe Readings.
@MainActor @Observable
public final class EditorSession {
    public static let pauseInterval: Duration = .seconds(2)

    public private(set) var text: String
    public private(set) var cursor: Int
    public private(set) var selection: Range<Int>
    public private(set) var readings: Readings?
    public private(set) var status: EvaluationStatus = .idle
    public var target: Target
    public var scope: Scope = .paragraph {
        didSet { refresh() }
    }

    /// The Scope actually being evaluated, nil when nothing under the cursor can be.
    public private(set) var activeUnit: EvaluationUnit?

    public var isSelectionActive: Bool {
        if case .selection = activeUnit { true } else { false }
    }

    public var wordCount: Int { MarkdownSegmenter.wordCount(of: text) }

    /// Replaceable, e.g. when the model setting changes.
    @ObservationIgnored public var model: any ModelClient
    @ObservationIgnored private let startPause: PauseStarter
    @ObservationIgnored private var task: Task<Void, Never>?

    /// Identifies an Evaluation: the same text against the same Target always gets the same Readings.
    private struct EvaluationKey: Hashable {
        let unit: EvaluationUnit
        let target: Target
    }

    @ObservationIgnored private var cache: [EvaluationKey: Readings] = [:]
    /// What the shown Readings describe.
    @ObservationIgnored private var shownKey: EvaluationKey?
    /// What is waiting for a pause or being evaluated.
    @ObservationIgnored private var pendingKey: EvaluationKey?

    public convenience init(
        text: String = "",
        cursor: Int = 0,
        target: Target = BuiltInTargets.default,
        model: any ModelClient
    ) {
        self.init(text: text, cursor: cursor, target: target, model: model, clock: ContinuousClock())
    }

    public init<C: Clock<Duration>>(
        text: String = "",
        cursor: Int = 0,
        target: Target = BuiltInTargets.default,
        model: any ModelClient,
        clock: C
    ) {
        self.text = text
        self.cursor = cursor
        self.selection = cursor..<cursor
        self.target = target
        self.model = model
        self.startPause = pauseStarter(on: clock)
    }

    /// The writer edited the text.
    public func textDidChange(_ text: String, selection: Range<Int>) {
        self.text = text
        select(selection)
    }

    public func textDidChange(_ text: String, cursor: Int) {
        textDidChange(text, selection: cursor..<cursor)
    }

    /// The Gauges follow the cursor and Selection to whatever text they're in.
    public func selectionDidChange(_ selection: Range<Int>) {
        select(selection)
    }

    public func cursorDidMove(to cursor: Int) {
        select(cursor..<cursor)
    }

    private func select(_ selection: Range<Int>) {
        self.selection = selection
        cursor = selection.lowerBound
        refresh()
    }

    /// Evaluate what's under the cursor, e.g. when a Document is opened or the model changes.
    public func scheduleEvaluation() {
        pendingKey = nil
        shownKey = nil
        refresh()
    }

    private var currentUnit: EvaluationUnit? {
        if !selection.isEmpty {
            let ns = text as NSString
            let clamped = selection.clamped(to: 0..<ns.length)
            let selected = ns.substring(with: NSRange(location: clamped.lowerBound, length: clamped.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if MarkdownSegmenter.wordCount(of: selected) >= 2 { return .selection(selected) }
        }
        switch scope {
        case .paragraph:
            guard let paragraph = MarkdownSegmenter.paragraph(at: cursor, in: text),
                  MarkdownSegmenter.wordCount(of: paragraph.text) >= MarkdownSegmenter.minimumParagraphWords
            else { return nil }
            return .paragraph(paragraph.text)
        case .sentence:
            guard let (sentence, paragraph) = MarkdownSegmenter.sentence(at: cursor, in: text),
                  MarkdownSegmenter.wordCount(of: sentence.text) >= MarkdownSegmenter.minimumSentenceWords
            else { return nil }
            return .sentence(sentence.text, paragraph: paragraph.text)
        case .document:
            return nil
        }
    }

    private func refresh() {
        activeUnit = currentUnit
        guard let unit = activeUnit else {
            // Too little text, or not prose: the Gauges show an empty state, not old Readings.
            cancelPending()
            readings = nil
            shownKey = nil
            status = .idle
            return
        }
        let key = EvaluationKey(unit: unit, target: target)
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
        let sleep = startPause(Self.pauseInterval)
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
        let prompt = PromptBuilder.evaluation(of: key.unit, target: key.target)
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
