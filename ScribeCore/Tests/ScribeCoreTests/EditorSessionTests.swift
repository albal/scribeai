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
        The first paragraph sits here, quiet and unassuming.

        The second paragraph is where the cursor rests.
        """

    @Test func gaugesAreEmptyBeforeTheFirstEvaluation() {
        let session = makeSession()
        #expect(session.readings == nil)
        #expect(session.status == .idle)
    }

    @Test func nothingIsEvaluatedBeforeTheWriterPausesForTwoSeconds() async {
        let session = makeSession()
        session.textDidChange("Some words being typed.", cursor: 5)
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
        let prompt = model.prompts[0].user
        #expect(prompt.contains("The second paragraph is where the cursor rests."))
        #expect(!prompt.contains("The first paragraph"))
    }

    @Test func eachKeystrokeRestartsThePause() async {
        let session = makeSession()
        session.textDidChange("Typing", cursor: 6)
        await clock.advance(by: .seconds(1.5))
        session.textDidChange("Typing on", cursor: 9)
        await clock.advance(by: .seconds(1.5))
        #expect(model.prompts.isEmpty)

        await clock.advance(by: .seconds(0.5))
        #expect(await waitUntil { model.prompts.count == 1 })
        #expect(model.prompts[0].user.contains("Typing on"))
    }

    @Test func theEvaluationIsMeasuredAgainstTheTargetsStyleBrief() async {
        let session = makeSession()
        session.textDidChange("A sentence to judge.", cursor: 0)
        await clock.advance(by: .seconds(2))
        #expect(await waitUntil { model.prompts.count == 1 })

        let prompt = model.prompts[0].user
        #expect(prompt.contains(BuiltInTargets.default.name))
        #expect(prompt.contains(BuiltInTargets.default.styleBrief))
    }

    @Test func aFailedEvaluationIsReportedAndShowsNoReadings() async {
        model.enqueue(.failure(OllamaError.invalidOutput))
        let session = makeSession()
        session.textDidChange("A sentence to judge.", cursor: 0)
        await clock.advance(by: .seconds(2))

        #expect(await waitUntil { if case .failed = session.status { true } else { false } })
        #expect(session.readings == nil)
    }

    @Test func aCursorOnABlankLineEvaluatesNothing() async {
        let session = makeSession()
        session.textDidChange("Para one.\n\n\n\nPara two.", cursor: 10)
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
