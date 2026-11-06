# Local prediction and reconciliation

## Human input

Each player must see movement and animation respond immediately on their own machine. Joining must not make the local character tinted: the other player is tinted in each view, and a downward triangle identifies the local character.

## Implementation

The host remains authoritative. Its local slot 1 advances directly at 60 Hz. Replica slot 2 now predicts its own movement, jump, facing, attack cooldown/ID and logical animation each local fixed tick. Prediction calls the same C++ rules in simulation.h on an isolated actor world with no enemy damage or emitted events. No GDScript movement solver or animation override is supplied.

Replica authority stays in its accepted snapshot state. Read-view/numeric actor fields return the predicted local actor and the authoritative remote actor. HP and core events remain confirmed; speculative attacks cannot damage the dummy or emit confirmed attack/damage cues.

Protocol 3 (EC03) adds the last applied input sequence and actual host jump-edge memory to each snapshot. The replica replaces its baseline with the accepted authoritative actor, removes acknowledged inputs with modular sequence comparison, and replays the unacknowledged suffix once. Corrections are immediate; correction smoothing and server rollback are not implemented. The host queues the actual command frames and executes each once, up to eight per host tick. It never advances a guest from a repeated held command between arrivals. ACKs identify the final executed frame, so the authoritative baseline and replay suffix cover disjoint input time. Eight recent input frames travel in each packet; overlaps deduplicate and short loss bursts recover without reliable-transport blocking. Loss beyond that window can still require a correction.

Both host command queue and replica prediction history are bounded to 128 frames; a full host queue rejects a complete packet atomically. Replica history is bounded to 128 active-actor input frames. Exhaustion freezes further speculation while input transmission continues; a fresh accepted snapshot drops exhausted history and resumes prediction. Reset, observed actor inactivity and initial activation clear the old trajectory. No state is predicted before the first active authoritative actor arrives.

Input packets carry recent per-frame held states and cumulative jump/attack press counters. Recent lost/coalesced press/release frames execute in order. If a press is older than the redundant window, its counter provides one bounded fallback attempt; duplicate packets cannot replay it. Ground/contact/cooldown rules still decide whether that attempt succeeds. Counters use modular uint32 comparison. This is not a reliable event stream or an anti-cheat boundary.

The adapter flushes newly emitted packets after the same core tick, removing the previous extra fixed-tick wait. Configured artificial-delay due times still apply. Remote-position interpolation excludes the local predicted actor. CharacterView.present remains on the fixed pose clock.

## Identity

Each view colors its own slot white (original art colors), the remote slot cyan. A gold downward triangle sits above the local character. Appearance and marker position update with perspective; reset hides the marker. Stable authority slots remain host=1 and guest=2.

## Verification and limits

Core sanitizer and real-Wasm tests cover immediate movement/jump animation before host delivery, delayed acknowledgements, correction/replay, held-jump continuity, malformed ACK atomicity, bounded outage recovery, and suppression of speculative effects. Tap tests cover lost/coalesced press packets, duplicate rejection and serial wrap. Godot integration covers per-view colors, triangle ownership/reset and same-tick dispatch with retained artificial delay.

A same-machine two-browser relay/TLS check observes guest movement and run animation on its first local input tick while host snapshots are blocked, with no intervening accepted snapshot. Human acceptance and input-to-display timing remain separate; native/Wasm equality does not establish input-to-display milliseconds. Network authority, world effects, remote actors and corrections still have latency. Both peers must reload for protocol 3; EC01/EC02 gameplay is rejected rather than reinterpreted. The existing lobby accepts versions 1/2/3 in separate matching signaling pairs during rollout. Delayed/batched native regression scenarios (one/three/six/nine ticks, with two-packet losses) require no position or animation correction after activation. This specifically covers the protocol-2 regression: repeated held-input host steps plus ACK/replay caused regular 8–23-pixel jumps.
