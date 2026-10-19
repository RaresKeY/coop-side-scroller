# C ABI and message contract, version 1.0

Source of truth: `core/include/ember_core.h`. Symbol prefix is `ec_v1_`; ABI value is `0x00010000`, protocol version is independently 1. `create` requires the exact ABI version. Future incompatible layouts/protocols require a new version, not reinterpretation of existing messages.

## Calls and ownership

All arguments and fields use uint32_t/int32_t, uint8_t buffers, an opaque EC_Handle pointer, or caller-owned fixed-layout structs. No STL types, engine objects or exceptions cross the ABI. Native view sizes are asserted in C++: EC_Player=40, EC_View=116, EC_Event=16 bytes, with ordinary 4-byte field alignment. C ABI structs are native views and **must not be sent over the network**. No returned view/message/event points into mutable internal storage.

| API suffix | Contract |
| --- | --- |
| `abi_version`, `protocol_version` | Query supported version values. |
| `create(abi,role,local_slot)` | Host role/local slot 1 or replica role/local slot 2. Returns a core-owned opaque handle or NULL on invalid configuration/exhaustion. Caller owns its lifetime. |
| `destroy(handle)` | Releases that handle; no external allocator/free. Do not use the pointer again, including after storage is reused by another create. NULL is harmless. |
| `reset(handle,role,local_slot)` | Clears state/queues/sequences and reconfigures an existing owned handle. Host starts with slot 1; replica has no actors until a snapshot. |
| `set_local_input(handle,axis,flags)` | Axis [-1000,1000], jump bit 0, attack bit 1; unknown bits/values reject. No player identity in this call; it affects only the handle's configured local slot. |
| `set_peer_active(handle,2,active)` | Host-only membership; active must be 0 or 1. |
| `tick(handle)` | One fixed host tick or one replica input-emission tick. |
| `receive(handle,sender_slot,bytes,size)` | Borrows bytes only for this call; never retains caller pointers. Adapter authenticates sender_slot. Maximum size 104; exact type lengths, fields and authority are validated before state mutation. Rejections increment a diagnostic counter. |
| `next_message(handle,buffer,capacity,&size)` | Copies one outbound message into caller memory, then consumes it. Too-small/NULL buffer reports required size without consuming. Empty returns EC_EMPTY and size 0. Messages are gameplay payloads, with no transport framing. |
| `next_event(handle,&event)` | Copies and consumes one event; EC_EMPTY if none. Poll and route to your own callbacks. |
| `read_view(handle,&view,capacity)` | Copies current state; capacity must be at least sizeof(EC_View). Caller memory must be valid and naturally aligned. |
| `reset_dummy(handle)` | Host-only prototype/debug action. |

Status values: EC_OK=0, EC_EMPTY=1, invalid handle=-1, invalid argument=-2, authority=-3, malformed message=-4, stale sequence=-5, capacity=-6. Exported functions do not throw. External callers are responsible for valid accessible pointer buffers, correct capacities, handle lifetime and external serialization. Handles and creation/destruction are not thread-safe. Do not invoke a handle concurrently or recursively while a core call is active. Event/message callbacks are adapter-owned, after a completed call.

## Wire serialization

Every multibyte field is exactly 32 bits, **little-endian**; signed fields use two's-complement encoding. There is no native packing, padding, floating-point field or object serialization. Header bytes 0..3 are ASCII `EC01` (wire version 1), type at offset 4 and uint32 message sequence at offset 8. No checksum/MAC is supplied; transport security belongs outside this library.

Input type 1, exactly **24 bytes**:

| Offset | Field |
| --- | --- |
| 0/4/8 | Magic / type=1 / input sequence |
| 12 | Source slot, exactly 2; authenticated sender must also be 2 |
| 16 | int32 axis milli-input |
| 20 | uint32 held flags |

Snapshot type 2, exactly **104 bytes**:

| Offset | Field |
| --- | --- |
| 0/4/8 | Magic / type=2 / snapshot sequence |
| 12 | uint32 host fixed tick |
| 16 | uint32 dummy HP [0,12] |
| 20 | uint32 slot record count, exactly 2 |
| 24 / 64 | Slot 1 / slot 2 record, each 40 bytes |

Each slot record contains, in order at +0,+4,…,+36: slot ID, active, signed x, signed y, signed vy, signed facing, attack ticks, attack ID, animation enum, grounded. Inactive slots retain their ID but do not render. Active coordinates/velocity, facing ±1, boolean fields, cooldown ≤24 and animation [0,4] are range-checked. Snapshots from sender slots other than 1 reject at a replica, and hosts never apply snapshots.

The input and snapshot sequence spaces are independent. Messages are idempotent by sequence rejection; a transport may reorder/drop them. The test/reference transport uses ordered unreliable delivery and periodic full snapshots. Events are not a separately reliable network stream.

## Numeric reference bridge

`ec_v1_command(handle,operation,a,b)` is a bounded helper for the minimal native Godot and JS bridges. It uses int32 inputs/results so JS needs no i64/BigInt interop. Godot rejects arguments outside int32 range before narrowing, and validates Variant argument types before conversion. The JavaScript bridge likewise rejects non-integers, non-numbers, NaN/infinity and values outside int32 before WebAssembly can coerce/wrap them; commands also require a live bridge-owned handle. The facade consumes events before invoking their callbacks. Engine integrations with native FFI should prefer the typed calls above. Command output counters reinterpret uint32 values as signed int32 after 2³¹; typed ABI views remain uint32.

| Operation | Meaning |
| --- | --- |
| 0 | Reset: a=role, b=local slot |
| 1 | Set local input: a=axis, b=flags |
| 2 | Fixed tick |
| 3 | Set remote membership: a=2, b=active |
| 4/5/6 | Begin receive (a=authenticated slot,b=size), write each byte (a=index,b=byte), finish receive. Write all bytes before finish; duplicate writes do not count as missing bytes. Incomplete finish rejects, and every finish consumes the stage. Begin requires 12–104 bytes and invalidates any previous stage even on error; stage is per handle. |
| 7/8/9 | Peek outgoing size, read outgoing byte at a, consume outgoing message |
| 10 | Read view field a, actor slot b where needed |
| 11 | Host reset dummy |
| 12/13 | Peek front event field a (0 type,1 slot,2 value,3 tick), then consume event. Type 0 means empty. |
| 14 | ABI version |

Field numbers for operation 10: 0 tick, 1 dummy HP, 2 active, 3 x, 4 y, 5 vy, 6 facing, 7 attack ticks, 8 attack ID, 9 animation, 10 grounded, 11 snapshot sequence, 12 rejected messages, 13 dropped events, 14 dropped messages. Actor fields require b=1 or 2. Staged receive and outgoing reads must be completed synchronously without overlapping operations on the same handle.

In Wasm, handles/buffer pointers are wasm32 offsets into **that module's** memory, never pointers into Godot/Unity's different Wasm instance or native engine memory. The build exports a fixed 1 MiB memory and `__heap_base` for caller-owned scratch in the boundary test; no memory growth, WASI or external imports are required. The JS reference bridge avoids caller-buffer allocation by using the numeric helper. Native applications should not depend on Wasm scratch placement.
