Snapshot source: /workspace/research/studies/game-networking-models-2026-11-06/report.md (general-x86, 2026-11-06). Origin/receiver: co-op-side-scroller. General findings remain centrally owned; this copy supplies project context.

# Conventional networking and Ember Bridge

Checked 2026-11-06. Origin: co-op-side-scroller, https://github.com/RaresKeY/coop-side-scroller, General x86 checkout /workspace/coop-side-scroller. Baseline: ae4a046 plus the preserved deterministic experiment at bc3e979.

## Human input

Research how conventional game networking differs from this project; work in a General x86 clone, test both peers on that machine, use no Runpod, and review/patch until clean.

## Findings

There is no single conventional game networking architecture. The running game already uses a conventional client-host authoritative snapshot model. Its portable C++ rules, C ABI and browser transport are implementation choices within that model. The separate deterministic experiment belongs to the established input-replication/rollback family; it is not the running Godot game's synchronization mode.

| Question | Common approach | Running game | Deterministic experiment |
|---|---|---|---|
| Who decides state? | A dedicated server or a player-host; deterministic games may instead coordinate inputs | Trusted player-host simulates at 60 Hz | Both peers execute the same integer rules from common inputs |
| What crosses the network? | Snapshots/deltas, inputs and selected reliable commands | 24-byte guest inputs; full 104-byte snapshots at 20 Hz | 48-byte headers plus four bytes per input, ACKs and hashes; 140-byte trusted checkpoints |
| How is movement presented? | Interpolate remote objects; predict local controls when supported | Remote-actor position interpolation now buffers six ticks (100 ms nominal). Local guest remains unpredicted and undelayed by this buffer | Up to twelve speculative ticks, followed by bounded resimulation; missing input eventually stalls |
| How are mistakes corrected? | Server state reconciles predictions | New accepted host snapshots replace authoritative replica state | Confirmed input establishes state; hash disagreement freezes progress until explicit checkpoint recovery |
| Does it need deterministic engine physics? | Snapshot replication can tolerate different client physics | Current movement is a small C++ floor/arena model | Exact shared simulation, content and compatible build are required; arbitrary Godot physics cannot be substituted |
| What happens on disconnect? | End session, reconnect, migrate host or resume a server, depending on product | Host exit ends the session; one setup-time TLS retry exists | Explicit epoch/checkpoint/membership barriers are tested; automatic live recovery is not integrated |

Godot provides ENet, WebRTC and WebSocket peers; browser targets lack general raw UDP access. Our ENet-native/WebRTC-browser split therefore concerns platform transport, separately from authority. Channels and transfer modes let replaceable snapshots avoid waiting behind reliable commands. [Godot 4.7](https://docs.godotengine.org/en/4.7/tutorials/networking/high_level_multiplayer.html)

Buffered snapshots trade a small render delay for smoother remote motion. They do not predict local input. The new adapter interpolates only x/y, holds the last position across gaps, and resets after suspension, an observed membership change or session reset. Animation, combat, health and events continue to come from current core state. This is a bounded presentation improvement, with network and simulation rules unchanged. [Fiedler, snapshot interpolation](https://gafferongames.com/post/snapshot_interpolation/)

Local prediction with authoritative reconciliation is a separate implementation: retain input history, identify the server's processed input, restore state and replay pending inputs. Fusion's documented input/state authority split illustrates this family. Our snapshot protocol does not yet carry the acknowledgements needed for it. [Fusion 2 input](https://doc.photonengine.com/fusion/v2/manual/input/player-input)

Input-only replication reduces state-transfer requirements but depends on exact determinism and input availability. Rollback predicts missing input rather than eliminating that dependency. Quantum additionally has a server confirm input; our direct-peer experiment does not supply that server arbitration. Its hashes detect disagreement, not cheating or fair input ordering. [Fiedler, lockstep](https://gafferongames.com/post/deterministic_lockstep/), [Quantum 3 frames](https://doc.photonengine.com/quantum/v3/manual/frames)

## Infrastructure and trust

The Cloudflare Worker discovers rooms, exchanges signaling and issues temporary ICE configuration. TURN forwards traffic. Neither runs the authoritative game. A relay route does not make a dedicated simulation server, and encrypted transport does not make a trusted player-host honest. A dedicated server would add an operational authority and availability boundary, not merely replace WebRTC with UDP.

## AI Inferred

Retain the working host-authoritative game while qualifying the deterministic experiment separately. Integrating rollback requires a start/build barrier, clock/stall policy, effect handling and coordinated recovery, beyond calling the experimental ABI. Local prediction/reconciliation remains a worthwhile separate scope. Matchmaking, interest management, cloud checkpoints and hostile-client hardening should follow concrete game requirements.

## Evidence and limits

Project sources: core/src/ember_core.cpp, core/src/ember_deterministic.cpp, adapters/web/deterministic_peer.mjs, src/main.gd and src/snapshot_interpolator.gd; contracts: specs/architecture.md and specs/deterministic-coop.md. Tests and final review are recorded in the receiving project's specs/verification.md and HANDOFF.md.

Same-machine ENet/WebRTC and simulated impairments do not establish NAT, independent-network, mobile, human-feel or production-service acceptance. No SDK adoption, new service, paid compute or publication is implied. See [search coverage](sources.md).
