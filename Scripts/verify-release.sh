#!/bin/zsh
set -euo pipefail

app_bundle="${1:?usage: verify-release.sh /path/to/OpenLoop ADHD.app}"
info_plist="$app_bundle/Contents/Info.plist"
allow_adhoc_release="${OPENLOOP_ALLOW_ADHOC_RELEASE:-0}"
actual_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist")"

[[ -d "$app_bundle" ]]
[[ -x "$app_bundle/Contents/MacOS/OpenLoopADHD" ]]
expected_version="${OPENLOOP_EXPECTED_VERSION#v}"
if [[ -n "$expected_version" && "$actual_version" != "$expected_version" ]]; then
    print -u2 -- "Expected version $expected_version, found $actual_version."
    exit 1
fi
if /usr/libexec/PlistBuddy -c 'Print :OpenLoopLocalDevelopmentBuild' "$info_plist" >/dev/null 2>&1; then
    print -u2 -- "Release bundle contains the local-development key flag."
    exit 1
fi
/usr/bin/codesign --verify --deep --strict "$app_bundle"
authority="$(/usr/bin/codesign -dvv "$app_bundle" 2>&1 | /usr/bin/sed -n 's/^Authority=//p' | /usr/bin/head -1)"
if [[ -z "$authority" && "$allow_adhoc_release" != "1" ]]; then
    print -u2 -- "Release bundle is ad-hoc signed."
    exit 1
fi

signature_kind="${authority:-ad-hoc community build}"
print -r -- "release-verification=passed version=$actual_version signature=$signature_kind"
