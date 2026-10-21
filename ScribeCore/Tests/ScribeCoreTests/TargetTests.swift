import Foundation
import Testing
@testable import ScribeCore

struct TargetTests {
    @Test func thereAreNineBuiltInTargetsWithUniqueStableIDs() {
        #expect(BuiltInTargets.levels.map(\.name) == [
            "Middle Grade", "Young Adult", "Accessible/Mainstream", "Academic", "High Literary Fiction",
        ])
        #expect(BuiltInTargets.publications.map(\.name) == ["The Economist", "Wired", "The New Yorker", "Nature"])
        #expect(Set(BuiltInTargets.all.map(\.id)).count == 9)
        #expect(BuiltInTargets.all.allSatisfy { $0.isBuiltIn && !$0.styleBrief.isEmpty })
    }

    @Test func aStoredIDResolvesToItsTarget() {
        let resolution = TargetCatalog().resolve(storedID: "publication.new-yorker", defaultID: nil)
        #expect(resolution.target == BuiltInTargets.newYorker)
        #expect(resolution.unknownID == nil)
    }

    @Test func noStoredIDUsesTheDefault() {
        let resolution = TargetCatalog().resolve(storedID: nil, defaultID: "level.academic")
        #expect(resolution.target == BuiltInTargets.academic)
        #expect(resolution.unknownID == nil)
    }

    @Test func anUnknownStoredIDFallsBackToTheDefaultAndIsReported() {
        let resolution = TargetCatalog().resolve(storedID: "custom.deleted", defaultID: "level.academic")
        #expect(resolution.target == BuiltInTargets.academic)
        #expect(resolution.unknownID == "custom.deleted")
    }

    @Test func anUnknownDefaultFallsBackToTheBuiltInDefault() {
        let resolution = TargetCatalog().resolve(storedID: nil, defaultID: "nonsense")
        #expect(resolution.target == BuiltInTargets.default)
    }

    @Test func customTargetsResolve() {
        let hemingway = Target(id: "custom.1", name: "Hemingway", kind: .custom, styleBrief: "Short and true.")
        let resolution = TargetCatalog(custom: [hemingway]).resolve(storedID: "custom.1", defaultID: nil)
        #expect(resolution.target == hemingway)
    }

    @Test func theEvaluationPromptIncludesTheStyleBrief() {
        let prompt = PromptBuilder.evaluation(of: .paragraph("Some prose."), target: BuiltInTargets.economist)
        #expect(prompt.user.contains("Target: The Economist"))
        #expect(prompt.user.contains(BuiltInTargets.economist.styleBrief))
    }
}

struct MarkdownFileTests {
    @Test func aFileWithoutFrontMatterIsAllBody() {
        let file = MarkdownFile(parsing: "# Title\n\nBody.")
        #expect(file.frontMatter.isEmpty)
        #expect(file.body == "# Title\n\nBody.")
        #expect(file.targetID == nil)
        #expect(file.rendered == "# Title\n\nBody.")
    }

    @Test func theTargetIsReadFromFrontMatterAndHiddenFromTheBody() {
        let file = MarkdownFile(parsing: "---\nscribeai-target: publication.wired\n---\nThe story.")
        #expect(file.targetID == "publication.wired")
        #expect(file.body == "The story.")
    }

    @Test func quotedValuesAreUnquoted() {
        #expect(MarkdownFile(parsing: "---\nscribeai-target: \"level.academic\"\n---\n").targetID == "level.academic")
    }

    @Test func roundTripPreservesTheFileExactly() {
        let text = "---\ntitle: Draft\nscribeai-target: level.young-adult\ntags: [a, b]\n---\nBody\n\nMore body.\n"
        #expect(MarkdownFile(parsing: text).rendered == text)
    }

    @Test func settingTheTargetPreservesOtherKeys() {
        var file = MarkdownFile(parsing: "---\ntitle: Draft\nscribeai-target: level.young-adult\n---\nBody")
        file.targetID = "publication.nature"
        #expect(file.rendered == "---\ntitle: Draft\nscribeai-target: publication.nature\n---\nBody")
    }

    @Test func settingTheTargetAddsFrontMatterWhenThereIsNone() {
        var file = MarkdownFile(parsing: "Body")
        file.targetID = "level.academic"
        #expect(file.rendered == "---\nscribeai-target: level.academic\n---\nBody")
        #expect(MarkdownFile(parsing: file.rendered) == file)
    }

    @Test func settingTheTargetAppendsToExistingFrontMatter() {
        var file = MarkdownFile(parsing: "---\ntitle: Draft\n---\nBody")
        file.targetID = "level.academic"
        #expect(file.rendered == "---\ntitle: Draft\nscribeai-target: level.academic\n---\nBody")
    }

    @Test func anUnclosedDelimiterIsNotFrontMatter() {
        let file = MarkdownFile(parsing: "---\nNot front matter after all.")
        #expect(file.frontMatter.isEmpty)
        #expect(file.body == "---\nNot front matter after all.")
    }

    @Test func aNewFileCanCarryATarget() {
        #expect(MarkdownFile(body: "", targetID: "level.academic").rendered == "---\nscribeai-target: level.academic\n---\n")
    }
}

@MainActor
struct TargetChangeTests {
    let clock = ManualClock()
    let model = FakeModelClient()

    @Test func changingTheTargetReEvaluatesTheCurrentScope() async throws {
        let session = EditorSession(model: model, clock: clock)
        session.textDidChange(long("A paragraph of prose."), cursor: 0)
        await clock.advance(by: EditorSession.pauseInterval)
        #expect(await waitUntil { session.readings != nil })

        session.target = BuiltInTargets.nature
        #expect(session.status == .pending)
        await clock.advance(by: EditorSession.pauseInterval)
        #expect(await waitUntil { model.prompts.count == 2 })
        #expect(try #require(model.prompts.last).user.contains(BuiltInTargets.nature.styleBrief))
    }

    @Test func switchingBackToAnEarlierTargetUsesCachedReadings() async {
        let session = EditorSession(model: model, clock: clock)
        session.textDidChange(long("A paragraph of prose."), cursor: 0)
        await clock.advance(by: EditorSession.pauseInterval)
        #expect(await waitUntil { session.readings != nil })
        session.target = BuiltInTargets.nature
        await clock.advance(by: EditorSession.pauseInterval)
        #expect(await waitUntil { model.prompts.count == 2 && session.status == .idle })

        session.target = BuiltInTargets.default
        #expect(session.status == .idle)
        #expect(model.prompts.count == 2)
    }
}
