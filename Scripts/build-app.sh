#!/bin/zsh
set -euo pipefail

openloop_root="${0:A:h:h}"
artifacts_dir="$openloop_root/.artifacts"
app_bundle="$artifacts_dir/app/OpenLoop ADHD.app"
contents_dir="$app_bundle/Contents"

swift build --package-path "$openloop_root" -c release --arch arm64
if [[ -e "$app_bundle" ]]; then
    /bin/rm -rf "$app_bundle"
fi
/bin/mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources"
/usr/bin/ditto "$openloop_root/Resources/Info.plist" "$contents_dir/Info.plist"
/usr/bin/ditto \
    "$openloop_root/.build/arm64-apple-macosx/release/OpenLoopADHD" \
    "$contents_dir/MacOS/OpenLoopADHD"
/usr/bin/codesign --force --deep --sign - "$app_bundle"
/usr/bin/codesign --verify --deep --strict "$app_bundle"
print -r -- "$app_bundle"
