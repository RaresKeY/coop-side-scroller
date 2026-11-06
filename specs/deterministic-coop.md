# Deterministic co-op experiment

Owners: `core/include/ember_deterministic.h`, `core/src/ember_deterministic.cpp`, shared rules in `core/src/simulation.h`, `adapters/web/deterministic_peer.mjs`, `tools/deterministic_lab.py` and `tests/deterministic*`.

This is a runnable alternative to the shipping host/snapshot model, not a replacement for its Godot menus, lobby protocol or adapter. It runs the same movement/combat rules independently on two clients. No game server, external dependency, SFU, service deployment or paid plan is required by the experiment. See [the comparison and integration decision](../design/deterministic-coop.md) and [budget assumptions](../design/no-server-budget.md).

## Core contract

The additive `ec_v1_deterministic_*` C ABI shares `EC_ABI_V1`, `EC_Player`, `EC_View` and `EC_Event`; it does not reinterpret the shipping `EC02` protocol or host/replica calls. Four opaque handles are available. Each has a caller-supplied nonzero 128-bit session ID, epoch, authenticated local slot 1/2, and prediction limit 0–12 ticks. Calls are externally serialized. Destroyed pointers must not be reused, including after a storage slot is recycled.

The adapter captures contiguous local inputs for numbered ticks and supplies authenticated remote packets. Tick numbers are bounded to `0x7ffffe00`; start a new session before exhausting the range. A 256-frame ring retains actual inputs and state hashes. Unacknowledged local inputs cannot be overwritten. If capture/history capacity is exhausted, pause input capture or negotiate recovery; never skip missing inputs silently. The laboratory limits capture lead and catch-up work explicitly.

`advance(target)` confirms sequential ticks only when every active player's actual input is available. `prediction=0` is lockstep. A positive limit speculates ahead using the last known remote held input, requiring actual local input. Late actual inputs cause resimulation from confirmed state, bounded by the prediction window. Reaching that bound returns `EC_EMPTY` and stalls rather than extending speculation indefinitely. A detected hash mismatch returns `EC_ERR_DESYNC` and freezes input/advance until an explicit trusted checkpoint load.

The `max_correction` statistic measures horizontal displacement in milli-reference-pixels at a corrected predicted frame; vertical correction and audiovisual quality need gameplay inspection. The core supplies no wall clock or adaptive clock synchronization; adapters need a common start barrier, bounded capture/catch-up and an explicit stall policy.

State hashes are 32-bit FNV-1a over canonical complete simulation bytes. They detect disagreement in the tested traces; they are neither collision-proof nor an anti-cheat signature. Common rules/build compatibility is represented by `EC_DETERMINISTIC_RULES=1`, which must be bumped for incompatible rule changes. Production pairing must additionally agree on exact core/build identity; the test harness explicitly loads the same compiled module in both pages.

Only newly confirmed ticks emit events. Speculative execution and replay emit no effects, so rollback does not duplicate confirmed attack/damage/animation cues. This delays confirmed audio/feedback; immediate speculative effects with correction/deduplication are not integrated. The event queue holds 64 entries and counts overflow; adapters must drain promptly and bound catch-up. Rendering may read predicted `EC_View` actors; `snapshot_sequence` carries the confirmed tick in this API only.

## Input packet

`pack(first,count)` returns an explicitly serialized `EDI1` packet of `48 + 4*count` bytes, with 0–8 contiguous input records. Zero records is a heartbeat. The caller chooses new batches and retransmission timing; the laboratory sends every two or four ticks and retries the oldest unacknowledged range every twelve clock ticks. Acknowledgements cover the remote contiguous input prefix, not execution of application effects.

| Offset | Field |
| --- | --- |
| 0 | ASCII `EDI1` |
| 4 | 16-byte session identifier |
| 20 / 24 | uint32 epoch / rules version |
| 28 / 32 | uint32 first input tick (0 for heartbeat) / acknowledged input tick |
| 36 / 40 | uint32 confirmed hash tick / state hash |
| 44 / 45 / 46 | uint8 source slot / record count / two reserved zero bytes |
| 48 + 4*i | int16 axis [-1000,1000], uint8 held flags [0,3], reserved zero byte |

