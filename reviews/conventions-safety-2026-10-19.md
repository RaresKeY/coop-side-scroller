# Conventions and safety review — 2026-10-19

Scope: committed baseline `9d35b09` plus the in-progress browser-entry/diagnostics changes present during review. [Terminology](../specs/terminology.md) was created first to distinguish user-facing names, ABI/transport identities, access credentials, connection metadata and timing measurements. The original review changed documentation only; findings were open at that snapshot. See the local follow-up resolution below for subsequent patches. Concurrent diagnostics work was re-read before recording findings.

## Findings

### P2 — Diagnostic uploads postpone expired-room cleanup

Location: `server/turn/worker.mjs`, `PrivateLobbies.fetch`, the `diagnostics_record` branch (line 204 at review). Introduced in the in-progress diagnostics changes.

Every diagnostic upload replaces the Durable Object alarm with `now + ROOM_IDLE_MS`, without pruning rooms or preserving an earlier deadline. Active games upload summaries about every 15 seconds. If an abandoned room exists while another game continues sending diagnostics, the alarm never becomes due. The room record, potentially including stored SDP/ICE, can remain beyond both its idle lease and absolute setup lifetime until ordinary lobby traffic prunes it or diagnostic uploads stop.

Offline reproduction: create one abandoned room, then advance a fake clock by 15 seconds and send 45 valid diagnostic uploads through the public handler (synthetic authorization, HTTP 200), honoring due alarms before each upload. At 675,000 ms, no alarm has fired, the expired room still exists, and its next alarm is another 90,000 ms away. Once uploads stop and that alarm runs, the room is removed. This is a retention/cleanup defect, not evidence that an expired room can be joined: normal lobby requests still prune before use.

Suggested correction: preserve the earliest relevant room/journal deadline, or prune room state on the diagnostics path and schedule the next actual expiry. Add a fake-clock regression that keeps diagnostic traffic flowing past a room's expiry; existing journal-expiry tests stop traffic before invoking the alarm.

### P2 — Wasm destroy bypasses handle validation before numeric narrowing

Location: `adapters/web/ember_core_bridge.js`, `EmberCoreWeb.destroy` (line 50 at review; the same implementation exists in committed baseline `9d35b09`).

`command()` checks membership in the bridge-owned handle set, but `destroy()` passes its argument straight to the Wasm export. Wasm converts it to a 32-bit pointer. Given live handle `h`, `destroy(h + 2**32)` therefore destroys `h`, while `handles.delete(h + 2**32)` leaves `h` registered in JavaScript. The adapter retains a supposedly live instance whose core storage has been released; later reuse can compound the bookkeeping error.

Offline reproduction using the actual prepared core Wasm: ABI query returns 65536 before the call, then -1 for the original handle afterward, while bridge diagnostics still reports one live handle. This is a local API/lifetime-safety defect. It does not demonstrate that an unauthenticated remote peer can execute JavaScript or call this method.

Suggested correction: require an exact live bridge-owned handle before calling the export, use a consistent destroy/no-op/error contract, and test out-of-range, fractional/string and duplicate destruction without affecting another live instance.

## Checked and not currently findings

| Area | Review/check result |
| --- | --- |
| Core/adapter ownership | Simulation and gameplay serialization remain in C++; rendering, clocks, input and transports remain outside it. |
| ABI and wire conventions | Fixed-width fields, copied views/buffers, explicit lifetime, little-endian wire data and independent sequence spaces remain documented. Current native contract tests pass under ASan/UBSan. |
| Native/Wasm preparation | `tools/build_core.py --check` passes; the handle probe uses the current prepared Wasm. No broad determinism claim is made. |
| Worker access and bounds | Seventeen current offline issuer/lobby/diagnostics tests pass. Shared access versus per-seat ownership and operator-only report reading remain separate. These tests do not cover the alarm finding above. |
| Diagnostic event vocabulary | Initial inspection found omitted `ice`/service-error values; the concurrent implementation corrected them before the review snapshot. Offline client-shaped `ice`, `list` and rate-limit events now validate; authorized synthetic upload returns 200. Not counted as an open issue. |
| Secrets and public source | Existing publication audit run against all stored Git objects and source candidates; no known-secret/signature matches. The local Web candidate was present and included in this audit. No raw `assets/private/` paths occur in branch history checked. |
| Scope of evidence | No cloud deployment, pod allocation, live endpoint write, gameplay change or new internet acceptance test was performed for this review. |

## Reproduction evidence

Sanitized local output: `build/conventions-safety-probes.json`; suite output: `build/conventions-review-worker-tests.log`. `build/conventions-review-snapshot-path.txt` records the temporary source snapshot used for the offline probes, with source hashes and `probe.mjs`. These files are ignored evidence, not public credentials or production code. The snapshot includes synthetic credentials only in the probe and makes no network requests. Local temporary evidence may later be removed; the steps and expected outcomes above are the durable reproduction record.

Recheck findings against later implementation changes before treating this dated review as current status. Source and exported-build versions remain separate; no claim is made that the in-progress diagnostics code is the currently hosted build.

## Local follow-up resolution

Both P2 findings are addressed in the current uncommitted checkout. Room scheduling now preserves the earliest actual seat/lifetime/journal deadline; the public-handler regression sends 45 diagnostic uploads at 15-second intervals, services due alarms, and verifies removal at 90 seconds while uploads continue through 675 seconds. This supplements the earlier earliest-deadline regression.

Wasm `destroy()` now requires exact membership in the bridge-owned set before invoking the export. Invalid numeric aliases, fractional/string/nonfinite values and duplicate destruction are harmless no-ops. A regression executes the production boot code against the actual prepared Wasm and verifies a second instance and the live registry survive. It failed against the pre-fix bridge and passes with the guard. Raw offsets remain subject to the documented caller lifetime rule after storage reuse; this is not a generational handle redesign.

The separate TODO replica rejoin defect was also reproduced and patched: inactive-to-active snapshots trigger attack cues only for a currently active attack, while continuous-actor attack-ID changes retain their existing behavior. Native and Wasm regressions cover idle rejoin, the next real attack and joining mid-attack. No wire/ABI version changed. These are local fixes, not deployment evidence; earlier review observations above describe their original snapshot.
