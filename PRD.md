# Product Requirements Document (PRD): ScribeAI (Codename)

Terms in **bold** are defined in [`GLOSSARY.md`](./GLOSSARY.md). Key decisions are recorded in [`docs/adr/`](./docs/adr/).

## 1. Executive Summary

**ScribeAI** is a native macOS app for Apple Silicon that acts as a real-time critique partner for writers. A local Large Language Model running in Ollama evaluates the writer's prose against a chosen **Target**: a literary **Level**, a **Publication**'s house style, or a **Custom Target**. The UI is a distraction-free split pane. The writer composes a **Document** on the left, and on the right four **Gauges** give at-a-glance **Readings**, each of which expands into a written **Critique** on request. Everything runs on-device within 16GB of RAM.

ScribeAI critiques; it never writes. Critiques diagnose problems in the writer's own words and never offer replacement text ([ADR 0003](./docs/adr/0003-critiques-never-rewrite.md)).

## 2. Target Audience

**v1:** Developers, and the author, who build the app from source in Xcode and are comfortable installing Ollama themselves ([ADR 0002](./docs/adr/0002-developer-audience-for-v1.md)).

**Eventually:**

* **Novelists & Creative Writers:** Seeking stylistic refinement, pacing analysis and tone consistency.
* **Journalists & Essayists:** Pitching to specific publications (e.g., *The New Yorker*, *The Economist*) and needing to match in-house style.
* **Academic & Technical Writers:** Adjusting the complexity and density of their work for specific audiences.

## 3. Core Value Proposition

* **100% Privacy:** No text is ever sent to the cloud. All inference happens on-device.
* **Real-Time Feedback:** Readings update when the writer pauses, without breaking the creative flow.
* **Context-Aware:** Every Evaluation is measured against the Target's **Style Brief**, not a generic standard.
* **The Writer's Own Words:** ScribeAI explains what is wrong and why, but never rewrites.

---

## 4. Feature Specifications

### 4.1 Environment Setup

* **Ollama is a prerequisite.** The user installs it themselves (`brew install ollama` or ollama.com).
* **Launch check:** On launch the app checks for Ollama on `http://localhost:11434`. If Ollama isn't reachable, the app shows a "not running" screen with install instructions.
* **Model download:** If Ollama is running but the configured model is missing, the app downloads it via `/api/pull` and shows a progress bar.
* **Model setting:** The model name is a user setting. The default is `gemma3:12b`, which fits in 16GB. Other candidates compared with the prompt-testing harness (see §9) include `llama3.1:8b` and `qwen3:8b`.
* **Out of scope for v1:** A first-launch wizard and silent installation of the Ollama binary.

### 4.2 Split-Pane User Interface

* **Left Pane (Editor):**
  * A Markdown text editor for the current Document, with word count ([ADR 0001](./docs/adr/0001-markdown-documents.md)).
  * ScribeAI is a document-based app that opens and saves `.md` files.
  * The Document's Target is stored in YAML front matter. The editor hides the front matter, and it is never evaluated.
* **Right Pane (Gauges):**
  * Shows the four Gauges with their current Readings. Clicking a Gauge expands its Critique.

### 4.3 Targets

* **Target Selector:** A toolbar menu for choosing the Document's Target. Each Document has its own Target. New Documents use an app-wide default.
* Every Target is a name plus a **Style Brief**: a short written description of the standard (sentence length, vocabulary, register, things to avoid). Evaluations judge text against the Style Brief, not against the model's own knowledge of the outlet.
* **Built-in Targets** (9), each with a handwritten Style Brief:
  * *Levels:* Middle Grade, Young Adult, Accessible/Mainstream, Academic, High Literary Fiction.
  * *Publications:* *The Economist*, *Wired*, *The New Yorker*, *Nature*.
* Built-in Style Briefs are read-only. **Duplicate as Custom** copies one into an editable Custom Target.
* **Custom Target:** A Style Brief the user writes themselves (e.g., "Write like Hemingway").

### 4.4 Scope

* **Scope Selector** (segmented control):
  1. **Sentence:** The Sentence containing the cursor. It is judged with its surrounding Paragraph sent as context, but the Readings describe only the Sentence.
  2. **Paragraph:** The Paragraph containing the cursor.
  3. **Document:** The whole Document. It is evaluated only when the user presses a button, never automatically.
* **Selection:** A highlighted selection of two or more words overrides the selector, and exactly the selection is evaluated. Clearing the selection returns to the chosen Scope.
* **Markdown structure:**
  * A Paragraph is a blank-line-separated block of prose. Each list item and blockquote is also a Paragraph.
  * Headings, code blocks and front matter are never evaluated.
  * Sentences are split with Apple's `NLTokenizer`.
* **Minimum length:** Below 4 words for a Sentence or 15 words for a Paragraph, no Evaluation runs and the Gauges show an empty state.
* **Language:** v1 supports English only. The app does not detect language. Text in other languages is evaluated, but the Readings may not be meaningful.

### 4.5 Evaluation & Gauges

* An **Evaluation** is the fast, automatic pass. It produces one Reading per Gauge and nothing else. Sentence, Paragraph and Selection Scope are evaluated 2 seconds after the user stops typing.
* **Gauges:**

| Gauge | Reading | Kind | Display |
| --- | --- | --- | --- |
| 🎯 **Alignment** | **Alignment Score** 0–100 | Judging | Letter **Grade** (A–F, +/−) derived from the score by fixed bands. The LLM never produces the letter. |
| ✂️ **Concision** | 0–100, tight → bloated, relative to the Target | Judging | Coloured good/bad |
| 🌡️ **Intensity** | 0–100, Restrained → Purple | Describing | Neutral, no good/bad colouring |
| 🎭 **Tone** | Exactly one of: Academic, Casual, Formal, Suspenseful, Humorous, Melancholic, Urgent, Neutral | Describing | Icon per Tone, neutral |

