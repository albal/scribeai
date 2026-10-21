import Foundation
import ScribeCore

/// Runs sample passages × Targets through candidate models to compare structured-output validity,
/// Reading consistency, latency and adherence to the no-rewrite rule.
///
///     swift run prompt-harness --models llama3.1:8b,qwen3:8b --runs 3
@main
struct PromptHarness {
    struct Options {
        var models = ["llama3.1:8b", "qwen3:8b", "gemma3:12b"]
        var runs = 3
        var targets = [BuiltInTargets.accessibleMainstream, BuiltInTargets.economist, BuiltInTargets.literaryFiction]
        var baseURL = OllamaClient.defaultBaseURL
        var critiques = true
        var verbose = false
    }

    static let usage = """
        Usage: prompt-harness [--models a,b,c] [--runs N] [--targets id,id|all] [--base-url URL] [--no-critiques] [--verbose]

          --models     Ollama models to compare (default: llama3.1:8b,qwen3:8b,gemma3:12b)
          --runs       Evaluations of each passage × Target per model (default: 3)
          --targets    Built-in Target ids, or "all" (default: level.accessible-mainstream,
                       publication.economist,level.literary-fiction)
          --base-url   Ollama server (default: http://localhost:11434)
          --no-critiques  Skip the Critique pass
          --verbose    Print every Reading and each flagged Critique
        """

    static func main() async {
        let options: Options
        do {
            options = try parse(Array(CommandLine.arguments.dropFirst()))
        } catch {
            print("\(error)\n\n\(usage)")
            exit(2)
        }

        var reports: [ModelReport] = []
        for model in options.models {
            let client = OllamaClient(baseURL: options.baseURL, model: model)
            switch await client.status() {
            case .ollamaNotRunning:
                print("Ollama isn't reachable at \(options.baseURL). Start it with `ollama serve`.")
                exit(1)
            case .modelMissing:
                print("Skipping \(model): not downloaded (run `ollama pull \(model)`).")
                continue
            case .ready:
                print("Evaluating with \(model)…")
                reports.append(await run(client, options))
            }
        }

        guard !reports.isEmpty else {
            print("No models to report on.")
            exit(1)
        }
        let total = Passages.all.count * options.targets.count
        print("\n\(total) passage × Target pairs, \(options.runs) run(s) each.\n")
        print(Table.render(reports))
        print("""

            Valid: share of Evaluations returning schema-valid Readings.
            σ: mean standard deviation of a Gauge across repeated runs (lower is more consistent).
            Tone agree: how often repeated runs give the same Tone.
            Rewrites: Critiques the heuristic flags as suggesting replacement wording (read them with --verbose).
            """)
    }

    static func run(_ client: OllamaClient, _ options: Options) async -> ModelReport {
        var report = ModelReport(model: client.model)
        for target in options.targets {
            for passage in Passages.all {
                let key = "\(passage.name) × \(target.name)"
                let prompt = PromptBuilder.evaluation(of: .paragraph(passage.text), target: target)
                for _ in 0..<options.runs {
                    report.evaluations += 1
                    let started = ContinuousClock.now
                    do {
                        let readings = try await client.evaluate(prompt)
                        report.latencies.append(ContinuousClock.now - started)
                        report.validEvaluations += 1
                        report.readings[key, default: []].append(readings)
                        if options.verbose {
                            print("  \(key): \(readings.alignmentScore) \(readings.grade) · concision \(readings.concision) · intensity \(readings.intensity) · \(readings.tone.name)")
                        }
                    } catch {
                        if options.verbose { print("  \(key): failed: \(error)") }
                    }
                }

                guard options.critiques, let readings = report.readings[key]?.first else { continue }
                var critique = ""
                do {
                    for try await chunk in client.critique(PromptBuilder.critique(of: .alignment, readings: readings, unit: .paragraph(passage.text), target: target)) {
                        critique += chunk
                    }
                    report.critiques += 1
                    if RewriteDetector.suggestsRewording(critique) {
                        report.rewritingCritiques.append(critique)
                        if options.verbose { print("  ⚠︎ \(key) Critique suggests rewording:\n\(critique)\n") }
                    }
                } catch {
                    if options.verbose { print("  \(key): Critique failed: \(error)") }
                }
            }
        }
        return report
    }

    struct UsageError: Error, CustomStringConvertible {
        let description: String
    }

    static func parse(_ arguments: [String]) throws -> Options {
        var options = Options()
        var remaining = arguments[...]
        func value(for flag: String) throws -> String {
            guard let value = remaining.popFirst() else { throw UsageError(description: "\(flag) needs a value") }
            return value
        }
        while let argument = remaining.popFirst() {
            switch argument {
            case "--models":
                options.models = try value(for: argument).split(separator: ",").map(String.init)
            case "--runs":
                guard let runs = Int(try value(for: argument)), runs > 0 else { throw UsageError(description: "--runs must be a positive number") }
                options.runs = runs
            case "--targets":
                let ids = try value(for: argument)
                if ids == "all" {
                    options.targets = BuiltInTargets.all
                } else {
                    options.targets = try ids.split(separator: ",").map { id in
                        guard let target = BuiltInTargets.all.first(where: { $0.id == id }) else {
                            throw UsageError(description: "Unknown Target \(id). Known: \(BuiltInTargets.all.map(\.id).joined(separator: ", "))")
                        }
                        return target
                    }
                }
            case "--base-url":
                guard let url = URL(string: try value(for: argument)) else { throw UsageError(description: "Invalid --base-url") }
                options.baseURL = url
            case "--no-critiques":
                options.critiques = false
            case "--verbose":
                options.verbose = true
            case "--help", "-h":
                print(usage)
                exit(0)
            default:
                throw UsageError(description: "Unknown argument \(argument)")
            }
        }
        return options
    }
}
