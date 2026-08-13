# Local Technology Direction

The technology exists to support the ADHD interaction loop. Models and speech
engines are replaceable tools, not the architecture.

## Native stack

| Concern | Initial choice | Purpose |
| --- | --- | --- |
| Application | Swift 6, SwiftUI, AppKit where required | Native menu bar, shortcuts, permissions, and low latency |
| Concurrency | Swift structured concurrency and actors | Explicit ownership of streams and background work |
| Shared contracts | Dependency-free Swift package | Testable values and replaceable adapters |
| Persistence | SQLite through a repository interface | Transactions, FTS5, migrations, and local durability |
| Secrets | macOS Keychain | Store only the local vault key |
| Bulk encryption | CryptoKit envelope encryption | Protect captures, context, and memory locally |
| Microphone | AVAudioEngine | Optional local voice capture |
| System audio | ScreenCaptureKit, much later | Optional ambient context after explicit enablement |
| Speech | Apple Speech and whisper.cpp adapters | Benchmark-selected offline transcription |
| Local models | Core ML first; MLX experiments | Clarification, embeddings, and memory compilation |
| Distribution | `.app` inside a `.dmg` | Free file-based installation |
| Diagnostics | Local metrics export | Performance evidence without telemetry |

## Interface-first configuration

Every provider implements a narrow behavior interface:

- `CaptureProvider` produces raw captures;
- `ClarificationProvider` proposes intent and the next action;
- `ContextProvider` supplies optional local cues;
- `SpeechProvider` turns audio evidence into revisioned text;
- `MemoryCompiler` turns evidence into proposed temporal memories;
- `RetrievalProvider` returns ranked evidence and memories;
- `VaultRepository` persists and queries local state.

The user-facing configuration contains only meaningful choices:

- capture shortcut;
- voice enabled or disabled;
- automatic interruption snapshots;
- resurfacing intensity;
- audio and transcript retention;
- local model quality versus energy preference;
- private mode.

Model names, queue sizes, thresholds, and chunk durations remain advanced
diagnostic settings.

## Runtime scheduling

Performance is an accessibility feature for this product. Quick Capture must
never wait for a model.

- Save raw input first and return control immediately.
- Perform classification and clarification after capture.
- Never run inference, encryption, or database writes on audio callbacks.
- Use bounded queues and explicit backpressure.
- Cancel presentation work without cancelling durable capture.
- Defer embeddings and consolidation during thermal pressure.
- Load large models on demand and unload after an idle interval.
- Prefer deterministic transformations when they provide equal behavior.
- Precompute the next likely Return packet while the system is idle.

## Apple Silicon strategy

- Core ML is the initial production interface for models that convert reliably.
- MLX Swift is an experimentation path for compact local language models.
- Metal/MPSGraph is introduced only for a measured performance bottleneck.
- Apple Speech and whisper.cpp compete using the same private evaluation corpus.
- Persisted data never contains Core ML, MLX, Apple Speech, or whisper.cpp types.

## Performance budgets

| Behavior | Target |
| --- | ---: |
| Capture surface visible after shortcut | under 100 ms p95 |
| Typed thought durably accepted | under 50 ms p95 |
| Now surface visible | under 100 ms p95 |
| Local exact search | under 100 ms p95 |
| Local semantic results | under 300 ms p95 |
| Voice partial text | under 500 ms p95 |
| Voice refined result | under 2 s after utterance end |
| Idle CPU | under 1% average |
| Base resident memory | under 250 MB |
| Peak model memory | configurable; under 8 GB on the current 24 GB Mac |

Financial cost is not a target. Local latency, battery, temperature, disk safety,
and cognitive friction remain real constraints even when infrastructure cost is
irrelevant.
