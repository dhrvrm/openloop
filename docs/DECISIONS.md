# Decision Log

## D-001 — ADHD executive-function support defines the product

Status: accepted.

OpenLoop exists to externalize intention, reduce task-initiation effort, preserve
working context, support time awareness, recover after interruptions, and recall
relevant memory. Voice transcription is one input capability.

## D-002 — One person and one Mac

Status: accepted.

There are no organization, collaboration, identity-directory, or multi-user
requirements in the current roadmap.

## D-003 — Completely local operation

Status: accepted.

No account, cloud, server, hosted database, hosted inference, website, domain,
telemetry endpoint, or network connection is required.

## D-004 — Free DMG distribution is sufficient

Status: accepted.

The current distribution artifact is a `.dmg`. Code signing, notarization,
automatic updates, billing, licensing, and a download website are not current
release gates.

## D-005 — Apple Silicon only

Status: accepted.

The initial support floor is Apple Silicon. Intel compatibility would expand the
model and performance test surface without adding necessary personal behavior.

## D-006 — Text proves the interaction before voice

Status: accepted.

The first working loop uses instant typed capture. Voice arrives through the same
capture interface only after externalization, clarification, focus, interruption
recovery, and resurfacing demonstrate value.

## D-007 — Provider selection follows personal benchmarks

Status: accepted.

Apple Speech, whisper.cpp, Core ML, and MLX remain replaceable providers. No
persisted product meaning contains provider-specific types or model names.

## D-008 — Durable memory preserves evidence

Status: accepted.

Compression stores atomic temporal memories and evidence references. It does not
recursively summarize until original meaning disappears.

## D-009 — Cost is not an optimization target

Status: accepted.

There is no inference bill or storage-service bill because processing is local.
Optimization targets are interaction latency, battery, thermal behavior, memory,
disk safety, reliability, and user trust—not minimizing monetary infrastructure
cost.

## D-010 — Formal subsystem graph is deferred

Status: blocked pending an explicitly authorized subsystem-design workflow.

The connection document is a provisional implementation proposal and must not be
treated as a materialized `SUBSYSTEM.md` graph.

## D-011 — Increment 1 uses an encrypted atomic snapshot

Status: accepted.

The current small local dataset is persisted as one authenticated AES-GCM
snapshot with a Keychain-owned root key. This is the minimally complex store for
instant capture, restart durability, and migration from the development JSON
file. SQLite remains the intended adapter when exact search, FTS5, or dataset
size makes indexed queries observable product behavior.

## D-012 — Ad-hoc builds use the standard macOS login Keychain

Status: accepted for trusted testing.

Data Protection Keychain access requires signed application-identifier and
access-group entitlements that macOS does not grant to the current ad-hoc build.
The Increment 1 vault key therefore remains a generic-password item in the local
login Keychain. A Developer ID/provisioned build may move it to the Data
Protection Keychain later; the application does not claim device-only key
semantics in the current distribution.

## D-013 — Focus lifecycle pairs are persisted atomically

Status: accepted.

Each intention owns one durable focus session. Active and paused sessions are the
single current focus; interrupted sessions move to Return and no longer block a
new current intention. Every coupled intention/session lifecycle change is saved
in one repository snapshot write so relaunch cannot observe half a transition.
Older active or interrupted intentions without a focus-session record are
upgraded when they next start or resume.