* The Gauges are the same four for every Target.
* **Following the cursor:** The Gauges always describe the Sentence or Paragraph the cursor is in. Readings are cached against the exact text, so going back to unchanged text shows its Readings instantly, without calling the LLM.
* **Stale Evaluations:** If the user types while an Evaluation is running, it is cancelled. The previous Readings stay visible, dimmed, until the next Evaluation finishes.
* **Document Scope:** The Document is split into chunks to fit the model's context window, and each chunk is evaluated. Alignment, Concision and Intensity are averaged across chunks, weighted by word count. Tone is whichever Tone covers the most words. v1 does not highlight weak passages.
* Readings are never saved. Reopening a Document starts the Evaluations again.

### 4.6 Critique

* Clicking a Gauge requests a **Critique** of that one Gauge's Reading. A Critique is generated only on request.
* A Critique quotes the writer's own text to point at problems and names the principle at stake (register, rhythm, redundancy). It **never** offers replacement wording, not even a single word, and nothing in a Critique can be inserted into the Document ([ADR 0003](./docs/adr/0003-critiques-never-rewrite.md)).
* A Critique request takes priority over a running Evaluation, which is cancelled.
* A Critique explains the Reading the user clicked. If the text it describes changes afterwards, the Critique is marked out of date.

---

## 5. Technical Requirements & Architecture

### 5.1 Technology Stack

* **Language:** Swift 6.
* **UI Framework:** SwiftUI with the Observation framework.
* **Local Backend:** Ollama REST API on `http://localhost:11434`, chosen over Apple's Foundation Models ([ADR 0004](./docs/adr/0004-ollama-not-foundation-models.md)).
* **Structured Output:** Evaluations use Ollama's structured outputs (a JSON schema passed in `format`), so the app doesn't depend on the model obeying a prompt instruction to output JSON.
* **Networking:** `URLSession`.
* **Text Segmentation:** `NaturalLanguage` (`NLTokenizer`).

### 5.2 Application Architecture

* **`ScribeCore` (local Swift package):** All logic that can be tested without the UI or a running model:
  * Splitting a Document into Sentences and Paragraphs, and applying the minimum-length rules.
  * Building prompts from text, Scope and Style Brief.
  * Mapping Alignment Scores to Grades.
  * Combining chunk Readings at Document Scope.
  * Caching Readings and detecting when an Evaluation or Critique is out of date.
  * The Ollama client, behind a seam that lets tests replace it with a fake.
* **App target (thin):** SwiftUI views, document handling (Markdown and front matter), the Ollama status and model-download screen, and wiring the editor's cursor and selection to `ScribeCore`.

### 5.3 System Requirements

* **OS:** macOS 26 or newer.
* **Hardware:** Apple Silicon (M1 and later).
* **RAM:** 16GB unified memory minimum.
* **Storage:** At least 10GB free (app plus model weights).
* **Build:** Xcode, built from source.

---

## 6. Prompt Strategy (Internal)

There are two kinds of request:

* **Evaluation prompt:** *"You are an expert editor. Judge the following [Sentence (with its Paragraph as context) / Paragraph / Selection / chunk] against this Style Brief: [Style Brief]."* The response must match a JSON schema with `alignment_score` (0–100), `concision` (0–100), `intensity` (0–100) and `tone` (an enum of the 8 Tones). It contains no prose.
* **Critique prompt:** *"Explain why this text received a [Gauge] Reading of [Reading] against this Style Brief: [Style Brief]. Quote the text to point at specific problems and name the principle involved. Do not suggest replacement words or rewritten text."*

## 7. User Flow (Example Scenario)

1. **Launch:** The user opens ScribeAI. The app confirms Ollama is running and the model is present.
2. **Set Target:** The user opens a Document and chooses the Publication *The New Yorker*.
3. **Writing:** The user writes a paragraph at Paragraph Scope.
4. **Passive Feedback:** The user pauses for 2 seconds and an Evaluation runs. The Gauges update:
   * Alignment: **C+**
   * Intensity: **72**, leaning ornate
   * Concision: **58**
   * Tone: 🤠 Casual
5. **Active Engagement:** The user clicks the **C+**.
6. **Critique:** A panel expands: *"The register is too colloquial for this Style Brief: 'really bad' and 'kind of a mess' read as spoken rather than written English. The move from the second sentence to the third has no transition, so the argument jumps."*
7. **Edit:** The user revises in their own words. The next Evaluation raises the Grade to **A−**, and the Critique is marked out of date.

## 8. Out of Scope for v1.0

* Windows/Linux support.
* Mac App Store or signed, notarized distribution.
* A first-launch setup wizard and automatic Ollama installation.
* Rewrite suggestions or applying text from a Critique, at any point (not just v1).
* Highlighting weak passages at Document Scope.
* Saving Readings or Critiques.
* Languages other than English.
* Cloud sync beyond standard iCloud Drive file saving.
* Fine-tuning models locally.
* Cloud LLM fallback, or Apple Foundation Models as a backend.

## 9. Next Steps / Action Items for Development

1. **Prompt Testing:** Build a small test set of passages and Targets. Compare the candidate models on whether their structured output is valid and their Readings are consistent, then pick the default model.
2. **Style Briefs:** Write the 9 Built-in Style Briefs.
3. **ScribeCore:** Build the Sentence/Paragraph splitting, prompt building, Grade bands and chunk combining, test-first.
4. **Ollama Client:** Add the launch status check, model download with progress, Evaluations with structured output, and Critiques.
5. **UI:** Build the document-based Markdown editor, the split pane, the Target and Scope controls, and the Gauges with expandable Critiques.
