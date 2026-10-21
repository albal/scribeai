import Foundation
import Synchronization
@testable import ScribeCore

/// A clock that only moves when the test advances it.
final class ManualClock: Clock, Sendable {
    struct Instant: InstantProtocol {
        var offset: Duration
        func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
        func duration(to other: Instant) -> Duration { other.offset - offset }
        static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
    }

    private struct Sleeper {
        let id: UUID
        let deadline: Instant
        let continuation: CheckedContinuation<Void, any Error>
    }

    private struct State {
        var now = Instant(offset: .zero)
        var sleepers: [Sleeper] = []
    }

    private let state = Mutex(State())

    var now: Instant { state.withLock { $0.now } }
    var sleeperCount: Int { state.withLock { $0.sleepers.count } }
    var minimumResolution: Duration { .zero }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                state.withLock { state in
                    if Task.isCancelled {
                        continuation.resume(throwing: CancellationError())
                    } else if deadline <= state.now {
                        continuation.resume()
                    } else {
                        state.sleepers.append(Sleeper(id: id, deadline: deadline, continuation: continuation))
                    }
                }
            }
        } onCancel: {
            let cancelled = state.withLock { state -> Sleeper? in
                guard let index = state.sleepers.firstIndex(where: { $0.id == id }) else { return nil }
                return state.sleepers.remove(at: index)
            }
            cancelled?.continuation.resume(throwing: CancellationError())
        }
    }

    /// Moves time forward, waking every sleeper whose deadline has passed.
    func advance(by duration: Duration) async {
        await settle()
        let due = state.withLock { state -> [Sleeper] in
            state.now = state.now.advanced(by: duration)
            let due = state.sleepers.filter { $0.deadline <= state.now }
            state.sleepers.removeAll { $0.deadline <= state.now }
            return due
        }
        due.forEach { $0.continuation.resume() }
        await settle()
    }
}

/// Lets scheduled tasks run until they block.
func settle() async {
    for _ in 0..<50 { await Task.yield() }
}

/// Waits (briefly, in real time) for asynchronous work to satisfy `condition`.
@MainActor
func waitUntil(timeout: Duration = .seconds(2), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while !condition() {
        if ContinuousClock.now >= deadline { return false }
        try? await Task.sleep(for: .milliseconds(1))
    }
    return true
}

/// A scripted model client that records every prompt it receives.
final class FakeModelClient: ModelClient, Sendable {
    private struct State {
        var prompts: [EvaluationPrompt] = []
        var responses: [Result<Readings, any Error>] = []
        var statuses: [ModelStatus] = []
        var statusChecks = 0
        var pullEvents: [Result<PullProgress, any Error>] = []
        var holdsEvaluations = false
        var held: [CheckedContinuation<Void, any Error>] = []
        var cancellations = 0
    }

    private let state = Mutex(State())
    let defaultReadings: Readings
    let model = "fake-model"

    init(readings: Readings = .sample) {
        defaultReadings = readings
    }

    var statusChecks: Int { state.withLock { $0.statusChecks } }
    var cancellations: Int { state.withLock { $0.cancellations } }
    var heldCount: Int { state.withLock { $0.held.count } }

    /// While holding, Evaluations don't return until `release()` or cancellation.
    func hold() {
        state.withLock { $0.holdsEvaluations = true }
    }

    /// Stops holding and lets every held Evaluation return.
    func release() {
        let held = state.withLock { state in
            state.holdsEvaluations = false
            defer { state.held = [] }
            return state.held
        }
        held.forEach { $0.resume() }
    }

    /// Queues status answers; once the queue is empty, `.ready` is returned.
    func enqueue(status: ModelStatus...) {
        state.withLock { $0.statuses.append(contentsOf: status) }
    }

    /// Sets what the next `pull()` will emit, in order.
    func scriptPull(_ events: [Result<PullProgress, any Error>]) {
        state.withLock { $0.pullEvents = events }
    }

    func status() async -> ModelStatus {
        state.withLock { state in
            state.statusChecks += 1
            return state.statuses.isEmpty ? .ready : state.statuses.removeFirst()
        }
    }

    func pull() -> AsyncThrowingStream<PullProgress, any Error> {
        let events = state.withLock { $0.pullEvents }
        return AsyncThrowingStream { continuation in
            for event in events {
                switch event {
                case .success(let progress): continuation.yield(progress)
                case .failure(let error): continuation.finish(throwing: error); return
                }
            }
            continuation.finish()
        }
    }

    var prompts: [EvaluationPrompt] { state.withLock { $0.prompts } }

    /// Queues the next result; once the queue is empty, `defaultReadings` is returned.
    func enqueue(_ result: Result<Readings, any Error>) {
        state.withLock { $0.responses.append(result) }
    }

    func evaluate(_ prompt: EvaluationPrompt) async throws -> Readings {
        let (next, holds) = state.withLock { state -> (Result<Readings, any Error>?, Bool) in
            state.prompts.append(prompt)
            return (state.responses.isEmpty ? nil : state.responses.removeFirst(), state.holdsEvaluations)
        }
        if holds { try await waitForRelease() }
        return try (next ?? .success(defaultReadings)).get()
    }

    private func waitForRelease() async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                state.withLock { state in
                    if Task.isCancelled {
                        state.cancellations += 1
                        continuation.resume(throwing: CancellationError())
                    } else {
                        state.held.append(continuation)
                    }
                }
            }
        } onCancel: {
            let held = state.withLock { state in
                defer { state.held = [] }
                state.cancellations += state.held.count
                return state.held
            }
            held.forEach { $0.resume(throwing: CancellationError()) }
        }
    }
}

extension Readings {
    static let sample = try! Readings(alignmentScore: 78, concision: 60, intensity: 40, tone: .casual)
}
