#!/bin/zsh
set -euo pipefail

app_bundle="${1:?usage: verify-release.sh /path/to/OpenLoop ADHD.app}"
info_plist="$app_bundle/Contents/Info.plist"

[[ -d "$app_bundle" ]]
[[ -x "$app_bundle/Contents/MacOS/OpenLoopADHD" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist")" == "1.0.0" ]]
if /usr/libexec/PlistBuddy -c 'Print :OpenLoopLocalDevelopmentBuild' "$info_plist" >/dev/null 2>&1; then
    print -u2 -- "Release bundle contains the local-development key flag."
    exit 1
fi
/usr/bin/codesign --verify --deep --strict "$app_bundle"
authority="$(/usr/bin/codesign -dvv "$app_bundle" 2>&1 | /usr/bin/sed -n 's/^Authority=//p' | /usr/bin/head -1)"
[[ -n "$authority" ]]

print -r -- "release-verification=passed"
