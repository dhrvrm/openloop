# Local voice platform

OpenLoop treats a transcript as evidence. The recognizer may be uncertain; the stored audio, timestamps, language order, speaker turns, and competing hypotheses must remain available for correction and evaluation.

## Shipped recognition path

```text
microphone or imported audio
  → 16 kHz mono samples
  → bounded high-pass, presence recovery, and automatic gain
  → Whisper large-v3 with VAD chunking and word timestamps
  → SpeakerKit/Pyannote turn alignment
  → Qwen3-ASR witness with personal vocabulary and rolling context
  → timestamp-safe fusion
  → transcript, review evidence, summary, and semantic memory
```

Whisper owns the canonical meeting timeline because it provides the word timestamps needed for speaker alignment. Qwen is a separate local witness: agreement increases confidence; a safe, time-aligned terminology correction can replace text; broad or mismatched evidence is retained for review and cannot overwrite a short speaker turn.

Automatic language detection remains the default. Hindi and English can occur in the same recording and in the same sentence. Qwen receives only a bounded tail of accepted prior text, labelled as context that must not be repeated, so a long meeting can keep names and language continuity without treating the whole transcript as a prompt.

## Acoustic behavior

The durable source file is never overwritten. Inference uses a conditioned copy with:

- removal of DC and low-frequency rumble;
- conservative presence recovery for muffled consonants;
- bounded, smoothed gain for quiet speech;
- soft limiting so boosted audio cannot clip;
- speech-aware long-form boundaries rather than fixed cuts through words.

This is not a claim that deterministic conditioning replaces a learned denoiser. RNNoise/WebRTC-style suppression is eligible only after it improves held-out WER and diarization error across real Mac recordings; perceptual cleanliness alone is insufficient.

## Quality evidence

The reproducible suite lives in [`Evaluation/voice/README.md`](../Evaluation/voice/README.md). It measures:

- WER by acoustic condition and language;
- Devanagari CER;
- language-switch sequence accuracy;
- domain-term recall and dropped speech;
- speaker-count error and diarization error;
- stop-to-final latency.

The official corpus ledger includes Mozilla Common Voice, AI4Bharat IndicVoices, Google FLEURS, Microsoft DNS Challenge, and VoxConverse. Dataset metadata and tools can be fetched with:

```bash
Scripts/evals/bootstrap_voice_corpora.sh
```

Audio remains in ignored `.eval-data/`. Licenses and user consent govern each source; no third-party or private voice recording is committed to the repository.

## How to provide your evaluation set

Create `.eval-data/private/release.jsonl` with one JSON object per recording:

```json
{"id":"dhruv-fan-hinglish-01","audio":".eval-data/private/dhruv-fan-hinglish-01.wav","reference":"I was thinking कि release time कम कर सकते हैं for SGLC releases.","languages":["en","hi","en","hi","en"],"condition":"noise-5db","domain_terms":["release time","SGLC"],"speaker_turns":[{"speaker":"dhruv","start":0.0,"end":6.2}]}
```

The reference must be literal: keep fillers, grammatical mistakes, repeated words, and the language actually spoken. Do not translate Hindi or rewrite the intended meaning. For a multi-speaker recording, annotate speaker changes in seconds; labels can be arbitrary.

Use at least 100 consented clips spread across:

- near, arm's-length, and across-room microphone distance;
- fan/AC, keyboard, street, café, reverberation, and muffling;
- English, Hindi, and mid-sentence Hinglish switches;
- names, acronyms, release terminology, and code vocabulary;
- one speaker, clean turns, interruptions, and overlap.

Freeze a held-out release split before tuning. Compare every candidate and competitor against that exact split with `Scripts/evals/voice_quality_eval.py`. A best-in-class claim is blocked until condition-level gates and a controlled competitor comparison pass.
