# ScribeAI

A native macOS critique partner that grades your prose against a chosen writing standard, using a local LLM. Nothing leaves your machine. See [`PRD.md`](./PRD.md), [`GLOSSARY.md`](./GLOSSARY.md) and [`docs/adr/`](./docs/adr/).

## Install

Download **ScribeAI-macOS.dmg** from the [latest release](https://github.com/albal/scribeai/releases/latest). ScribeAI needs macOS 26 or later.

ScribeAI isn't sold through the App Store, so the first time you open it your Mac will ask you to confirm that you trust it. You only need to do this once.

1. **Copy the app.** Open the downloaded `ScribeAI-macOS.dmg`, then drag the **ScribeAI** icon onto the **Applications** folder beside it.
2. **Try to open it.** Open your **Applications** folder and double-click **ScribeAI**. Your Mac will say it can't verify the app. That's expected: click **Done** (or **Cancel**).
3. **Allow it.** Open **System Settings** and choose **Privacy & Security** in the sidebar. Scroll down to the **Security** section, where you'll see a message about ScribeAI, and click **Open Anyway**. Enter your Mac password or use Touch ID when asked, then click **Open Anyway** again if your Mac asks.

After that, ScribeAI opens normally, like any other app.

**One more thing:** ScribeAI checks your writing using a free helper app called [Ollama](https://ollama.com/download), which runs on your Mac so your writing never leaves it. If ScribeAI says Ollama isn't running, download Ollama, open it, and ScribeAI will connect by itself. ScribeAI will then offer to download the writing model it needs (a few gigabytes).

## Building from source

### Requirements

- macOS 26 or later on Apple Silicon, 16GB RAM
- Xcode 26 or later
- [Ollama](https://ollama.com) (`brew install ollama`), running

### Build and run

Open `ScribeAI.xcodeproj` in Xcode and run the **ScribeAI** scheme, or:

```sh
xcodebuild -project ScribeAI.xcodeproj -scheme ScribeAI build
```

### Tests

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

## Packaging a release

Pushing a `v*` tag runs `.github/workflows/release.yml`, which builds a Universal (Apple Silicon + Intel) app, ad-hoc signs it, packages it as `ScribeAI-macOS.dmg` and attaches it and its SHA-256 checksum to a GitHub Release. To build the same DMG locally (needs `brew install create-dmg`):

```sh
scripts/package-dmg.sh          # writes dist/ScribeAI-macOS.dmg
scripts/package-dmg.sh 1.2.0    # sets the app version
```

## Layout

- `ScribeCore/`: the domain logic (editor session, segmentation, prompts, Ollama client), test-first with Swift Testing
- `ScribeCore/Sources/PromptHarness/`: the prompt-testing harness
- `App/`: the thin SwiftUI app target
