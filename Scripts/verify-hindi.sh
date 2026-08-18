#!/bin/zsh
set -euo pipefail

TASK_ROOT=${0:A:h:h}
TASK_MODEL_STORAGE=${OPENLOOP_MODEL_STORAGE:-"$HOME/Library/Application Support/OpenLoopADHD/Models/WhisperKit"}
TASK_FIXTURE_DIR=$(mktemp -d /tmp/openloop-hindi-acceptance.XXXXXX)

cleanup() {
    if [[ -n ${TASK_FIXTURE_DIR:-} && $TASK_FIXTURE_DIR == /tmp/openloop-hindi-acceptance.* ]]; then
        rm -rf "$TASK_FIXTURE_DIR"
    fi
}
trap cleanup EXIT

if ! say -v '?' | rg -q '^Lekha[[:space:]]+hi_IN'; then
    print -u2 'Hindi acceptance requires the macOS Lekha voice.'
    exit 1
fi

say -v Lekha -r 165 \
    -o "$TASK_FIXTURE_DIR/hinglish-source.aiff" \
    'नमस्ते team, आज की meeting में हमने project launch करने का decision लिया है। Rahul design complete करेंगे और Seema client को email भेजेंगी।'
afconvert -f WAVE -d LEI16@16000 \
    "$TASK_FIXTURE_DIR/hinglish-source.aiff" \
    "$TASK_FIXTURE_DIR/hinglish.wav"

OPENLOOP_HINDI_FIXTURE="$TASK_FIXTURE_DIR/hinglish.wav" \
OPENLOOP_MODEL_STORAGE="$TASK_MODEL_STORAGE" \
OPENLOOP_LANGUAGE_CODE=hi \
    "$TASK_ROOT/Scripts/test.sh" --filter localWhisperRecognizesHindiFixture
