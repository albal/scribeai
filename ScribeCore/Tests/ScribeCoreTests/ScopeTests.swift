import Foundation
import Testing
@testable import ScribeCore

@MainActor
struct ScopeTests {
    let clock = ManualClock()
    let model = FakeModelClient()

    static let shortSentence = "He left."
    static let paragraph = """
        The harbour lights came on one by one as the fog rolled in. \
        Nobody on the quay noticed the boat slip its mooring and drift out past the breakwater.
        """

    func makeSession(scope: Scope = .paragraph) -> EditorSession {
        let session = EditorSession(model: model, clock: clock)
        session.scope = scope
        return session
    }

    func cursor(before needle: String, in text: String) -> Int {
        (text as NSString).range(of: needle).location + 1
    }

    func pause() async {
        await clock.advance(by: EditorSession.pauseInterval)
    }

    @Test func sentenceScopeEvaluatesTheSentenceWithItsParagraphAsContext() async throws {
        let session = makeSession(scope: .sentence)
        session.textDidChange(Self.paragraph, cursor: cursor(before: "Nobody", in: Self.paragraph))
        await pause()
        #expect(await waitUntil { model.prompts.count == 1 })

        let prompt = try #require(model.prompts.first).user
        #expect(prompt.contains("Judge the sentence below"))
        #expect(prompt.contains("given for context only"))
        #expect(prompt.contains("\"\"\"\n\(Self.paragraph)\n\"\"\""))
        #expect(prompt.hasSuffix("Sentence:\n\"\"\"\nNobody on the quay noticed the boat slip its mooring and drift out past the breakwater.\n\"\"\""))
    }

    @Test func paragraphScopeEvaluatesTheWholeParagraph() async throws {
        let session = makeSession()
        session.textDidChange(Self.paragraph, cursor: 3)
        await pause()
        #expect(await waitUntil { model.prompts.count == 1 })
        let prompt = try #require(model.prompts.first).user
        #expect(prompt.contains("Judge the paragraph below"))
        #expect(!prompt.contains("given for context only"))
    }

    @Test func changingScopeReEvaluates() async {
        let session = makeSession()
        session.textDidChange(Self.paragraph, cursor: 3)
        await pause()
        #expect(await waitUntil { session.readings != nil })

        session.scope = .sentence
        #expect(session.status == .pending)
        await pause()
        #expect(await waitUntil { model.prompts.count == 2 })
    }

    @Test func aSelectionOfTwoOrMoreWordsOverridesTheScope() async throws {
        let session = makeSession(scope: .sentence)
        let start = (Self.paragraph as NSString).range(of: "came on one").location
        session.textDidChange(Self.paragraph, selection: start..<(start + 11))
        #expect(session.isSelectionActive)
        await pause()
        #expect(await waitUntil { model.prompts.count == 1 })
        let prompt = try #require(model.prompts.first).user
        #expect(prompt.hasSuffix("Passage:\n\"\"\"\ncame on one\n\"\"\""))
    }

    @Test func aOneWordSelectionDoesNotOverrideTheScope() {
        let session = makeSession()
        session.textDidChange(Self.paragraph, selection: 4..<11)
        #expect(!session.isSelectionActive)
        #expect(session.activeUnit == .paragraph(Self.paragraph))
    }

    @Test func clearingTheSelectionReturnsToTheChosenScope() {
        let session = makeSession()
        session.textDidChange(Self.paragraph, selection: 4..<25)
        #expect(session.isSelectionActive)
        session.selectionDidChange(10..<10)
        #expect(session.activeUnit == .paragraph(Self.paragraph))
    }

    @Test func aSentenceUnderFourWordsShowsTheEmptyStateWithoutCallingTheModel() async {
        let text = "\(Self.shortSentence) Then the long afternoon stretched on without him."
        let session = makeSession(scope: .sentence)
        session.textDidChange(text, cursor: 1)
        #expect(session.activeUnit == nil)
        #expect(session.readings == nil)
        #expect(session.status == .idle)
        await pause()
        await settle()
        #expect(model.prompts.isEmpty)
    }

    @Test func aParagraphUnderFifteenWordsShowsTheEmptyState() async {
        let session = makeSession()
        session.textDidChange("Only fourteen words are here, which is one short of the paragraph minimum.", cursor: 1)
        #expect(session.activeUnit == nil)
        await pause()
        await settle()
        #expect(model.prompts.isEmpty)
    }

    @Test func movingIntoTooShortTextClearsOldReadings() async {
        let text = "# A heading\n\n\(Self.paragraph)"
        let session = makeSession()
        session.textDidChange(text, cursor: (text as NSString).length)
        await pause()
        #expect(await waitUntil { session.readings != nil })

        session.cursorDidMove(to: 3)
        #expect(session.readings == nil)
        #expect(session.status == .idle)
    }

    @Test func aCursorInACodeBlockShowsTheEmptyState() {
        let text = "\(Self.paragraph)\n\n```\nlet code = \"this is code and should never be judged as prose at all\"\n```"
        let session = makeSession()
        session.textDidChange(text, cursor: (text as NSString).length - 8)
        #expect(session.activeUnit == nil)
    }

    @Test func documentScopeNeverEvaluatesAutomatically() async {
        let session = makeSession(scope: .document)
        session.textDidChange(Self.paragraph, cursor: 3)
        await pause()
        await settle()
        #expect(model.prompts.isEmpty)
    }
}
