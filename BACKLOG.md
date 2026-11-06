# Remaining work

The implemented baseline is in [architecture](specs/architecture.md); recorded acceptance is in [verification](specs/verification.md). These are possible next increments, not prerequisites for the working private lobby prototype.

## Future online game directions

Start with small games for two players, short sessions and a trusted host. Use private, bounded playtests to explore actual game integration and measure connection success, responsiveness and relay usage. Existing connection tests establish a starting point, not general online reliability.

- **Reconnection:** explore interrupted connections, reload/rejoin, ICE restart, re-signaling and credential refresh. Define whether a returning guest resumes the same state. Treat host migration as a separate requirement.
- **Prediction and presentation:** compare snapshot interpolation with local input prediction and authoritative reconciliation under measured latency, jitter and loss. Check movement and combat feel, correction size and state convergence.
- **Larger player counts:** choose a concrete next target before extending the two-player contracts. Measure host CPU, bandwidth, relay usage and connection count; compare a host-centered topology with a dedicated authoritative server when needed.
- **Hostile clients:** define the threat model before public access. Explore malformed or excessive messages, impossible inputs, replay, unauthorized room access, per-player removal and service abuse. A trusted host can validate guests but cannot guarantee fair play against a dishonest host; evaluate dedicated authority if that becomes necessary.

These are exploration directions, not implemented features or a commitment to add every capability before the next playtest. The sections below track the related implementation and acceptance gaps.

## Deterministic co-op with existing Cloudflare services

The [runnable experiment](specs/deterministic-coop.md) now runs the same C++ rules independently on both clients without a dedicated game server. [The comparison](design/deterministic-coop.md) records integration choices; [the budget assessment](design/no-server-budget.md) separates relay allowance from service quotas. The shipping Godot game still uses the host-authoritative baseline.

- **Implemented and tested:** tick-addressed inputs, stable slot order, bounded input history, ACKs/retransmission, session/epoch/rules checks and state hashes. Three 6,000-tick traces match across GCC, Clang and Wasm; simulated loss/reordering/suspension cases converge against independent reference peers.
- **Compared in the lab:** delayed lockstep versus twelve-tick bounded rollback, two/four-tick batching, stalls, correction sizes and speculative execution counts. Confirmed-only events avoid duplicate replay cues. Human gameplay feel, speculative effects/audio and actual background-tab suspension remain untested.
- **Implemented checkpoints:** canonical 140-byte complete save/load, including jump-edge memory and last inputs. Continuity tests compare restored peers against uninterrupted peers.
- **Exercised recovery barriers:** fresh peer/Wasm instances, new WebRTC connections and TURN credentials, creator departure with slot 2 continuing, and local checkpoint restore after reload. Test code coordinates checkpoint/epoch/membership; automatic recovery is not delivered.
- **Compared traffic and allowances:** encoded traffic and real WebRTC transport counters, plus a shared-egress budget calculator and reviewed free-tier terms. Provider-metered totals are not available through the current operator; estimates and credential issuance limits do not enforce a spending cap.

Remaining integration work:

- Negotiate synchronization mode, exact core/build identity and start barriers in Godot/private lobbies; connect predicted views and confirmed cues to the current game and compare actual platforming/combat feel before changing defaults.
- Add bounded resumable service records, authenticated seat reclamation, automatic fresh signaling/credential refresh and coordinated checkpoint/membership recovery. Test abrupt interruption, reload, creator exit and physical-network changes. Keep per-tick gameplay on peers.
- Compare local/downloadable saves with optional Cloudflare checkpoint storage when both clients exit. No cloud checkpoint endpoint or independent anti-cheat referee is supplied.
- Validate broader browsers/architectures, real suspension, selected direct and TURN/TLS routes, sustained loss, provider-metered egress and separate service quotas. Establish enforceable provider/account limits before promising strictly zero charges. No new services or paid plans are authorized by this exploration.

## Connectivity and service operation

- Broaden acceptance beyond workstation↔Runpod Chrome forced relay: Firefox, other physical PCs/networks, selected direct paths, direct-to-relay fallback, UDP blocked with TURN TCP/TLS, and latency/loss. Test invalid/expired/revoked access, host exit, reload/rejoin, sleep and network changes in real browsers.
- Add reconnect/ICE restart, re-signaling and temporary credential refresh if sessions need recovery or longer lifetimes. Host migration is separate work.
- Measure polling and relay usage before broader access. Current per-location request limits are not a global spending cap. Add global budgets/stronger abuse controls as needed; per-tester identity and revocation are separate from the shared key.
- Consider invite links and hibernating WebSockets if usability or measured polling usage warrants them. Private room listing, Create/Join and automatic signaling are already implemented.
- Self-hosted signaling/coturn is an alternative only if requirements justify replacing managed services. No VPS deployment is needed for the current architecture. Such a change needs temporary credentials, public networking, relay ports, TLS/renewal, monitoring and bandwidth controls.

## Gameplay and portability

- Add guest interpolation and prediction/reconciliation; current replicas display 20 Hz authoritative snapshots without smoothing or rollback.
- Evaluate reliable gameplay event IDs/acknowledgements, action-tick reconciliation and prolonged loss handling. Existing input/snapshot sequencing does not make events a reliable stream.
- Integrate real level collision, enemies and game-specific movement through explicit core/adapter contracts. This prototype is not a drop-in multiplayer retrofit for another game.
- Add Unity/Unreal/custom-engine and additional OS adapters only against concrete target requirements. Current integration guidance is not implementation evidence.
- Broaden native/Wasm parity traces across compilers, architectures and inputs before making any stronger determinism claim.

## Tools and presentation

- Add loss/jitter controls and an interactive browser network lab. The native two-process lab already provides both keyboard schemes, delay injection and live diagnostics; browser automation already covers two-network lobby gameplay.
- Extend input/layout acceptance to touch, gamepads and accessibility use cases beyond the tested desktop controls.
- Add audio and broader gameplay/level presentation when they enter the prototype's scope.
