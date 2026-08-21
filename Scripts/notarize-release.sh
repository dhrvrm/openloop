#!/bin/zsh
set -euo pipefail

dmg_path="${1:?usage: notarize-release.sh /path/to/OpenLoop.dmg}"
key_path="${APPLE_NOTARY_KEY_PATH:?APPLE_NOTARY_KEY_PATH is required}"
key_id="${APPLE_NOTARY_KEY_ID:?APPLE_NOTARY_KEY_ID is required}"
issuer_id="${APPLE_NOTARY_ISSUER_ID:?APPLE_NOTARY_ISSUER_ID is required}"

[[ -f "$dmg_path" ]]
[[ -f "$key_path" ]]

/usr/bin/xcrun notarytool submit "$dmg_path" \
    --key "$key_path" \
    --key-id "$key_id" \
    --issuer "$issuer_id" \
    --wait
/usr/bin/xcrun stapler staple "$dmg_path"
/usr/bin/xcrun stapler validate "$dmg_path"
/usr/bin/shasum -a 256 "$dmg_path" > "$dmg_path.sha256"

print -r -- "notarization=passed artifact=$dmg_path"
