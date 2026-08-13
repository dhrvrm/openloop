#!/bin/zsh
set -euo pipefail

openloop_root="${0:A:h:h}"
"$openloop_root/Scripts/test.sh"
swift build --package-path "$openloop_root" -c release
