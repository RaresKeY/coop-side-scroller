#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
python3 "$ROOT/tools/build_core.py" --check
gamescope --backend headless -W 960 -H 540 -w 960 -h 540 --xwayland-count 1 -- \
 "$HOME/workspace/tooling/godot-podman/bin/godot-podman" run --project "$ROOT" --timeout 90s --grace 2s -- bash -eu -c '
 godot --headless --path /workspace --script res://tests/character_view.gd
 godot --path /workspace --audio-driver Dummy --script res://tests/pixel_sampling.gd
 godot --path /workspace --audio-driver Dummy --script res://tests/animation_capture.gd -- --output=res://build/animation-after
 '
python3 "$ROOT/tools/animation_report.py" "$ROOT/build/animation-after"
