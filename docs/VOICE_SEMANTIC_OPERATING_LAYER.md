# OpenLoop Voice Semantic Operating Layer

Status: product and systems architecture direction  
Audience: product, design, application, ML, infrastructure, and evaluation work  
Primary constraint: private and useful by default, with a complete local/offline path

## 1. Product thesis

OpenLoop should not become another product that converts voice into transcripts, summaries, tasks, and action items. Those are useful capabilities, but they are table stakes and they are not the product center.

OpenLoop should become a private AI layer for the computer that turns natural speech into durable, usable context and can act through connected tools when the user explicitly asks.

The core experience is:

```text
SPEAK
  ↓
UNDERSTAND
  ↓
REMEMBER
  ↓
CONNECT
  ↓
EMERGE
  ↓
ASK
  ↓
ACT
```

The system continuously distinguishes:

```text
WHAT WAS SAID
      ↓
WHAT IT MAY MEAN
      ↓
WHAT CONTEXT IT RELATES TO
      ↓
WHAT COULD BE DONE
      ↓
WHAT SHOULD BE REMEMBERED
      ↓
WHAT THE USER HAS AUTHORIZED IT TO DO
```

Transcription is the sensory layer. The product is the semantic memory and action system built on top of it.

### Positioning

Avoid positioning OpenLoop as:

- AI voice notes
- an AI meeting assistant
- an AI task manager
- a voice-to-text utility

Position it as:

> A private AI layer for your computer that listens when invited, understands context, remembers how your thinking evolves, and lets you act through natural language.

The technical differentiator is the combination of local semantic memory, contextual voice intelligence, and permission-aware MCP actions.

## 2. Product principles

### 2.1 Observations before tasks

Speech should create evidence and observations first. It should not create a task merely because a sentence contains words such as “should,” “need,” or “probably.”

“The checkout is getting slow after we added PostHog” is an observation with a possible causal relationship. “Maybe we should migrate to Postgres” is a possibility. Neither is an explicit commitment.

Tasks are created only when:

- the user expresses a clear commitment;
- the user confirms a suggested action;
- a connected workflow has an explicit rule that authorizes task creation.

### 2.2 Quiet, latent intelligence

The system should do useful semantic work without interrupting the user. It can retain high-confidence understanding, keep low-confidence interpretations provisional, and surface recurring or relevant threads later.

It should not generate a stream of unsolicited summaries, suggestions, and fake urgency. The system earns attention only when it has strong evidence that something is repeated, relevant, unresolved, or explicitly requested.

### 2.3 Evidence before inference

Every semantic claim points back to immutable evidence: original audio, raw transcript spans, application context, imported material, or tool results. Rewriting and inference never replace raw evidence.

### 2.4 Confidence is part of the data

Semantic objects carry calibrated confidence and epistemic status. The UI and action router must distinguish settled facts, working interpretations, and suspect inferences.

### 2.5 Beliefs evolve through supersession

Old beliefs are not edited out of history. A new claim supersedes an earlier claim and records why. The system must be able to answer:

> What did I believe about this six months ago, and what changed my mind?

### 2.6 Local-first does not mean single-model

A serious local system uses specialized components for audio conditioning, voice activity, speech recognition, fusion, editing, intent routing, memory, and execution. Local quality comes from composition and routing, not from forcing one model to solve every problem.

### 2.7 MCP gives the system hands

MCP is an execution layer, not the product identity. Users speak in terms of goals. The system discovers which connected capabilities can observe, prepare, or perform the requested work.

## 3. Target user experience

The immediate interaction should feel like system-wide dictation:

- one configurable global push-to-talk shortcut;
- continuous microphone feedback with a red recording state and live dB meter;
- low-latency partial text while speaking;
- stable text separated from unstable text;
- automatic language and code-switch detection;
- modes for raw dictation, polished prose, code, email, casual text, bullets, Markdown, and structured data;
- output into Chrome, VS Code, terminals, Slack, Discord, and other focused applications;
- accessibility insertion first, clipboard insertion with restoration second, and simulated keyboard input as a last fallback;
- optional spoken feedback for confirmations and accessibility;
- visible progress and recovery when a model is loading, downloading, retrying, or falling back.

The longer-term interaction should feel like semantic continuity:

