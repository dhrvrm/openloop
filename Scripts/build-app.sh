#!/bin/zsh
set -euo pipefail

openloop_root="${0:A:h:h}"
artifacts_dir="$openloop_root/.artifacts"
app_bundle="$artifacts_dir/app/OpenLoop ADHD.app"
contents_dir="$app_bundle/Contents"
sign_identity="${OPENLOOP_SIGN_IDENTITY:--}"

swift build --package-path "$openloop_root" -c release --arch arm64
speech_swift_metallib="$openloop_root/.build/checkouts/speech-swift/scripts/build_mlx_metallib.sh"
if [[ ! -x "$speech_swift_metallib" ]]; then
    print -u2 -- "Missing speech-swift Metal build script: $speech_swift_metallib"
    exit 1
fi
BUILD_DIR="$openloop_root/.build" "$speech_swift_metallib" release
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
mlx_metallib="$openloop_root/.build/release/mlx.metallib"
if [[ ! -f "$mlx_metallib" ]]; then
    mlx_metallib="$openloop_root/.build/arm64-apple-macosx/release/mlx.metallib"
fi
if [[ ! -f "$mlx_metallib" ]]; then
    print -u2 -- "MLX Metal library was not produced; refusing to package a crashing app."
    exit 1
fi
/usr/bin/ditto "$mlx_metallib" "$contents_dir/MacOS/mlx.metallib"
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
