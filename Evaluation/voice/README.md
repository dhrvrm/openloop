# Voice quality evaluation

OpenLoop does not call a recognizer “accurate” from a successful demo. This suite keeps literal speech evidence and reports where the pipeline fails.

## What to measure

- Word error rate for English, Hindi, and mixed speech.
- Devanagari character error rate so a plausible-looking Hindi sentence cannot hide wrong words.
- Language-sequence accuracy across code switches.
- Domain-term recall for names, acronyms, and project vocabulary.
- Dropped-span rate for speech that vanished entirely.
- Speaker-count error and frame-based diarization error when speaker turns are annotated.
- Stop-to-final latency, reported beside accuracy rather than folded into it.

Every result must also be grouped by `condition`: `clean`, `muffled`, `reverberant`, `noise-20db`, `noise-10db`, `noise-5db`, `noise-0db`, `overlap`, or another explicit label.

## Public evidence

Run the metadata bootstrap:

```bash
Scripts/evals/bootstrap_voice_corpora.sh
```

It clones metadata and official tooling for AI4Bharat IndicVoices, Microsoft DNS Challenge, and VoxConverse into ignored `.eval-data/sources/`. It deliberately does not pull the DNS training corpus, which is hundreds of gigabytes, or click through dataset licenses for you.

The source and license ledger is [`corpora.json`](corpora.json). Recommended evidence:

- Mozilla Common Voice English and Hindi for speaker/accent diversity.
- AI4Bharat IndicVoices Hindi conversational and extempore speech for spontaneous Indian speech.
- Google FLEURS `en_us` and `hi_in` as a stable multilingual comparison set.
- Microsoft DNS Challenge noise and room impulse responses to generate reproducible noisy, reverberant, speakerphone, and interfering-talker cases.
- VoxConverse 0.3 dev audio and corrected RTTM annotations for speaker turns and overlap.

Kaggle is optional. Authentication does not make a dataset suitable for training.
Every candidate must first have an exact slug, observed version, license evidence,
usage status, allowed uses, and forbidden uses in `corpora.json`. Catalog metadata
without downloading audio:

```bash
OPENLOOP_KAGGLE_CLI=/path/to/kaggle \
  Scripts/evals/bootstrap_voice_corpora.sh \
  --kaggle owner/dataset-slug \
  --catalog-only
```

Audio download is denied unless the catalog marks the exact dataset
`evaluation-approved` and the caller repeats that status explicitly with
`--allow-status evaluation-approved`. Pending, exploratory, or commercially
excluded corpora cannot enter fine-tuning or release evaluation. Downloaded
material stays under ignored `.eval-data/kaggle/`.

The authenticated audit on 2026-08-27 found that the Kaggle Punjabi Shrutilipi
mirror reports `other` through the API while its description says CC0; it remains
pending license resolution. The YouTube-derived Indian-languages collection is
excluded from commercial work. The InfoBay Hindi, Punjabi, and Spanish call-center
samples have isolated speaker channels but no literal transcripts and conflicting
commercial wording, so they are exploratory-only rather than WER or training data.

## Your private gold set

Public corpora will not reproduce your microphone, room, vocabulary, pace, or Hindi–English switching style. Keep at least 100 private, speaker-consented clips under `.eval-data/private/`:

1. Record the same content at arm's length, across the room, beside a fan, with keyboard noise, and with intentional muffling.
2. Include single-speaker Hinglish, language changes at sentence boundaries and mid-sentence, two-speaker turns, interruption, and overlap.
3. Write the exact words that were spoken. Do not polish grammar, translate Hindi, remove fillers, or repair a misstatement in the reference.
4. Write language order as heard, for example `["en", "hi", "en"]`.
5. For meetings, annotate speaker turns in seconds. Speaker names are arbitrary and scored label-independently.
6. Freeze the references before comparing engine versions. Never tune on the held-out release set.

Copy [`manifest.example.jsonl`](manifest.example.jsonl) and add one JSON object per line. Audio is identified by path for local runs; third-party or private audio is never committed.

## Run OpenLoop's engines without opening the app

Build the native executable, then run its headless evaluation command from the repository root:

```bash
swift build -c release --product OpenLoopADHD

.build/release/OpenLoopADHD --voice-eval \
  --manifest .eval-data/private/release.jsonl \
  --output .eval-data/results/openloop-local.jsonl \
  --engine dictation \
  --language auto
```

This command is intercepted before AppKit, the vault, global shortcuts, or any window is initialized. It does not activate OpenLoop or ask for microphone/keychain access. Audio files are read locally from the paths in the manifest. The first run may download the selected local speech models; later rows in the same run reuse the resident models.

Engine choices mirror the product paths:

- `dictation` — quality Qwen primary, Whisper cross-check; the default for global voice typing.
- `meeting` — timestamped Whisper primary, quality Qwen cross-check; the default for imported meetings.
- `qwen` — isolate the quality multilingual recognizer.
- `whisper` — isolate the timestamped recognizer and diarization path.

`--language auto` is the default and is the correct setting for mixed Hindi and English. A manifest row may set `"language_hint":"hi"` or `"language_hint":"en"` only when the recording is intentionally single-language. `--data-directory` can point at an isolated model cache; otherwise the command reuses `~/Library/Application Support/OpenLoopADHD`.

The output is one JSON object per case. It contains the literal hypothesis, ordered language-script runs, speaker segments, model identifier, error text, and full-call latency. The first row is marked `cold_start`; warm percentile metrics exclude it.

## Score a candidate

Export one hypothesis row per reference using the shape in `Tests/Fixtures/voice-eval/hypotheses.example.jsonl`, then run:

```bash
python3 Scripts/evals/voice_quality_eval.py \
  --manifest Evaluation/voice/manifest.example.jsonl \
  --hypotheses Tests/Fixtures/voice-eval/hypotheses.example.jsonl
```

For a release gate:

```bash
python3 Scripts/evals/voice_quality_eval.py \
  --manifest .eval-data/private/release.jsonl \
  --hypotheses .eval-data/results/openloop-local.jsonl \
  --max-wer 0.10 \
  --max-devanagari-cer 0.08 \
  --max-diarization-error 0.15 \
  --max-dropped-span-rate 0.01 \
  --max-empty-hypothesis-rate 0.005 \
  --max-warm-p95-ms 900 \
  --min-language-sequence-accuracy 0.95 \
  --output .eval-data/results/openloop-local-report.json
```

Treat those values as internal targets, not proof of market leadership. A “better than” claim additionally needs the same frozen audio, transcription convention, and scoring code applied to the competitor output.

## Training boundary

Do not fine-tune on the release evaluation split. Use separate training/development speakers, keep public license obligations with derived models, and first determine whether errors come from audio conditioning, recognition, language continuity, vocabulary, timestamp alignment, or diarization. Fine-tuning an ASR model cannot repair a broken microphone signal or discarded speaker timeline.

Before a fine-tuning job, run `voice_corpus_guard.py`, generate conservative
teacher labels with `teacher_consensus.py`, and export with
`export_distillation_dataset.py`. The exporter accepts only `distill-train`
rows from an `evaluation-approved` corpus whose allowed uses explicitly include
fine-tuning, or private rows with `training_consent: true`. Human-confirmed text
wins over teacher consensus. Release-test, review-required, ambiguous-license,
and unconsented private rows are written to the exclusion ledger instead.

Speaker turns remain a separate sidecar. The ASR student learns literal words
and language continuity; it does not own diarization or persistent speaker
identity.
