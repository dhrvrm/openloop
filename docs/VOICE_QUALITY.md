# Voice quality evidence

OpenLoop does not treat a model name as evidence of accuracy. A release candidate must be decoded headlessly against retained audio, compared by timestamp coverage and literal words, and scored against a human-confirmed reference before any WER claim.

## 2026-08-27 retained recording

The private 27.17-second AAC source was intact: mono 44.1 kHz, peak -18.3 dBFS, RMS -36.3 dBFS, and no clipping. It was evaluated locally and was never uploaded.

| Engine | Language | Result |
| --- | --- | --- |
| Shipped WhisperKit 626 MB | `en + pt` | Dropped the Hindi span and produced “I am a man and I'm curious as not … job you will download.” |
| Full WhisperKit Core ML | `en + pt` | Still treated the Hindi switch as Portuguese and hallucinated English. |
| Qwen3-ASR 1.7B MLX 8-bit | `en` | Hallucinated Chinese tokens and dropped speech. It is not accepted for final text. |
| Official whisper.cpp full large-v3 | `en + hi` | Preserved the English-Hindi-English order, the Hindi sentence, and the full speech interval. |

The accepted local hypothesis is:

```text
I am a man, the accuracy is not coming,
जो भी बोलता हूँ वो समझ नहीं आता है,
and the transcription is not getting there.
I think there is no continuity in there, and the voice clarity is okay.
The mic is really good. If I give this recording to OpenAI, that will work,
and somehow we are not able to achieve that.
```

The opening words still require the speaker's confirmation. Until that reference is confirmed, this document reports recovery and coverage, not WER.

## Accepted engine structure

```text
record original audio once
  ├─ Qwen small: disposable low-latency partial feedback
  └─ whisper.cpp full large-v3: final local words and token timestamps
       └─ SpeakerKit: speaker turns and local voice fingerprints
            └─ deterministic learned vocabulary normalization
```

The full 3.1 GB model downloads once, is checked against SHA-256, and remains in OpenLoop's application-support directory. The helper is built from pinned whisper.cpp commit `371b5a7` (tag `b4938`) and bundled in the signed app. Final recognition uses the original 16 kHz audio; deterministic conditioning is reserved for experiments until it improves held-out WER.

## Reproduce without launching the app

```bash
.build/release/OpenLoopADHD --voice-eval \
  --manifest .eval-data/private/release.jsonl \
  --output .artifacts/voice-results.jsonl \
  --engine whispercpp \
  --whisper-cli /path/to/whisper-cli \
  --data-directory .artifacts/voice-data
```

Required multilingual matrix: English, Hindi, Punjabi, and Spanish individually; switches in both directions; Romanized Hindi; two to four speakers; short turns; interruptions; overlap; fan, keyboard, room echo, and muffled speech. Speaker identity must remain stable across language changes. A model must abstain or surface uncertainty rather than inventing text.
