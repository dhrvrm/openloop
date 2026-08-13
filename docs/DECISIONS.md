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
