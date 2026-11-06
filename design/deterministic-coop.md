# Deterministic co-op comparison

The experiment in [the deterministic contract](../specs/deterministic-coop.md) explores the backlog's two-player, no-dedicated-server direction. The shipping game still uses host authority and snapshots. Both use the same `simulation.h` rules; the existing native/Wasm snapshot trace is the regression baseline for that extraction.

## What the experiment establishes

Every client can calculate the same world using complete tick-addressed inputs. A fixed ring and acknowledgement/retransmission policy recover missing inputs without relying on periodic snapshots to conceal a dropped action. Complete checkpoints make catch-up/reload possible without replaying an entire match from its beginning. Membership can change at an explicit checkpoint/epoch barrier, so slot 2 can retain and simulate the world after slot 1 leaves.

BAR/Recoil's lesson is the separation of deterministic simulation, ordered inputs, match coordination and transport. Its [netcode overview](https://recoilengine.org/articles/netcode-overview/) explains the command stream and desync cost. This experiment retains WebRTC/TURN rather than importing BAR's dedicated UDP server, lobby software or engine. Its two-player frame numbers and slot order supply the stable input order; it does not need a server sequencing every frame.

## Responsiveness decision

Pure lockstep is a useful correctness baseline, but it waits for every input. The lab compares a six-tick (100 ms) input buffer against zero added local input delay and up to twelve predicted ticks. Rollback can show immediate local movement while actual remote inputs are in flight, but large corrections are possible. Loss exceeding the prediction window still pauses play. A suspended browser can stall either design; background throttling is not solved by determinism.

The next gameplay integration should favor bounded rollback if actual platforming/combat playtests tolerate the corrections. Evaluate a small local delay and speculative presentation separately. Confirmed-only events prevent duplicated effects but delay cues; do not imply that the current experimental policy supplies polished immediate audio. The [GGPO description](https://github.com/pond3r/ggpo#whats-ggpo) is the reference for the prediction/rewind distinction, not a newly added dependency.

## Recovery decision

Use explicit trusted checkpoints at a confirmed tick, an incremented epoch and agreed active players. Retain enough inputs to catch up; if history is unavailable, transfer a new complete checkpoint. Freeze on disagreement and request an explicitly chosen source rather than silently overwriting one peer with whichever packet arrived last. Two trusted peers can choose a source; this supplies no independent referee against cheating.

Keep gameplay inputs/checkpoints on the existing peer connection. Extend the existing Cloudflare session service only for resumable identity, discovery and re-signaling when transport is lost; credentials must be refreshed for a new attempt. The current service deletes setup records after connection, so automatic rejoin requires a separate bounded session lifetime and authenticated seat-reclaim contract. This has not been implemented or deployed by the experiment.

Local saves suffice for the demonstrated reload when retained by a participant. Both players exiting without retaining a checkpoint loses the world. Optional Cloudflare checkpoint storage would allow later retrieval, but adds authentication, retention, storage/write quotas and a choice of trusted source. Compare this with a downloadable/local save before adding an endpoint. No continuously running cloud simulation is necessary for either approach.

## What to integrate next

1. Negotiate synchronization mode, exact build/rules identity, session/epoch and start barrier in the existing Godot/private-lobby flow.
2. Add a Godot facade for the typed deterministic ABI and bind predicted views/confirmed cues to the current renderer. Keep simulation out of GDScript. Measure gameplay feel rather than extrapolating from scripted trajectories.
3. Add recovery UI, bounded session retention, authenticated seat reclamation and automatic fresh signaling. Test reload, browser suspension, creator exit and network changes on physical peers.
4. Measure selected direct and TURN/TLS routes, sustained loss, transport overhead and provider-metered usage before selecting defaults or a zero-cost operating envelope.

Future collision, AI and randomness must preserve deterministic ordering and complete checkpoints. Engine-owned floating-point physics, local wall time, unordered iteration and unseeded random draws cannot enter shared simulation unnoticed. The current tests cover the small integer arena, not arbitrary future game systems.
