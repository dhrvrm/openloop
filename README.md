# OpenLoop ADHD

OpenLoop ADHD is a free, completely local macOS application that acts as an
external executive-function layer for one person.

It is not a voice recorder with memory added. Voice is only one way to get a
thought into the system. The product exists to help a person:

```text
externalize -> choose -> begin -> stay oriented -> recover -> remember -> close
```

The product is centered on ADHD experiences:

- a thought disappears before it can be organized;
- the next action feels unclear or too large to begin;
- an interruption erases the working context;
- time passes without becoming emotionally real;
- remembered obligations create anxiety but not action;
- useful context exists somewhere but is difficult to recover.

## Current scope

- One person
- One Mac
- Local processing
- Local encrypted storage
- No account
- No organization features
- No cloud transcription, backend, account, telemetry, billing, or subscription
- One network download for local speech models; transcription works offline afterward
- Free distribution as a `.dmg`
- Apple Silicon only

A domain is not required. If a download page is added later, it can be a static
page that only serves the `.dmg`; it is not part of the application system.

Code signing and notarization can improve installation trust later, but they are
not gates for the first free builds. An unsigned or ad-hoc-signed `.dmg` is
acceptable during personal development and trusted testing.

## First complete behavior

The smallest useful version is not transcription. It is a complete thought loop:

1. Press one shortcut.
2. Dump an unstructured thought without choosing a project or category.
3. Turn it into a tiny next action, a memory, or something deliberately ignored.
4. Start the action with the relevant context visible.
5. Save an interruption snapshot automatically or with one shortcut.
6. Return later and see exactly where to resume.
7. Mark the loop closed without maintaining another productivity system.

Voice capture is introduced as an interchangeable input after this loop works
with text. Ambient speech and local semantic memory arrive later.

## Documents

- [ADHD-centered product definition](docs/PRODUCT.md)
- [Local Mac feasibility](docs/FEASIBILITY.md)
- [Native technology choices](docs/TECHNOLOGY.md)
- [Local storage, compression, and encryption](docs/DATA.md)
- [Proposed component connection interfaces](docs/PROPOSED-CONNECTIONS.md)
- [Small independent increments](docs/INCREMENTS.md)
- [Decision log](docs/DECISIONS.md)
- [First implementation plan](.ai/plans/2026-08-12-adhd-core-loop.md)

## Build rules

1. Each increment must be useful on its own.
2. Each capability must be testable without the full application.
3. Connections carry versioned values through narrow interfaces.
4. Voice, models, storage, and UI are replaceable adapters.
5. No component may require a network connection.
6. The application never uses guilt, streak loss, punitive overdue states, or
   fabricated urgency.
7. The user can capture first and organize never; the system performs gradual
   clarification only when it creates immediate value.
8. Performance is part of the ADHD experience: capture must appear instantly and
   must never make the person wait before externalizing a thought.
9. There are no formal `SUBSYSTEM.md` contracts yet. The connection document is
   a provisional implementation proposal.

## Immediate sequence

1. Build the text-based thought loop.
2. Use it personally and measure whether thoughts are recovered and actions
   resumed.
3. Add focus orientation and interruption recovery.
4. Add local voice capture and benchmark speech recognition.
5. Add evidence-backed compressed memory.
6. Add ambient context only when it improves the ADHD loop.

## Development verification

Run `Scripts/verify.sh` to execute the core tests and create a release build.
`Scripts/test.sh` includes the framework-path workaround required by the current
Command Line Tools installation.

Try the first local behavior with:

```bash
swift run thought-loop capture "todo: open the latest design"
swift run thought-loop list
swift run thought-loop capture "later: reconsider the launch framing"
swift run thought-loop captures later
```

## Instant Capture app

The macOS app uses Command-Shift-Space for Quick Capture and provides quiet Now,
Return, and Later surfaces. Raw text is accepted into an AES-GCM
encrypted local vault before Quick Capture closes. Release builds can keep the
256-bit root key in macOS Keychain; ad-hoc local builds use a protected local key
file so changing development signatures do not trigger recurring Keychain ACL
prompts. The app launches as a regular Dock application and opens its workspace
immediately; the menu-bar entry remains available.

Run `Scripts/verify-increment-1.sh` to test the core, measure capture latency,
inspect the encrypted vault, build and ad-hoc sign the app, and mount-check the
DMG. The resulting artifact is `.artifacts/OpenLoop-ADHD.dmg`. Ad-hoc signing is
intended for personal and trusted testing and may still produce Gatekeeper
friction when shared with another Mac.

## Focus and interruption recovery

Open Now to start one intention. While focused, the app shows only its outcome,
exact next action, a calm elapsed-time cue, and Pause, Interrupt, and Finish.
Interrupt saves what was just completed, the exact restart action, an optional
blocker, manual files/links/notes, and the frontmost application name when it is
locally available. This adapter does not request Accessibility or Automation
permission.

