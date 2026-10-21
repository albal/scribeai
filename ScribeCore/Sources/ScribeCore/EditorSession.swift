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

/// The written explanation of why one Gauge shows its Reading. It diagnoses; it never rewrites.
public struct Critique: Equatable, Sendable {
    public let gauge: Gauge
    /// The Readings the writer clicked; the Critique keeps explaining these even as the text changes.
    public let readings: Readings
    /// The text the Critique describes.
    public let unit: EvaluationUnit
    /// Grows as the model writes.
    public internal(set) var text = ""
    public internal(set) var isComplete = false
    /// The text it describes has since changed.
    public internal(set) var isOutOfDate = false
    public internal(set) var failure: EvaluationFailure?
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
    /// Changing the Target evaluates again.
    public var target: Target {
        didSet { if target != oldValue { refresh() } }
    }
    public var scope: Scope = .paragraph {
        didSet { if scope != oldValue { refresh() } }
    }

    public private(set) var critique: Critique?
    /// The last on-request Evaluation of the whole Document, if any.
    public private(set) var documentEvaluation: DocumentEvaluation?

    /// The Document's text or Target has changed since its Evaluation.
    public var isDocumentEvaluationOutOfDate: Bool {
        guard let documentEvaluation else { return false }
        return documentEvaluation.evaluatedText != text || documentEvaluation.evaluatedTarget != target
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
    @ObservationIgnored private var critiqueTask: Task<Void, Never>?
    @ObservationIgnored private var critiqueID = 0
    @ObservationIgnored private var documentTask: Task<Void, Never>?
    /// Restored if a Document Evaluation is cancelled.
    @ObservationIgnored private var previousDocumentEvaluation: DocumentEvaluation?

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
        if let unit = critique?.unit {
            critique?.isOutOfDate = !describesCurrentText(unit)
        }
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

    // MARK: Critique

    /// Explains the Reading `gauge` shows. Only one model request runs at a time, and a Critique
    /// goes first: any Evaluation in progress is cancelled and resumes afterwards.
    public func requestCritique(of gauge: Gauge) {
        guard let readings, let key = shownKey else { return }
        cancelPending()
        status = currentUnit.map { EvaluationKey(unit: $0, target: target) } == shownKey ? .idle : .pending

        critiqueTask?.cancel()
        critiqueID += 1
        let id = critiqueID
        critique = Critique(gauge: gauge, readings: readings, unit: key.unit)
        let stream = model.critique(PromptBuilder.critique(of: gauge, readings: readings, unit: key.unit, target: key.target))
        critiqueTask = Task {
            do {
                for try await chunk in stream {
                    guard !Task.isCancelled else { return }
                    self.critique?.text += chunk
                }
                guard !Task.isCancelled else { return }
                self.critique?.isComplete = true
            } catch {
                guard !Task.isCancelled, !(error is CancellationError) else { return }
                self.critique?.failure = error as? EvaluationFailure ?? .other(String(describing: error))
            }
            self.critiqueDidEnd(id)
        }
    }

    public func closeCritique() {
        critiqueTask?.cancel()
        critique = nil
        critiqueDidEnd(critiqueID)
    }

    private func critiqueDidEnd(_ id: Int) {
        guard id == critiqueID else { return }
        critiqueTask = nil
        pendingKey = nil
        refresh()
    }

    private func describesCurrentText(_ unit: EvaluationUnit) -> Bool {
        if case .selection(let selected) = unit { return text.contains(selected) }
        return MarkdownSegmenter.paragraphs(in: text).contains { $0.text.contains(unit.text) }
    }

    // MARK: Document Scope

    /// Evaluates the whole Document, chunk by chunk. Document Scope never runs automatically.
    public func evaluateDocument() {
        documentTask?.cancel()
        let chunks = DocumentChunker.chunks(of: text)
        if documentEvaluation?.readings != nil { previousDocumentEvaluation = documentEvaluation }
        let previous = previousDocumentEvaluation
        documentEvaluation = DocumentEvaluation(totalChunks: chunks.count, evaluatedText: text, evaluatedTarget: target)
        let target = target
        documentTask = Task {
            while let critiqueTask = self.critiqueTask {
                await critiqueTask.value
            }
            var parts: [(readings: Readings, words: Int)] = []
            for chunk in chunks {
                do {
                    let readings = try await self.model.evaluate(PromptBuilder.evaluation(of: .chunk(chunk), target: target))
                    guard !Task.isCancelled else { return }
                    parts.append((readings, MarkdownSegmenter.wordCount(of: chunk)))
                    self.documentEvaluation?.completedChunks += 1
                } catch {
                    guard !Task.isCancelled, !(error is CancellationError) else { return }
                    self.documentEvaluation?.failure = error as? EvaluationFailure ?? .other(String(describing: error))
                    self.documentTask = nil
                    return
                }
            }
            if let combined = DocumentChunker.combine(parts) {
                self.documentEvaluation?.readings = combined
            } else {
                self.documentEvaluation = previous
            }
            self.documentTask = nil
            self.refresh()
        }
        refresh()
    }

    /// Stops a Document Evaluation; its remaining chunks are not evaluated.
    public func cancelDocumentEvaluation() {
        guard let documentTask else { return }
        documentTask.cancel()
        self.documentTask = nil
        documentEvaluation = previousDocumentEvaluation
        refresh()
    }

    // MARK: Evaluation

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
        if scope == .document, activeUnit == nil {
            // Document Scope shows the Document's Readings, and only evaluates on request.
            cancelPending()
            shownKey = nil
            readings = documentEvaluation?.readings
            status = documentTask != nil ? .evaluating : .idle
            return
        }
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
        // One model request at a time: wait for a Critique or Document Evaluation to finish.
        while let running = critiqueTask ?? documentTask {
            await running.value
            guard !Task.isCancelled else { return }
        }
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
