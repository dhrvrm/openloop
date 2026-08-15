#!/bin/zsh
set -euo pipefail

openloop_root="${0:A:h:h}"
app_bundle="$openloop_root/.artifacts/app/OpenLoop ADHD.app"
binary="$app_bundle/Contents/MacOS/OpenLoopADHD"
dmg_path="$openloop_root/.artifacts/OpenLoop-ADHD.dmg"
data_dir=$(mktemp -d /tmp/openloop-focus-verify-data.XXXXXX)
mount_dir=$(mktemp -d /tmp/openloop-focus-verify-mount.XXXXXX)
keychain_service="dev.openloop.focus.verify.$(/usr/bin/uuidgen)"
mounted=false

cleanup() {
    if [[ "$mounted" == true ]]; then
        /usr/bin/hdiutil detach "$mount_dir" -quiet || true
    fi
    /usr/bin/security delete-generic-password \
        -s "$keychain_service" -a root-key >/dev/null 2>&1 || true
    /bin/rm -rf "$data_dir" "$mount_dir"
}
trap cleanup EXIT

"$openloop_root/Scripts/verify.sh"
"$openloop_root/Scripts/build-dmg.sh"
/usr/bin/codesign --verify --deep --strict "$app_bundle"

focus_interrupt_output=$(
    OPENLOOP_DATA_DIR="$data_dir" \
    OPENLOOP_KEYCHAIN_SERVICE="$keychain_service" \
        "$binary" --focus-interrupt-test
)
print -r -- "$focus_interrupt_output"
focus_intention_id=$(print -r -- "$focus_interrupt_output" | \
    /usr/bin/awk -F= '/^focus-interrupted-id=/{print $2}')
[[ -n "$focus_intention_id" ]]

OPENLOOP_DATA_DIR="$data_dir" \
OPENLOOP_KEYCHAIN_SERVICE="$keychain_service" \
    "$binary" --focus-resume-test "$focus_intention_id"

packet_markers=(
    "packaged focus recovery marker"
    "packaged completed recovery marker"
    "packaged exact next recovery marker"
    "packaged blocker recovery marker"
    "packaged-reference-recovery-marker"
)
for marker in "${packet_markers[@]}"; do
    if LC_ALL=C /usr/bin/grep -R -a -q "$marker" "$data_dir"; then
        print -u2 "Plaintext recovery marker found in vault files: $marker"
        exit 1
    fi
done

OPENLOOP_DATA_DIR="$data_dir" \
OPENLOOP_KEYCHAIN_SERVICE="$keychain_service" \
    "$binary" --benchmark-save 100
OPENLOOP_DATA_DIR="$data_dir" \
OPENLOOP_KEYCHAIN_SERVICE="$keychain_service" \
    "$binary" --benchmark-capture 100
OPENLOOP_DATA_DIR="$data_dir" \
OPENLOOP_KEYCHAIN_SERVICE="$keychain_service" \
    "$binary" --hotkey-test

/usr/bin/hdiutil attach "$dmg_path" -nobrowse -readonly -mountpoint "$mount_dir" -quiet
mounted=true
[[ -d "$mount_dir/OpenLoop ADHD.app" ]]
[[ -L "$mount_dir/Applications" ]]
/usr/bin/hdiutil detach "$mount_dir" -quiet
mounted=false

print "Increment 2 verification passed."
