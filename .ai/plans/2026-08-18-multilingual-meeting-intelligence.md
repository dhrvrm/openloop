# Multilingual Meeting Intelligence Implementation Plan
> **For agentic workers:** REQUIRED SUB-SKILL: Use executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make short mixed Hindi-English recordings survive continuous code switches and give every saved meeting a visible, evidence-linked local summary, decisions, and action candidates.

**Architecture:** Keep transcription and intelligence fully local. Add a bounded code-switch chunk planner only to the existing short automatic-language path. Add a deterministic extractive intelligence compiler in `ADHDCore`; it returns verbatim evidence-backed insights and is derived from the saved transcript, so existing encrypted persistence remains backward-compatible and there is no second source of truth.

**Tech Stack:** Swift 6.2, SwiftUI/AppKit, WhisperKit 1.1, XCTest, existing encrypted repository.

---

## Task 1: Evidence-first meeting intelligence model

- [x] Add failing tests in `Tests/ADHDCoreTests/MeetingIntelligenceTests.swift` for multilingual sentence splitting, deterministic extractive summary ranking, explicit English/Hindi/Hinglish decisions, conservative action-candidate extraction, question/negation rejection, stable IDs, and exact segment evidence.
- [x] Add `Sources/ADHDCore/MeetingIntelligence.swift` with `MeetingEvidence`, `MeetingInsight`, `MeetingIntelligence`, and `MeetingIntelligenceCompiler`.
- [x] Make summary selection deterministic using multilingual token frequency, position/marker weighting, and redundancy suppression; preserve the exact original sentence text.
- [x] Require action and decision cues to be explicit; never infer an assignee or silently create a task.
- [x] Run `./scripts/test.sh --filter MeetingIntelligenceTests`.

## Task 2: Native transcript intelligence surface

- [x] Add pure presentation tests in `Tests/OpenLoopAppTests/MeetingIntelligencePresentationTests.swift` for section labels, counts, empty states, and timestamp evidence labels.
- [x] Refactor `MeetingTranscriptRow` in `Sources/OpenLoopApp/MainWindowController.swift` to show a `Meeting brief` before the raw transcript.
- [x] Add visible `Summary`, `Decisions`, and `Action candidates` sections, each with exact timestamp/speaker evidence and honest empty states.
- [x] Label the brief `LOCAL · EXTRACTIVE`; explain that candidates are not added to Now without review.
- [x] Keep transcript copy/delete controls, and add per-insight copy without changing persistence behavior.
- [x] Run the focused presentation and core intelligence tests.

## Task 3: Bounded continuous code-switch planning

- [x] Add failing unit tests in `Tests/OpenLoopAppTests/CodeSwitchChunkPlannerTests.swift` for stable `en,en,hi,hi` probe transitions, noisy single-probe rejection, low-margin rejection, exact core ownership, bounded context, and chunk budgets.
- [x] Add `Sources/OpenLoopApp/CodeSwitchChunkPlanner.swift` as a pure planner whose core ranges cover speech once and whose decode ranges add bounded context.
- [x] Extend `Sources/OpenLoopApp/LocalMeetingTranscriber.swift` to run capped sequential language probes and adaptive chunks only for automatic-language recordings at most 45 seconds.
- [x] Preserve forced-language behavior, long-file incremental decoding, participant-only prompt context, and promptless recovery.
- [x] Trim overlap by word timestamp/core ownership so boundaries do not duplicate words.
- [x] Strengthen `Scripts/verify-codeswitch.sh` so its English-Hindi fixture has no silence long enough for the existing VAD splitter, then require both language output and Devanagari.
- [x] Run focused chunk-planning, transcriber, and code-switch acceptance tests.

## Task 4: Release increment

- [x] Bump the app build metadata from 11 to 12 and document the local meeting-brief and continuous code-switch behavior in `README.md`.
- [x] Run one focused test pass covering the changed surfaces, followed by `./Scripts/build-app.sh` (or the repository's canonical build script casing).
- [x] Request a targeted code review for correctness, concurrency, evidence integrity, and regressions; address material findings.
- [x] Replace `/Applications/OpenLoop ADHD.app` with build 12 while leaving it closed.
- [x] Confirm the installed bundle version and that no `OpenLoopADHD` process remains running; do not repeatedly launch the app.
