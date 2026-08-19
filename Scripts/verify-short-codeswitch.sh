#!/bin/zsh
set -euo pipefail

TASK_ROOT=${0:A:h:h}
TASK_MODEL_STORAGE=${OPENLOOP_MODEL_STORAGE:-"$HOME/Library/Application Support/OpenLoopADHD/Models/WhisperKit"}
TASK_FIXTURE_DIR=$(mktemp -d /tmp/openloop-short-codeswitch.XXXXXX)

cleanup() {
    if [[ -n ${TASK_FIXTURE_DIR:-} && $TASK_FIXTURE_DIR == /tmp/openloop-short-codeswitch.* ]]; then
        rm -rf "$TASK_FIXTURE_DIR"
    fi
}
trap cleanup EXIT

if ! say -v '?' | rg -q '^Lekha[[:space:]]+hi_IN' \
    || ! say -v '?' | rg -q '^Rishi[[:space:]]+en_IN'; then
    print -u2 'Short code-switch acceptance requires the macOS Rishi and Lekha voices.'
    exit 1
fi

say -v Rishi -r 150 \
    -o "$TASK_FIXTURE_DIR/english-one.aiff" \
    'Hello this is Dhruv. I am speaking in English continuously while checking our meeting transcript and the release plan.'
say -v Lekha -r 165 \
    -o "$TASK_FIXTURE_DIR/hindi.aiff" \
    'अब मैं हिंदी में बात कर रहा हूँ।'
say -v Rishi -r 150 \
    -o "$TASK_FIXTURE_DIR/english-two.aiff" \
    'Now I am back in English without stopping the recording, and every spoken language should remain accurate in the final transcript.'

for source in english-one hindi english-two; do
    afconvert -f WAVE -d LEI16@16000 \
        "$TASK_FIXTURE_DIR/$source.aiff" \
        "$TASK_FIXTURE_DIR/$source.wav"
done

TASK_FIXTURE_DIR="$TASK_FIXTURE_DIR" python3 <<'PY'
import array
import os
import wave

root = os.environ["TASK_FIXTURE_DIR"]
names = ["english-one", "hindi", "english-two"]

def read(name):
    with wave.open(os.path.join(root, name + ".wav"), "rb") as source:
        return source.getparams(), source.readframes(source.getnframes())

parameters, first = read(names[0])
payloads = [first]
for name in names[1:]:
    candidate_parameters, payload = read(name)
    assert candidate_parameters.nchannels == parameters.nchannels
    assert candidate_parameters.sampwidth == parameters.sampwidth
    assert candidate_parameters.framerate == parameters.framerate
    payloads.append(payload)

def trim_silence(payload):
    samples = array.array("h")
    samples.frombytes(payload)
    if os.sys.byteorder != "little":
        samples.byteswap()
    active = [index for index, value in enumerate(samples) if abs(value) >= 180]
    if not active:
        return payload
    padding = int(parameters.framerate * 0.04) * parameters.nchannels
    lower = max(0, active[0] - padding)
    upper = min(len(samples), active[-1] + padding + 1)
    trimmed = array.array("h", samples[lower:upper])
    if os.sys.byteorder != "little":
        trimmed.byteswap()
    return trimmed.tobytes()

payloads = [trim_silence(payload) for payload in payloads]
silence_frames = int(parameters.framerate * 0.12)
silence = bytes(silence_frames * parameters.nchannels * parameters.sampwidth)
output_path = os.path.join(root, "short-codeswitch.wav")
with wave.open(output_path, "wb") as output:
    output.setparams(parameters)
    output.writeframes((silence.join(payloads)))

with wave.open(output_path, "rb") as fixture:
    duration = fixture.getnframes() / fixture.getframerate()
assert 17 <= duration <= 22, f"fixture duration {duration:.2f}s is outside 17...22s"
print(f"short-codeswitch-duration={duration:.2f}s")
PY

env -u OPENLOOP_LANGUAGE_CODE \
OPENLOOP_HINDI_FIXTURE="$TASK_FIXTURE_DIR/short-codeswitch.wav" \
OPENLOOP_MODEL_STORAGE="$TASK_MODEL_STORAGE" \
OPENLOOP_EXPECTED_NAME=Dhruv \
OPENLOOP_EXPECTED_LANGUAGES=en,hi \
OPENLOOP_EXPECTED_CHUNK_EVENTS=3 \
    "$TASK_ROOT/Scripts/test.sh" --filter localWhisperRecognizesHindiFixture
