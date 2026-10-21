import Foundation
import Testing
@testable import ScribeCore

@MainActor
struct StaleAndCacheTests {
    let clock = ManualClock()
    let model = FakeModelClient()

    static let text = """
        The first paragraph sits here, quiet and unassuming.

        The second paragraph is where the cursor rests.
        """
    static let firstParagraph = 10
    static let secondParagraph = (text as NSString).length - 5

    func makeSession() -> EditorSession {
        EditorSession(model: model, clock: clock)
    }

    /// Types `text`, pauses, and waits for the resulting Readings.
    func evaluate(_ session: EditorSession, _ text: String, cursor: Int) async {
        session.textDidChange(text, cursor: cursor)
        await clock.advance(by: EditorSession.pauseInterval)
        _ = await waitUntil { session.status == .idle && session.readings != nil }
    }

    @Test func typingDuringAnEvaluationCancelsItAndItsResultIsNeverShown() async throws {
        let session = makeSession()
        model.hold()
        model.enqueue(.success(try Readings(alignmentScore: 10, concision: 10, intensity: 10, tone: .urgent)))
        session.textDidChange("A first draft of the line.", cursor: 0)
        await clock.advance(by: EditorSession.pauseInterval)
        #expect(await waitUntil { model.heldCount == 1 })
        #expect(session.status == .evaluating)

        session.textDidChange("A second draft of the line.", cursor: 0)
        #expect(await waitUntil { model.cancellations == 1 })
        #expect(session.status == .pending)
        #expect(session.readings == nil)

        model.release()
        await clock.advance(by: EditorSession.pauseInterval)
        #expect(await waitUntil { session.readings == .sample })
        #expect(model.prompts.last?.user.contains("A second draft of the line.") == true)
    }

    @Test func previousReadingsStayVisibleButStaleUntilTheNextEvaluation() async {
        let session = makeSession()
        await evaluate(session, "A first draft of the line.", cursor: 0)
        #expect(session.readings == .sample)

        model.hold()
        session.textDidChange("A changed draft of the line.", cursor: 0)
        #expect(session.status == .pending)
        #expect(session.readings == .sample)

        await clock.advance(by: EditorSession.pauseInterval)
        #expect(await waitUntil { session.status == .evaluating })
        #expect(session.readings == .sample)
        model.release()
        #expect(await waitUntil { session.status == .idle })
    }

    @Test func movingToAnotherParagraphSchedulesAnEvaluationForIt() async {
        let session = makeSession()
        await evaluate(session, Self.text, cursor: Self.firstParagraph)
        #expect(model.prompts.count == 1)

        session.cursorDidMove(to: Self.secondParagraph)
        #expect(session.status == .pending)
        await clock.advance(by: EditorSession.pauseInterval)
        #expect(await waitUntil { model.prompts.count == 2 })
        #expect(model.prompts.dropFirst().first?.user.contains("The second paragraph") == true)
    }

    @Test func returningToUnchangedTextShowsCachedReadingsWithoutCallingTheModel() async throws {
        let first = try Readings(alignmentScore: 90, concision: 80, intensity: 20, tone: .formal)
        let second = try Readings(alignmentScore: 50, concision: 40, intensity: 70, tone: .casual)
        model.enqueue(.success(first))
        model.enqueue(.success(second))
        let session = makeSession()

        await evaluate(session, Self.text, cursor: Self.firstParagraph)
        session.cursorDidMove(to: Self.secondParagraph)
        await clock.advance(by: EditorSession.pauseInterval)
        #expect(await waitUntil { session.readings == second })

        session.cursorDidMove(to: Self.firstParagraph)
        #expect(session.readings == first)
        #expect(session.status == .idle)
        await clock.advance(by: .seconds(10))
        #expect(model.prompts.count == 2)
    }

    @Test func movingWithinTheSameParagraphChangesNothing() async {
        let session = makeSession()
        await evaluate(session, Self.text, cursor: Self.firstParagraph)
        session.cursorDidMove(to: Self.firstParagraph + 5)
        #expect(session.status == .idle)
        await clock.advance(by: .seconds(10))
        #expect(model.prompts.count == 1)
    }

    @Test func undoingBackToEvaluatedTextShowsItsReadingsImmediately() async {
        let session = makeSession()
        await evaluate(session, "A first draft of the line.", cursor: 0)
        session.textDidChange("A first draft of the line!", cursor: 0)
        #expect(session.status == .pending)

        session.textDidChange("A first draft of the line.", cursor: 0)
        #expect(session.status == .idle)
        #expect(model.prompts.count == 1)
    }

    @Test func theCacheIsKeyedByTarget() async {
        let session = makeSession()
        await evaluate(session, "A first draft of the line.", cursor: 0)

        session.target = Target(id: "custom.test", name: "Test", kind: .custom, styleBrief: "Short and plain.")
        session.scheduleEvaluation()
        await clock.advance(by: EditorSession.pauseInterval)
        #expect(await waitUntil { model.prompts.count == 2 })
        #expect(model.prompts.dropFirst().first?.user.contains("Short and plain.") == true)
    }

    @Test func aSelectionChangeNotificationAfterAKeystrokeDoesNotRestartThePause() async {
        let session = makeSession()
        session.textDidChange("Typing a line", cursor: 13)
        await clock.advance(by: .seconds(1.5))
        session.cursorDidMove(to: 13)
        await clock.advance(by: .seconds(0.5))
        #expect(await waitUntil { model.prompts.count == 1 })
    }
}
