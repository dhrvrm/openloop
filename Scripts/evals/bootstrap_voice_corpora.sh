#!/bin/zsh
set -euo pipefail

openloop_root="${0:A:h:h:h}"
data_root="$openloop_root/.eval-data"
profile="metadata"
kaggle_dataset=""
catalog_only=0
allow_status=""

while (( $# > 0 )); do
    case "$1" in
        --profile)
            profile="${2:?--profile requires metadata}"
            shift 2
            ;;
        --kaggle)
            kaggle_dataset="${2:?--kaggle requires owner/dataset}"
            shift 2
            ;;
        --catalog-only)
            catalog_only=1
            shift
            ;;
        --allow-status)
            allow_status="${2:?--allow-status requires a catalog status}"
            shift 2
            ;;
        *)
            print -u2 -- "Unknown argument: $1"
            exit 2
            ;;
    esac
done

if [[ "$profile" != "metadata" ]]; then
    print -u2 -- "Only the safe metadata profile is automatic. Follow Evaluation/voice/README.md for licensed audio downloads."
    exit 2
fi

/bin/mkdir -p "$data_root/sources"

clone_official() {
    local url="$1"
    local destination="$2"
    if [[ -d "$destination/.git" ]]; then
        print -r -- "present: $destination"
        return
    fi
    /usr/bin/git clone --depth 1 "$url" "$destination"
}

if (( ! catalog_only )) && [[ -z "$kaggle_dataset" ]]; then
    clone_official \
        "https://github.com/AI4Bharat/IndicVoices.git" \
        "$data_root/sources/indicvoices"
    clone_official \
        "https://github.com/microsoft/DNS-Challenge.git" \
        "$data_root/sources/dns-challenge"
    clone_official \
        "https://github.com/joonson/voxconverse.git" \
        "$data_root/sources/voxconverse"
fi

if [[ -n "$kaggle_dataset" ]]; then
    kaggle_cli="${OPENLOOP_KAGGLE_CLI:-$(command -v kaggle || true)}"
    if [[ -z "$kaggle_cli" || ! -x "$kaggle_cli" ]]; then
        print -u2 -- "Kaggle CLI is not installed. Set OPENLOOP_KAGGLE_CLI to the authenticated executable."
        exit 1
    fi
    catalog="$openloop_root/Evaluation/voice/corpora.json"
    usage_status="$(python3 - "$catalog" "$kaggle_dataset" <<'PY'
import json
import sys

catalog, slug = sys.argv[1:]
document = json.load(open(catalog, encoding="utf-8"))
matches = [
    corpus for corpus in document["corpora"]
    if corpus.get("source_kind") == "kaggle" and corpus.get("exact_slug") == slug
]
print(matches[0]["usage_status"] if len(matches) == 1 else "")
PY
)"
    if [[ -z "$usage_status" ]]; then
        print -u2 -- "Kaggle dataset is absent or duplicated in Evaluation/voice/corpora.json: $kaggle_dataset"
        exit 1
    fi
    safe_name="${kaggle_dataset//\//__}"
    if (( catalog_only )); then
        destination="$data_root/catalog/kaggle/$safe_name"
        /bin/mkdir -p "$destination"
        "$kaggle_cli" datasets metadata "$kaggle_dataset" --path "$destination"
        "$kaggle_cli" datasets files "$kaggle_dataset" --page-size 200 \
            > "$destination/files.txt"
        print -r -- "kaggle-catalog=$destination"
    else
        if [[ "$allow_status" != "evaluation-approved" || "$usage_status" != "$allow_status" ]]; then
            print -u2 -- "Audio download denied: catalog status is '$usage_status'. Only an explicit --allow-status evaluation-approved may download audio."
            exit 2
        fi
        destination="$data_root/kaggle/$safe_name"
        /bin/mkdir -p "$destination"
        "$kaggle_cli" datasets download --dataset "$kaggle_dataset" \
            --path "$destination" --unzip
    fi
fi

print -r -- "voice-eval-metadata=$data_root/sources"
print -r -- "corpus-manifest=$openloop_root/Evaluation/voice/corpora.json"
