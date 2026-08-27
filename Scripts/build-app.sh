#!/bin/zsh
set -euo pipefail

openloop_root="${0:A:h:h}"
artifacts_dir="$openloop_root/.artifacts"
app_bundle="$artifacts_dir/app/OpenLoop ADHD.app"
contents_dir="$app_bundle/Contents"
sign_identity="${OPENLOOP_SIGN_IDENTITY:--}"
allow_adhoc_release="${OPENLOOP_ALLOW_ADHOC_RELEASE:-0}"
prebuilt_metallib="${OPENLOOP_PREBUILT_METALLIB:-}"
whisper_helper="${OPENLOOP_WHISPER_HELPER:-}"

if [[ -z "$whisper_helper" ]]; then
    whisper_helper="$("$openloop_root/scripts/build-whisper-helper.sh")"
fi
if [[ ! -x "$whisper_helper" ]]; then
    print -u2 -- "Missing executable whisper.cpp helper: $whisper_helper"
    exit 1
fi

swift build --package-path "$openloop_root" -c release --arch arm64
speech_swift_metallib="$openloop_root/.build/checkouts/speech-swift/scripts/build_mlx_metallib.sh"
if [[ ! -x "$speech_swift_metallib" ]]; then
    print -u2 -- "Missing speech-swift Metal build script: $speech_swift_metallib"
    exit 1
fi
if ! BUILD_DIR="$openloop_root/.build" "$speech_swift_metallib" release; then
    if [[ -f "$prebuilt_metallib" ]]; then
        /bin/mkdir -p "$openloop_root/.build/release"
        /usr/bin/ditto "$prebuilt_metallib" "$openloop_root/.build/release/mlx.metallib"
        print -r -- "Reused explicitly supplied MLX Metal library: $prebuilt_metallib"
    else
        print -u2 -- "Metal compilation failed and OPENLOOP_PREBUILT_METALLIB was not provided."
        exit 1
    fi
fi
if [[ -e "$app_bundle" ]]; then
    /bin/rm -rf "$app_bundle"
fi
/bin/mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources"
/usr/bin/ditto "$openloop_root/Resources/Info.plist" "$contents_dir/Info.plist"
if [[ "$sign_identity" == "-" && "$allow_adhoc_release" != "1" ]]; then
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
/bin/mkdir -p "$contents_dir/Resources/Transcription"
/usr/bin/ditto "$whisper_helper" "$contents_dir/Resources/Transcription/whisper-cli"
/bin/chmod 755 "$contents_dir/Resources/Transcription/whisper-cli"
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
