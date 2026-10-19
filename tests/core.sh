#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
python3 "$ROOT/tools/build_core.py"
g++ -std=c++17 -g -fno-exceptions -fno-rtti -fsanitize=address,undefined -fno-omit-frame-pointer -I "$ROOT/core/include" "$ROOT/core/src/ember_core.cpp" "$ROOT/core/tests/core_tests.cpp" -o "$ROOT/build/native/core-tests"
"$ROOT/build/native/core-tests"
cc -std=c11 -Wall -Wextra -Werror -I "$ROOT/core/include" "$ROOT/core/tests/c_consumer.c" -L "$ROOT/build/native" -lember_core '-Wl,-rpath,$ORIGIN' -o "$ROOT/build/native/c-consumer"
"$ROOT/build/native/c-consumer"
"$ROOT/build/native/standalone"
python3 "$ROOT/tests/core_trace.py"
deno run --no-config --allow-read="$ROOT/build" "$ROOT/tests/core_wasm.mjs"

deno test --no-config --allow-read="$ROOT/adapters/web/ember_core_bridge.js,$ROOT/build/wasm/ember_core.wasm" "$ROOT/tests/web_handle_safety.test.js"