1. The user speaks naturally while working.
2. OpenLoop stores evidence and extracts provisional meaning.
3. Repeated concepts form threads without becoming tasks.
4. The user asks about a remembered topic in ordinary language.
5. OpenLoop retrieves the relevant belief history and evidence.
6. When the user decides to act, the MCP router identifies suitable tools.
7. OpenLoop observes, proposes, or acts according to the granted permission level.

## 4. System architecture

```text
GLOBAL HOTKEY / IMPORT / CONTINUOUS SESSION
                     │
                     ▼
              AUDIO CAPTURE
       16 kHz mono PCM + device metadata
                     │
                     ▼
                AUDIO DSP
     AEC · noise suppression · AGC · filter
                     │
                     ▼
                SILERO VAD
    speech start/end · preroll · endpointing
                     │
                     ▼
              ROLLING BUFFER
     stable audio spans + current open span
                     │
                     ▼
          LOCAL RECOGNITION ROUTER
       Qwen3-ASR accuracy-first final text
       Whisper large-v3 timestamp fallback
       uncertainty-based second-pass routing
                     │
                     ▼
             TRANSCRIPT FUSION
  agreement · vocabulary · correction evidence
                     │
                     ▼
              INTENT ROUTER
 raw insert · command · format · ambiguous request
                     │
          ┌──────────┴──────────┐
          ▼                     ▼
 DETERMINISTIC PATH       LOCAL LLM PATH
 exact normalization      compact editor or
 direct insertion         larger model escalation
          └──────────┬──────────┘
                     ▼
              CONTEXT ENGINE
 app · field · selection · bounded surrounding text
                     │
          ┌──────────┴──────────┐
          ▼                     ▼
   SEMANTIC MEMORY         OUTPUT ADAPTER
 evidence-backed graph     AX · clipboard · keyboard
          │                     │
          ▼                     ▼
     ASK / EMERGING          FOCUSED APP
          │
          ▼
   PERMISSIONED MCP ROUTER
 observe · suggest · act
```

## 5. Local speech pipeline

### 5.1 Audio capture

Capture the microphone once and distribute normalized frames to metering, VAD, recording, and partial transcription. Do not create independent microphone sessions for each subsystem.

Target format:

- 16 kHz mono float PCM for model input;
- retain the original recording when meeting fidelity matters;
- process 20–32 ms frames;
- keep a short preroll buffer so initial phonemes are not clipped;
- record input device, sample rate, peak dB, and clipping events for diagnostics.

### 5.2 Audio conditioning

The production pipeline should support:

- acoustic echo cancellation when speaker playback can leak into the microphone;
- noise suppression for fan, traffic, keyboard, and room noise;
- automatic gain control with conservative limits;
- a speech-oriented high-pass filter;
- resampling to the recognizer’s native sample rate;
- clipping and low-signal detection.

WebRTC audio processing is a strong reference for AEC, noise suppression, and gain control. RNNoise-style suppression is a candidate for targeted noise reduction. Each stage must be benchmarked against raw audio because aggressive processing can damage Indian accents, quiet consonants, and code-switched speech.

### 5.3 Voice activity detection

Use Silero VAD as the speech boundary authority. Recognition models should not be responsible for deciding whether speech exists.

VAD responsibilities:

- detect speech start and end;
- retain preroll and short trailing context;
- avoid inference on silence;
- trigger partial recognition during an open segment;
- automatically stop after an appropriate pause when the interaction mode allows it;
- split long speech at quiet boundaries without losing words.

### 5.4 Streaming text model

Maintain two visible transcript regions:

```text
STABLE
Let's refactor the authentication

UNSTABLE
middleware because
```

The stable region contains finalized spans. The unstable region is replaceable and is decoded from the current rolling audio window. Partial results should normally refresh every 300–800 ms. The final pass can use more context and more compute than the partial pass.

The system should measure:

- time to first visible partial;
- partial stabilization time;
- stop-to-final latency;
- final correctness;
- partial churn, meaning how often already-visible words change.

### 5.5 Recognition engines

Do not choose an engine solely from public benchmark speed. Benchmark the actual target speech:

- Indian English;
- Devanagari Hindi;
- Romanized Hinglish;
- English-to-Hindi and Hindi-to-English switches inside one sentence;
- project names, acronyms, people, and technical terminology;
- laptop microphones under fan, keyboard, room, and traffic noise;
- short dictation and long meetings.

