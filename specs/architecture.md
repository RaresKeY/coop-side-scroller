# Current architecture

Ember Bridge is a two-player, host-authoritative co-op prototype built around an engine-independent C++17 library. Godot is the working reference adapter. The browser game runs from GitHub Pages or its Firebase Hosting mirror and uses a protected Cloudflare service for private room discovery, connection signaling and temporary TURN credentials. Gameplay travels over WebRTC directly or through TURN. The native development lab uses ENet instead.

## Ownership

| Component | Owns | Boundary |
| --- | --- | --- |
| `core/` | Fixed-tick movement/combat, input validation, logical animation state/events, authority, input/snapshot serialization | Versioned `ec_v1_*` C ABI; opaque handles, copied views/events and byte messages |
| `adapters/godot/` | Native C-interface GDExtension and GDScript facade | Calls the same core API on native and Web targets |
| `adapters/web/ember_core_bridge.js` | Separate core Wasm boot/bridge and browser-native text/copy dialogs | Godot and core Wasm memories remain separate |
| `src/main.gd`, `src/character_view.gd` | Fixed-tick scheduling, input capture, menus, rendering, sprite playback, transport and diagnostics | Supplies inputs/ticks, sends opaque messages, consumes core views/events |
| `src/player_chat.gd` | Session player names, reliable chat, RPG HUD/name tags and speech plates | Adapter metadata; no simulation state or persistent service storage |
| `src/diagnostics.gd` | Bounded browser connection events, best-effort uploads and copyable reports | Adapter-only; sanitized journal in existing Worker/DO |
| `src/private_lobby.gd`, `src/relay_credentials.gd`, `src/connection_codes.gd` | HTTP setup, credential validation and versioned signaling envelopes | Connection metadata stays outside the core |
| `server/turn/worker.mjs` | Playtest-key authorization, temporary ICE issuance, private room directory/signaling | `/v1/ice` and `/v1/lobby`; one SQLite Durable Object holds bounded setup records |
| Cloudflare TURN | Forwarding encrypted WebRTC traffic when selected | No simulation or gameplay authority |
| GitHub Pages / Firebase Hosting | Static HTML, Godot engine/export, core Wasm and notices | No server execution or credentials embedded in the page |
| `labs/` | Native worker lifecycle, two keyboard schemes, delay controls and telemetry | Separate processes/cores communicate through real ENet; controller sends no world state |

Player identity and [chat](player-chat.md) use a separate reliable adapter metadata stream. The core does not own names, chat, clocks, input devices, rendering, audio, assets, engine physics, HTTP or network transports. Its simple floor/arena rules are implemented in C++; integration with an engine collision scene is not supplied. The host is trusted. The shared playtest key controls service access, not host honesty or individual player identity.

## Session lifecycle

1. Each browser loads its own Godot engine and standalone core Wasm instance.
2. Both players enter the private playtest key. Host reserves a room for up to one hour; guest joins its directory entry. TURN/ICE preparation begins after the second seat joins. Every room/credential request is authorized by the service.
3. The adapters obtain temporary ICE configuration and exchange offer/answer/candidates through the room. ICE chooses the route; the default permits direct traffic and TURN fallback. Relay-only is a diagnostic mode; Compatibility (TLS 443) restricts the browser-to-relay leg to TLS/TCP port 443.
4. The host advances authority at 60 fixed ticks/second. Guest ticks emit input packets; the host emits full snapshots at 20 Hz. The replica uses bounded [remote-actor position interpolation](snapshot-presentation.md); the guest's local actor uses [bounded C++ prediction/reconciliation](local-prediction.md) for immediate movement/pose feedback.
5. Once both browsers report connected, the service deletes the signaling record and clients stop setup polling. Gameplay no longer depends on the directory. A selected TURN route still depends on the relay.
6. An eligible initial private-room transport failure automatically requests one coordinated TLS compatibility retry while the room remains available. Other failed or ended sessions return to setup. Host migration, credential refresh and automatic reconnect/ICE restart are not implemented.

Native solo/Host/Join uses the same core through the GDExtension. ENet is a separate transport with its own reachability requirements; native-to-browser play is not implemented. Advanced manual browser pairing remains a diagnostic alternative to the lobby.

A separate [deterministic co-op experiment](deterministic-coop.md) now runs shared C++ rules independently on both peers, with bounded rollback, compact input batches and complete checkpoints. Its native impairment lab and typed Wasm/WebRTC probe compare that alternative; it is not selected by the Godot game or existing private-lobby flow. Automatic service-side recovery and optional cloud checkpoint storage remain integration work.

## Contracts and evidence

- [Portable core](portable-core.md): ticks, units, authority and bounds.
- [C ABI](c-abi.md): ownership, status codes and exact wire layout.
- [Browser connection](browser-connection.md), [private lobbies](private-lobbies.md), [TURN service](turn-service.md): adapter/service contracts.
- [Builds and targets](build-targets.md): preparation and tested targets.
- [Verification](verification.md): bounded test results, deployment evidence and unverified combinations.
- [Engine integration](../design/engine-integration.md): Unity/Unreal/custom-engine guidance; these adapters are not delivered.

The architecture supports replacing an adapter or transport without moving simulation into that layer. Broader gameplay, engine integrations and recovery behavior require explicit work listed in [the backlog](../BACKLOG.md). Current limits are implementation scope, not permanent exclusions from future designs.
