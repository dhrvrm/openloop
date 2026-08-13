# Small Independent Increments

Each increment produces a complete working behavior. Later increments connect
through the declared interfaces without making earlier ones unusable alone.

## Increment 0 — Thought Loop Core

Behavior: raw text becomes a durable personal capture that can be clarified into
one next action, held for later, remembered without action, or released.

Independent systems:

- capture value and append-only journal;
- clarification rules with a replaceable provider interface;
- intention state machine;
- local repository;
- command-line test harness using fixtures.

Exit gate: a thought survives process restart and can move through captured,
clarified, active, interrupted, resumed, and closed states without the UI.

## Increment 1 — Instant Capture DMG

Behavior: one global shortcut opens Quick Capture, saves immediately, and closes.
A small menu-bar application shows Now and Later and ships as a free `.dmg`.

Independent systems:

- native menu-bar host;
- global shortcut adapter;
- Quick Capture surface;
- Now and Later read models;
- Keychain-owned vault key and encrypted local repository;
- one-time migration from the Increment 0 development store;
- local `.app` packaging and DMG script.

Exit gate: capture appears within 100 ms, saved thoughts survive relaunch, and the
DMG installs on the current Mac without a backend or website. Inspection of the
vault files reveals no plaintext captures or intentions.

## Increment 2 — Focus and Interruption Recovery

Behavior: the user starts one intention, sees its smallest next action, snapshots
their state during interruption, and later resumes without reconstruction.

Independent systems:

- focus-session state machine;
- calm elapsed-time cue;
- interruption snapshot composer;
- Return surface;
- optional active-application and document-reference adapter.

Exit gate: a session can be interrupted, the application can quit, and the exact
return packet restores the next action and references after relaunch.

## Increment 3 — Contextual Resurfacing

Behavior: the application resurfaces a small number of relevant intentions based
on explicit time and local context without producing notification debt.

Independent systems:

- local context events;
- relevance scoring;
- cooldown and suppression policy;
- suggestion history;
- user feedback and tuning.

Exit gate: suggestions are rate-limited, explain why they appeared, and can be
silenced permanently or temporarily in one action.

## Increment 4 — Local Voice Capture

Behavior: the user holds a shortcut, speaks naturally, sees responsive local
text, and the resulting capture enters the same thought loop as typed input.

Independent systems:

- microphone capture and audio journal;
- voice activity detection;
- speech-provider contract;
- Apple Speech provider;
- whisper.cpp provider experiment;
- personal vocabulary and correction history;
- reproducible accuracy, latency, memory, and energy benchmark.

Exit gate: the selected provider meets personal-corpus thresholds, names and
technical words are measured separately, and voice failure never loses already
captured audio or blocks typed capture.

## Increment 5 — Personal Recall

Behavior: captures, intentions, return packets, and corrections are searchable
locally through exact and semantic retrieval.

Independent systems:

- encrypted local index;
- lexical retrieval;
- embedding provider;
- evidence ranking;
- Recall surface and global shortcut.

Exit gate: at least 95% of a fixed personal evaluation set has relevant evidence
in the first five results, and exact search stays within its latency budget.

## Increment 6 — Compressed Working Memory

Behavior: the application derives evidence-backed decisions, commitments,
preferences, questions, and corrections without turning everything into tasks.

Independent systems:

- deterministic candidate rules;
- local structured extraction provider;
- evidence validator;
- temporal memory ledger;
- semantic delta merge;
- contradiction and supersession handling.

Exit gate: every accepted memory has retained evidence or is visibly marked when
that evidence expired; corrections change current recall without erasing history.

## Increment 7 — Optional Ambient Context

Behavior: when explicitly enabled, local system-audio or application-context
signals can create draft captures and improve Return packets. Nothing is uploaded
or shared.

Independent systems:

- system-audio adapter;
- episode segmentation;
- local application-context adapter;
- private-mode and retention controls;
- draft-review policy preventing ambient noise from becoming obligations.

Exit gate: ambient mode demonstrably improves recovered context without harming
battery budgets or flooding the user with false tasks.

## Sequence rule

Experiments may happen early, but an increment cannot become a dependency until
its own exit gate passes. Voice and ambient memory are extensions of the ADHD
loop. The product remains useful if every ambient capability is disabled.
