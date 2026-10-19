#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
exec gamescope --backend headless -W 960 -H 540 -w 960 -h 540 --xwayland-count 1 -- python3 "$ROOT/tests/browser_check.py" "$@"
