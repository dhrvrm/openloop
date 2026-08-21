#!/bin/zsh
set -euo pipefail

openloop_root="${0:A:h:h}"
artifacts_dir="$openloop_root/.artifacts"
stage_dir="$artifacts_dir/dmg-stage"
app_bundle="$artifacts_dir/app/OpenLoop ADHD.app"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$openloop_root/Resources/Info.plist")"
architecture="${OPENLOOP_ARCHITECTURE:-arm64}"
dmg_path="$artifacts_dir/OpenLoop-$version-$architecture.dmg"

"$openloop_root/Scripts/build-app.sh"
if [[ -e "$stage_dir" ]]; then
    /bin/rm -rf "$stage_dir"
fi
/bin/mkdir -p "$stage_dir"
/usr/bin/ditto "$app_bundle" "$stage_dir/OpenLoop ADHD.app"
/bin/ln -s /Applications "$stage_dir/Applications"
/usr/bin/hdiutil create \
    -volname "OpenLoop ADHD" \
    -srcfolder "$stage_dir" \
    -ov \
    -format UDZO \
    "$dmg_path"
/usr/bin/shasum -a 256 "$dmg_path" > "$dmg_path.sha256"
print -r -- "$dmg_path"
