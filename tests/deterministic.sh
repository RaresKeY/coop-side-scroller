#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
python3 "$ROOT/tools/build_core.py"
g++ -std=c++17 -g -Wall -Wextra -Werror -fno-exceptions -fno-rtti \
 -fsanitize=address,undefined -fno-omit-frame-pointer -I "$ROOT/core/include" \
 "$ROOT/core/src/ember_deterministic.cpp" "$ROOT/core/tests/deterministic_tests.cpp" \
 -o "$ROOT/build/native/deterministic-tests"
"$ROOT/build/native/deterministic-tests"
python3 "$ROOT/tools/deterministic_lab.py"
python3 - "$ROOT" <<'PY'
from pathlib import Path
import subprocess,sys,tempfile
root=Path(sys.argv[1])
with tempfile.TemporaryDirectory(prefix='.deterministic-clang-',dir=root/'build') as stage:
 output=Path(stage)/'core.so'
 subprocess.run(['clang++','-std=c++17','-O2','-shared','-fPIC','-fno-exceptions',
  '-fno-rtti','-Wall','-Wextra','-Werror','-I',str(root/'core/include'),
  str(root/'core/src/ember_deterministic.cpp'),'-o',str(output)],check=True)
 subprocess.run(['python3',str(root/'tools/deterministic_lab.py'),
  '--library',str(output),'--trace-only'],check=True)
PY
deno run --no-config --allow-read="$ROOT/build/wasm/ember_core.wasm,$ROOT/build/deterministic/native-traces.json" \
 "$ROOT/tests/deterministic_wasm.mjs"
deno test --no-config --allow-read="$ROOT/build/wasm/ember_core.wasm,$ROOT/tests/deterministic_browser.html,$ROOT/adapters/web/deterministic_peer.mjs" \
 "$ROOT/tests/deterministic_probe.test.mjs"
python3 -m unittest discover -s "$ROOT/tests" -p 'test_network_budget.py'
python3 -m unittest discover -s "$ROOT/tests" -p 'test_deterministic_browser.py'
python3 -m unittest discover -s "$ROOT/tests" -p 'test_browser_cdp.py'
