# ScribeAI

A native macOS critique partner that grades your prose against a chosen writing standard, using a local LLM. Nothing leaves your machine. See [`PRD.md`](./PRD.md), [`GLOSSARY.md`](./GLOSSARY.md) and [`docs/adr/`](./docs/adr/).

## Requirements

- macOS 26 or later on Apple Silicon, 16GB RAM
- Xcode 26 or later
- [Ollama](https://ollama.com) (`brew install ollama`), running

## Build and run

Open `ScribeAI.xcodeproj` in Xcode and run the **ScribeAI** scheme, or:

```sh
xcodebuild -project ScribeAI.xcodeproj -scheme ScribeAI build
```

## Tests

All behaviour lives in the `ScribeCore` Swift package:

```sh
cd ScribeCore && swift test
```

## Prompt-testing harness

`prompt-harness` runs a fixed set of sample passages against Built-in Targets through each candidate model, using ScribeCore's real prompts and Ollama client. It reports, per model:

- **Valid**: the share of Evaluations that returned schema-valid Readings
- **σ Align / σ Conc / σ Int**: how much each Gauge varies across repeated runs of the same input (lower is more consistent)
- **Tone agree**: how often repeated runs give the same Tone
- **Latency**: the mean time per Evaluation
- **Rewrites**: Critiques flagged by a simple heuristic as suggesting replacement wording (ADR 0003)

With Ollama running:

```sh
cd ScribeCore
swift run prompt-harness                                  # llama3.1:8b, qwen3:8b, gemma3:12b; 3 runs; 3 Targets
swift run prompt-harness --models llama3.1:8b,qwen3:8b --runs 5 --targets all
swift run prompt-harness --verbose                        # print every Reading and each flagged Critique
```

Models that aren't downloaded are skipped; pull them first with `ollama pull <model>`. Run `swift run prompt-harness --help` for all options.

## Layout

- `ScribeCore/`: the domain logic (editor session, segmentation, prompts, Ollama client), test-first with Swift Testing
- `ScribeCore/Sources/PromptHarness/`: the prompt-testing harness
- `App/`: the thin SwiftUI app target
