import ScribeCore
import SwiftUI

/// The right pane: the four Gauges for the current Evaluation.
struct GaugePane: View {
    let session: EditorSession

    private var readings: Readings? { session.readings }
    private var isStale: Bool { session.status != .idle }

    private var scopeCaption: String {
        switch session.activeUnit {
        case .selection: "Selection"
        case .sentence: "Sentence"
        case .paragraph: "Paragraph"
        case nil:
            switch session.scope {
            case .sentence: "Place the cursor in a sentence of \(MarkdownSegmenter.minimumSentenceWords)+ words"
            case .paragraph: "Place the cursor in a paragraph of \(MarkdownSegmenter.minimumParagraphWords)+ words"
            case .document: "Document"
            }
        }
    }

    private var failure: EvaluationFailure? {
        if case .failed(let failure) = session.status { failure } else { nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if let failure {
                Label(failure.message, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    gauges
                    if let critique = session.critique {
                        CritiquePanel(critique: critique, close: session.closeCritique)
                    }
                }
            }
            .scrollIndicators(.automatic)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background.secondary)
    }

    private var gauges: some View {
        VStack(alignment: .leading, spacing: 16) {
            critiqueButton(.alignment) { AlignmentGauge(readings: readings) }
            critiqueButton(.concision) {
                ScaleGauge(
                    title: "Concision", symbol: "✂️", value: readings?.concision,
                    lowLabel: "Bloated", highLabel: "Tight", judging: true
                )
            }
            critiqueButton(.intensity) {
                ScaleGauge(
                    title: "Intensity", symbol: "🌡️", value: readings?.intensity,
                    lowLabel: "Restrained", highLabel: "Purple", judging: false
                )
            }
            critiqueButton(.tone) { ToneGauge(tone: readings?.tone) }
        }
        .opacity(isStale && readings != nil ? 0.45 : 1)
        .animation(.easeInOut(duration: 0.2), value: isStale)
    }

    /// Clicking a Gauge asks for a Critique of its Reading.
    private func critiqueButton(_ gauge: ScribeCore.Gauge, @ViewBuilder _ content: () -> some View) -> some View {
        Button {
            session.requestCritique(of: gauge)
        } label: {
            content()
                .overlay {
                    if session.critique?.gauge == gauge {
                        RoundedRectangle(cornerRadius: 10).strokeBorder(.tint, lineWidth: 2)
                    }
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(readings == nil)
        .help(readings == nil ? "" : "Explain this \(gauge.name) Reading")
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.target.name)
                    .font(.headline)
                Text(scopeCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            switch session.status {
            case .evaluating:
                ProgressView().controlSize(.small)
            case .idle, .pending, .failed:
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

/// The written explanation of one Gauge's Reading. It can be read but never applied to the Document.
private struct CritiquePanel: View {
    let critique: Critique
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Critique · \(critique.gauge.name)")
                    .font(.subheadline.weight(.semibold))
                if critique.isOutOfDate {
                    Text("Out of date")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.yellow.opacity(0.25), in: .capsule)
                        .help("The text this Critique describes has changed since")
                }
                Spacer()
                if !critique.isComplete, critique.failure == nil {
                    ProgressView().controlSize(.small)
                }
                Button(action: close) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close the Critique")
            }
            Text(critique.gauge.describe(critique.readings))
                .font(.caption)
                .foregroundStyle(.secondary)
            if critique.text.isEmpty, critique.failure == nil {
                Text("Thinking…").foregroundStyle(.secondary)
            } else {
                Text(critique.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let failure = critique.failure {
                Label(failure.message, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: .rect(cornerRadius: 10))
        .opacity(critique.isOutOfDate ? 0.6 : 1)
    }
}
