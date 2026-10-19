# Co-op Side Scroller specs

Start with [current architecture](architecture.md): portable C++ core, Godot native/Web adapters, private Cloudflare lobbies and TURN, and GitHub Pages hosting.

`specs/` describes implemented contracts and recorded verification. `design/` explains decisions, network implications and integration guidance. `BACKLOG.md` contains future work. Preserve historical detail only when it explains a current choice or an evidence boundary; implementation chronology belongs in Git history. A recorded test result is not a claim about every subsequent build.

| Spec | Sources | Read when |
| --- | --- | --- |
| [Architecture](architecture.md) | `core/`, `adapters/`, `src/`, `server/turn/` | Understanding ownership, deployment and session lifecycle |
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
| [Verification](verification.md) | `tests/` including `browser_cross_network.py` and `browser_lobby_cross_network.py`, Web export and browser/manual checks | Assessing what is actually proven |

Supporting documents:

- [Internet connectivity](../design/internet-connectivity.md): NAT, routing, certificates and native/browser differences.
- [Service decision](../design/network-options.md): selected provider and reasons to retain or revisit earlier alternatives.
- [Engine integration](../design/engine-integration.md): C ABI guidance for engines beyond the tested Godot adapter.
- [Runpod testing](../design/runpod-agent-browser.md): separate-controller lifecycle and cross-network harness.
- [Remaining work](../BACKLOG.md): unimplemented features and acceptance gaps.
