import Foundation
import Testing
@testable import ScribeCore

struct MarkdownSegmenterTests {
    func paragraphTexts(_ text: String) -> [String] {
        MarkdownSegmenter.paragraphs(in: text).map(\.text)
    }

    @Test func paragraphsAreSeparatedByBlankLines() {
        let text = "First line\nstill first.\n\n  \nSecond one."
        #expect(paragraphTexts(text) == ["First line still first.", "Second one."])
    }

    @Test func eachListItemIsAParagraph() {
        let text = """
            Intro paragraph.
            - First item
              continues here.
            * Second item
            1. Numbered item
            2) Another numbered item
            """
        #expect(paragraphTexts(text) == [
            "Intro paragraph.",
            "First item continues here.",
            "Second item",
            "Numbered item",
            "Another numbered item",
        ])
    }

    @Test func eachBlockquoteIsAParagraphWithoutItsMarkers() {
        let text = """
            > A quoted line
            > that continues.
            >
            > > A second, nested quote.
            Plain prose after.
            """
        #expect(paragraphTexts(text) == ["A quoted line that continues.", "A second, nested quote.", "Plain prose after."])
    }

    @Test func headingsAreNeverProse() {
        let text = "# Title\nBody text.\n## Section\n####### Not a heading"
        #expect(paragraphTexts(text) == ["Body text.", "####### Not a heading"])
    }

    @Test func fencedCodeBlocksAreNeverProse() {
        let text = """
            Before.

            ```swift
            let prose = "not prose"

            print(prose)
            ```

            ~~~
            more code
            ~~~
            After.
            """
        #expect(paragraphTexts(text) == ["Before.", "After."])
    }

    @Test func frontMatterIsNeverProse() {
        let text = "---\ntarget: publication.new-yorker\n---\nThe story begins."
        #expect(paragraphTexts(text) == ["The story begins."])
    }

    @Test func aRuleSeparatesParagraphs() {
        #expect(paragraphTexts("One.\n***\nTwo.") == ["One.", "Two."])
    }

    @Test func paragraphRangesCoverTheSourceIncludingMarkers() throws {
        let text = "Intro.\n\n> Quoted text."
        let quote = try #require(MarkdownSegmenter.paragraphs(in: text).last)
        #expect((text as NSString).substring(with: NSRange(quote.range)) == "> Quoted text.")
    }

    @Test func aCursorInAHeadingFindsNoParagraph() {
        let text = "# Title\n\nBody text."
        #expect(MarkdownSegmenter.paragraph(at: 3, in: text) == nil)
        #expect(MarkdownSegmenter.paragraph(at: 12, in: text)?.text == "Body text.")
    }

    // MARK: Sentences

    func sentenceTexts(_ text: String) throws -> [String] {
        let paragraph = try #require(MarkdownSegmenter.paragraphs(in: text).first)
        return MarkdownSegmenter.sentences(in: paragraph, of: text).map(\.text)
    }

    @Test func sentencesSurviveAbbreviationsAndQuotedSpeech() throws {
        #expect(try sentenceTexts("Dr. Smith said, 'Stop!' and left. Then the rain came.") == [
            "Dr. Smith said, 'Stop!' and left.",
            "Then the rain came.",
        ])
    }

    @Test func sentencesSplitOnTerminalPunctuation() throws {
        #expect(try sentenceTexts("He left. She stayed! Why? Mr. Jones arrived at 3 p.m. on Tuesday.") == [
            "He left.", "She stayed!", "Why?", "Mr. Jones arrived at 3 p.m. on Tuesday.",
        ])
    }

    @Test func sentencesInAQuoteHaveNoMarkers() throws {
        #expect(try sentenceTexts("> First sentence. Second\n> sentence spans lines.") == [
            "First sentence.", "Second sentence spans lines.",
        ])
    }

    @Test func theSentenceAtTheCursorComesWithItsParagraph() throws {
        let text = "Intro.\n\nOne sentence here. Another sentence there."
        let cursor = (text as NSString).range(of: "Another").location + 2
        let found = try #require(MarkdownSegmenter.sentence(at: cursor, in: text))
        #expect(found.sentence.text == "Another sentence there.")
        #expect(found.paragraph.text == "One sentence here. Another sentence there.")
    }

    @Test func aCursorAtTheEndOfAParagraphFindsItsLastSentence() throws {
        let text = "One sentence here. Another sentence there."
        let found = try #require(MarkdownSegmenter.sentence(at: (text as NSString).length, in: text))
        #expect(found.sentence.text == "Another sentence there.")
    }
}
