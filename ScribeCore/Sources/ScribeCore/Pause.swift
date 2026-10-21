/// Returns a sleep whose deadline is fixed now, not when the returned closure first runs,
/// so a pause is measured from the keystroke that started it.
func pause<C: Clock>(on clock: C, for duration: C.Duration) -> @Sendable () async throws -> Void {
    let deadline = clock.now.advanced(by: duration)
    return { try await clock.sleep(until: deadline, tolerance: nil) }
}