Whisper large-v3 remains a valuable baseline because it is mature, multilingual, timestamped, and already integrated through WhisperKit. Qwen3-ASR is the accuracy-first candidate for final code-switched text. On the retained 13.6-second OpenLoop sample, Qwen3-ASR 0.6B produced:

> मैं यह सोच रहा था कि release time जो है, वो क्या हम कम कर सकते हैं? Can we reduce the release time for SGLC releases?

This materially improved the corresponding Whisper output and ran locally on the M4 GPU. That result justifies integration and broader evaluation; it does not by itself establish universal superiority.

Candidate recognizers should include:

- Whisper large-v3;
- Whisper large-v3 Turbo;
- WhisperKit and whisper.cpp deployment paths;
- faster-whisper/CTranslate2 on supported NVIDIA systems;
- Qwen3-ASR 0.6B and 1.7B quantized variants;
- newer compatible models only after they pass the personal evaluation corpus.

On Apple Silicon, keep the selected MLX model warm in unified memory. On NVIDIA systems, keep the chosen CTranslate2 or CUDA model resident in VRAM. Avoid a load-transcribe-unload cycle for interactive dictation.

### 5.6 Ensemble policy

An ensemble should not run every recognizer over every frame. Use routing:

1. A fast primary produces partials and an initial final result.
2. The quality system identifies uncertain spans, language switches, dropped spans, and domain-term mismatches.
3. A second recognizer processes only those spans or the complete utterance when evidence is insufficient.
4. Fusion accepts exact agreement, applies learned terminology, and marks unresolved disagreement.
5. Raw outputs from each engine remain inspectable in Advanced mode.

For meetings, Whisper can continue to provide word timestamps and speaker alignment while Qwen provides the stronger final wording. Forced alignment can map the chosen text back onto the audio timeline.

### 5.7 Accuracy metric

The primary product metric is:

> Time from stopping speech to correct final text.

Supporting metrics:

- word error rate for Latin-script text;
- character error rate for Devanagari;
- code-switch boundary preservation;
- proper-name and technical-term recall;
- acronym recall;
- dropped-span rate;
- hallucinated-span rate;
- p50 and p95 time to first partial;
- p50 and p95 stop-to-final latency;
- memory pressure, energy impact, and thermal behavior;
- correction rate after insertion.

## 6. Vocabulary and correction learning

Vocabulary should be automatic and scoped. A conceptual local layout is:

```text
OpenLoop vocabulary
├── global
├── programming
├── projects
└── personal
```

A vocabulary entry can contain a canonical term and observed variants:

```json
{
  "canonical": "TanStack Query",
  "variants": ["tan stack query", "tanstack query"],
  "scope": "programming",
  "evidenceCount": 4,
  "lastConfirmedAt": "2026-08-21T00:00:00Z"
}
```

Vocabulary participates in two distinct stages:

1. Recognition context supplies names and terms to models that support bounded hints.
2. Deterministic normalization replaces only sufficiently evidenced variants in an appropriate context.

Correction learning rules:

- keep recognized and corrected text separately;
- derive terminology from user edits;
- require repeated evidence before applying broad replacements;
- prefer anchored replacements with surrounding words;
- scope project vocabulary to matching application or repository context;
- never force Hindi or any other language globally;
- detect language automatically by default;
- make every learned rule visible, reversible, and deletable.

## 7. Local semantic editing

Speech recognition answers “what sounds were spoken?” A semantic editor answers “how should those words be represented for this destination?” They are separate outputs.

Example:

```text
RAW
uh so basically we need to move this to redis because it's kind of slow

POLISHED
We need to move this to Redis because it's slow.
```

The polished result must link to the raw result. Users must be able to inspect, copy, restore, and correct the raw text.

### 7.1 Modes

Support explicit modes:

- Raw: punctuation only when produced by the recognizer; no semantic rewrite.
- Polished: remove fillers, repair punctuation, preserve intent and detail.
- Code: preserve identifiers, syntax, indentation, filenames, commands, and literals.
- Email: add conventional greeting, paragraphs, and closing only when requested or configured.
- Casual: retain conversational tone.
- Bullets: structure independent points without inventing new ones.
- Markdown: produce valid headings, lists, links, and code fences from spoken structure.
- JSON: emit schema-valid data or surface a validation failure.

### 7.2 Routing

Do not send every transcript through an LLM.

