#!/bin/zsh
set -euo pipefail

openloop_root="${0:A:h:h}"
app_bundle="$openloop_root/.artifacts/app/OpenLoop ADHD.app"
binary="$app_bundle/Contents/MacOS/OpenLoopADHD"
dmg_path="$openloop_root/.artifacts/OpenLoop-ADHD.dmg"
data_dir=$(mktemp -d /tmp/openloop-increment3-verify-data.XXXXXX)
mount_dir=$(mktemp -d /tmp/openloop-increment3-verify-mount.XXXXXX)
keychain_service="dev.openloop.increment3.verify.$(/usr/bin/uuidgen)"
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

run_diagnostic() {
    OPENLOOP_DATA_DIR="$data_dir" \
    OPENLOOP_KEYCHAIN_SERVICE="$keychain_service" \
        "$binary" "$@"
}

run_diagnostic --window-test
run_diagnostic --resurfacing-test
run_diagnostic --voice-controller-test

focus_interrupt_output=$(run_diagnostic --focus-interrupt-test)
print -r -- "$focus_interrupt_output"
focus_intention_id=$(print -r -- "$focus_interrupt_output" | \
    /usr/bin/awk -F= '/^focus-interrupted-id=/{print $2}')
[[ -n "$focus_intention_id" ]]
run_diagnostic --focus-resume-test "$focus_intention_id"

private_markers=(
    "packaged linked resurfacing marker"
    "packaged unrelated resurfacing marker"
    "packaged permanent suppression marker"
    "dev.openloop.packaged-context-marker"
    "Packaged Context Marker"
    "packaged on-device voice transcript marker"
    "packaged focus recovery marker"
    "packaged completed recovery marker"
    "packaged exact next recovery marker"
    "packaged blocker recovery marker"
    "packaged-reference-recovery-marker"
)
for marker in "${private_markers[@]}"; do
    if LC_ALL=C /usr/bin/grep -R -a -q "$marker" "$data_dir"; then
        print -u2 "Private marker found as plaintext in vault files: $marker"
        exit 1
    fi
done

run_diagnostic --benchmark-save 100
run_diagnostic --benchmark-capture 100
run_diagnostic --hotkey-test

[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
    "$app_bundle/Contents/Info.plist")" == "0.3.0" ]]
[[ -z "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' \
    "$app_bundle/Contents/Info.plist" 2>/dev/null || true)" ]]
/usr/libexec/PlistBuddy -c 'Print :NSMicrophoneUsageDescription' \
    "$app_bundle/Contents/Info.plist" | /usr/bin/grep -q 'does not retain audio'
/usr/libexec/PlistBuddy -c 'Print :NSSpeechRecognitionUsageDescription' \
    "$app_bundle/Contents/Info.plist" | /usr/bin/grep -q 'on-device'
/usr/bin/otool -L "$binary" | /usr/bin/grep -q 'AVFoundation.framework'
/usr/bin/otool -L "$binary" | /usr/bin/grep -q 'Speech.framework'

/usr/bin/hdiutil attach "$dmg_path" -nobrowse -readonly -mountpoint "$mount_dir" -quiet
mounted=true
[[ -d "$mount_dir/OpenLoop ADHD.app" ]]
[[ -L "$mount_dir/Applications" ]]
/usr/bin/hdiutil detach "$mount_dir" -quiet
mounted=false

print "Increment 3 verification passed."
