# Ember Bridge — portable co-op prototype

[Play in browser](https://rareskey.github.io/coop-side-scroller/) · [Public source](https://github.com/RaresKeY/coop-side-scroller) · [Architecture](specs/architecture.md) · [Specs index](specs/_readme.md)

A two-player side-scroller with an engine-independent C++17 simulation and a Godot 4.7 reference game. The core owns movement/combat, inputs, automatic animation states, host authority and snapshots behind a versioned C ABI. Adapters own rendering, controls, clocks, assets and network transports. Native and browser builds use the same core sources.

The scene contains one animated saber fighter per player, a square-tile floor and a training dummy. Character animation follows gameplay automatically. This is a small integration prototype, with a simple floor model and no audio, inventory or authored RPG map. It contains no other game's source or assets.

## Browser play

1. Open the game and enter your privately shared **playtest access code** in Menu. Click the field to type or paste into the browser-native dialog.
2. Open **Private rooms**. One player clicks **Create room**; the other clicks **Join** on that room.
3. Keep both pages open until connected. Move with **A/D**, jump with **W**, attack with **F**.

The game exchanges connection details and obtains temporary TURN credentials automatically. **Direct + relay fallback** is the default; **Relay only (test)** forces TURN and shows diagnostics. The shared key authorizes room access and relay usage, not Cloudflare account administration. It stays in page memory and expires under the service's invitation policy.

GitHub Pages hosts the static game. Cloudflare handles protected room setup and TURN credential issuance. Gameplay is host-authoritative WebRTC, direct where possible or relayed when selected. Rooms have two seats, expire when abandoned and are deleted once both peers connect. There are no public lobbies or individual accounts.

Automatic lobby connection, movement and combat have passed between this workstation and a Runpod Chrome guest through TURN. Firefox, direct-path and restrictive-network acceptance remain unverified. Host migration, automatic reconnect and credential refresh are not implemented; start a fresh session before the one-hour TURN credentials expire. See [verification](specs/verification.md) for exact evidence and limits. **Manual connection (advanced)** retains the diagnostic offer/reply flow.

## Native game and network lab

On the owning workstation, explicitly prepare the core and Godot imports:

```sh
python3 tools/build_core.py
./play.sh --headless --editor --import --quit
./play.sh
```

The launchers check freshness without rebuilding. `play.sh` uses the shared Godot Podman runtime; other machines can use the standalone CMake build below. Native Host/Join uses ENet UDP, default port 27840. LAN/VPN or other UDP reachability is required; native ENet does not use browser TURN.

```sh
./play-labs.sh       # chooser: Local pair / Host only / Join only
./play-labs.sh pair  # two independent game processes
```

The local pair gives the host **A/D/W/F** and guest **Left/Right/Up/L** on one keyboard. Focus either worker or the lab panel to control both; losing all lab focus neutralizes input. The controller routes controls, never world state. Each worker has its own core and exchanges real gameplay messages through ENet.

Choose **0 / 50 / 100 / 200 ms delay each way**. The HUD shows measured RTT, snapshots, actor count and RPC counters. This is application-level delay, not OS packet shaping. Closing the controller or either worker stops the owned pair. See [network lab](specs/network-lab.md).

## Assets and builds

Raw CraftPix source art is private. A public checkout uses original fallback art when the licensed selection is absent. Owners can import their own library:

```sh
python3 tools/import_craftpix.py --library ../CraftPix
./play.sh --headless --editor --import --quit
```

The importer requires Python/Pillow. It preserves vendor source, records hashes and enables mipmaps. Runtime frame regions, anchors and shader sampling provide the current character presentation without enlarged source copies. See [assets and hosting](specs/assets-hosting.md), [character presentation](specs/character-presentation.md) and [notices](THIRD_PARTY_NOTICES.md).

For the standalone C/C++ library and example:

```sh
cmake -S . -B build/cmake -DCMAKE_BUILD_TYPE=Debug
cmake --build build/cmake --parallel 2
ctest --test-dir build/cmake --output-on-failure
./build/cmake/ember_standalone
```

For the static browser candidate:

```sh
./tools/build_web.sh
python3 -m http.server 27841 --bind 127.0.0.1 --directory build/web
```

The single-thread Compatibility export runs on ordinary HTTPS Pages hosting. Source stays on `main`; compiled playable resources and notices go to `gh-pages`. Publication uses the explicit project deployment tool and secret audit, documented in [assets and hosting](specs/assets-hosting.md).

## Integration and validation

[Build commands and targets](specs/build-targets.md) · [C ABI/wire contract](specs/c-abi.md) · [Unity/Unreal/custom-engine guidance](design/engine-integration.md) · [Remaining work](BACKLOG.md)

Tested: Linux C/C++, Godot Linux, freestanding wasm32, and Godot Web in Chromium/Chrome. Other engine and OS adapters are documented possibilities. The native/Wasm byte-identical test trace is bounded evidence, not a deterministic-lockstep guarantee. Game state uses host snapshots; prediction and interpolation are not implemented.
