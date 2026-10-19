#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
COMMON_DIR="$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir)"
exec 9>"$COMMON_DIR/web-publication.lock"
flock -w 1200 9
python3 "$ROOT/tools/build_core.py"
mkdir -p "$ROOT/build/web"
touch "$ROOT/build/.gdignore"
"$ROOT/play.sh" --headless --editor --import --quit
"$ROOT/play.sh" --headless --export-release Web build/web/index.html
python3 "$ROOT/tools/prepare_web_core.py"
touch "$ROOT/build/web/.nojekyll"
cp "$ROOT/THIRD_PARTY_NOTICES.md" "$ROOT/build/web/THIRD_PARTY_NOTICES.txt"
