#!/bin/zsh
set -euo pipefail

openloop_root="${0:A:h:h:h}"
data_root="$openloop_root/.eval-data"
profile="metadata"
kaggle_dataset=""

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

clone_official \
    "https://github.com/AI4Bharat/IndicVoices.git" \
    "$data_root/sources/indicvoices"
clone_official \
    "https://github.com/microsoft/DNS-Challenge.git" \
    "$data_root/sources/dns-challenge"
clone_official \
    "https://github.com/joonson/voxconverse.git" \
    "$data_root/sources/voxconverse"

if [[ -n "$kaggle_dataset" ]]; then
    if ! command -v kaggle >/dev/null 2>&1; then
        print -u2 -- "Kaggle CLI is not installed. Install it and configure ~/.kaggle/kaggle.json after accepting the dataset terms."
        exit 1
    fi
    safe_name="${kaggle_dataset//\//__}"
    destination="$data_root/kaggle/$safe_name"
    /bin/mkdir -p "$destination"
    kaggle datasets download --dataset "$kaggle_dataset" --path "$destination" --unzip
fi

print -r -- "voice-eval-metadata=$data_root/sources"
print -r -- "corpus-manifest=$openloop_root/Evaluation/voice/corpora.json"
