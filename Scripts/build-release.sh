#!/bin/zsh
set -euo pipefail

openloop_root="${0:A:h:h}"
: "${OPENLOOP_SIGN_IDENTITY:?Set OPENLOOP_SIGN_IDENTITY to a stable Apple signing identity}"

if [[ "$OPENLOOP_SIGN_IDENTITY" == "-" ]]; then
    print -u2 -- "Release builds refuse ad-hoc signing."
    exit 1
fi

"$openloop_root/Scripts/build-dmg.sh"
"$openloop_root/Scripts/verify-release.sh" \
    "$openloop_root/.artifacts/app/OpenLoop ADHD.app"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$openloop_root/Resources/Info.plist")"
print -r -- "$openloop_root/.artifacts/OpenLoop-$version-arm64.dmg"
