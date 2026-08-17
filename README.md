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
- No cloud, backend, website, telemetry, billing, or subscription
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
encrypted local vault before Quick Capture closes; its 256-bit root key is owned
by macOS Keychain. The app launches as a regular Dock application and opens its
workspace immediately; the menu-bar entry remains available. The app has no
account, network dependency, or telemetry.

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

## On-device voice capture

Press Command-Shift-R once to open a visible recording panel and begin live
transcription. Press the same shortcut again to stop and save. The transcript
uses the same encrypted capture path as typed text and remains editable if a
save fails. Empty recordings are discarded, and sessions stop after one minute.

OpenLoop requires Apple's on-device speech recognizer and never falls back to a
network recognizer. Raw microphone audio is streamed only into the recognizer;
OpenLoop does not write or retain it. The first explicit use asks for Microphone
and Speech Recognition permission. If the current Dictation language has no
on-device recognizer, OpenLoop reports that limitation instead of uploading
audio.

Run `Scripts/verify-increment-3.sh` to execute all tests, build and sign the app,
verify the visible foreground lifecycle, contextual scoring and suppression,
voice-controller capture, dual global hot keys, encrypted-at-rest markers,
capture latency, privacy usage strings, framework linkage, and the mounted DMG.
The artifact remains `.artifacts/OpenLoop-ADHD.dmg`.
