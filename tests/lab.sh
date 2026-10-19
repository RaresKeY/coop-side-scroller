#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$ROOT/build"
touch "$ROOT/build/.gdignore"
exec gamescope --backend headless -W 1920 -H 1080 -w 1920 -h 1080 --xwayland-count 1 -- \
 "$HOME/workspace/tooling/godot-podman/bin/godot-podman" run --project "$ROOT" --network host --timeout 35s --grace 2s -- \
 godot --path /workspace --audio-driver Dummy res://labs/main.tscn -- --lab-test
