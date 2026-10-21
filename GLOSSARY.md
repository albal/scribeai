# ScribeAI

A local, private co-editor that grades a writer's prose against a chosen writing standard while they write.

## Writing

**Document**:
A single piece of writing the user composes and saves in ScribeAI.
_Avoid_: Work, Canvas, file, manuscript

## Targets

**Target**:
The writing standard a Document is judged against. Every evaluation is measured against exactly one Target; each Document has its own, defaulting to an app-wide choice.
_Avoid_: Goal, style, mode

**Level**:
A kind of Target describing a readership or literary register, such as Young Adult or High Literary Fiction.
_Avoid_: Literary Level, grade level

**Publication**:
A kind of Target describing the house style of a named outlet, such as *The Economist* or *The New Yorker*.
_Avoid_: Target Publication, outlet, magazine

**Custom Target**:
A kind of Target the user describes in their own words, such as "write like Hemingway". It is simply a user-written Style Brief.
_Avoid_: Custom Prompt

**Style Brief**:
The short written description of a Target's standard (sentence length, vocabulary, register, things to avoid) that text is judged against. Every Target has one.
_Avoid_: Style guide, prompt, persona

**Built-in Target**:
A Level or Publication shipped with ScribeAI, whose Style Brief the writer cannot edit but can duplicate into a Custom Target.
_Avoid_: Preset, default Target

## Evaluating

**Scope**:
The span of text being evaluated: a **Sentence**, a **Paragraph**, the whole **Document**, or a **Selection** the writer has highlighted. A Selection overrides the chosen Scope while it exists. Sentence, Paragraph and Selection Scope are evaluated automatically when the writer pauses; Document Scope only on request.
_Avoid_: Granularity, Complete Work, highlighted sentence

**Paragraph**:
A blank-line-separated block of prose; each list item and blockquote is also a Paragraph. Headings and code are never prose and are never evaluated.
_Avoid_: Block, passage

**Evaluation**:
The fast, automatic assessment of the text in the current Scope against its Target, producing one Reading per Gauge and nothing else. An Evaluation overtaken by further typing is discarded.
_Avoid_: Analysis, check, grading, pass

**Reading**:
The value a single Gauge shows as the result of an Evaluation.
_Avoid_: Score (except for Alignment Score), result, metric

**Critique**:
The written explanation of why one Gauge shows its Reading, produced only when the writer asks for it. A Critique diagnoses; it never offers rewritten text.
_Avoid_: Feedback, detailed critique, review, drill-down, suggestion

## Gauges

**Gauge**:
One of the four fixed at-a-glance indicators shown for every Evaluation: Alignment, Intensity, Concision and Tone. Alignment and Concision are **judging** Gauges (good or bad relative to the Target); Intensity and Tone are **describing** Gauges (neutral, neither good nor bad).
_Avoid_: Icon, dashboard, meter, indicator

**Alignment Score**:
A number from 0 to 100 measuring how closely the text matches its Target. It is the canonical measure of alignment.
_Avoid_: Target Alignment Score, rating

**Grade**:
The letter (A–F, with +/−) shown for an Alignment Score, derived from it by fixed bands. A display of the score, never assessed independently.
_Avoid_: Letter grade, mark

**Intensity**:
How ornate, heightened or emotionally charged the prose is, from restrained to purple.
_Avoid_: Temperature, Stylistic Temperature, heat

**Concision**:
How economically the text uses words, from tight to bloated, judged relative to the Target.
_Avoid_: Bloat, wordiness

**Tone**:
The perceived emotional or social register of the text, always exactly one of: Academic, Casual, Formal, Suspenseful, Humorous, Melancholic, Urgent, Neutral.
_Avoid_: Mood, voice
