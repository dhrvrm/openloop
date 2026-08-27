# Local voice platform

OpenLoop treats a transcript as evidence. The recognizer may be uncertain; the stored audio, timestamps, language order, speaker turns, and competing hypotheses must remain available for correction and evaluation.

## Shipped recognition path

```text
microphone or imported audio
  → 16 kHz mono samples
  → Qwen small disposable partial feedback
  → official whisper.cpp full large-v3 on original audio
  → SpeakerKit/Pyannote turn alignment
  → learned vocabulary and deterministic normalization
  → transcript, review evidence, summary, and semantic memory
```

Official whisper.cpp owns final words and token timestamps. Qwen small is limited to partial feedback while speech is still arriving; its output is replaceable and cannot overwrite the final transcript. Speaker turns and language changes are independent, so changing language does not create a new speaker.

Automatic language detection remains the default. Hindi and English can occur in the same recording and in the same sentence. Learned names and terminology are supplied automatically as bounded vocabulary; the user does not choose a language or write a prompt for ordinary recording.

## Speaker identity

SpeakerKit emits a centroid embedding for each voice cluster. OpenLoop keeps that observation with the encrypted transcript and resolves it against prior local observations using cosine distance, an ambiguity margin, and one-profile-per-speaker assignment. A close but ambiguous match is treated as a new voice; the application does not guess a person's identity merely because two voices sound similar.

New voices appear as Speaker A, Speaker B, Speaker C, and so on. Selecting a speaker label lets the user assign an alias such as Dhruv. The alias is attached to the stable local profile and updates prior transcripts carrying that profile; future recordings reuse it only when the fingerprint match clears both confidence gates. The interface explicitly says when speaker separation was unavailable, rather than presenting an unlabeled transcript as successful diarization.

Fingerprint observations are model-derived vectors, not playable audio and not an authentication credential. They remain inside the same encrypted local vault as the transcript. Deleting the connected transcripts removes their observations; no enrollment or voice data is uploaded.

## Correction learning

An explicit transcript edit becomes local evidence after one save. The learning layer compares the recognized and corrected token sequences, removes matching sentence context, and stores the smallest changed phrase. For example, editing `It was tit-for-tat in the meeting` to `It was tip for tap in the meeting` teaches only `tit for tat` → `tip for tap`, not the complete sentence.

Learned rules are token-boundary aware, tolerate space and hyphen variants, and run after recognizer fusion for meetings and dictation. Timing, speaker profile, language, and competing recognizer evidence remain unchanged. This is deterministic terminology correction, not semantic rewriting; ambiguous wording stays reviewable.

## Acoustic behavior

The durable source file is never overwritten. Final recognition uses the original resampled audio. The existing conditioned copy is an experimental route with:

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
