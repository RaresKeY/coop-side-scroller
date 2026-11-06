# General x86 networking review — 2026-11-06

## Scope and review

Work stayed in the normal /workspace/coop-side-scroller checkout on general-x86, branch work/network-review-20261106. Upstream ae4a046 and all transferred tracked/untracked deterministic source were preserved first as bc3e979. No Runpod, live relay issuance, new deployed service, push or PR was used.

The review covered host/replica and deterministic wire/authority/checkpoint boundaries, the new presentation buffer, main-loop lifecycle, the typed browser boundary and the browser probe/CDP harness. This was agent self-review with regression checks, not an independent human review.

| Finding | Resolution | Evidence |
|---|---|---|
| Delaying the local guest would add input latency before prediction exists | Interpolate remote positions only; exclude slot 2 | snapshot_interpolator.gd and snapshot_presentation.gd tests |
| Moving CharacterView.present to render cadence would accelerate pose clocks | Keep presentation at 60 Hz; render only changes positions | Real main/CharacterView integration, seven checks |
| CDP's 15-second socket timeout could hide the page's 20-second ICE error | Whole-operation deadlines and a 30-second page-evaluation budget | Two fragmented/timeout socket regressions |
| The probe required a display and external STUN even for isolated local protocol work | Explicit headless/local-only modes, loopback candidates and fixture permissions; default GPU gate retained | Real Chromium WebRTC convergence/recovery |
| Relocated Debian Clang could not find wasm-ld-19 | Add the matching project-local linker alias | Full native/Wasm build and parity |
| Final-packet loss stalls the browser probe when its target is not divisible by twelve | Drive retransmission from a separate callback clock | Tick-599 failure reproduced in Chromium and real-Wasm fixture, then passed |
| A long packet blackout exhausts browser input history and aborts instead of resuming | Bound capture lead to 120 ticks and retain the pending tick on capacity | Real-Wasm blackout/recovery regression and actual Chromium injected loss |

Final inspection found no further actionable defects in the reviewed change. Remaining architectural features are recorded in BACKLOG.md; this is not a general security or internet-reliability certification.

## Verification

All commands below ran on General x86, with both gameplay peers on that machine:

- tests/core.sh: native ASan/UBSan contracts, C consumer, standalone, native/Wasm trace and bridge ownership passed.
- tests/deterministic.sh: contracts, twelve local simulated impairment cases, checkpoint/reload/departure and GCC/Clang/Wasm equality across 18,000 trace ticks passed.
- Offline Worker/lobby tests: 19 passed.
- CMake Debug build and CTest: four passed.
- Snapshot interpolation: 13 checks; real main/CharacterView presentation: seven checks.
- CDP deadline tests: two passed; HTTP allowlist test passed.
- Actual two-process Godot ENet: both exit codes zero, replicated movement/combat passed.
- Actual two-page Chromium host-candidate WebRTC: initial tick 600, fresh-transport tick 840 and creator-departure/local reload tick 1080 match the native reference; no desync/dropped confirmed events. Both headless protocol and NVIDIA WebGL modes passed.
- Godot 4.7 Compatibility capture: GTX 960/NVIDIA 550.163.01, clean script execution; gameplay.png was opened and inspected.
- Changed Markdown links, whitespace and shell/Python syntax were checked at closeout.

The follow-up pass reviewed packet ordering, ring reuse, recovery barriers, interpolation/lifecycle, the typed boundary and browser scheduling. It repeated the full deterministic suite including two new real-Wasm browser-fixture regressions; all passed. Worker, lobby and diagnostics tests passed together: 27 tests. Actual headless Chromium WebRTC passed with a 5.5-second injected send blackout (197 packets discarded per direction) and one discarded final-input packet per direction at tick 599. Confirmed state/events matched the native oracle; fresh transport reached 840 and solo/reload reached 1080 without desync or dropped events. A 3 MiB CDP return value also passed. No further actionable findings remain in those reviewed paths.

The protected relay and cross-network harnesses were not run. The cloned game uses its committed fallback art; private CraftPix sources were not transferred. New presentation fixtures use synthetic frame textures, so animation-clock correctness is distinct from final art acceptance.

## Runtime and retained failures

The prepared workbench supplies GCC 14.2, Godot 4.7 and Deno 2.9.8. Approved Clang/LLD 19.1.7 and Chromium 156.0.8078.79 were downloaded through signed Debian APT metadata and extracted under .local/test-tools; packages.json records hashes. No system installation was performed.

Initial attempts retained: bulk transfer timeout (recovered through verified compressed chunks), missing relocated linker name, display-only browser guard, premature CDP timeout, zero ICE candidates, Chromium WebGL blocklist, denied Wayland scanout and rejected llvmpipe renderer. None was counted as a pass.

The successful Chromium wrapper uses ANGLE GLES, NVIDIA vendor selection, ignored driver blocklist and disabled GPU desktop compositing inside the isolated test container. The actual WebGL renderer gate still requires NVIDIA. Native Godot uses the existing private hardware compositor/lock. The original host Podman/Gamescope launcher is unavailable in this isolated workbench, so its documented prepared direct-runtime fallback was used; no shared service or container permissions changed.

## Evidence and reproduction

Ignored evidence: .local/network-review-20261106/{core,deterministic,service,cdp,browser-handler,interpolation,presentation,enet-host,enet-client,gpu-capture,browser-direct,browser-gpu}.log; browser-final.json, browser-headless.json, enet-pair.json, transfer.json and gameplay.png. Rejected attempts remain alongside them. Build reports: build/core-build.json and build/deterministic/. Test tool pins/wrappers: .local/test-tools/.

Source /workspace/agent-kit/env.sh and prepend the project's .local/test-tools/bin to PATH. Use /usr/local/bin/godot --headless for the two snapshot scripts. Run python3 tests/deterministic_browser.py --headless --local-only for protocol-only checking. For the retained NVIDIA check, use the existing GPU lock/compositor and NVIDIA EGL/GLX vendor environment; the project-local Chromium wrapper records its complete flags.

Follow-up evidence: .local/network-rereview-20261106/{tail-before,probe-before,probe-after,deterministic,services,browser-impairment}.log, browser-impairment.json and the retained injected-loss script browser-impairment.py. The original tick-599 timeout and history-capacity failure are retained, distinct from successful reruns. An initial relocated Python import error and incomplete SDP mock were setup errors, corrected before the behavior regressions; the mock error log is retained separately. The follow-up reused installed runtimes, imports and local test dependencies; no GPU repeat was needed for network-only changes. Godot rendering/ENet and NVIDIA evidence above belong to the preceding pass.

Same-machine success does not establish NAT traversal, independent-network behavior, phone controls, human latency acceptance, full Godot Web/private-room acceptance or automatic production recovery.
