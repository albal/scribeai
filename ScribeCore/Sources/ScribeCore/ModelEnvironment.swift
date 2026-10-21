import Observation

/// Whether the model server and model are ready, and getting them ready if not.
/// ScribeAI never installs Ollama itself (ADR 0002); it only detects it and pulls the model.
@MainActor @Observable
public final class ModelEnvironment {
    public enum State: Equatable, Sendable {
        case checking
        case ollamaNotRunning
        case modelMissing
        case downloading(PullProgress)
        case downloadFailed(String)
        case ready
    }

    public static let pollInterval: Duration = .seconds(3)

    public private(set) var state: State = .checking
    public private(set) var client: any ModelClient

    @ObservationIgnored private let clock: any Clock<Duration>
    @ObservationIgnored private var task: Task<Void, Never>?

    public init(client: any ModelClient, clock: any Clock<Duration> = ContinuousClock()) {
        self.client = client
        self.clock = clock
    }

    /// Checks the server, polling until Ollama comes up.
    public func check() {
        task?.cancel()
        state = .checking
        task = Task { [clock] in
            while !Task.isCancelled {
                let status = await self.client.status()
                guard !Task.isCancelled else { return }
                switch status {
                case .ready: self.state = .ready
                case .modelMissing: self.state = .modelMissing
                case .ollamaNotRunning: self.state = .ollamaNotRunning
                }
                guard status == .ollamaNotRunning else { return }
                do { try await clock.sleep(for: Self.pollInterval) } catch { return }
            }
        }
    }

    /// Switches to another model client (e.g. the model setting changed) and checks again.
    public func use(_ client: any ModelClient) {
        self.client = client
        check()
    }

    /// Downloads the missing model. Also used to retry a failed download.
    public func download() {
        task?.cancel()
        state = .downloading(PullProgress(status: "starting", fraction: nil))
        task = Task {
            do {
                for try await progress in self.client.pull() {
                    self.state = .downloading(progress)
                }
                guard !Task.isCancelled else { return }
                self.state = await self.client.status() == .ready ? .ready : .downloadFailed("The download finished but the model isn't available.")
            } catch is CancellationError {
                return
            } catch {
                self.state = .downloadFailed(String(describing: error))
            }
        }
    }

    /// An Evaluation failed in a way that suggests the environment changed.
    public func evaluationFailed(_ failure: EvaluationFailure) {
        if failure == .ollamaNotRunning || failure == .modelMissing {
            check()
        }
    }
}
