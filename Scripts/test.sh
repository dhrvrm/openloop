#!/bin/zsh
set -euo pipefail

openloop_root="${0:A:h:h}"
developer_dir="$(xcode-select -p)"

if [[ "$developer_dir" == "/Library/Developer/CommandLineTools" ]]; then
    test_frameworks="$developer_dir/Library/Developer/Frameworks"
    DYLD_FRAMEWORK_PATH="$test_frameworks" swift test \
        --package-path "$openloop_root" \
        --enable-swift-testing \
        --disable-xctest \
        -Xswiftc -F \
        -Xswiftc "$test_frameworks" \
        -Xswiftc -Xfrontend \
        -Xswiftc -disable-cross-import-overlays \
        -Xlinker -F \
        -Xlinker "$test_frameworks" \
        -Xlinker -rpath \
        -Xlinker "$test_frameworks" \
        "$@"
else
    swift test --package-path "$openloop_root" "$@"
fi
