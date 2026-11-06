#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$ROOT/build/deterministic"
STATUS_FILE="$(mktemp "$ROOT/build/deterministic/.browser-status-XXXXXX")"
trap 'python3 -c '\''from pathlib import Path; import sys; Path(sys.argv[1]).unlink(missing_ok=True)'\'' "$STATUS_FILE"' EXIT
set +e
timeout --signal=TERM --kill-after=5s 180s gamescope --backend headless \
 -W 960 -H 540 -w 960 -h 540 --xwayland-count 1 -- \
 bash -c 'python3 "$1/tests/deterministic_browser.py" "${@:3}"; result=$?; printf "%s\n" "$result" > "$2"; exit "$result"' \
 deterministic-probe "$ROOT" "$STATUS_FILE" "$@"
RUNNER_STATUS=$?
set -e
CHILD_STATUS="$(cat "$STATUS_FILE")"
if [[ "$CHILD_STATUS" != 0 ]]; then
 echo "Deterministic browser probe failed (child=${CHILD_STATUS:-missing}, gamescope=$RUNNER_STATUS)" >&2
 exit 1
fi
if [[ "$RUNNER_STATUS" != 0 && "$RUNNER_STATUS" != 139 ]]; then
 echo "Gamescope failed: $RUNNER_STATUS" >&2
 exit "$RUNNER_STATUS"
fi
if [[ "$RUNNER_STATUS" == 139 ]]; then
 echo 'Gamescope crashed during shutdown after the probe returned success; child status verified.' >&2
fi
