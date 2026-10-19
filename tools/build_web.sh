#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$ROOT/build/web"
touch "$ROOT/build/.gdignore"
"$ROOT/play.sh" --headless --editor --import --quit
"$ROOT/play.sh" --headless --export-release Web build/web/index.html
touch "$ROOT/build/web/.nojekyll"
cp "$ROOT/THIRD_PARTY_NOTICES.md" "$ROOT/build/web/THIRD_PARTY_NOTICES.txt"
