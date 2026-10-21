import Foundation
import ScribeCore

/// What one model did across the whole run.
struct ModelReport {
    let model: String
    var evaluations = 0
    var validEvaluations = 0
    /// Readings for each passage × Target, across repeated runs.
    var readings: [String: [Readings]] = [:]
    var latencies: [Duration] = []
    var critiques = 0
    var rewritingCritiques: [String] = []

    var validRate: Double { evaluations == 0 ? 0 : Double(validEvaluations) / Double(evaluations) }

    /// Mean standard deviation of a Gauge's value across repeated runs of the same input.
    func spread(_ value: (Readings) -> Int) -> Double {
        let groups = readings.values.filter { $0.count > 1 }
        guard !groups.isEmpty else { return 0 }
        return groups.map { Statistics.standardDeviation($0.map { Double(value($0)) }) }.reduce(0, +) / Double(groups.count)
    }

    /// How often repeated runs agree with the most common Tone for that input.
    var toneAgreement: Double {
        let groups = readings.values.filter { !$0.isEmpty }
        guard !groups.isEmpty else { return 0 }
        let agreements = groups.map { group -> Double in
            let counts = Dictionary(grouping: group, by: \.tone).mapValues(\.count)
            return Double(counts.values.max() ?? 0) / Double(group.count)
        }
        return agreements.reduce(0, +) / Double(agreements.count)
    }

    var meanLatency: Duration {
        latencies.isEmpty ? .zero : latencies.reduce(.zero, +) / latencies.count
    }
}

enum Statistics {
    static func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        return variance.squareRoot()
    }
}

/// A simple check for Critiques that slip into suggesting replacement wording (ADR 0003).
/// It errs towards flagging; read the flagged Critiques before trusting a count.
enum RewriteDetector {
    static let patterns = [
        #"\b(replace|replacing|swap|substitute)\b[^.]*\b(with|for)\b"#,
        #"\binstead of\b"#,
        #"\b(consider|try)\s+(using|writing|saying|changing|rephrasing)\b"#,
        #"\b(could|might|would) (be )?(rewritten|rephrased|reworded|revised)\b"#,
        #"\b(rewrite|rephrase|reword)\b"#,
        #"\bchange\b[^.]*\bto\s+["“']"#,
        #"\bsomething like\s+["“']"#,
        #"\bfor example,?\s+["“'][^"”']+["”']\s+(would|could|reads)"#,
        "→",
    ]

    static func suggestsRewording(_ critique: String) -> Bool {
        patterns.contains { critique.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil }
    }
}

enum Table {
    static func render(_ reports: [ModelReport]) -> String {
        let header = ["Model", "Valid", "σ Align", "σ Conc", "σ Int", "Tone agree", "Latency", "Rewrites"]
        let rows = reports.map { report in
            [
                report.model,
                percent(report.validRate),
                String(format: "%.1f", report.spread(\.alignmentScore)),
                String(format: "%.1f", report.spread(\.concision)),
                String(format: "%.1f", report.spread(\.intensity)),
                percent(report.toneAgreement),
                String(format: "%.1fs", Double(report.meanLatency.components.seconds) + Double(report.meanLatency.components.attoseconds) / 1e18),
                "\(report.rewritingCritiques.count)/\(report.critiques)",
            ]
        }
        let widths = header.indices.map { column in ([header] + rows).map { $0[column].count }.max() ?? 0 }
        func line(_ cells: [String]) -> String {
            cells.enumerated().map { $1.padding(toLength: widths[$0], withPad: " ", startingAt: 0) }.joined(separator: "  ")
        }
        return ([line(header), line(widths.map { String(repeating: "-", count: $0) })] + rows.map(line)).joined(separator: "\n")
    }

    static func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }
}
