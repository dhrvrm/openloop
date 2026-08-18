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

if ! say -v '?' | rg -q '^Lekha[[:space:]]+hi_IN'; then
    print -u2 'Code-switch acceptance requires the macOS Lekha voice.'
    exit 1
fi

say -v Lekha -r 165 \
    -o "$TASK_FIXTURE_DIR/codeswitch-source.aiff" \
    'Hello, this is Dhruv. I am talking in English. अब मैं हिंदी में बात कर रहा हूँ।'
afconvert -f WAVE -d LEI16@16000 \
    "$TASK_FIXTURE_DIR/codeswitch-source.aiff" \
    "$TASK_FIXTURE_DIR/codeswitch.wav"

env -u OPENLOOP_LANGUAGE_CODE \
OPENLOOP_HINDI_FIXTURE="$TASK_FIXTURE_DIR/codeswitch.wav" \
OPENLOOP_MODEL_STORAGE="$TASK_MODEL_STORAGE" \
OPENLOOP_CONTEXT_PROMPT="$TASK_CONTEXT" \
OPENLOOP_EXPECTED_NAME=Dhruv \
    "$TASK_ROOT/Scripts/test.sh" --filter localWhisperRecognizesHindiFixture