All multibyte fields are little-endian, with signed axes encoded as two's complement. Sender identity comes from the transport, never the payload alone. Session, epoch, rules, sizes, reserved bytes, ranges and immutable duplicate inputs are checked before recording a packet. Unknown/retired confirmed inputs return `EC_ERR_STALE`, including when their old ring slots hold unacknowledged newer inputs; exact retained duplicates are idempotent. A future confirmed hash is retained until that tick can be checked. Recovery-barrier hashes are retained for reordered packets after resumption. The adapter must discard stale-packet status rather than treating ordinary reordering as a fatal transport error.

## Checkpoint and recovery

`save` copies a 140-byte `EDC1` checkpoint of confirmed state only. It includes session/epoch/rules, tick, dummy HP, both full actors, jump-edge memory and both last inputs, followed by a state hash and whole-checkpoint checksum. It excludes clocks, predicted frames, transport objects, credentials and effect queues. This is a canonical byte format, not a native struct dump. It is suitable for trusted peer transfer or local storage; no cloud checkpoint endpoint is delivered.

`load(checkpoint,new_epoch,active_mask)` validates everything into temporary state before replacing the handle. The epoch must exceed both current handle and checkpoint epochs, and the selected active mask must include the local player. It resets pending inputs, ACKs, prediction and effect queues at the checkpoint tick. Removed players become inactive; newly active players spawn using the shared rules. Both peers must explicitly agree on the same checkpoint, epoch and membership before exchanging fresh traffic. Old-epoch packets reject.

The laboratory exercises a fresh peer rejoining, the original creator departing while slot 2 continues alone, and reconstruction after both handles close using retained bytes. The browser probe recreates Wasm instances and WebRTC connections with fresh TURN credentials, then exercises local checkpoint persistence across a page reload. Test code coordinates these barriers: automatic service-side session recovery, player identity/seat reclamation, ICE restart, negotiation of membership and recovery during adversarial disagreement remain integration work.

## Run

```sh
./tests/deterministic.sh
python3 tools/deterministic_lab.py --ticks 30000
python3 tools/network_budget.py --billed-kbytes-per-second 12 --match-hours 10000
# Two local browser contexts, hardware GPU, muted, existing TURN issuer only:
./tests/deterministic-browser.sh --relay
```

The shell suite explicitly prepares the same native and import-free Wasm core. The standalone lab's default library and the browser probe require a fresh build receipt; they do not silently build. Deno uses only local modules with restricted file permissions, no network/packages. The typed adapter copies the validated session ID before asynchronous instantiation, so callers can reuse their input buffer without changing the peer identity.

The browser probe bounds captured input lead to 120 ticks ahead of confirmed state and pauses on history capacity without skipping the pending tick. Retransmissions use a separate callback clock, so missing final inputs are retried even after the simulation target stops advancing. `tests/deterministic_probe.test.mjs` runs the actual browser fixture and real Wasm with controlled clocks/packet loss, covering final-packet loss at tick 599 and a long blackout followed by convergence; it runs inside the shell suite. These controlled fixtures do not establish real browser scheduling or NAT behavior.

The browser probe accepts `--local-only` for same-machine host candidates without STUN/TURN and `--headless` for protocol checks without a GPU-rendering claim. The default rendered mode still requires NVIDIA; it selects Wayland when supplied, otherwise X11. `--relay` and `--local-only` are exclusive. CDP page evaluation has a 30-second budget so the 20-second ICE gather deadline can surface its actual error; complete frames share one bounded read deadline.

The browser probe serves an allowlist of three local resources for both GET and HEAD; relay mode binds the existing allowlisted localhost origin and reads the existing invitation privately in memory. Its public fixture session is for tests only. Real sessions require fresh random identifiers and authenticated transport-to-slot mapping. Superseded asynchronous preparation cannot replace a fresh peer. A native reference runs during each browser probe; confirmed hashes/events are checked before and after recovery, and solo continuation checks complete checkpoint bytes and events against native execution.

Current results are in [verification](verification.md); generated traces/reports live under ignored `build/deterministic/`. Reports distinguish simulated impairment, local direct connectivity and selected TURN routes. Matching GCC/Clang/Wasm traces on this workstation do not establish all compiler/architecture/browser combinations. Browser timer throttling is disabled in the real transport probe; suspension is modeled separately in the native lab. Transport counters do not establish billed egress.

The browser shell wrapper independently records the Python child's exit status. A Gamescope shutdown status of 139 is reported separately and accepted only after the child returned 0; missing/failed child status, timeout and other runner failures remain failures. The Python probe removes its previous result before starting, so a stale successful JSON file cannot validate a new failed run.
