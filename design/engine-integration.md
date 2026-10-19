# Integrating the portable core

Only the Godot reference adapter, standalone native example and standalone/browser Wasm boundary are implemented and tested. Unity, Unreal, Windows/macOS packaging, mobile, console and custom-engine integrations below are **guidance**, not delivered/tested adapters. You do not need Godot to use the library.

## Common integration loop

1. Build the C++17 core for your exact target architecture with CMake or your engine build system. Include `core/include/ember_core.h`. Check `ec_v1_abi_version()` and create the appropriate owned handle. Destroy it during shutdown, on the same externally serialized lifecycle.
2. Capture engine controls outside the core. Convert horizontal input to [-1000,1000], and jump/attack to held flags. On focus loss, explicitly submit neutral local input.
3. At each **1/60-second fixed update**, call `set_local_input` and `tick` exactly once. Do not pass render-frame delta or tick once per arbitrary rendered frame. Decide your own pause/catch-up limits. The host advances movement/combat; replica ticks emit inputs and do not predict movement.
4. Drain `next_message` into your own uint8 buffer and pass the resulting **opaque bytes** to a transport callback. Borrowing ends when the C call returns. No engine object goes into a packet. You can send via UDP, WebRTC data channels or another transport without changing simulation code.
5. When receiving, authenticate/map the actual peer to stable slot 1 or 2 outside the core. Supply that slot and the packet bytes to `receive`. Reject oversized frames before dispatch. Do not trust a player ID claimed in payload data.
6. Read the host/replica view for rendering. Drain events to your engine's animation/effect/audio callbacks. The core chooses animation state and attack ID; you choose sprites, rigs, animation assets, blending and playback. The reference game selects animation automatically.

The prototype uses a scalar floor and fixed arena boundaries. It has no engine collision scene integration. If you need engine physics/collision queries, keep that engine service in the adapter and design an explicit collision-result contract; do not put engine types/callback objects inside the C ABI. This version is a small portable game simulation, not a general character-controller middleware package.

Coordinates: Godot uses `(x/1000, y/1000)` pixels. For Unity at 100 reference pixels/metre, render `(x/100000, -y/100000, 0)` metres. For an Unreal X/Z side view at one reference pixel/centimetre, render `(x/1000, 0, -y/1000)` centimetres. Those scale choices belong to each adapter; the core units never change.

## Unity native: documented possibility

Build `ember_core` for the target, package the native library through Unity's platform-specific plugin import settings, and keep the exported C symbol names/calling convention. A minimal P/Invoke surface starts like this (not a full adapter):

```csharp
using System;
using System.Runtime.InteropServices;
static class Ember {
    const string Library = "ember_core";
    [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
    internal static extern uint ec_v1_abi_version();
    [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
    internal static extern IntPtr ec_v1_create(uint abi, uint role, uint localSlot);
    [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
    internal static extern int ec_v1_set_local_input(IntPtr handle, int axisMilli, uint flags);
    [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
    internal static extern int ec_v1_tick(IntPtr handle);
    [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
    internal static extern void ec_v1_destroy(IntPtr handle);
}
```

Use explicit sequential, 4-byte-field managed structs matching the header for view/event calls; verify Marshal.SizeOf is 40/116/16, and map uint32_t→uint, int32_t→int, pointers→IntPtr. Do not marshal C++ classes or a C# bool into uint32 fields. Own each handle with a SafeHandle wrapper or try/finally; never use it after destroy. Add checked result handling, message buffers, view/event mappings and your transport before treating this as a production integration. Unity's default FixedUpdate interval may differ from 1/60; configure it or use an explicit fixed-step accumulator.

Unity WebGL would require either compiling the C ABI into Unity's own Wasm build with a suitable JS/native bridge or bridging a separate module like this project's Godot Web facade. The standalone Wasm output is not automatically a Unity WebGL plugin; no Unity/IL2CPP build has been tested.

## Unreal native: documented possibility

Keep the core as an external native dependency of a project-owned module/plugin. Link a CMake-built static library (define EC_STATIC) or package the shared library and load the `ec_v1_*` symbols with the target platform's loader. Use the header's C functions from your wrapper; do not export UObject, FString, TArray, engine allocators or C++ exceptions through this boundary. Engine-owned containers are fine on the adapter side after copying C views/bytes.

Create/destroy a handle with your subsystem's lifecycle, run a 60 Hz fixed-step schedule, map view coordinates into your chosen X/Z plane and route animation enum/events to your own animation graph or flipbook. Integrate your existing network transport by forwarding bytes and authenticated sender slots. Build rules, packaged target libraries, module wrappers, engine physics and replication-graph integration are not supplied or tested here. No Unreal browser target is claimed.

## Custom C/C++ engine and standalone browser

`examples/standalone.cpp` is the tested minimal typed C ABI example. Its transfer function stands in for a transport callback, passing serialized input/snapshots between independent handles. `core/tests/c_consumer.c` verifies the header from C11 as well as C++17.

For a browser, instantiate `build/wasm/ember_core.wasm` with no imports, create a handle, and use the exported C ABI. Caller byte buffers must be offsets in that module's own memory; pointers from a different engine Wasm memory are invalid. The numeric `ec_v1_command` helper avoids allocations and i64 JS conversion for small adapters. The tested wrapper in `adapters/web/ember_core_bridge.js` loads the module before Godot starts; `diagnostics()` is an adapter-only smoke-test probe of handle count, calls and views, not a core gameplay/transport API. HTTP asset fetch, input events, requestAnimationFrame/clock scheduling, rendering and WebRTC all stay outside the core.

The boundary tests compare a 600-tick native/Wasm byte trace and exercise browser-driven Godot movement. Separate network tests verify the Godot browser adapter on the routes listed in [verification](../specs/verification.md); neither set of tests establishes deterministic lockstep, production latency or an integration with an untested engine.