Interrupted work leaves Now and appears in Return. Its packet remains encrypted
on disk and can be resumed after quitting and reopening the app; Resume restores
the saved next action rather than asking for reconstruction. The menu-bar item
exposes Capture, Record & Transcribe, Now, Pause/Continue, Return, Later, and the
current private-mode status. No background sensing is active.

Run `Scripts/verify-increment-2.sh` to execute all tests, prove an exact Return
packet survives a fresh encrypted-repository instance, scan for packet plaintext,
recheck capture latency and the global hot key, sign the app, build the DMG, and
mount-check it. The artifact remains `.artifacts/OpenLoop-ADHD.dmg`.

An action can be moved through the complete durable loop with:

```bash
swift run thought-loop start <id>
swift run thought-loop interrupt <id> "write the first sentence"
swift run thought-loop resume <id>
swift run thought-loop close <id>
```

Set `OPENLOOP_DATA_DIR` to use an isolated development vault. Without it, the
CLI stores data in `~/Library/Application Support/OpenLoopADHD`.

## Visible library and contextual resurfacing

Later exposes every unfinished open loop with its desired outcome, exact next
action, and neutral state, followed by non-action notes and captures. An open
loop can be explicitly linked to the application that was foreground when
OpenLoop opened by choosing `Suggest in <Application>`. OpenLoop samples that
application only on launch, Dock reopen, or the Now menu action; it does not
watch application activity in the background.

At most two linked open loops can appear in Now. Every suggestion states its
reason and shows the complete relevance contribution as a native bar. The
algorithm requires one explicit application match, then uses a four-hour
per-loop cooldown. `Later` silences a suggestion for one day and `Never suggest`
silences it permanently; both are single actions. There are no overdue states,
streaks, urgency scores, or notifications.

## Local multilingual meeting transcription

Use **Import audio…** for WAV, MP3, M4A, MP4, FLAC, AIFF, or CAF, or press
Command-Shift-R to start and stop a local M4A recording. Import needs no privacy
permission. Recording requests only Microphone permission; the production path
does not request macOS Speech Recognition access. While recording, the primary
control turns red and a live input meter shows the microphone's measured dB level,
signal strength, and movement; it is driven by local audio power rather than a
decorative animation.

The first job downloads WhisperKit's `large-v3-v20240930_626MB` Core ML model,
selected for maximum multilingual accuracy. The UI distinguishes model download,
audio preparation, transcription, speaker separation, encryption, completion,
failure, cancellation, and retry. Real partial text appears as a selectable live
transcript while Whisper is working; after encryption, the completed transcript
remains visible below the job and the newest Recall transcript opens automatically.
Long files use bounded-memory incremental loading. Whisper detects the spoken
language automatically for every import and recording; no language setup appears
in the normal workflow. Short automatic recordings are split at meaningful silent
boundaries so each utterance can detect its own language, and mixed results report
an ordered summary such as `en + hi`. If an utterance produces an empty model
result, OpenLoop automatically retries the complete recording instead of failing.
After recording stops, the job retains captured duration and peak dB so quiet input
can be distinguished from a decoding failure. Word and segment timestamps and local
SpeakerKit Pyannote diarization produce speaker-labelled evidence when the diarization model
is available; transcription still completes if speaker separation cannot run.

Audio stays on the Mac. Imported or recorded audio is copied to a local staging
directory only for the active or retryable job and removed after its transcript
is saved into the AES-GCM vault. Recall shows source, duration, detected language,
model, timestamps, speaker labels, selectable text, explicit capture, and delete
actions. A transcript never becomes a task unless the user explicitly captures it.

The older Apple Speech controller remains temporarily as a compiled compatibility
test seam, but the packaged app no longer constructs or authorizes it.

### Hindi, Hinglish, and Indian languages

Hindi, Hinglish, and other supported languages use automatic detection by default.
The completed transcript shows the detected language. For an unusually difficult
recording, Advanced mode offers a temporary manual language override that resets
to automatic detection on the next app launch.

For better proper-name and code-switch accuracy, OpenLoop gives Whisper a short
on-device context containing the local Mac account name and English, Hindi, and
Hinglish vocabulary guidance. The context never leaves the Mac. Hindi-dominant
audio remains in Devanagari, and silence-separated Hindi utterances at the end of
English speech are decoded independently so the language switch remains visible.

The Advanced override exposes the multilingual model's verified tokens for English,
Bengali, Marathi, Tamil, Telugu, Gujarati, Kannada, Malayalam, Punjabi, Urdu,
Assamese, Nepali, Sanskrit, and Sindhi. Auto detect remains available when the
language is unknown. OpenLoop transcribes rather than translates, so Hindi stays
Hindi instead of being silently converted into English.

