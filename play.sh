#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec "$HOME/workspace/tooling/godot-podman/bin/godot-podman" run --project "$ROOT" --network host -- godot --path /workspace "$@"
