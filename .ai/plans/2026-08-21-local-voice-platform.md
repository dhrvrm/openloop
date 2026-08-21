# Local Voice Platform Implementation Plan

> **For Codex:** Execute this plan incrementally. Keep raw speech evidence immutable, expose every model decision in Advanced mode, and gate claims with user-corrected audio cases.

**Goal:** Turn OpenLoop from a batch meeting transcriber into a trustworthy, system-wide, offline voice layer for Indian-English, Hindi, and code-switched Hinglish.

**Architecture:** Capture 16 kHz mono audio once, use VAD to create speech spans, and route each span through a pluggable local recognizer. Qwen3-ASR is the accuracy-first final-text engine; Whisper large-v3 remains a timestamped fallback and ensemble witness. A fusion layer combines recognizer evidence, personal vocabulary, and correction history. A policy router decides whether to return raw text, apply deterministic normalization, invoke a small local editor, or escalate a difficult request to a larger local model. Output adapters insert the final text through Accessibility, clipboard, or keyboard fallback while preserving raw audio and transcript evidence.

**Tech Stack:** Swift 6/AppKit/SwiftUI, AVFoundation, Qwen3-ASR + Silero VAD through pinned `speech-swift`/MLX, WhisperKit/SpeakerKit, encrypted local vault, macOS Accessibility APIs.

---

### Task 1: Establish a measurable accuracy gate

**Files:**
- Create: `Sources/ADHDCore/VoiceQuality.swift`
- Create: `Tests/ADHDCoreTests/VoiceQualityTests.swift`
- Modify: `Sources/ADHDCore/VoiceBenchmark.swift`

1. Represent an immutable audio-case ID, reference transcript, locale mix, domain terms, engine output, latency, and correction.
2. Calculate word error rate for Latin text, character error rate for Devanagari, domain-term recall, and dropped-span rate.
3. Keep user corrections as reference truth in the encrypted repository.
4. Gate engine changes on the real corrected corpus, not a synthetic phrase alone.

### Task 2: Add the accuracy-first local Qwen engine

**Files:**
- Modify: `Package.swift`
- Create: `Sources/OpenLoopApp/QwenMeetingTranscriber.swift`
- Modify: `Sources/OpenLoopApp/OpenLoopApp.swift`
- Modify: `Sources/OpenLoopApp/MeetingSystemDiagnostics.swift`
- Modify: `Scripts/build-app.sh`
- Test: `Tests/OpenLoopAppTests/QwenMeetingTranscriberTests.swift`

1. Pin `soniqo/speech-swift` to reviewed commit `17302bd13c2fc192d89fd79a71810a3a1d8c4f1a` and link only `Qwen3ASR`; this predates its separate Whisper dependency and avoids duplicate WhisperKit products.
2. Load `aufklarer/Qwen3-ASR-0.6B-MLX-4bit` once and keep it warm in unified memory.
3. Auto-detect language; provide learned vocabulary as optional context without requiring user prompts.
4. Emit visible download/load/transcription progress and a raw preview.
5. Produce a duration-bounded transcript segment and fall back to Whisper if Qwen cannot load or yields no speech.
6. Package exactly one `mlx.metallib` beside the executable.

### Task 3: Build VAD-guided streaming sessions

**Files:**
- Create: `Sources/ADHDCore/VoiceSession.swift`
- Create: `Sources/OpenLoopApp/StreamingVoiceSession.swift`
- Modify: `Sources/OpenLoopApp/MeetingAudioRecorder.swift`
- Modify: `Sources/OpenLoopApp/MeetingTranscriptionController.swift`
- Test: `Tests/OpenLoopAppTests/StreamingVoiceSessionTests.swift`

1. Capture 20–32 ms PCM frames and meter input continuously.
2. Use Silero VAD for speech start/end, rolling preroll, and automatic endpointing.
3. Maintain separate stable and unstable transcript regions.
4. Emit partial updates every 400–800 ms while keeping final decoding independent.
5. Track stop-to-correct-final latency in Advanced mode.

### Task 4: Add transcript fusion and uncertainty

