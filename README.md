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
```

An action can be moved through the complete durable loop with:

```bash
swift run thought-loop start <id>
swift run thought-loop interrupt <id> "write the first sentence"
swift run thought-loop resume <id>
swift run thought-loop close <id>
```

Set `OPENLOOP_DATA_DIR` to use an isolated development vault. Without it, the
CLI stores data in `~/Library/Application Support/OpenLoopADHD`.
