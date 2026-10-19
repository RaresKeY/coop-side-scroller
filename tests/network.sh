#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
exec "$HOME/workspace/tooling/godot-podman/bin/godot-podman" run --project "$ROOT" --network host --timeout 25s --grace 2s -- bash -c '
set -u
godot --headless --path /workspace -- --test-host > /tmp/host.log 2>&1 & host_pid=$!
sleep 1
godot --headless --path /workspace -- --test-client > /tmp/client.log 2>&1 & client_pid=$!
wait "$host_pid"; host_result=$?
wait "$client_pid"; client_result=$?
cat /tmp/host.log /tmp/client.log
test "$host_result" = 0 && test "$client_result" = 0 && ! grep -E "SCRIPT ERROR|^ERROR:" /tmp/host.log /tmp/client.log
'
