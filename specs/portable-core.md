# Portable simulation core

## Ownership

`core/include/ember_core.h` and `core/src/ember_core.cpp` own movement, combat, player input validation, automatic animation state/events, host authority and input/snapshot synchronization. The same sources compile into a native library and a freestanding wasm32 module. They include no engine/network APIs, STL containers, exceptions, allocation services, clocks, threads, graphics, audio or asset loading. The public boundary is the versioned C ABI documented in [c-abi.md](c-abi.md).

`adapters/godot/portable_core.gd` is the reference facade. It calls the C ABI through the small native C-interface GDExtension (`native_extension.cpp`) or the standalone Wasm module (`adapters/web/ember_core_bridge.js`). It emits adapter callbacks/signals for outbound bytes and core events. Each engine owns sprite playback and can replace the facade. `src/main.gd` captures inputs, supplies explicit ticks, transports opaque bytes, consumes views/events and renders. It contains no authoritative movement/combat solver or animation-selection rules. Engine physics is not invoked by the core; the current gameplay rules use a simple engine-independent floor model, not an engine collision service.

## Fixed ticks and coordinates

An explicit `ec_v1_tick()` advances one host tick at **60 Hz**. There is no variable `dt`, wall clock or accumulated real time inside the library. Replica ticks produce local input messages and do not advance authoritative movement/combat. Their displayed simulation tick comes from accepted host snapshots. Adapters must schedule fixed ticks and define pause/catch-up behavior; Godot's reference adapter sets `Engine.physics_ticks_per_second=60` and calls once per physics callback. Background browser throttling is not solved here.

Coordinates are signed integer **milli-reference-pixels**, origin top-left, +x right and +y down. Actor position is the feet/ground anchor. Velocity is milli-pixels **per fixed tick**. X clamps to [24000,936000], floor y=448000, dummy x=720000. Full-speed horizontal displacement is 2833 units/tick (169.98 reference pixels/second), jump velocity -6000 units/tick, rising gravity +300 units/tick² and falling gravity +500 units/tick². Releasing jump clamps upward velocity to at least -2400 before gravity, making tap jumps lower. A held jump reaches a 57000-unit apex after 19–20 ticks and lands on tick 35; descent is quicker than ascent. Integer division truncates toward zero. All wire integers use the serialization in c-abi.md, not native struct memory.

Input is axis [-1000,1000] plus held jump/attack flags. Jump is edge-triggered and grounded-only. Attack can repeat every 24 ticks while held. Damage is evaluated once at age 15 ticks (cooldown remaining 9), after anticipation/downstroke rather than immediately on attack start. A hit needs horizontal distance <65000, vertical distance <45000 and correct facing. Dummy HP starts at 12. Remote host input expires after 18 authority ticks (300 ms); local callers must send neutral input themselves when capture/focus stops. The lab input bus does this independently.

## Authority and synchronization

A host handle owns slot 1 and can add/remove the sole remote slot 2. A replica owns local input slot 2 and accepts authoritative snapshots only from sender slot 1. Transport adapters authenticate/map actual peers to these stable slots; payloads cannot grant authority. Godot maps its actual ENet/WebRTC peer ID to slot 2 on the host and requires actual peer ID 1 for replica snapshots.

Replica ticks emit sequenced 24-byte input messages. Host ticks apply latest validated remote input and emit a 104-byte snapshot every third tick (20 Hz). Snapshots contain fixed-tick state, both actor slots and dummy HP. Replica applies a completely validated snapshot atomically. Duplicate/old messages are rejected using modular uint32 sequence comparison; a jump of half the sequence space is not considered newer. Input sequencing resets on peer reactivation. No deterministic lockstep, rollback, prediction, interpolation, host migration or reliable event delivery is claimed.

Animation states are idle/run/jump/attack/walk. State, attack ID, cooldown and ground contact are authoritative. Core events describe joins/leaves, attacks, damage and animation transitions; replica events are observations of accepted snapshots and can coalesce transitions between snapshots. Sprite frame counts, sheet pivots, playback speed, palette and effects belong to each renderer. Godot restarts attacks by replicated attack ID and shows damage feedback from core events. No animation selection UI exists.

## Bounds

There are 32 externally serialized handles, two actors per host, 64 queued outbound messages and 64 queued events per handle. Full queues drop newly produced entries and increment diagnostic counters; they do not stall the simulation. Callers should drain both each tick. No unbounded allocation occurs. Views report queue drops and rejected messages. The host is trusted, with no cryptographic authentication or anti-cheat in the core. Transport encryption, connection setup, liveness and identity belong to the host adapter.

The native/Wasm 600-tick trace is byte-identical in current tests. That verifies that one test scenario on the recorded toolchains; it does **not** establish deterministic lockstep across compilers, architectures or all inputs.
