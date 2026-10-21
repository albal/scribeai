import ScribeCore
import SwiftUI

/// Shown in place of the Gauges until Ollama and the model are ready.
struct EnvironmentStatusView: View {
    let environment: ModelEnvironment

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch environment.state {
            case .checking:
                ProgressView("Checking for Ollama…")
            case .ollamaNotRunning:
                Label("Ollama isn't running", systemImage: "bolt.horizontal.circle")
                    .font(.headline)
                Text("ScribeAI evaluates your writing with a local model served by Ollama. Install it and start it, and ScribeAI will connect automatically.")
                    .foregroundStyle(.secondary)
                Text("brew install ollama\nollama serve")
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .background(.background, in: .rect(cornerRadius: 6))
                Link("Or download it from ollama.com", destination: URL(string: "https://ollama.com/download")!)
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for Ollama…").font(.caption).foregroundStyle(.secondary)
                }
            case .modelMissing:
                Label("Model not downloaded", systemImage: "arrow.down.circle")
                    .font(.headline)
                Text("Ollama is running, but **\(environment.client.model)** isn't downloaded yet. It's several gigabytes.")
                    .foregroundStyle(.secondary)
                Button("Download \(environment.client.model)", action: environment.download)
                    .buttonStyle(.borderedProminent)
            case .downloading(let progress):
                Label("Downloading \(environment.client.model)", systemImage: "arrow.down.circle")
                    .font(.headline)
                if let fraction = progress.fraction {
                    ProgressView(value: fraction) {
                        Text(progress.status).font(.caption)
                    } currentValueLabel: {
                        Text(fraction, format: .percent.precision(.fractionLength(0)))
                    }
                } else {
                    ProgressView { Text(progress.status).font(.caption) }
                }
            case .downloadFailed(let message):
                Label("Download failed", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text(message).foregroundStyle(.secondary).textSelection(.enabled)
                Button("Retry", action: environment.download)
                    .buttonStyle(.borderedProminent)
            case .ready:
                EmptyView()
            }
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background.secondary)
    }
}
