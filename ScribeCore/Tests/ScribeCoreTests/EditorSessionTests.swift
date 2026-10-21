import Foundation
import Testing
@testable import ScribeCore

@MainActor
struct EditorSessionTests {
    let clock = ManualClock()
    let model = FakeModelClient()

    func makeSession() -> EditorSession {
        EditorSession(model: model, clock: clock)
    }

    static let twoParagraphs = """
        The first paragraph sits here, quiet and unassuming, waiting for a reader who may never come along.

        The second paragraph is where the cursor rests, blinking patiently at the end of a long line.
        """

    @Test func gaugesAreEmptyBeforeTheFirstEvaluation() {
        let session = makeSession()
        #expect(session.readings == nil)
        #expect(session.status == .idle)
    }

    @Test func nothingIsEvaluatedBeforeTheWriterPausesForTwoSeconds() async {
        let session = makeSession()
        session.textDidChange(long("Some words being typed."), cursor: 5)
        #expect(session.status == .pending)

        await clock.advance(by: .milliseconds(1999))
        #expect(model.prompts.isEmpty)
        #expect(session.readings == nil)
    }

    @Test func theParagraphUnderTheCursorIsEvaluatedAfterAPause() async {
        let session = makeSession()
        let cursor = (Self.twoParagraphs as NSString).length
        session.textDidChange(Self.twoParagraphs, cursor: cursor)

        await clock.advance(by: .seconds(2))
        #expect(await waitUntil { session.readings != nil })

        #expect(session.readings == .sample)
        #expect(session.status == .idle)
        #expect(model.prompts.count == 1)
        let prompt = model.prompts.first?.user ?? ""
        #expect(prompt.contains("The second paragraph is where the cursor rests, blinking patiently at the end of a long line."))
        #expect(!prompt.contains("The first paragraph"))
    }

    @Test func eachKeystrokeRestartsThePause() async {
        let session = makeSession()
        session.textDidChange(long("Typing"), cursor: 6)
        await clock.advance(by: .seconds(1.5))
        session.textDidChange(long("Typing on"), cursor: 9)
        await clock.advance(by: .seconds(1.5))
        #expect(model.prompts.isEmpty)

        await clock.advance(by: .seconds(0.5))
        #expect(await waitUntil { model.prompts.count == 1 })
        #expect(model.prompts.first?.user.contains("Typing on") == true)
    }

    @Test func theEvaluationIsMeasuredAgainstTheTargetsStyleBrief() async {
        let session = makeSession()
        session.textDidChange(long("A sentence to judge."), cursor: 0)
        await clock.advance(by: .seconds(2))
        #expect(await waitUntil { model.prompts.count == 1 })

        let prompt = model.prompts.first?.user ?? ""
        #expect(prompt.contains(BuiltInTargets.default.name))
        #expect(prompt.contains(BuiltInTargets.default.styleBrief))
    }

    @Test func aFailedEvaluationIsReportedAndShowsNoReadings() async {
        model.enqueue(.failure(EvaluationFailure.invalidOutput))
        let session = makeSession()
        session.textDidChange(long("A sentence to judge."), cursor: 0)
        await clock.advance(by: .seconds(2))

        #expect(await waitUntil { if case .failed = session.status { true } else { false } })
        #expect(session.readings == nil)
    }

    @Test func aFailedEvaluationIsRetriedOnTheNextPause() async {
        model.enqueue(.failure(EvaluationFailure.ollamaNotRunning))
        let session = makeSession()
        session.textDidChange(long("A sentence to judge."), cursor: 0)
        await clock.advance(by: .seconds(2))
        #expect(await waitUntil { session.status == .failed(.ollamaNotRunning) })

        session.textDidChange(long("A sentence to judge again."), cursor: 0)
        await clock.advance(by: .seconds(2))
        #expect(await waitUntil { session.readings == .sample })
        #expect(session.status == .idle)
    }

    @Test func aCursorOnABlankLineEvaluatesNothing() async {
        let session = makeSession()
        session.textDidChange(long("Para one.\n\n\n\nPara two."), cursor: 10)
        await clock.advance(by: .seconds(2))
        #expect(await waitUntil { session.status == .idle })
        #expect(model.prompts.isEmpty)
    }

    @Test func wordCountCountsWhitespaceSeparatedWords() {
        let session = makeSession()
        session.textDidChange("One two  three\nfour", cursor: 0)
        #expect(session.wordCount == 4)
    }
}
