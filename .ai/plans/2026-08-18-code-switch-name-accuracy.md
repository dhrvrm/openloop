# Code-Switch Name Accuracy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Improve automatic English/Hindi/Hinglish transcription of uncommon names without adding setup to the normal UI.

**Architecture:** Build a short local Whisper conditioning prompt from the Mac account name plus code-switching vocabulary guidance, inject its ordinary tokenizer tokens into `DecodingOptions.promptTokens`, and keep automatic language detection enabled. Validate the behavior with a synthesized English-to-Hindi clip whose unconditioned baseline misrecognizes “Dhruv.”

**Tech Stack:** Swift 6, WhisperKit 1.1, Swift Testing, macOS `say` and `afconvert`, zsh packaging scripts.

---

### Task 1: Define and test safe local transcription context

**Files:**
- Create: `Sources/OpenLoopApp/TranscriptionContext.swift`
- Create: `Tests/OpenLoopAppTests/TranscriptionContextTests.swift`

- [x] **Step 1: Write the failing context tests**

Add tests asserting that `TranscriptionContext.make(localUserName: "Dhruv Sharma")` contains `Dhruv Sharma`, `English`, `Hindi`, and `Hinglish`; trims whitespace; and omits a blank account name.

- [x] **Step 2: Run the context tests and confirm the missing type fails compilation**

Run: `Scripts/test.sh --filter TranscriptionContextTests`

Expected: compilation fails because `TranscriptionContext` does not exist.

- [x] **Step 3: Implement the minimal context builder**

Create a `TranscriptionContext` enum with `static func make(localUserName: String) -> String`. Normalize whitespace, cap the account name at 80 characters, and return transcript-style context such as `Participants: Dhruv Sharma. Multilingual conversation in English and Hindi (हिन्दी), including Hinglish code-switching. Preserve names. Write Hindi speech in Devanagari and English speech in Latin; do not translate.`

- [x] **Step 4: Run the context tests**

Run: `Scripts/test.sh --filter TranscriptionContextTests`

Expected: all context tests pass.

### Task 2: Condition Whisper without disabling automatic detection

**Files:**
- Modify: `Sources/OpenLoopApp/LocalMeetingTranscriber.swift`
- Modify: `Sources/OpenLoopApp/OpenLoopApp.swift`
- Modify: `Tests/OpenLoopAppTests/HindiMeetingIntegrationTests.swift`
- Create: `Scripts/verify-codeswitch.sh`

- [x] **Step 1: Extend the integration seam**

Read optional `OPENLOOP_CONTEXT_PROMPT` and `OPENLOOP_EXPECTED_NAME` values in `HindiMeetingIntegrationTests`. Pass the context to `WhisperKitMeetingTranscriber` and assert the expected name when supplied.

- [x] **Step 2: Add the real code-switch fixture script**

Generate `Hello, this is Dhruv. I am talking in English. अब मैं हिंदी में बात कर रहा हूँ।` with the macOS Lekha voice, run the integration test in automatic language mode, pass the local context text, and require `Dhruv`, `English`, and Hindi text in the result.

- [x] **Step 3: Run the fixture and confirm the new initializer seam fails**

Run: `Scripts/verify-codeswitch.sh`

Expected: compilation fails because the transcriber does not yet accept `contextPrompt`.

- [x] **Step 4: Inject ordinary prompt tokens**

Add `contextPrompt: String?` to `WhisperKitMeetingTranscriber`. After loading the pipeline, encode the prompt through `pipeline.tokenizer`, filter out special tokens, and set `DecodingOptions.promptTokens`; retain `language: nil` and `detectLanguage: true` for automatic jobs.

- [x] **Step 5: Supply the local account context in production**

Construct `WhisperKitMeetingTranscriber` with `TranscriptionContext.make(localUserName: NSFullUserName())` in `OpenLoopApp.swift`. No control or onboarding field is added.

- [x] **Step 6: Run the real code-switch and existing Hindi gates**

Run: `Scripts/verify-codeswitch.sh && Scripts/verify-hindi.sh`

Expected: both tests detect Hindi automatically; the code-switch fixture contains `Dhruv`, English, and Hindi text, and the Hindi fixture retains its existing Devanagari/meeting assertions.

### Task 3: Package and install build 8 closed

**Files:**
- Modify: `Resources/Info.plist`
- Modify: `README.md`

- [x] **Step 1: Document invisible local context conditioning**

Explain that OpenLoop gives Whisper the local Mac account name and multilingual vocabulary as on-device context, never uploads it, and keeps language detection automatic.

- [x] **Step 2: Bump `CFBundleVersion` from 7 to 8**

Set the integer build string to `8`.

- [x] **Step 3: Build and install**

Run `Scripts/build-app.sh`, verify the signature, move build 7 to a recoverable Trash backup, copy build 8 to `/Applications/OpenLoop ADHD.app`, and leave the process closed.

- [x] **Step 4: Run the focused final gate and commit**

Run the two real speech fixtures, focused unit tests, `git diff --check`, installed build/signature checks, and confirm `pgrep -x OpenLoopADHD` is empty. Commit with `fix: improve code-switch name accuracy`.

## Self-review

- Spec coverage: proper-name context, English/Hindi code switching, invisible automatic behavior, real-model acceptance, build, and closed installation are covered.
- Placeholder scan: every code change and command is explicit; no deferred work markers remain.
- Type consistency: `TranscriptionContext.make`, `WhisperKitMeetingTranscriber(contextPrompt:)`, and the integration environment names match across tasks.
