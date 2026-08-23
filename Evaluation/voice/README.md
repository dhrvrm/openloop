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

Kaggle is optional. After accepting a dataset's terms and configuring the Kaggle CLI:

```bash
Scripts/evals/bootstrap_voice_corpora.sh --kaggle owner/dataset-slug
```

The dataset is placed under ignored `.eval-data/kaggle/`. Record its exact slug, version, license, and split in `corpora.json` before using it in a release comparison.

## Your private gold set

Public corpora will not reproduce your microphone, room, vocabulary, pace, or Hindi–English switching style. Keep at least 100 private, speaker-consented clips under `.eval-data/private/`:

1. Record the same content at arm's length, across the room, beside a fan, with keyboard noise, and with intentional muffling.
2. Include single-speaker Hinglish, language changes at sentence boundaries and mid-sentence, two-speaker turns, interruption, and overlap.
3. Write the exact words that were spoken. Do not polish grammar, translate Hindi, remove fillers, or repair a misstatement in the reference.
4. Write language order as heard, for example `["en", "hi", "en"]`.
5. For meetings, annotate speaker turns in seconds. Speaker names are arbitrary and scored label-independently.
6. Freeze the references before comparing engine versions. Never tune on the held-out release set.

Copy [`manifest.example.jsonl`](manifest.example.jsonl) and add one JSON object per line. Audio is identified by path for local runs; third-party or private audio is never committed.

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
  --hypotheses .eval-data/results/openloop-1.0.6.jsonl \
  --max-wer 0.12 \
  --max-devanagari-cer 0.08 \
  --max-diarization-error 0.15 \
  --min-language-sequence-accuracy 0.95 \
  --output .eval-data/results/openloop-1.0.6-report.json
```

Treat those values as internal targets, not proof of market leadership. A “better than” claim additionally needs the same frozen audio, transcription convention, and scoring code applied to the competitor output.

## Training boundary

Do not fine-tune on the release evaluation split. Use separate training/development speakers, keep public license obligations with derived models, and first determine whether errors come from audio conditioning, recognition, language continuity, vocabulary, timestamp alignment, or diarization. Fine-tuning an ASR model cannot repair a broken microphone signal or discarded speaker timeline.
