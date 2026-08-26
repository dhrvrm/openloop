# Changelog

All notable changes are recorded here. Releases follow semantic versioning.

## [Unreleased]

- Added local Speaker A/B/C separation with encrypted voice fingerprints, conservative cross-recording identity matching, and durable user aliases.
- Made speaker-separation failure visible and preserved speaker identity through accuracy-first transcript fusion and corrections.
- Added one-edit phrase learning so minimal corrections such as `tit-for-tat` → `tip for tap` are applied to future meeting and dictation transcripts.

## [1.0.6] — 2026-08-23

- Routed all Whisper decoding paths through the same conditioned 16 kHz signal.
- Added conservative presence recovery for quiet and muffled speech.
- Added VAD-aware Whisper chunking and low-energy Qwen boundaries for long recordings.
- Carried bounded prior transcript context across Qwen windows without forcing a language.
- Preserved Whisper word timestamps and SpeakerKit labels as the canonical meeting timeline.
- Prevented broad witness spans from overwriting short speaker turns during transcript fusion.
- Added public-corpus provenance, safe metadata bootstrapping, private gold-set guidance, and condition-level voice evaluation metrics.

## [1.0.5] — 2026-08-22

- Added a global record-and-transcribe shortcut with visible status in the workspace top bar.
- Added explicit System, Light, and Dark appearance controls shared by the native app and product site.
- Replaced generic recording labels with timestamped voice-note names before semantic title generation.
- Reworked the main workspace around an open list canvas and a persistent bottom capture dock.
- Updated the product site mockup to reflect the native workspace and capture behavior.

## [1.0.4] — 2026-08-22

- Added local title generation and semantic context naming for recorded evidence.
- Improved the native visual tokens and public product presentation.

## [1.0.3] — 2026-08-22

- Hardened multilingual local transcription and recording recovery.
- Added semantic summaries, action candidates, and connected-memory presentation.

## [1.0.2] — 2026-08-22

- Made community DMG signing an explicit, verified release mode.
- Removed hard-coded version checks from bundle verification.

## [1.0.1] — 2026-08-22

- Added the public product website and GitHub Pages deployment.
- Organized the native application source by capability.
- Added repository architecture, contribution, security, and release documentation.
- Added versioned DMG and GitHub Release automation.
- Increased main workspace and inspector vertical breathing room.
- Rewrote simple-mode and website language around concrete user actions.

## [1.0.0] — 2026-08-22

- Added local multilingual voice capture with visible recording feedback.
- Added meeting transcription, summary and action-candidate presentation.
- Added local semantic memory, return and connected graph surfaces.
- Added encrypted local storage, permission-aware capture and advanced diagnostics.
- Established the native visual system and global capture shortcuts.

[Unreleased]: https://github.com/dhrvrm/openloop/compare/v1.0.6...HEAD
[1.0.6]: https://github.com/dhrvrm/openloop/compare/v1.0.5...v1.0.6
[1.0.5]: https://github.com/dhrvrm/openloop/compare/v1.0.4...v1.0.5
[1.0.4]: https://github.com/dhrvrm/openloop/compare/v1.0.3...v1.0.4
[1.0.3]: https://github.com/dhrvrm/openloop/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/dhrvrm/openloop/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/dhrvrm/openloop/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/dhrvrm/openloop/releases/tag/v1.0.0
