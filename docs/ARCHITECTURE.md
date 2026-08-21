# Architecture

OpenLoop uses a ports-and-adapters core with a native AppKit composition layer. The intent is simple: domain behavior remains testable without macOS UI, storage, model, or permission frameworks.

## Dependency direction

```text
                         OpenLoopApp
                      composition root
                    /        |         \
             LocalStore  VaultStore  RuleClarifier
                    \        |         /
                         ADHDCore

ThoughtLoopCLI also composes the same core through explicit adapters.
```

Dependencies point inward. `ADHDCore` does not import AppKit, AVFoundation, Security, MLX, WhisperKit, or a concrete database.

## Native application capabilities

`Sources/OpenLoopApp` is grouped by behavior:

- `App/` owns process lifecycle, shared state, workspace routing, and composition.
- `Voice/` owns hotkeys, capture sessions, streaming recognition, local editing, context routing, and output adapters.
- `Meetings/` owns durable audio capture, transcription, diagnostics, and presentation-ready meeting intelligence.
- `Context/` reads the active application and builds privacy-scoped local context.
- `UI/` renders the workspace, advanced diagnostics, capture surface, and semantic graph.

Folder names describe ownership; they do not create new dependency layers. Cross-capability coordination belongs in `App/`, while domain rules shared outside the executable move into `ADHDCore`.

## Data path

```text
microphone or file
  -> durable local audio staging
  -> voice activity / segmentation
  -> multilingual speech recognition
  -> optional deterministic or local-model editing
  -> evidence-preserving transcript
  -> semantic extraction
  -> encrypted local persistence
  -> recall, return, graph, or an authorized output adapter
```

The raw evidence and generated interpretation are different records. A summary may be regenerated; source audio and transcript provenance must not be silently replaced.

## Runtime boundaries

- Microphone and accessibility permissions are requested at the point of use.
- Audio imports do not request microphone permission.
- Local mode must not silently become cloud mode.
- Credentials belong in Keychain, never in repository files or user defaults.
- External actions are routed through capability and permission checks.

## Extending the system

1. Define a stable domain type or port in `ADHDCore` when the behavior is reusable.
2. Add a concrete adapter in the narrowest target or `OpenLoopApp` capability folder.
3. Compose it in `OpenLoopApp/App` or `ThoughtLoopCLI`.
4. Put deterministic tests next to the owning target.
5. Record non-obvious architectural changes in `docs/DECISIONS.md`.

Avoid global singletons, storage calls from views, model-specific types in the domain, and silent fallback behavior.