Run the real local Hindi/Hinglish acceptance fixture with:

```bash
Scripts/verify-hindi.sh
```

This synthesizes a code-switched Hindi meeting sample with macOS's Hindi voice,
processes it through the same cached WhisperKit model and forced-Hindi decoding
path as the app, and requires Hindi detection, substantial Devanagari output,
and recognizable meeting vocabulary.

### Advanced Mode

Turn on **Advanced** at the bottom of the workspace sidebar to open a live system
inspector beside the current surface. It shows the real local pipeline from audio
and retry-safe staging through Whisper, speaker separation, encrypted vault, and
Recall; the active stage and coarse progress milestones update while a meeting is
processed. The inspector also reports the selected local models, whether the
Whisper model is cached, microphone availability, encrypted transcript storage,
and a bounded recent-activity history.

Advanced Mode is optional, off by default, and remembered on this Mac. It does not
add logging, upload telemetry, inspect transcript contents, expose a full home
directory path, or fabricate throughput and accuracy figures. Turning it off
returns to the calm four-destination workspace without disabling any capability.

## Personal Recall

Press Command-Shift-F to open Recall. Exact phrases, shared words, and local
semantic similarity search captures, every intention state, saved return
packets, and voice corrections. Each result is stored evidence with its source,
date, excerpt, and separate match contributions; Recall does not generate an
answer or fill gaps with plausible text.

Apple Natural Language supplies sentence embeddings on this Mac. If that local
provider is unavailable, exact and shared-word search still work. The derived
document/vector index is encrypted independently with an HKDF-separated key,
contains no plaintext sidecar, and can be discarded and rebuilt from the
authoritative encrypted vault. Capture never waits for indexing.

The reproducible fixture measures top-five evidence retrieval and exact-query
p95 latency:

```bash
swift run OpenLoopADHD --recall-evaluation Tests/Fixtures/recall-evaluation.json
```

Fixture success validates the retrieval harness, not the roadmap's 95% personal
corpus gate. That gate requires representative queries from actual use. The
exact-search target remains under 100 ms p95 and local semantic retrieval under
300 ms p95.

## Compressed Working Memory

Recall now compiles a small temporal ledger only from explicit evidence markers:
`remember:`, `decision:`, `commitment:` or `promise:`, `prefer:` or
`preference:`, `question:`, and `correction: old -> new`. Stored voice
corrections are also eligible. Ordinary notes and action prose never become
memory, and OpenLoop does not generate claims or fill missing context.

Every accepted statement keeps its exact source excerpt and evidence identity in
the encrypted vault. Equivalent statements merge evidence. An explicit
correction supersedes the matching prior statement without deleting it;
unresolved conflicting statements remain visible. If source evidence later
disappears, the statement remains in history with an “evidence expired” state.

Compilation starts only when Recall opens or “Refresh evidence” is pressed, so
Quick Capture has no memory-compilation dependency. The checked-in fixture
reports evidence coverage, contradiction preservation, current-state accuracy,
and the number of accepted memories:

```bash
swift run OpenLoopADHD --memory-evaluation Tests/Fixtures/memory-evaluation.json
```

These are deterministic fixture metrics, not a claim about a personal corpus.

## Private focus context

Private Mode remains the default. From Now or the menu bar, explicitly enable
Focus Context to retain a short application trail only while a focus session is
active. OpenLoop stores the focus, session, observation time, normalized bundle
identifier, and readable application name. It does not collect window or
document titles, typed text, URLs, clipboard contents, microphone or system
audio, location, keystrokes, or screenshots.

Consecutive observations of the same application compress into one visible
episode. The Now surface renders chronological application nodes and arrows;
pausing focus also pauses collection. Events are bounded to eight hours and 100
observations per session. Turning Private Mode back on immediately stops new
collection and erases retained context events. Context never creates tasks,
captures, memories, or notifications.

When a focused session is interrupted, retained evidence contributes one
selectable `Context trail — Xcode → Safari` reference to the existing Return
packet. Manual recovery fields remain authoritative. The deterministic fixture
reports accepted events, episode compression, false-event rate, and Return
reference coverage:

```bash
swift run OpenLoopADHD --context-trail-evaluation Tests/Fixtures/context-trail-evaluation.json
```

The fixture validates policy wiring only; it is not evidence of battery impact
or recovery improvement in personal use.

Run `Scripts/verify-increment-3.sh` to execute all tests, build and sign the app,
verify the visible foreground lifecycle, contextual scoring and suppression,
voice-controller capture, dual global hot keys, encrypted-at-rest markers,
capture latency, privacy usage strings, framework linkage, and the mounted DMG.
The artifact remains `.artifacts/OpenLoop-ADHD.dmg`.
