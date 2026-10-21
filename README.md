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

## Layout

- `ScribeCore/`: the domain logic (editor session, segmentation, prompts, Ollama client), test-first with Swift Testing
- `App/`: the thin SwiftUI app target