```text
TRANSCRIPT
   │
   ├── clean raw dictation ───────────────→ INSERT
   ├── deterministic normalization ───────→ NORMALIZE → INSERT
   ├── explicit safe command ─────────────→ COMMAND ROUTER
   ├── requested formatting ──────────────→ COMPACT LOCAL MODEL
   └── ambiguous or difficult operation ─→ LARGE LOCAL MODEL
```

The compact model handles punctuation, filler removal, ordinary formatting, and simple intent classification. A larger quantized model is loaded only for difficult transformations, multi-step reasoning, or ambiguous requests. It should not remain resident when the interactive ASR working set needs the memory.

On a 24 GB Apple Silicon system, model policy must include explicit memory budgets and unload behavior. The system should never swap heavily merely to polish a short sentence.

### 7.3 Meaning-preservation contract

The editor must not silently:

- change names, numbers, dates, commands, URLs, file paths, or code identifiers;
- turn a possibility into a decision;
- turn a suggestion into a commitment;
- remove negation;
- add facts that are absent from the transcript;
- translate unless translation was requested;
- convert Hindi into English merely for stylistic uniformity.

High-risk transformations should show a raw/polished comparison or remain in Raw mode.

## 8. Context engine

The context engine supplies bounded, consented information needed to recognize terminology and format output correctly.

Possible inputs:

- active application and bundle identifier;
- focused control role;
- selected text;
- bounded surrounding text;
- current document or repository name;
- terminal working directory;
- clipboard content when explicitly enabled;
- active OpenLoop mode;
- relevant personal or project vocabulary;
- recent semantic thread chosen by retrieval.

Context must be minimized by default. Sensitive field roles, password inputs, private browser contexts, and excluded applications must block capture. Temporary context used for recognition or editing should not automatically become durable memory.

App-specific behavior belongs in policies, not model folklore. VS Code may favor Code mode and repository vocabulary; Slack may favor Casual mode; a terminal must preserve shell syntax; an email composer may use Email mode only when configured.

## 9. Output adapters

Use a layered insertion strategy:

1. Accessibility API insertion into the focused editable element.
2. Clipboard insertion while preserving and restoring the previous clipboard value.
3. Simulated keyboard input when neither direct insertion nor paste is available.
4. App-specific APIs for integrations that explicitly support richer structured output.

Each insertion records the adapter used, destination application, success or failure, and whether the clipboard was restored. It must never log the content in plaintext diagnostics.

Voice commands and generated actions require a separate command path. Dictated text must never be executed merely because it resembles a shell command.

## 10. Semantic graph

### 10.1 Fundamental objects

The core database is not a set of transcripts, summaries, and tasks. It is an evidence-backed graph of:

- entities;
- events;
- observations;
- facts;
- concepts;
- projects;
- people;
- technologies;
- problems;
- ideas;
- questions;
- possibilities;
- preferences;
- decisions;
- intentions;
- actions;
- procedures;
- references;
- relationships.

Transcripts are evidence sources. Tasks are one optional projection of explicit intentions and actions.

### 10.2 Semantic object schema

```swift
struct SemanticObject: Codable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        case observation
        case fact
        case problem
        case idea
        case question
        case possibility
        case preference
        case decision
        case intention
        case action
        case procedure
        case reference
    }

    enum Confidence: String, Codable, Sendable {
        case settled
        case working
        case suspect
    }

    let id: UUID
    let kind: Kind
    let claim: String
    let confidence: Confidence
    let confidenceScore: Double
    let status: String?
    let createdAt: Date
    let supersededBy: UUID?
    let evidence: [EvidenceReference]
    let context: [ContextReference]
}
```

The implementation may evolve, but it must retain type, confidence, status, evidence, context, creation time, and supersession.

### 10.3 Relationships

Relationships are first-class, directional, evidence-backed, and confidence-scored. Initial relationship types include:

- `about`
- `partOf`
- `mentions`
- `relatedTo`
- `possiblyCausedBy`
- `contradicts`
- `supports`
- `supersedes`
- `dependsOn`
- `blocks`
- `motivates`
- `resultedIn`
- `ownedBy`
- `appliesTo`

Do not collapse “possibly caused by” into “caused by.” Epistemic precision is a product feature.

### 10.4 Note representation

Every durable note can be rendered as a human-readable file:

```yaml
---
id: checkout-performance-after-posthog
kind: observation
claim: Checkout performance degraded after the PostHog integration.
confidence: working
superseded-by:
---
```

