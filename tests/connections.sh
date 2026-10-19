#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
python3 "$ROOT/tools/build_core.py" --check
exec "$HOME/workspace/tooling/godot-podman/bin/godot-podman" run --project "$ROOT" --timeout 15s --grace 2s -- \
 godot --headless --path /workspace --script res://tests/connection_codes.gd
