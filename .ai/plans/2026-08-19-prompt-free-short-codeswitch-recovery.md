# Prompt-Free Short Code-Switch Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Correct brief Hindi islands inside continuous English speech without prompts, and retain each local source recording so a user can re-transcribe a wrong result.

**Architecture:** Automatic meeting transcription will pass no prompt tokens. The bounded language planner will accept one exceptionally strong normalized language-probability margin only when surrounded by stable runs, allowing short `en → hi → en` islands without treating one noisy probe as a switch. Saved transcripts will reference their retry-safe staged audio by validated filename; retry overwrites the same transcript ID, and Dismiss explicitly removes the local source.

**Tech Stack:** Swift 6.2, SwiftUI/AppKit, WhisperKit 1.1, encrypted `MeetingTranscript` persistence, XCTest, macOS `say` acceptance audio.

---

### Task 1: Remove hidden prompt conditioning

**Files:**
- Modify: `Sources/OpenLoopApp/LocalMeetingTranscriber.swift`
- Modify: `Sources/OpenLoopApp/OpenLoopApp.swift`
- Delete: `Sources/OpenLoopApp/TranscriptionContext.swift`
- Modify: `Tests/OpenLoopAppTests/LocalMeetingTranscriberTests.swift`
- Delete: `Tests/OpenLoopAppTests/TranscriptionContextTests.swift`
- Modify: `Tests/OpenLoopAppTests/HindiMeetingIntegrationTests.swift`

- [ ] Remove `contextPrompt` from `WhisperKitMeetingTranscriber` and construct every meeting `DecodingOptions` with `promptTokens: nil`.
- [ ] Remove the participant-prompt tokenizer path and promptless retry branches that can no longer activate.
- [ ] Delete the unused hidden multilingual/name context and update integration construction.
- [ ] Add a focused assertion that the meeting decoder policy is prompt-free for automatic and forced-language jobs.
- [ ] Run `./scripts/test.sh --filter 'LocalMeetingTranscriberTests|TranscriptionContextTests'`; expect all selected tests to pass and no `TranscriptionContextTests` to remain.

### Task 2: Recognize a brief high-confidence language island

**Files:**
- Modify: `Sources/OpenLoopApp/CodeSwitchChunkPlanner.swift`
- Modify: `Tests/OpenLoopAppTests/CodeSwitchChunkPlannerTests.swift`
- Create: `Scripts/verify-short-codeswitch.sh`
- Modify: `Tests/OpenLoopAppTests/HindiMeetingIntegrationTests.swift`

- [ ] Add a RED planner test where `en,en,hi,en,en` splits into three chunks only when the single Hindi probe has a normalized margin of at least `0.95`.
- [ ] Keep the existing `0.9` single-probe noise case unsplit.
- [ ] Implement `LanguageRun.isStable` as two ordinary confident probes or one exceptionally confident probe, and require stable runs on both sides of each boundary.
- [ ] Create a real 17–22 second fixture with continuous English, a roughly three-second Hindi island, and continuous English; trim voice silence and join sections with 120 ms gaps.
- [ ] Capture progress and require `Language change found`, three chunk decode progress events, `en + hi`, the participant name, English output, and at least ten Devanagari scalars.
- [ ] Run `Scripts/verify-short-codeswitch.sh`; expect the short Hindi phrase to remain in Devanagari without any prompt environment variable.

### Task 3: Keep source audio retryable and replace the wrong transcript

**Files:**
- Modify: `Sources/ADHDCore/MeetingTranscription.swift`
- Modify: `Sources/OpenLoopApp/MeetingTranscriptionController.swift`
- Modify: `Sources/OpenLoopApp/MainWindowController.swift`
- Modify: `Tests/ADHDCoreTests/MeetingTranscriptionTests.swift`
- Modify: `Tests/OpenLoopAppTests/MeetingTranscriptionControllerTests.swift`

- [ ] Add optional `sourceAudioFileName` to `MeetingTranscript`, validate it as one path component, and preserve backward-compatible decoding with `decodeIfPresent`.
- [ ] Change successful transcription to retain staged audio, expose retry for `.ready`, and state visibly that Dismiss removes the source.
- [ ] Store `completedTranscriptID`; retry with that ID so the repository replaces the wrong transcript rather than creating a duplicate.
- [ ] During `refresh()`, restore retry state for the newest transcript whose referenced staging file still exists.
- [ ] Delete referenced audio when its transcript is deleted or its finished job is dismissed.
- [ ] Update the ready action to `Retranscribe source` and keep failure action as `Retry locally`.
- [ ] Add controller tests for retained audio, same-ID replacement, explicit cleanup, and relaunch restoration.
- [ ] Run `./scripts/test.sh --filter 'MeetingTranscriptionTests|MeetingTranscriptionControllerTests'`; expect all selected tests to pass.

### Task 4: Build 13, review, and install closed

**Files:**
- Modify: `Resources/Info.plist`
- Modify: `README.md`

- [ ] Bump `CFBundleVersion` from `12` to `13` and document prompt-free automatic decoding, short language islands, and source-backed retranscription.
- [ ] Run focused changed-surface tests and `Scripts/verify-short-codeswitch.sh`; do not run repetitive exhaustive loops.
- [ ] Request a targeted review for prompt leakage, false language splits, path traversal, retry replacement, and source cleanup; fix Critical and Important findings.
- [ ] Run `Scripts/build-app.sh`, verify its signature, replace `/Applications/OpenLoop ADHD.app` while keeping it closed, and confirm installed build `13` with no process running.
- [ ] Commit the increment on `feature/v1-completion` without merging it.
