#!/bin/zsh
set -euo pipefail

openloop_root="${0:A:h:h}"
commit="371b5a7"
archive_sha256="89051d8fca516a3ad1f5c2f8f9d2fccb089afbaec338fca3f8731999babc6f81"
tool_root="$openloop_root/.build/openloop-tools/whispercpp-$commit"
output="$openloop_root/.build/openloop-tools/whisper-cli"
cmake_bin="${OPENLOOP_CMAKE:-$(command -v cmake || true)}"

if [[ -x "$output" ]]; then
    print -r -- "$output"
    exit 0
fi
if [[ -z "$cmake_bin" || ! -x "$cmake_bin" ]]; then
    print -u2 -- "CMake is required to build the pinned whisper.cpp helper. Set OPENLOOP_CMAKE to its executable."
    exit 1
fi

archive="$(mktemp -t openloop-whispercpp.XXXXXX).tar.gz"
source_dir="$(mktemp -d -t openloop-whispercpp-source.XXXXXX)"
trap '/bin/rm -f "$archive"; /bin/rm -rf "$source_dir"' EXIT
/usr/bin/curl -fsSL "https://github.com/ggml-org/whisper.cpp/archive/$commit.tar.gz" -o "$archive"
actual_sha256="$(/usr/bin/shasum -a 256 "$archive" | /usr/bin/awk '{print $1}')"
if [[ "$actual_sha256" != "$archive_sha256" ]]; then
    print -u2 -- "Pinned whisper.cpp source checksum mismatch."
    exit 1
fi
/usr/bin/tar -xzf "$archive" -C "$source_dir" --strip-components=1

"$cmake_bin" -S "$source_dir" -B "$tool_root/build" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DWHISPER_BUILD_TESTS=OFF \
    -DWHISPER_BUILD_EXAMPLES=ON \
    -DWHISPER_BUILD_SERVER=OFF \
    -DGGML_NATIVE=OFF \
    -DGGML_METAL=ON \
    -DGGML_BLAS=ON \
    -DGGML_BLAS_VENDOR=Apple >&2
"$cmake_bin" --build "$tool_root/build" --config Release -j 6 --target whisper-cli >&2
/bin/mkdir -p "${output:h}"
/usr/bin/ditto "$tool_root/build/bin/whisper-cli" "$output"
/bin/chmod 755 "$output"
print -r -- "$output"
