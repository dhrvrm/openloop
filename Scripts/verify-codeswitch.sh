#!/bin/zsh
set -euo pipefail

TASK_ROOT=${0:A:h:h}
TASK_MODEL_STORAGE=${OPENLOOP_MODEL_STORAGE:-"$HOME/Library/Application Support/OpenLoopADHD/Models/WhisperKit"}
TASK_FIXTURE_DIR=$(mktemp -d /tmp/openloop-codeswitch-acceptance.XXXXXX)
TASK_CONTEXT='Participants: Dhruv. Multilingual conversation in English and Hindi (हिन्दी), including Hinglish code-switching. Preserve names. Write Hindi speech in Devanagari and English speech in Latin; do not translate.'

cleanup() {
    if [[ -n ${TASK_FIXTURE_DIR:-} && $TASK_FIXTURE_DIR == /tmp/openloop-codeswitch-acceptance.* ]]; then
        rm -rf "$TASK_FIXTURE_DIR"
    fi
}
trap cleanup EXIT

if ! say -v '?' | rg -q '^Lekha[[:space:]]+hi_IN' \
    || ! say -v '?' | rg -q '^Rishi[[:space:]]+en_IN'; then
    print -u2 'Code-switch acceptance requires the macOS Rishi and Lekha voices.'
    exit 1
fi

say -v Rishi -r 165 \
    -o "$TASK_FIXTURE_DIR/english-source.aiff" \
    'Hello. Hello. Hello. I am Dhruv. I am talking in English.'
say -v Lekha -r 165 \
    -o "$TASK_FIXTURE_DIR/hindi-source.aiff" \
    'अब मैं हिंदी में बात कर रहा हूँ।'
afconvert -f WAVE -d LEI16@16000 \
    "$TASK_FIXTURE_DIR/english-source.aiff" \
    "$TASK_FIXTURE_DIR/english.wav"
afconvert -f WAVE -d LEI16@16000 \
    "$TASK_FIXTURE_DIR/hindi-source.aiff" \
    "$TASK_FIXTURE_DIR/hindi.wav"

TASK_FIXTURE_DIR="$TASK_FIXTURE_DIR" python3 <<'PY'
import os
import wave

root = os.environ["TASK_FIXTURE_DIR"]
paths = [os.path.join(root, "english.wav"), os.path.join(root, "hindi.wav")]
with wave.open(paths[0], "rb") as first:
    parameters = first.getparams()
    english = first.readframes(first.getnframes())
with wave.open(paths[1], "rb") as second:
    assert second.getnchannels() == parameters.nchannels
    assert second.getsampwidth() == parameters.sampwidth
    assert second.getframerate() == parameters.framerate
    hindi = second.readframes(second.getnframes())
silence_frames = int(parameters.framerate * 0.8)
silence = bytes(silence_frames * parameters.nchannels * parameters.sampwidth)
with wave.open(os.path.join(root, "codeswitch.wav"), "wb") as output:
    output.setparams(parameters)
    output.writeframes(english + silence + hindi)
PY

env -u OPENLOOP_LANGUAGE_CODE \
OPENLOOP_HINDI_FIXTURE="$TASK_FIXTURE_DIR/codeswitch.wav" \
OPENLOOP_MODEL_STORAGE="$TASK_MODEL_STORAGE" \
OPENLOOP_CONTEXT_PROMPT="$TASK_CONTEXT" \
OPENLOOP_EXPECTED_NAME=Dhruv \
OPENLOOP_EXPECTED_LANGUAGES=en,hi \
    "$TASK_ROOT/Scripts/test.sh" --filter localWhisperRecognizesHindiFixture
