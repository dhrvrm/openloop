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
| Immediate lossless recording | Partial | Durable audio must start before VAD or ASR model preparation. |
| Red recording state and live dB feedback | Partial | Main window works; a non-activating global HUD must expose the same state in other apps. |
| Stable and partial text while speaking | Partial | Streaming state exists; inference needs coalescing and global HUD delivery. |
| Automatic Hindi/English/Hinglish | Partial | Default is automatic, but real short-switch and romanized-Hinglish fixtures must pass. |
| Long meeting transcription | Partial | Qwen must decode bounded timestamped spans instead of one 448-token whole-file request. |
| Accuracy-first local ensemble | Partial | Disputed spans must be fused or shown for review instead of silently retaining Qwen. |
| Personal and technical vocabulary | Shipped | Corrections persist and feed recognition/normalization. |
| Audio conditioning | Missing | Add a measured conditioning adapter for noise suppression, gain, filtering, and optional echo cancellation. |
| Raw, polished, code, email, casual, Markdown, bullets, JSON | Partial | Modes exist; JSON/code validation and distinct fast/deep editors remain. |
| App-aware insertion | Partial | Context and three output routes exist; per-app policies and clipboard timing remain. |
| Optional cloud route | Missing | Must be explicit, opt-in, and visibly separate from local mode. |
| Optional spoken feedback | Missing | Add only after latency and status feedback are stable. |

## Memory and action

| Requirement | Status | Completion gate |
| --- | --- | --- |
| Durable captures and task/focus lifecycle | Shipped | Capture, review, Now, Later, Return, reorder, start, interrupt, resume, finish, and release persist. |
| Evidence-backed transcript brief | Partial | Extractive summary/decisions/actions exist; structured semantic interpretation must persist separately from raw evidence. |
| Typed semantic graph with confidence and supersession | Shipped | Nodes, relations, vectors, evidence, and history persist in the encrypted event ledger. |
| Automatic semantic extraction | Missing | One utterance must produce provisional observations, ideas, problems, questions, decisions, and intentions with evidence. |
| Emerging, Connections, Unresolved | Partial | Surfaces exist; they need automatic entities/relations and recurrence-based ranking. |
| Ask your context | Partial | Token overlap exists; retrieval must combine lexical, multilingual vector, graph, and belief history evidence. |
| Consolidation and belief history | Partial | Supersession exists; recurring episodes do not yet consolidate into procedures. |
| MCP Observe/Suggest/Act | Missing | Connect a runtime registry, persisted grants, confirmation, execution, and audit history. |

## Native experience

| Requirement | Status | Completion gate |
| --- | --- | --- |
| Simple task management | Shipped | Core capture, Now, Inbox, Later, Return, edit, reorder, finish, and release work. |
| Things-like spacing and hierarchy | Partial | Align the code tokens with `DESIGN.md` and remove compressed 16-point major section gaps. |
| Things-like Move and drag/drop | Partial | Add destination moves, sidebar drops, transactional undo, keyboard parity, and multi-selection. |
| Quick Find and type-to-travel | Missing | Search and navigate all destinations without mouse-only traversal. |
| Headings, checklists, dates, Upcoming, Someday, Spaces | Missing | Add domain-backed structures before view-only controls. |
| Slim mode and multiple windows | Missing | Use a resizable/collapsible native split layout and independent window navigation. |
| First-class transcript destination | Missing | A completed recording must open or surface a durable transcript row immediately. |
| Advanced observability | Partial | Diagnostics exist; collapse inactive groups and keep only the live signal pinned. |
| Interactive 3D stored-memory graph | Partial | Orbit/zoom/evidence work; add full-space mode, search/filter, labels, and truthful projection wording. |

## Website, repository, and distribution

| Requirement | Status | Completion gate |
| --- | --- | --- |
| Design-led product website | Partial | Source builds; replace stale failure imagery, add successful product proof, legal/accessibility pages, metadata, and a real mobile menu. |
| Direct DMG download | Partial | Versioned DMG and checksum exist; website CTA should link directly and disclose signing state. |
| Clean public repository | Shipped | Capability-oriented source tree, architecture, contribution, security, CI, and release workflows exist. |
| GitHub Pages deployment | Blocked | Repository admin must enable Pages once; current CLI identity has read-only permission. |
| Repository description/homepage/topics | Blocked | Run `Scripts/configure-github.sh` from an admin-authenticated GitHub CLI session. |
| Stable Developer ID signing and notarization | Blocked | Requires Apple Developer certificate, team, and notary credentials. |
| No recurring Keychain password prompt | Partial | Migrate existing local-key installations and keep a stable key policy across ad-hoc and Developer ID builds. |
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
