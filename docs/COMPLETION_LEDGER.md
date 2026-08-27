# Product Completion Ledger

This ledger is the source of truth for whether OpenLoop's product promises work
end to end. A type, view, or test double is not enough to mark a behavior done.
Each item needs a user-visible path, durable data behavior, and representative
verification.

## Status definitions

- **Shipped** — wired through the installed product and covered by deterministic
  tests or a representative acceptance fixture.
- **Partial** — useful implementation exists, but a system boundary, recovery
  path, or representative proof is missing.
- **Blocked** — implementation is ready or understood, but completion requires
  credentials or authority not present in this workspace.
- **Missing** — no end-to-end production implementation exists.

## Voice and transcription

| Requirement | Status | Completion gate |
| --- | --- | --- |
| One global shortcut for dictation | Shipped | Control–Option–Space starts and stops local dictation. |
| Immediate lossless recording | Shipped | Durable audio starts before VAD or ASR model preparation. |
| Red recording state and live dB feedback | Shipped | Main window and non-activating global HUD share the same recording state. |
| Stable and partial text while speaking | Shipped | Streaming inference is coalesced and exposes stable plus partial regions. |
| Automatic Hindi/English/Hinglish | Partial | The retained English-Hindi-English failure now passes with official full large-v3; Punjabi, Spanish, romanized-Hinglish, and a held-out corpus remain. |
| Long meeting transcription | Partial | Recognition is bounded into timestamped spans; a representative 25-minute audio fixture is still required. |
| Accuracy-first local final | Partial | Official whisper.cpp full large-v3 owns final words and missing witnesses are visible; a human-confirmed held-out corpus remains. |
| Personal and technical vocabulary | Shipped | Corrections persist and feed recognition/normalization. |
| Audio conditioning | Partial | Raw audio now owns final recognition after conditioning harmed the retained code-switch; conditioning remains an evaluated optional path. |
| Raw, polished, code, email, casual, Markdown, bullets, JSON | Partial | Modes exist; JSON/code validation and distinct fast/deep editors remain. |
| App-aware insertion | Partial | Context and three output routes exist; per-app policies and clipboard timing remain. |
| Optional cloud route | Missing | Must be explicit, opt-in, and visibly separate from local mode. |
| Optional spoken feedback | Missing | Add only after latency and status feedback are stable. |

## Memory and action

| Requirement | Status | Completion gate |
| --- | --- | --- |
| Durable captures and task/focus lifecycle | Shipped | Capture, review, Now, Later, Return, reorder, start, interrupt, resume, finish, and release persist. |
| Evidence-backed transcript brief | Shipped | Versioned local interpretations persist separately and reject ungrounded excerpts. |
| Typed semantic graph with confidence and supersession | Shipped | Nodes, relations, vectors, evidence, and history persist in the encrypted event ledger. |
| Automatic semantic extraction | Shipped | One utterance can produce multiple typed, confidence-bearing objects with exact evidence. |
| Emerging, Connections, Unresolved | Shipped | Automatic relations and recurrence ranking drive these evidence-backed surfaces. |
| Ask your context | Shipped | Retrieval combines lexical, multilingual vector, graph, recency, confidence, and belief history signals. |
| Consolidation and belief history | Shipped | Recurring derived meanings consolidate through append-only supersession without deleting episodes. |
| MCP Observe/Suggest/Act | Shipped | Local stdio discovery, persisted grants, prepare/confirm, execution, and audit are connected. |

## Native experience

| Requirement | Status | Completion gate |
| --- | --- | --- |
| Simple task management | Shipped | Core capture, Now, Inbox, Later, Return, edit, reorder, finish, and release work. |
| Things-like spacing and hierarchy | Shipped | Native tokens use the documented reading measure, row grammar, warm neutrals, restrained blue accent, and expanded edge spacing. |
| Things-like Move and drag/drop | Partial | Add destination moves, sidebar drops, transactional undo, keyboard parity, and multi-selection. |
| Quick Find and type-to-travel | Shipped | Command-F searches lists and tasks and travels without mouse-only traversal. |
| Headings, checklists, dates, Upcoming, Someday, Spaces | Partial | Task metadata and time destinations are domain-backed and editable; user-defined Spaces remain. |
| Slim mode and multiple windows | Missing | Use a resizable/collapsible native split layout and independent window navigation. |
| First-class transcript destination | Shipped | Completed recordings surface in Transcripts with raw evidence and saved interpretation. |
| Advanced observability | Partial | Diagnostics exist; collapse inactive groups and keep only the live signal pinned. |
| Interactive 3D stored-memory graph | Partial | Orbit/zoom/evidence work; add full-space mode, search/filter, labels, and truthful projection wording. |

## Website, repository, and distribution

| Requirement | Status | Completion gate |
| --- | --- | --- |
| Design-led product website | Shipped | Code-native product proof, legal/accessibility pages, metadata, responsive navigation, and motion build successfully. |
| Direct DMG download | Shipped | The website links to the versioned DMG and checksum with install and signing disclosure. |
| Clean public repository | Shipped | Capability-oriented source tree, architecture, contribution, security, CI, and release workflows exist. |
| GitHub Pages deployment | Blocked | Repository admin must enable Pages once; current CLI identity has read-only permission. |
| Repository description/homepage/topics | Blocked | Run `Scripts/configure-github.sh` from an admin-authenticated GitHub CLI session. |
| Stable Developer ID signing and notarization | Blocked | Requires Apple Developer certificate, team, and notary credentials. |
| No recurring Keychain password prompt | Shipped | Release key selection migrates once to a protected stable local key without recurring prompts. |
| Better-than-leading-products claim | Blocked | Requires a representative corrected audio corpus and measured comparative accuracy/latency evidence. |

## Execution order

1. Make release key selection migration-safe and correct source-audio retention.
2. Start durable recording immediately and add bounded streaming back-pressure.
3. Wire a non-activating global dictation HUD and first-class transcripts.
4. Segment multilingual and long-form ASR; expose and resolve disagreements.
5. Persist structured meeting intelligence and automatic semantic objects.
6. Complete retrieval, Emerging/Connections/Unresolved, and consolidation.
7. Finish the Things-style native interaction model.
8. Add permission-aware MCP execution and optional cloud/TTS adapters.
9. Replace website proof assets and finish public distribution metadata.
10. Gate public claims and stable releases on real audio, signing, and notarization.
