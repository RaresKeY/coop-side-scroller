# Co-op Side Scroller specs

Portable C++ co-op core with a versioned C ABI, native/Wasm builds, a Godot reference adapter, one CraftPix character, square-tile floor and independent-process testing.

| Spec | Sources | Read when |
| --- | --- | --- |
| [Portable core](portable-core.md) | `core/`, `adapters/` | Changing fixed-tick simulation, authority or state/event boundaries |
| [C ABI](c-abi.md) | `core/include/ember_core.h`, `core/src/ember_core.cpp` | Changing lifetime, status, native layouts, serialization or bridge operations |
| [Builds and targets](build-targets.md) | `CMakeLists.txt`, `tools/build_core.py`, `tests/`, `vendored/` | Building/testing or assessing tested platform support |
| [Prototype](prototype.md) | `src/main.gd`, `project.godot`, `main.tscn` | Changing gameplay, menus, animation or transport |
| [Character presentation](character-presentation.md) | `src/character_view.gd`, `shaders/`, animation captures/tests | Changing sprite size, anchors, atlas slicing, frame timing or sampling |
| [Browser connection](browser-connection.md) | `src/connection_codes.gd`, WebRTC in `src/main.gd`, `adapters/web/ember_core_bridge.js`, `tests/connections.sh` | Changing browser pairing, validation, timeouts or assessing internet/NAT requirements |
| [Private lobbies](private-lobbies.md) | `src/private_lobby.gd`, `server/turn/`, browser lobby tests | Changing authenticated room discovery, automatic signaling, leases or deployment |
| [TURN service](turn-service.md) | `server/turn/`, `src/relay_credentials.gd`, browser setup | Changing invitation protection, credential issuance, relay configuration or deployment |
| [Network lab](network-lab.md) | `play-labs.sh`, `labs/`, `src/lab_keys.gd`, `tests/lab.sh` | Changing interactive tests, keyboard routing, latency/debug or process ownership |
| [Assets and hosting](assets-hosting.md) | `tools/`, `assets/craftpix-manifest.json`, `export_presets.cfg`, `.gitignore` | Importing art or building/publishing |
| [Verification](verification.md) | `tests/` including `browser_cross_network.py`, Web export and browser/manual checks | Assessing what is actually proven |

The conventional NAT/TURN/certificate study is in `design/internet-connectivity.md`. Provider alternatives are in `design/network-options.md`; deferred work is in `BACKLOG.md`.

Separate disposable controller setup and the cross-network harness are documented in [Runpod agent browser](../design/runpod-agent-browser.md).
