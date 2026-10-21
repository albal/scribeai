import ScribeCore
import SwiftUI

/// The right pane: the four Gauges for the current Evaluation.
struct GaugePane: View {
    let session: EditorSession

    private var readings: Readings? { session.readings }
    private var isStale: Bool { session.status == .pending || session.status == .evaluating }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            AlignmentGauge(readings: readings)
            ScaleGauge(
                title: "Concision", symbol: "✂️", value: readings?.concision,
                lowLabel: "Bloated", highLabel: "Tight", judging: true
            )
            ScaleGauge(
                title: "Intensity", symbol: "🌡️", value: readings?.intensity,
                lowLabel: "Restrained", highLabel: "Purple", judging: false
            )
            ToneGauge(tone: readings?.tone)
            Spacer()
        }
        .padding(20)
        .opacity(isStale && readings != nil ? 0.45 : 1)
        .animation(.easeInOut(duration: 0.2), value: isStale)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background.secondary)
    }

    private var header: some View {
        HStack {
            Text(session.target.name)
                .font(.headline)
            Spacer()
            switch session.status {
            case .evaluating:
                ProgressView().controlSize(.small)
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .help(message)
            case .idle, .pending:
                EmptyView()
            }
        }
    }
}

private struct GaugeCard<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(title).font(.subheadline.weight(.semibold))
            } icon: {
                Text(symbol)
            }
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: .rect(cornerRadius: 10))
    }
}

private struct AlignmentGauge: View {
    let readings: Readings?

    var body: some View {
        GaugeCard(title: "Alignment", symbol: "🎯") {
            if let readings {
                HStack(alignment: .firstTextBaseline) {
                    Text(readings.grade.letter)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(judgingColor(readings.alignmentScore))
                    Text("\(readings.alignmentScore)/100")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            } else {
                EmptyReading()
            }
        }
    }
}

private struct ScaleGauge: View {
    let title: String
    let symbol: String
    let value: Int?
    let lowLabel: String
    let highLabel: String
    let judging: Bool

    var body: some View {
        GaugeCard(title: title, symbol: symbol) {
            if let value {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: Double(value), total: 100)
                        .tint(judging ? judgingColor(value) : .accentColor)
                    HStack {
                        Text(lowLabel)
                        Spacer()
                        Text("\(value)").monospacedDigit()
                        Spacer()
                        Text(highLabel)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            } else {
                EmptyReading()
            }
        }
    }
}

private struct ToneGauge: View {
    let tone: Tone?

    var body: some View {
        GaugeCard(title: "Tone", symbol: "🎭") {
            if let tone {
                HStack {
                    Text(tone.symbol).font(.title)
                    Text(tone.name).font(.title3)
                }
            } else {
                EmptyReading()
            }
        }
    }
}

private struct EmptyReading: View {
    var body: some View {
        Text("—").font(.title2).foregroundStyle(.tertiary)
    }
}

/// Colour for a judging Gauge: good, middling or poor.
private func judgingColor(_ value: Int) -> Color {
    switch value {
    case 80...: .green
    case 60..<80: .orange
    default: .red
    }
}