The body explains why the claim exists, which evidence supports it, and what would break if it were false. Links use explicit references such as `[[storefront-project]]`, `[[posthog]]`, and `[[checkout-performance-thread]]` in prose.

The storage implementation can remain encrypted and structured while providing deterministic export to this representation.

### 10.5 Four graph operations

1. **Capture** — preserve an episode with near-zero friction.
2. **Link** — connect every promoted semantic object to at least one existing object or an explicit root context.
3. **Supersede** — add a new claim and stamp the old claim with its successor; do not edit belief history in place.
4. **Consolidate** — periodically condense repeated episodes into a fact, procedure, preference, or thread while retaining archived source evidence.

Links and consolidation prevent the system from becoming a chronological pile.

### 10.6 Example: observation, not task

Input:

> The checkout is getting really slow after we added PostHog.

Possible graph result:

```text
Observation
  claim: Checkout performance has degraded.
  confidence: working

Context
  project: Storefront
  component: Checkout
  technology: PostHog

Relationship
  Checkout degradation possiblyCausedBy PostHog integration
  confidenceScore: 0.71

Potential action
  Investigate checkout performance
  status: uncommitted

Evidence
  original audio + transcript span + timestamp
```

No task is created.

### 10.7 Example: extracting multiple signals

Input:

> I'm going to rewrite this in Go because Node is killing us with memory usage, and I should probably benchmark it against the current implementation.

Extract:

- observation: the Node implementation has memory concerns;
- intention: investigate or pursue a Go rewrite;
- possibility: the Go rewrite may improve memory usage;
- potential action: benchmark Go against the current Node implementation;
- technologies: Go and Node.js;
- project: current repository or explicit project;
- uncertainty: benchmark is suggested, not yet committed;
- evidence: exact audio and transcript span.

## 11. Semantic compression

Do not summarize activity into vague prose. Compress meaning into queryable state.

Weak representation:

> Dhruv discussed performance problems.

Useful representation:

```text
Problem: Checkout performance
Project: Storefront
Component: Checkout
Possible contributor: PostHog
First observed: 2026-08-21
Status: unresolved
Evidence: episode 381, span 14.2–18.8s
```

The transcript remains available, but the semantic state becomes machine-usable for recurrence detection, retrieval, and tool routing.

## 12. Latent-intelligence surfaces

### 12.1 Threads

Threads collect repeated, connected meaning across episodes:

```text
Checkout performance
├── mentioned 8 times
├── PostHog
├── Cloudflare
├── caching
└── Redis
```

A thread is not automatically a project or a task. It is an evolving cluster with evidence, recurrence, and status.

### 12.2 Emerging

Emerging surfaces concepts that are becoming important based on recurrence, recency, cross-context breadth, and unresolved status.

```text
Authentication architecture     mentioned 11 times
Checkout performance            mentioned 7 times
Local AI infrastructure         mentioned 5 times
```

Useful language is factual and restrained:

> You have mentioned separating authentication six times across nine days. You have not explicitly decided to do it.

### 12.3 Connections

Connections surface recurring co-occurrence and evidence-backed relationships:

```text
PostHog
├── checkout
├── performance
├── bundle size
└── analytics

These concepts appeared together in four episodes.
```

### 12.4 Unresolved

Unresolved contains questions, contradictions, and problems without confirmed resolution:

```text
Why is checkout slow?

Related evidence mentions:
- PostHog
- Stripe
- image loading
- Cloudflare

No confirmed cause exists yet.
```

The system must not promote a frequently mentioned hypothesis into a fact.

## 13. Ask your context

Ask is a natural-language interface over semantic objects, relationships, belief history, and original evidence.

Representative questions:

- What have I been thinking about regarding authentication?
- What problems have I repeatedly noticed in this project?
- What did I say about checkout performance last week?
- Why did I decide against Redis?
- What did I believe about this six months ago?
- What evidence changed my mind?
- I remember wanting to fix something with PostHog. What was it?

Answers should:

- distinguish fact from inference;
- show confidence and unresolved contradictions;
- cite the underlying episode, audio span, transcript, document, or tool result;
- reveal belief changes through supersession links;
- avoid presenting generated prose as original evidence.

Initial retrieval can remain simple: exact search, links, temporal filters, and an LLM reading a bounded set of files or objects. Add an embedding or graph index only when measured retrieval failures require it.

