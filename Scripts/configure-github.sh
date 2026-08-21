#!/bin/zsh
set -euo pipefail

repository="${OPENLOOP_GITHUB_REPOSITORY:-dhrvrm/openloop}"
homepage="${OPENLOOP_HOMEPAGE:-https://dhrvrm.github.io/openloop/}"
description="A private working memory for macOS — local voice capture, multilingual transcription, semantic context, and intentional recall."

permission="$(gh repo view "$repository" --json viewerPermission --jq .viewerPermission)"
if [[ "$permission" != "ADMIN" && "$permission" != "MAINTAIN" ]]; then
    print -u2 -- "GitHub CLI needs ADMIN or MAINTAIN access to $repository; current permission is $permission."
    exit 1
fi

gh repo edit "$repository" \
    --description "$description" \
    --homepage "$homepage" \
    --enable-issues \
    --enable-projects=false \
    --enable-wiki=false \
    --add-topic macos \
    --add-topic swift \
    --add-topic speech-to-text \
    --add-topic whisper \
    --add-topic local-first \
    --add-topic semantic-memory \
    --add-topic voice-assistant \
    --add-topic open-source

if ! gh api "repos/$repository/pages" >/dev/null 2>&1; then
    gh api --method POST "repos/$repository/pages" -f build_type=workflow >/dev/null
fi

print -r -- "github-settings=configured repository=$repository homepage=$homepage"
