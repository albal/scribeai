import Foundation
import Testing
@testable import ScribeCore

struct DocumentChunkerTests {
    func paragraph(words: Int, word: String = "word") -> String {
        Array(repeating: word, count: words).joined(separator: " ") + "."
    }

    @Test func paragraphsAreGroupedUpToTheLimit() {
        let text = [paragraph(words: 40), paragraph(words: 40), paragraph(words: 40)].joined(separator: "\n\n")
        let chunks = DocumentChunker.chunks(of: text, maximumWords: 100)
        #expect(chunks.map(MarkdownSegmenter.wordCount(of:)) == [80, 40])
    }

    @Test func aParagraphIsNeverSplitEvenWhenLongerThanTheLimit() {
        let long = paragraph(words: 150, word: "long")
        let text = [paragraph(words: 10), long, paragraph(words: 10)].joined(separator: "\n\n")
        let chunks = DocumentChunker.chunks(of: text, maximumWords: 100)
        #expect(chunks.count == 3)
        #expect(chunks[1] == long)
    }

    @Test func everyParagraphLandsInExactlyOneChunk() {
        let paragraphs = (1...30).map { paragraph(words: $0 * 7, word: "p\($0)") }
        let chunks = DocumentChunker.chunks(of: paragraphs.joined(separator: "\n\n"), maximumWords: 200)
        #expect(chunks.flatMap { $0.components(separatedBy: "\n\n") } == paragraphs)
        #expect(chunks.allSatisfy { MarkdownSegmenter.wordCount(of: $0) <= 200 || !$0.contains("\n\n") })
    }

    @Test func headingsAndCodeAreLeftOut() {
        let text = "# Title\n\nProse here.\n\n```\ncode\n```"
        #expect(DocumentChunker.chunks(of: text) == ["Prose here."])
    }

    @Test func combiningWeightsScoresByWordCount() throws {
        let combined = try #require(DocumentChunker.combine([
            (try Readings(alignmentScore: 90, concision: 80, intensity: 10, tone: .formal), 300),
            (try Readings(alignmentScore: 50, concision: 40, intensity: 70, tone: .casual), 100),
        ]))
        #expect(combined.alignmentScore == 80)
        #expect(combined.concision == 70)
        #expect(combined.intensity == 25)
        #expect(combined.tone == .formal)
    }

    @Test func toneIsTheOneCoveringTheMostWords() throws {
        let combined = try #require(DocumentChunker.combine([
            (try Readings(alignmentScore: 50, concision: 50, intensity: 50, tone: .casual), 100),
            (try Readings(alignmentScore: 50, concision: 50, intensity: 50, tone: .urgent), 150),
            (try Readings(alignmentScore: 50, concision: 50, intensity: 50, tone: .casual), 100),
        ]))
        #expect(combined.tone == .casual)
    }

    @Test func aToneTieGoesToTheToneThatAppearsFirst() throws {
        let combined = try #require(DocumentChunker.combine([
            (try Readings(alignmentScore: 50, concision: 50, intensity: 50, tone: .urgent), 100),
            (try Readings(alignmentScore: 50, concision: 50, intensity: 50, tone: .academic), 100),
        ]))
        #expect(combined.tone == .urgent)
    }

    @Test func nothingToCombineGivesNoReadings() {
        #expect(DocumentChunker.combine([]) == nil)
    }
}

@MainActor
struct DocumentScopeTests {
    let clock = ManualClock()
    let model = FakeModelClient()

    static let document = """
        # A Title

        \(long("The first paragraph of the document begins here."))

        \(long("The second paragraph carries the story onward."))
        """

    func makeSession() -> EditorSession {
        let session = EditorSession(model: model, clock: clock)
        session.textDidChange(Self.document, cursor: 0)
        session.scope = .document
        return session
    }

    @Test func choosingDocumentScopeRunsNothingUntilRequested() async {
        let session = makeSession()
        await clock.advance(by: .seconds(30))
        await settle()
        #expect(model.prompts.isEmpty)
        #expect(session.readings == nil)
        #expect(session.documentEvaluation == nil)
    }

    @Test func evaluatingTheDocumentShowsCombinedReadings() async throws {
        let session = makeSession()
        session.evaluateDocument()
        #expect(session.documentEvaluation?.isRunning == true)
        #expect(session.status == .evaluating)

        #expect(await waitUntil { session.readings != nil })
        #expect(session.readings == .sample)
        #expect(session.status == .idle)
        #expect(session.documentEvaluation?.completedChunks == 1)
        let prompt = try #require(model.prompts.first).user
        #expect(prompt.contains("Judge the section below"))
        #expect(prompt.contains("The first paragraph"))
        #expect(prompt.contains("The second paragraph"))
        #expect(!prompt.contains("A Title"))
    }

    @Test func progressCountsChunksAndCancellingStopsTheRest() async {
        let paragraphs = (1...4).map { i in Array(repeating: "word\(i)", count: 1000).joined(separator: " ") }
        let session = EditorSession(model: model, clock: clock)
        session.textDidChange(paragraphs.joined(separator: "\n\n"), cursor: 0)
        session.scope = .document
        model.hold()

        session.evaluateDocument()
        #expect(session.documentEvaluation?.totalChunks == 4)
        #expect(await waitUntil { model.heldCount == 1 })
        model.release()
        #expect(await waitUntil { session.documentEvaluation?.completedChunks == 4 })
        #expect(await waitUntil { session.readings != nil })

        model.hold()
        session.evaluateDocument()
        #expect(await waitUntil { model.heldCount == 1 })
        session.cancelDocumentEvaluation()
        #expect(await waitUntil { model.cancellations == 1 })
        #expect(model.prompts.count == 5)
        #expect(session.documentEvaluation?.readings == .sample)
        model.release()
    }

    @Test func editingMarksTheDocumentReadingsOutOfDate() async {
        let session = makeSession()
        session.evaluateDocument()
        #expect(await waitUntil { session.readings != nil })
        #expect(!session.isDocumentEvaluationOutOfDate)

        session.textDidChange(Self.document + "\n\nOne more line.", cursor: 0)
        #expect(session.isDocumentEvaluationOutOfDate)
        #expect(session.readings == .sample)
    }

    @Test func changingTheTargetMarksTheDocumentReadingsOutOfDate() async {
        let session = makeSession()
        session.evaluateDocument()
        #expect(await waitUntil { session.readings != nil })
        session.target = BuiltInTargets.wired
        #expect(session.isDocumentEvaluationOutOfDate)
    }

    @Test func aFailedChunkStopsTheDocumentEvaluation() async {
        model.enqueue(.failure(EvaluationFailure.invalidOutput))
        let session = makeSession()
        session.evaluateDocument()
        #expect(await waitUntil { session.documentEvaluation?.failure == .invalidOutput })
        #expect(session.readings == nil)
    }

    @Test func switchingBackToParagraphScopeEvaluatesTheParagraph() async {
        let session = makeSession()
        session.evaluateDocument()
        #expect(await waitUntil { session.readings != nil && session.status == .idle })

        session.cursorDidMove(to: (Self.document as NSString).length)
        session.scope = .paragraph
        #expect(session.status == .pending)
        await clock.advance(by: EditorSession.pauseInterval)
        #expect(await waitUntil { model.prompts.count == 2 })
    }
}
