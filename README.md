# Ember Bridge — portable co-op core and Godot prototype

[Play in browser](https://rareskey.github.io/coop-side-scroller/) · [Public source](https://github.com/RaresKeY/coop-side-scroller)

An engine-independent C++17 co-op core with a versioned C ABI, native and WebAssembly builds, and a working Godot 4.7 reference game. Simulation, movement/combat, inputs, automatic animation states/events, host authority and binary snapshot synchronization live in `core/`. Rendering, clocks, captured controls, assets and transport stay in adapters. No STL or C++ exceptions cross the ABI.

[API and wire contract](specs/c-abi.md) · [Core architecture](specs/portable-core.md) · [Builds/targets](specs/build-targets.md) · [Unity/Unreal/custom-engine guidance](design/engine-integration.md)

This is independent of another game's source. One CraftPix prototype saber fighter animates automatically while moving, jumping and attacking. The level is a plain single-screen floor of square CraftPix prototype tiles and one training dummy. No animation selection controls or Mangler's Fate code/assets are included.

## Play

Prepare explicitly on the owning workstation (installed GCC/Clang/wasm-ld required):

```sh
python3 tools/build_core.py
./play.sh --headless --editor --import --quit
./play.sh
```

The launcher checks core freshness without rebuilding. Other machines can use the standalone CMake example or build the core for their target; the current native Godot shim is tested on Linux x86_64. Godot 4.7 Web uses the same core compiled as a separate import-free Wasm module, awaited before engine startup. There is no fallback GDScript simulation.

 Start with the Play solo / Host game / Join game menu. During play, only Menu, status and simple controls remain onscreen. Setup and browser connection codes stay in menus. Move with A/D, jump with W, attack with F. Arrows/Up/L are the alternate scheme. This build is silent.

## Live network lab

Run `./play-labs.sh`, then **Network → Local pair**. `./play-labs.sh pair` enters the pair directly. The compact chooser also offers **Host only** and **Join only** for two machines (enter the reachable host address and UDP port).

The local pair launches **two independent Godot processes** in separate windows. Host owns simulation; guest sends actions through real ENet UDP and receives snapshots. The lab controller owns their lifetime and routes keyboard input; it never copies world state between them.

- P1 host: **A/D** move, **W** jump, **F** attack.
- P2 guest: **Left/Right** move, **Up** jump, **L** attack.
- Focus either game window or the small lab panel; both schemes operate their respective processes simultaneously. Releasing focus from all lab windows neutralizes input.
- Choose **0 / 50 / 100 / 200 ms delay each way** in the panel. Delay is applied to outgoing gameplay RPCs in both processes, including ping replies; RTT includes application scheduling and network time. This is application-level delay injection, not OS packet shaping.
- Each game displays measured RTT, injected delay, actor count, packet counters, snapshot sequence/age and gaps. The controller shows each process PID and live telemetry. RTT is round-trip; guest snapshot age is time since its last received snapshot. Sequence gaps are observed missing snapshots, not a general network packet-loss percentage.
- **Back to labs** or closing either game stops the owned pair. Closing the lab controller also stops its workers. No provider account, signaling service or relay is needed for loopback/LAN ENet testing.

The lab is a native development tool. It does not prove browser WebRTC or internet NAT traversal. On two machines the remote route requires UDP reachability (LAN, an existing VPN, or suitable forwarding); relay remains deferred.

Raw CraftPix art is excluded from public source. After core preparation/import, the source checkout renders a small original fallback character if licensed art is absent. To restore the licensed selection from your own library:

```sh
python3 tools/import_craftpix.py --library ../CraftPix
./play.sh --headless --editor --import --quit
```

The import script needs Python 3 and Pillow; it copies seven character sheets, three button images, one 32×32 tile and the corresponding notices, records hashes and enables mipmaps. This is game integration, not an artwork exporter or AI training/evaluation dataset. See `assets/craftpix-manifest.json` and `THIRD_PARTY_NOTICES.md`.

## Browser P2P

The web build uses WebRTC data channels. Host runs simulation; guest sends bounded movement/jump/attack input. Host sends snapshots at 20 Hz. Browser Host creates an offer; Join opens the code panel. Send codes through your existing private chat:

1. Host: Create offer, wait for your code, Copy my code and send it to guest.
2. Guest: copy the received offer, Paste and accept, wait for the answer code, Copy my code and send it back.
3. Host: copy the answer, Paste and accept. Wait for connection status. If clipboard permission is denied, paste into the lower field and use Accept pasted code.

Browser P2P is experimental and not verified end to end: this workstation’s Chromium returned zero ICE candidates in both Godot and a separate plain WebRTC probe. The game reports this explicitly.

Keep both tabs active during setup. This manually replaces the signaling service, which is deferred. A public Google STUN endpoint is configured for address discovery; there is **no TURN relay**. Some NAT/firewall combinations will fail. Refresh or Solo resets a session. Codes contain temporary connection details; do not post them publicly.

Native Host/Join uses ENet on UDP 27840 for local/LAN development. Use the lab for simultaneous independent instances; the controller owns both workers inside one managed runtime, avoiding project-lock conflicts. Native ENet testing does not establish browser WebRTC or internet connectivity.

## Static site

`./tools/build_web.sh` creates the current candidate in ignored `build/web/`. Serve it locally using `python3 -m http.server 8080 --directory build/web`. Export uses Compatibility rendering and disables threads, allowing ordinary HTTPS GitHub Pages hosting without custom isolation headers. The source branch excludes licensed raw art; the Pages branch contains only the exported playable game and notices. No account credentials belong in either branch. Explicit deployment uses `python3 tools/deploy_pages.py`; it only pushes the reviewed current web candidate to this project’s `gh-pages` branch.

GitHub Pages is a static host, not a signaling or relay server. Firebase, Supabase and VPS options are assessed in [design/network-options.md](design/network-options.md). Deferred work is in [BACKLOG.md](BACKLOG.md).

## Standalone and tests

```sh
cmake -S . -B build/cmake -DCMAKE_BUILD_TYPE=Debug
cmake --build build/cmake --parallel 2
ctest --test-dir build/cmake --output-on-failure
./build/cmake/ember_standalone
./tests/core.sh
./tests/network.sh
./tests/lab.sh
./tools/build_web.sh
./tests/web.sh
```

The core suite checks the C ABI, bounded buffers/queues, authority, malformed/stale packets, sanitizer coverage and a 600-tick native/Wasm byte trace. The lab verifies independent processes and replicated combat under delay; the browser smoke test drives real Godot input into Wasm. Test commands/tool requirements are in `specs/build-targets.md`.

**Tested:** Linux native C/C++, Godot Linux reference, freestanding wasm32 and Godot Web/Chromium. **Documented possibilities only:** Unity, Unreal, other operating systems and custom engine adapters. The byte-identical test trace is not a general deterministic-lockstep guarantee. Prediction/interpolation, general engine collision integration, automatic signaling and relay deployment are deferred.