**Files:**
- Create: `Sources/ADHDCore/TranscriptFusion.swift`
- Create: `Sources/OpenLoopApp/AccuracyFirstTranscriber.swift`
- Modify: `Sources/ADHDCore/MeetingTranscription.swift`
- Test: `Tests/ADHDCoreTests/TranscriptFusionTests.swift`

1. Treat Qwen as primary text and Whisper as timestamp/fallback evidence.
2. Escalate only low-confidence, language-switch, and domain-term spans to the second recognizer.
3. Fuse exact agreements automatically; expose disagreements as reviewable spans.
4. Never silently replace raw evidence with inferred wording.

### Task 5: Learn vocabulary and deterministic corrections

**Files:**
- Modify: `Sources/ADHDCore/VoiceLearning.swift`
- Modify: `Sources/OpenLoopApp/MeetingTranscriptionController.swift`
- Modify: `Sources/OpenLoopApp/MainWindowController.swift`
- Test: `Tests/ADHDCoreTests/VoiceLearningTests.swift`

1. Make completed meeting transcripts editable.
2. Save raw and corrected text separately and record the correction in the encrypted vault.
3. Derive bounded, anchored terminology rules from repeated corrections.
4. Feed vocabulary hints into Qwen/Whisper and apply exact deterministic normalization after decoding.
5. Provide global, programming, project, and personal vocabulary scopes.

### Task 6: Route local semantic editing by mode

**Files:**
- Create: `Sources/ADHDCore/VoiceMode.swift`
- Create: `Sources/OpenLoopApp/LocalSpeechProcessor.swift`
- Create: `Sources/OpenLoopApp/LocalIntentRouter.swift`
- Modify: `Sources/OpenLoopApp/AppModel.swift`
- Test: `Tests/OpenLoopAppTests/LocalIntentRouterTests.swift`

1. Support Raw, Polished, Code, Email, Casual, Markdown, Bullets, and JSON modes.
2. Bypass the LLM for clean raw dictation and deterministic voice commands.
3. Use a compact local model for punctuation, fillers, and routine formatting.
4. Load a larger quantized local model only for ambiguous intent or difficult transformations.
5. Require meaning-preservation checks and retain an undoable raw version.

### Task 7: Add context and safe system-wide output

**Files:**
- Create: `Sources/OpenLoopApp/VoiceContextEngine.swift`
- Create: `Sources/OpenLoopApp/TextOutputAdapter.swift`
- Modify: `Sources/OpenLoopApp/FrontmostApplicationReferenceProvider.swift`
- Modify: `Sources/OpenLoopApp/GlobalHotKey.swift`
- Test: `Tests/OpenLoopAppTests/TextOutputAdapterTests.swift`

1. Read only consented active-app metadata, focused field role, selection, and bounded surrounding text.
2. Route app-specific formatting without retaining sensitive context by default.
3. Insert through Accessibility first, then clipboard restore, then simulated keyboard fallback.
4. Keep one configurable global push-to-talk shortcut and visible recording HUD.
5. Add deterministic voice commands with confirmation for destructive actions.

### Task 8: Ship trust and observability in the GUI

**Files:**
- Modify: `Sources/OpenLoopApp/AdvancedInspector.swift`
- Modify: `Sources/OpenLoopApp/MainWindowController.swift`
- Modify: `Sources/OpenLoopApp/OpenLoopVisualSystem.swift`
- Test: `Tests/OpenLoopAppTests/MainWindowControllerTests.swift`

1. Show audio level, VAD state, stable/unstable text, active recognizer, fallback reason, editor route, output adapter, and latency.
2. Add raw/polished comparison and one-click correction/undo.
3. Show model download size, memory residency, and private/offline status.
4. Keep the normal surface minimal; place engine detail behind Advanced mode.

### Release gate

The product is not marketed as better than Wispr Flow until the corrected personal corpus shows lower code-switched WER/CER, equal or better terminology recall, no silent dropped spans, and acceptable p95 stop-to-final latency across quiet, fan/traffic, and laptop-microphone conditions.
