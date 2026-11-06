Snapshot source: /workspace/research/studies/game-networking-models-2026-11-06/sources.md (general-x86, 2026-11-06). Origin/receiver: co-op-side-scroller. General findings remain centrally owned; this copy supplies project context.

# Vocabulary, searches and sources

Checked 2026-11-06. Searches used the public web; conclusions rely on opened primary sources and inspected project code.

## Vocabulary and coverage

| Family | Terms and distinctions | Search coverage |
|---|---|---|
| Authority | Client-server, listen/client-host, dedicated server; authority differs from packet route | Q1, Q2, Q3 |
| State replication | Snapshot interpolation, render delay, unreliable replaceable state | Q1, Q2, Q5 |
| Responsiveness | Client prediction, input history, reconciliation, resimulation; distinct from interpolating remote state | Q1, Q2, Q4 |
| Input replication | Deterministic lockstep, rollback, confirmed/predicted frames, desync | Q2, Q5 |
| Connectivity | ENet, WebRTC, WebSocket, channels, signaling, TURN; services are not the game simulation | Q3 and local contracts |

## Executed query ledger

All rows executed 2026-11-06. Combined terms were subsequently resolved through the linked primary pages.

| ID | Exact search strings |
|---|---|
| Q1 | site.valvesoftware.com Source Multiplayer Networking entity interpolation client prediction lag compensation; site:developer.valvesoftware.com/wiki Source Multiplayer Networking |
| Q2 | site:doc.photonengine.com fusion 2 deterministic quantum snapshot state transfer; site:doc.photonengine.com/fusion/current snapshot interpolation client prediction server authority; site:doc.photonengine.com/quantum/current deterministic rollback input networking |
| Q3 | site:docs.godotengine.org multiplayer high level networking ENet WebRTC |
| Q4 | site:doc.photonengine.com/fusion/current/manual client server player input prediction; site:docs.unity3d.com netcode client anticipation prediction interpolation |
| Q5 | site:gafferongames.com/post snapshot_interpolation deterministic_lockstep |

## Opened primary evidence

- [Godot 4.7 multiplayer](https://docs.godotengine.org/en/4.7/tutorials/networking/high_level_multiplayer.html): engine transport choices, browser limitations and channel behavior.
- [Snapshot interpolation](https://gafferongames.com/post/snapshot_interpolation/), Glenn Fiedler, 2014: first-person implementation explanation of buffering, loss and smoothness/latency tradeoffs.
- [Deterministic lockstep](https://gafferongames.com/post/deterministic_lockstep/), Glenn Fiedler, 2014: exact-input/state requirements and bandwidth boundary.
- [Fusion 2 client-server input](https://doc.photonengine.com/fusion/v2/manual/input/player-input): input authority, state authority, prediction and replay.
- [Quantum 3 frames](https://doc.photonengine.com/quantum/v3/manual/frames): server-confirmed input and predicted/verified frames.
- [Unity Netcode 2.4.2 interpolation](https://mp-docs.dl.it.unity3d.com/netcode/current/learn/clientside_interpolation/): archived conceptual corroboration only; page warns that it is no longer updated.

## Gaps

Valve's Source Multiplayer Networking page returned HTTP 403. The Fusion current/manual/network-simulation-loop URL was unavailable; the accessible versioned Fusion 2 input page supports the comparison instead. Search snippets and third-party summaries were not used as substitute proof. Product pricing/licensing, anti-cheat comparisons, large-scale interest management and backend selection were outside this bounded architectural comparison; no vendor recommendation is made.

## Project link

[Origin and project copy](_readme.md). Code inspection distinguishes observed implementation from proposed integration and measured runtime results.
