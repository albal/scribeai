import Foundation
import Testing
@testable import ScribeCore

@MainActor
struct CritiqueTests {
    let clock = ManualClock()
    let model = FakeModelClient()

    static let paragraph = long("The rain was really bad and it kind of made everything a mess, honestly.")

    /// A session showing Readings for `paragraph`.
    func evaluatedSession() async -> EditorSession {
        let session = EditorSession(target: BuiltInTargets.newYorker, model: model, clock: clock)
        session.textDidChange(Self.paragraph, cursor: 0)
        await clock.advance(by: EditorSession.pauseInterval)
        _ = await waitUntil { session.readings != nil && session.status == .idle }
        return session
    }

    @Test func clickingAGaugeStreamsACritiqueOfThatGauge() async throws {
        let session = await evaluatedSession()
        session.requestCritique(of: .alignment)
        #expect(session.critique?.gauge == .alignment)
        #expect(session.critique?.readings == .sample)

        #expect(await waitUntil { session.critique?.isComplete == true })
        #expect(session.critique?.text == "The register is too casual.")
        #expect(session.critique?.isOutOfDate == false)
    }

    @Test func theCritiquePromptCarriesTheTextGaugeReadingAndStyleBrief() async throws {
        let session = await evaluatedSession()
        session.requestCritique(of: .alignment)
        #expect(await waitUntil { model.critiquePrompts.count == 1 })

        let prompt = try #require(model.critiquePrompts.first)
        #expect(prompt.user.contains(Self.paragraph))
        #expect(prompt.user.contains("Alignment reading of 78/100 (Grade C+)"))
        #expect(prompt.user.contains(BuiltInTargets.newYorker.styleBrief))
    }

    @Test(arguments: Gauge.allCases)
    func everyCritiquePromptForbidsRewriting(gauge: Gauge) {
        let prompt = PromptBuilder.critique(of: gauge, readings: .sample, unit: .paragraph("Text."), target: BuiltInTargets.default)
        for message in [prompt.system, prompt.user] {
            #expect(message.contains("Never suggest replacement words, alternative phrasings or rewritten text, not even a single word."))
        }
        #expect(prompt.user.contains("\(gauge.name) reading of \(gauge.describe(.sample))"))
    }

    @Test func aCritiqueCancelsARunningEvaluation() async {
        let session = await evaluatedSession()
        model.hold()
        session.textDidChange(long("A different paragraph entirely."), cursor: 0)
        await clock.advance(by: EditorSession.pauseInterval)
        #expect(await waitUntil { model.heldCount == 1 })

        session.requestCritique(of: .tone)
        #expect(await waitUntil { model.cancellations == 1 })
        #expect(session.critique?.unit == .paragraph(Self.paragraph))
        #expect(await waitUntil { model.heldCount == 1 })
        model.release()
        #expect(await waitUntil { session.critique?.isComplete == true })
    }

    @Test func noEvaluationRunsWhileACritiqueIsStreaming() async {
        let session = await evaluatedSession()
        model.hold()
        session.requestCritique(of: .concision)
        #expect(await waitUntil { model.heldCount == 1 })

        session.textDidChange(long("The writer keeps typing new words."), cursor: 0)
        await clock.advance(by: EditorSession.pauseInterval)
        await settle()
        #expect(model.prompts.count == 1)

        model.release()
        #expect(await waitUntil { session.critique?.isComplete == true })
        await clock.advance(by: EditorSession.pauseInterval)
        #expect(await waitUntil { model.prompts.count == 2 })
    }

    @Test func theCritiqueIsMarkedOutOfDateWhenItsTextChanges() async {
        let session = await evaluatedSession()
        session.requestCritique(of: .alignment)
        #expect(await waitUntil { session.critique?.isComplete == true })

        session.textDidChange(Self.paragraph.replacingOccurrences(of: "really bad", with: "dreadful"), cursor: 0)
        #expect(session.critique?.isOutOfDate == true)
        #expect(session.critique?.readings == .sample)
    }

    @Test func editingOtherTextLeavesTheCritiqueCurrent() async {
        let session = await evaluatedSession()
        session.requestCritique(of: .alignment)
        #expect(await waitUntil { session.critique?.isComplete == true })

        session.textDidChange(Self.paragraph + "\n\nA new paragraph below.", cursor: 0)
        #expect(session.critique?.isOutOfDate == false)
    }

    @Test func aCritiqueKeepsExplainingTheClickedReadingWhileTheWriterTypes() async {
        let session = await evaluatedSession()
        model.hold()
        session.requestCritique(of: .alignment)
        #expect(await waitUntil { model.heldCount == 1 })
        session.textDidChange(long("Completely new text now."), cursor: 0)
        model.release()
        #expect(await waitUntil { session.critique?.isComplete == true })
        #expect(session.critique?.text == "The register is too casual.")
        #expect(session.critique?.isOutOfDate == true)
    }

    @Test func closingTheCritiqueClearsIt() async {
        let session = await evaluatedSession()
        session.requestCritique(of: .alignment)
        session.closeCritique()
        #expect(session.critique == nil)
    }

    @Test func aFailedCritiqueIsReported() async {
        model.scriptCritique(["Partial "], failure: EvaluationFailure.ollamaNotRunning)
        let session = await evaluatedSession()
        session.requestCritique(of: .intensity)
        #expect(await waitUntil { session.critique?.failure == .ollamaNotRunning })
        #expect(session.critique?.text == "Partial ")
    }

    @Test func noCritiqueWithoutReadings() {
        let session = EditorSession(model: model, clock: clock)
        session.requestCritique(of: .alignment)
        #expect(session.critique == nil)
    }
}
