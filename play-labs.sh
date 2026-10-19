#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
case "${1:-menu}" in
 menu) if [[ $# -gt 0 ]]; then shift; fi; extra=() ;;
 pair) shift; extra=(--lab-pair) ;;
 *) echo 'Usage: ./play-labs.sh [menu|pair]' >&2; exit 2 ;;
esac
python3 "$ROOT/tools/build_core.py" --check
exec "$HOME/workspace/tooling/godot-podman/bin/godot-podman" run --project "$ROOT" --network host -- godot --path /workspace --audio-driver Dummy res://labs/main.tscn -- "${extra[@]}" "$@"
