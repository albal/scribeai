import Testing
@testable import ScribeCore

@MainActor
struct ModelEnvironmentTests {
    let clock = ManualClock()
    let model = FakeModelClient()

    func makeEnvironment() -> ModelEnvironment {
        ModelEnvironment(client: model, clock: clock)
    }

    @Test func aReachableServerWithTheModelIsReady() async {
        let environment = makeEnvironment()
        environment.check()
        #expect(await waitUntil { environment.state == .ready })
    }

    @Test func recoversByItselfWhenOllamaStarts() async {
        model.enqueue(status: .ollamaNotRunning, .ollamaNotRunning)
        let environment = makeEnvironment()
        environment.check()
        #expect(await waitUntil { environment.state == .ollamaNotRunning })

        await clock.advance(by: ModelEnvironment.pollInterval)
        #expect(await waitUntil { model.statusChecks == 2 })
        #expect(environment.state == .ollamaNotRunning)

        await clock.advance(by: ModelEnvironment.pollInterval)
        #expect(await waitUntil { environment.state == .ready })
    }

    @Test func aMissingModelWaitsForTheWriterToDownloadIt() async {
        model.enqueue(status: .modelMissing)
        let environment = makeEnvironment()
        environment.check()
        #expect(await waitUntil { environment.state == .modelMissing })

        await clock.advance(by: .seconds(60))
        #expect(model.statusChecks == 1)
    }

    @Test func downloadReportsProgressThenBecomesReady() async {
        model.enqueue(status: .modelMissing)
        model.scriptPull([
            .success(PullProgress(status: "pulling", fraction: 0.5)),
            .success(PullProgress(status: "success", fraction: 1)),
        ])
        let environment = makeEnvironment()
        environment.check()
        #expect(await waitUntil { environment.state == .modelMissing })

        environment.download()
        #expect(await waitUntil { environment.state == .ready })
    }

    @Test func aFailedDownloadCanBeRetried() async {
        model.enqueue(status: .modelMissing)
        model.scriptPull([.failure(OllamaError.pullFailed("disk full"))])
        let environment = makeEnvironment()
        environment.check()
        #expect(await waitUntil { environment.state == .modelMissing })

        environment.download()
        #expect(await waitUntil { if case .downloadFailed = environment.state { true } else { false } })

        model.scriptPull([.success(PullProgress(status: "success", fraction: 1))])
        environment.download()
        #expect(await waitUntil { environment.state == .ready })
    }

    @Test func anEvaluationFindingOllamaGoneTriggersACheck() async {
        let environment = makeEnvironment()
        environment.check()
        #expect(await waitUntil { environment.state == .ready })

        model.enqueue(status: .ollamaNotRunning)
        environment.evaluationFailed(.ollamaNotRunning)
        #expect(await waitUntil { environment.state == .ollamaNotRunning })
    }

    @Test func invalidOutputDoesNotTriggerACheck() async {
        let environment = makeEnvironment()
        environment.check()
        #expect(await waitUntil { environment.state == .ready })

        environment.evaluationFailed(.invalidOutput)
        await settle()
        #expect(model.statusChecks == 1)
    }

    @Test func switchingModelChecksAgain() async {
        let environment = makeEnvironment()
        environment.check()
        #expect(await waitUntil { environment.state == .ready })

        let other = FakeModelClient()
        other.enqueue(status: .modelMissing)
        environment.use(other)
        #expect(await waitUntil { environment.state == .modelMissing })
    }
}
