#!/bin/zsh
set -euo pipefail

openloop_root="${0:A:h:h}"
artifacts_dir="$openloop_root/.artifacts"
app_bundle="$artifacts_dir/app/OpenLoop ADHD.app"
contents_dir="$app_bundle/Contents"
sign_identity="${OPENLOOP_SIGN_IDENTITY:--}"

swift build --package-path "$openloop_root" -c release --arch arm64
if [[ -e "$app_bundle" ]]; then
    /bin/rm -rf "$app_bundle"
fi
/bin/mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources"
/usr/bin/ditto "$openloop_root/Resources/Info.plist" "$contents_dir/Info.plist"
if [[ "$sign_identity" == "-" ]]; then
    /usr/libexec/PlistBuddy \
        -c "Add :OpenLoopLocalDevelopmentBuild bool true" \
        "$contents_dir/Info.plist"
fi
/usr/bin/ditto \
    "$openloop_root/.build/arm64-apple-macosx/release/OpenLoopADHD" \
    "$contents_dir/MacOS/OpenLoopADHD"
if [[ "$sign_identity" == "-" ]]; then
    /usr/bin/codesign --force --deep --sign - "$app_bundle"
else
    /usr/bin/codesign \
        --force \
        --deep \
        --options runtime \
        --timestamp \
        --sign "$sign_identity" \
        "$app_bundle"
fi
/usr/bin/codesign --verify --deep --strict "$app_bundle"
print -r -- "$app_bundle"