## 14. MCP action layer

### 14.1 Capability graph

Users should see connected capabilities, not server implementation details:

```text
CONNECTED

GitHub       ✓
Slack        ✓
Linear       ✓
Notion       ✓
Filesystem   ✓
VS Code      ✓
Browser      ✓
Terminal     ✓
```

Internally:

```text
MCP SERVER
    ↓
TOOLS
    ↓
CAPABILITY REGISTRY
    ↓
SEMANTIC ROUTER
    ↓
PERMISSION CHECK
    ↓
PLAN / ACTION
```

The user should be able to say “What happened to the deployment?” The router maps deployment investigation to available Vercel, GitHub, Sentry, or Cloudflare capabilities without requiring the phrase “use the Vercel MCP.”

### 14.2 Permission levels

Every capability declares separate authority:

- **Observe** — read bounded context and retrieve evidence.
- **Suggest** — analyze and prepare a proposed action or change.
- **Act** — perform an external mutation after policy and confirmation checks.

Example:

```text
GitHub
READ        allowed
ANALYZE     allowed
CREATE PR   confirmation required
MERGE       not allowed
DELETE      not allowed
```

Dangerous, destructive, financial, publishing, or externally visible actions require explicit confirmation. A broad instruction to “make it work” does not expand tool authority.

### 14.3 Contextual action flow

Example:

1. The user says the authentication logic is becoming coupled and may need extraction.
2. OpenLoop records an observation and a possible direction. It performs no external action.
3. Later the user says, “Actually, let’s do it.”
4. OpenLoop resolves the prior thread and asks whether it may inspect the current structure.
5. With approval, filesystem, IDE, or GitHub capabilities inspect the code.
6. OpenLoop reports the evidence and proposes a bounded change.
7. The user says, “Do it.”
8. The action layer makes the change within the granted scope and returns verification evidence.

## 15. GUI information architecture

Avoid building dozens of disconnected screens. The durable interface has five primary surfaces.

### 15.1 Live

Purpose: immediate voice interaction.

Show:

- red recording state;
- elapsed time;
- dB meter and VAD state;
- stable and unstable transcript;
- current mode;
- active application destination;
- stop, cancel, raw/polished, and undo controls;
- concise engine state and fallback feedback.

### 15.2 Context

Purpose: inspect what the system currently understands.

Show:

- active project;
- people;
- technologies;
- topics;
- observations;
- problems;
- decisions;
- ideas;
- current confidence and evidence.

### 15.3 Emerging

Purpose: expose repeated themes, unresolved questions, new connections, and potential directions without treating them as commitments.

Each item shows recurrence, time range, status, confidence, and supporting episodes.

### 15.4 Ask

Purpose: query semantic state and belief history in natural language. Answers remain linked to raw evidence.

### 15.5 Act

Purpose: inspect connected capabilities, permission levels, pending proposals, confirmations, execution state, and action history.

### 15.6 Advanced mode

Advanced mode provides full system visibility without cluttering the normal experience:

- capture device and format;
- live dB and VAD probabilities;
- rolling-buffer state;
- active recognizer and model version;
- model download and memory residency;
- raw outputs from each recognizer;
- fusion agreements and disagreements;
- personal vocabulary hits;
- editor route and model;
- semantic objects emitted with confidence;
- context sources used;
- output adapter chosen;
- MCP capability and permission decision;
- stage latency and failure reason.

## 16. Storage, privacy, and provenance

Local/private mode means audio, transcripts, semantic objects, vocabulary, corrections, context, and model processing remain on the device. Model downloads are the only network requirement for the offline path.

Storage rules:

- encrypt durable evidence and semantic state;
- retain raw and transformed text separately;
- keep explicit provenance for every generated object;
- use immutable IDs and append-only supersession records;
- allow deletion and export by evidence source, project, person, or time range;
- do not retain temporary app context unless a semantic object explicitly cites it;
- never store password-field contents;
- make retention policy visible and enforceable;
- make model and rule versions part of provenance.

## 17. Reliability and observability

A sellable system must explain what is happening.

Each voice session records a safe diagnostic envelope:

- session ID;
- input device and sample format;
- duration, peak dB, clipping, and speech duration;
- VAD boundaries;
- recognizer model/version;
- model load and inference latency;
- fallback attempts and reasons;
- partial count and stabilization time;
- detected languages;
- vocabulary hits without logging unrelated surrounding content;
- output mode and adapter;
- whether semantic extraction occurred;
- whether an external action was proposed or executed.

