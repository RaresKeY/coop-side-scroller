# Builds and supported targets

## Tested targets

| Target | Evidence / boundary |
| --- | --- |
| Linux x86_64 native shared C ABI | GCC 16.2.1, C11 consumer, sanitizer-backed contract tests, standalone replication example |
| Linux standalone static/shared through CMake | CMake Debug/Release builds and three CTest cases |
| Godot 4.7 Linux native reference | Small C-interface GDExtension, managed runtime, separate-process ENet lab and replicated combat |
| wasm32 standalone C ABI | Clang 23.1.3 / wasm-ld, freestanding, no imports, fixed 1 MiB memory; Deno 2.9.7 boundary/trace test |
| Godot 4.7 Web reference in Chromium | Standalone core Wasm + JS bridge, actual input/rendering, private lobby signaling and forced-relay replicated combat |

Other engines/operating systems are documented possibilities in `design/engine-integration.md`, not implemented/tested adapters. The native Godot shim's pinned 64-bit String/StringName layout and descriptor currently target Linux x86_64 only. Build and package it deliberately for another platform before claiming support. CMake provides the portable core, not those engine adapters. Browser forced-relay co-op is verified in Chromium/Chrome, including workstation↔Runpod private lobbies. Firefox, direct/fallback and restrictive-network acceptance remain unverified; see [verification](verification.md).

## Commands

From the project root:

```sh
python3 tools/build_core.py       # explicit native core, Godot shim, example and Wasm preparation
python3 tools/build_core.py --check  # freshness only, never builds or downloads
./play.sh                        # ordinary Godot game, current prepared core required
./play-labs.sh                   # compact native network chooser
./play-labs.sh pair              # independent host + guest processes
./tests/core.sh                  # build, ASan/UBSan contracts, C consumer, example, native/Wasm trace
./tests/animations.sh            # licensed-art frame audit, playback/anchors and GPU superscale comparison
./tests/connections.sh           # bounded manual-code validation and setup failure regressions
./tests/network.sh               # finite two-process native RPC/combat test
./tests/lab.sh                   # GPU Gamescope lab + 50 ms each-way delay + replicated combat
./tools/build_web.sh             # explicit current static candidate with awaited core Wasm boot
./tests/web.sh                   # offscreen Chromium, real keyboard input into Godot -> Wasm
./tests/web.sh --animation-check  # real keyboard run/jump/attack and authoritative damage in browser
./tests/web.sh --connection-setup # capture actual advanced browser Host setup UI
./tests/web.sh --clipboard-check  # native text/copy dialogs, cleanup and gameplay at four sizes
deno test --no-config server/turn/worker.test.mjs server/turn/lobby.test.mjs
```

`tests/core.sh` requires installed GCC/Clang/wasm-ld/Deno; tests/web.sh additionally needs installed Chromium/Gamescope. No package installation or remote module execution occurs. Deno is run without network permission and with read access restricted to build outputs plus the production bridge source for its real-Wasm handle-lifetime regression. Native graphics use the owning shared Godot Podman wrapper and Gamescope, muted/Dummy audio. Headless checks do not prove hardware rendering.

Live browser tests use the protected deployed service and privately configured playtest key. With a prepared local Web candidate:

```sh
gamescope --backend headless -W 960 -H 540 -w 960 -h 540 --xwayland-count 1 -- python3 tests/browser_relay.py --lobby
# To check the public artifact instead, append:
# --url https://rareskey.github.io/coop-side-scroller/
```

For separate-network testing, `tests/browser_lobby_cross_network.py` uses the public game and an explicitly deployed owned controller. Follow [Runpod testing](../design/runpod-agent-browser.md) for setup, result checks and teardown. The harness never allocates cloud resources. The manual-pairing harness remains a separate diagnostic path. Inspect the latest JSON result as well as process output; Gamescope can mask a child failure exit code.

For just the engine-independent C/C++ library and example:

```sh
cmake -S . -B build/cmake -DCMAKE_BUILD_TYPE=Debug
cmake --build build/cmake --parallel 2
ctest --test-dir build/cmake --output-on-failure
./build/cmake/ember_standalone
```

CMake produces `ember_core` shared and `ember_core_static` static. This does not prepare the Godot native descriptor or Wasm; use the Python builder for the reference adapters. Its explicit build stages outputs, replaces each output atomically and records source/output hashes and compiler identity in ignored `build/core-build.json`. The root play/lab launchers run the nonbuilding freshness check, rejecting missing/stale binaries with the exact preparation command. Core edits, build flags (builder source), pinned header and compiler identity invalidate the receipt. No import/build/export or retained idle runtime is performed merely to discover the project. Source import and Web export are explicit preparations.

## Dependencies and retention

The core has no runtime dependencies or STL/exception use. `vendored/dependencies.json` pins the single MIT Godot C-interface header by upstream revision and SHA-256. Godot is an external runtime. Workstation compiler versions are recorded, not downloaded/pinned compiler distributions. No JavaScript packages, WASI or Emscripten runtime are used. The Wasm module supplies only its own minimal memset/memcpy primitives.

`build/native/` and `build/wasm/` hold one current prepared output set needed by normal play/export, never public source. `build/cmake/` is an alternative disposable verification build. `build/web/` is the current ignored publish candidate; after hosted byte/runtime verification it can be deleted. Source art and manifests are retained separately. The public source includes only code, notices, selected hash metadata and the original fallback art. CraftPix PNG/PSD source stays under ignored `assets/private/`.

The Linux explicit builder holds an exclusive file lock while building/publishing; freshness checks hold a shared lock. It hashes staged outputs and publishes the receipt last by atomic replacement, preventing concurrent builders/checkers from certifying mixed generations. Source/compiler changes during compilation abort publication.
