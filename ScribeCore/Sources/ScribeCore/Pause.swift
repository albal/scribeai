/// Starts a pause whose deadline is fixed when it starts, not when the returned sleep first
/// runs, so a pause is measured from the keystroke that started it.
typealias PauseStarter = @Sendable (Duration) -> @Sendable () async throws -> Void

func pauseStarter<C: Clock<Duration>>(on clock: C) -> PauseStarter {
    { duration in
        let deadline = clock.now.advanced(by: duration)
        return { try await clock.sleep(until: deadline, tolerance: nil) }
    }
}