The GUI should translate this into clear feedback:

- “Listening — strong signal”
- “Speech detected”
- “Finalizing locally with Qwen”
- “Checking an uncertain Hindi span with Whisper”
- “Polishing for VS Code”
- “Inserted through Accessibility”
- “Could not access the focused field; copied instead”

Failures preserve audio and raw transcript when possible and offer a bounded retry. The app must not relaunch itself repeatedly to verify behavior.

## 18. Evaluation corpus and release gate

Build a user-corrected corpus from real interactions. Each case includes:

- source audio or a privacy-preserving local reference;
- exact reference transcript;
- language sequence;
- required names, acronyms, and technical terms;
- acoustic condition;
- destination mode;
- expected semantic objects;
- forbidden interpretations;
- expected latency class.

Test categories:

- short clean English;
- short clean Hindi;
- English-Hindi-English code switching;
- Romanized Hinglish;
- Indian English names and acronyms;
- code and command dictation;
- laptop fan and keyboard noise;
- room echo and speaker leakage;
- quiet speech and low microphone level;
- long meeting speech;
- ambiguous possibilities versus decisions;
- negation and correction;
- action requests with permission boundaries.

Do not claim superiority over Wispr Flow until the target corpus demonstrates:

- lower code-switched WER/CER on the intended users;
- equal or better terminology recall;
- no silent dropped spans;
- no unacceptable semantic meaning changes;
- acceptable p95 stop-to-final latency;
- reliable insertion across target applications;
- correct permission behavior for external actions.

## 19. Staged implementation

### Stage A: trustworthy local dictation

- Qwen3-ASR accuracy-first final text;
- Whisper fallback;
- automatic language detection;
- learned vocabulary context;
- stable/unstable transcript interface;
- global push-to-talk;
- visible dB/VAD/engine state;
- raw transcript preservation;
- Accessibility, clipboard, and keyboard output adapters.

### Stage B: semantic evidence graph

- semantic object and relationship schemas;
- confidence and epistemic status;
- immutable evidence references;
- link and supersede operations;
- editable transcript correction loop;
- project and application context;
- simple exact retrieval and evidence views.

### Stage C: latent intelligence

- thread discovery;
- Emerging and Unresolved projections;
- recurrence and connection scoring;
- scheduled consolidation of repeated episodes;
- Ask over semantic state and belief history;
- restrained surfacing thresholds.

### Stage D: local semantic routing

- Raw, Polished, Code, Email, Casual, Bullets, Markdown, and JSON modes;
- compact local editor;
- larger model escalation;
- meaning-preservation checks;
- deterministic voice commands;
- raw/polished comparison and undo.

### Stage E: MCP-native action

- capability registry;
- Observe, Suggest, and Act permissions;
- automatic capability discovery;
- proposal and confirmation workflow;
- action provenance and rollback information;
- initial high-value GitHub, filesystem, IDE, browser, terminal, Linear, Slack, and Notion integrations according to available connectors.

## 20. Explicit anti-goals

OpenLoop must not:

- turn every utterance into a task;
- treat every suggestion as a decision;
- interrupt the user with low-confidence insights;
- hide model failures or fallback behavior;
- overwrite raw transcripts with polished text;
- require users to select Hindi or English for every recording;
- require user-written prompts for ordinary multilingual speech;
- make the user choose an MCP server by name;
- execute text merely because it resembles a command;
- grant mutation authority based on inferred intent;
- delete superseded beliefs from history;
- add a complex index before simple retrieval has demonstrably failed;
- optimize benchmark throughput at the expense of correct final text.

## 21. Product health tests

The system is healthy when it can answer these questions with evidence:

- What did I believe about this topic six months ago?
- Which evidence changed that belief?
- What have I repeatedly noticed but not committed to fixing?
- Which ideas are becoming important across projects?
- Which claims are facts, which are working interpretations, and which are suspect?
- What did I mean when I referred to “that checkout thing”?
- Which tools could investigate this, and what authority do they have?
- What will happen before OpenLoop performs an external action?
- What exact audio and transcript support this semantic claim?
- How long did the last utterance take from stop to correct final text?

If OpenLoop cannot answer these, it has accumulated content rather than built a trustworthy semantic operating layer.
