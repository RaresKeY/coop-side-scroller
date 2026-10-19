# Verification and acceptance

Recorded evidence as of **2026-10-19**. This is a consolidated record of completed checks, not a claim that every suite was rerun for each documentation change. Implementation contracts live in the focused specs; commands and requirements are in [builds and targets](build-targets.md).

## Supported evidence boundary

| Surface | Recorded result | Limit |
| --- | --- | --- |
| C/C++ core | Linux x86_64, C11 consumer, standalone host/replica, Debug/Release CMake and sanitizer tests pass | Other OS/architectures not tested |
| Wasm boundary | Import-free wasm32 ABI and full native/Wasm trace match pass | One bounded trace/toolchain set; no deterministic-lockstep claim |
| Godot native | Actual GDExtension, two-process ENet combat and keyboard/delay lab pass | Native/LAN transport, not browser NAT traversal |
| Browser gameplay/UI | Chromium keyboard movement/jump/attack and native text/copy dialogs pass | Firefox, touch and gamepad acceptance absent |
| Private lobby + TURN | Hosted Create/Join and workstation↔Runpod Chrome movement/combat pass | Forced relay on one two-network route; direct/fallback and restrictive networks unverified |
| Unity/Unreal/custom engines | Integration guidance exists | No delivered/tested engine adapters |

## Core and native adapter

`tests/core.sh` passes native ASan/UBSan contracts, C11 ABI consumption, standalone replication and Wasm boundary checks. Coverage includes invalid configuration/input/authority, handle exhaustion, queue and buffer bounds, malformed/truncated/stale packets, atomic snapshot application, modular sequence wrap and incomplete/replayed staged receives. Repeated byte writes do not satisfy missing receive bytes.

The tested 600-tick native/Wasm host/replica trace matches **all 35,200 message bytes** and final state: tick 600, dummy HP 0 and guest x=667952 milli-pixels. The summary hash is diagnostic; byte equality is checked directly. This is not proof across every compiler, architecture or input. CMake Debug/Release each pass three CTest cases; inspected exports use `ec_v1_*`. Wasm has zero imports and typed view copying into caller-owned module memory is tested.

`tests/native_adapter.gd` exercises the actual GDExtension: a fixed tick moves host x=180000→182833, invalid/overflowing operation arguments reject, and reentrant event draining is safe after the completed call. JavaScript boundary regressions reject non-integer/out-of-range arguments and invalid bridge handles. The build freshness check blocks on the publication lock and succeeds after atomic receipt publication; this does not support replacing an extension inside a running engine.

`tests/network.sh` verifies independent native host/guest cores, opaque byte messages and replicated combat. `tests/lab.sh` additionally exercises both keyboard schemes, 50 ms application delay each way, measured RTT/snapshots and GPU viewport captures. Renderer evidence selects NVIDIA RTX 2080 Ti. The harness approaches the dummy by authoritative position, avoiding a wall-clock-only combat assumption.

## Character presentation

All 61 retained frames in both directions were captured and inspected in the actual game scene (**122 full-scene images**), plus 79 core-driven jump/attack ticks. Playback checks cover all 17 held-jump/landing poses, attack contact timing and mirrored/ground anchors. Source art hashes are unchanged. The six-case GPU comparison against temporary 8× nearest-copy/linear references has maximum channel difference 0; a shifted reference is rejected. This is bounded sampling evidence, not a performance benchmark or complete GPU matrix. Exact rules and retained evidence are in [character presentation](character-presentation.md).

## Browser setup and UI

`tests/connections.sh` passes bounded/versioned envelope and credential validation, role/session matching, reset cleanup, simulated gathering/connect/disconnect deadlines, stale callback rejection, Menu restoration and lobby cancellation. It also checks that completed directory cleanup does not terminate connected gameplay. Simulated connection states are not route acceptance.

`tests/web.sh` drives actual Godot keyboard input into the independent Wasm core. Movement/jump/attack and dummy damage pass. `--clipboard-check` covers acknowledged copying, denial/timeout fallback, real DOM text entry, focus, cancellation, detached-field erasure and delayed completion. The native access-key dialog round trip and single-line room-name selection/confirmation pass. Dialogs keep game context visible over a dimmed backdrop.

Desktop UI captures cover 1920×1080, 1280×720, 960×540 and 854×480. The clipboard fallback captures and smallest/largest lobby/Host views were visually inspected, including maximum-length room names. These checks do not establish Firefox remote-desktop clipboard compatibility or mobile/controller usability.

## Service and network acceptance

Thirteen offline Worker/room tests and eighteen Cloudflare operator tests pass. They cover authorization/origin/expiry, bounds, concurrent guest reservation, capacity, idempotent requests, seat isolation, immutable/session-matched signals, lease/alarm/leave/connected cleanup, and storage migration. All 32 rooms with near-maximum offers/answers fit separate SQLite records. Live issuer checks return 401 for invalid bearer, 403 for wrong origin and 200 with temporary no-store ICE for authorized requests.

`tests/browser_relay.py` verifies two actual Godot windows with independent cores, selected relay/relay candidates, bidirectional traffic, movement and guest combat. `--lobby` exercises automatic Create/Join without connection-code copying and completed signaling cleanup. The hosted two-window run recorded shared HP 12→11 and ICE RTT 151–155 ms.

### Separate-network private lobby

`tests/browser_lobby_cross_network.py` passed against **Pages `8cf749d`** with a hardware-rendered workstation Chromium host and a Runpod Chrome 141.0.7390.54 guest using intentional Mesa llvmpipe rendering. Both entered the key through the native DOM dialog and connected using the actual room list/Create/Join controls. No offer/reply copy wrapper was used.

Both selected routes were relay/relay under relay-only policy, with bidirectional bytes and ICE RTT **218 ms / 228 ms**. Independent cores each had two actors. Guest movement and attacks replicated (**HP 12→9**), followed by host movement replicated back. Final sampled positions matched: host x=230994 and guest x=673618 milli-pixels. Different sampled ticks reflect observation timing, not lockstep. Both-ready signaling cleanup occurred before the gameplay checks.

Directory/join/connected full-scene captures were visually inspected. Safe evidence is retained locally as `build/lobby-cross-network.json`, `build/lobby-cross-network-*.png` and `build/lobby-cross-network-hosted-hashes.json`. The disposable controller was deleted after recovery; the separate user-owned Firefox desktop was not controlled. The first harness attempt clicked Create before Godot consumed the HTTP completion; waiting for the UI transition resolved that harness race.

Earlier manual pairing also passed workstation↔Runpod relay combat (HP 12→10, ICE RTT 161–179 ms). That harness captured Copy output in memory and used DOM entry, so it did not verify human clipboard transfer. It remains useful as independent diagnostic-path evidence, not the primary player flow.

## Publication and evidence handling

The recorded Pages `8cf749d` HTML/PCK/engine Wasm/core Wasm/JS bridge hashes matched the reviewed candidate, and hosted UI/gameplay checks passed. The subsequent cross-network run verified the served artifact hashes separately. Source commits and Pages commits identify different artifacts; current working-tree contents alone do not establish what is hosted. Repeat hash and hosted runtime checks for a new deployment.

Source/Git-object audits compare all stored objects and public source candidates against known private values/Base64 forms and selected credential signatures; the recorded publication checks found no matches. An audit without a local Web export does not cover export bytes; those were checked during their publication. This is a scoped audit, not a guarantee against every unknown secret format. Licensed raw art stays excluded from source.

Ignored `build/` reports/captures are local evidence, not distributed source. Each cross-network harness keeps a separate `*-latest.json` for the current attempt and a historical successful report. Check the latest result explicitly: Gamescope may exit successfully after a failed child test. Manual-harness startup interruption can leave `running`; the lobby harness records preflight failure without erasing prior success. No credentials, SDP or candidate addresses belong in reports.

## Still unverified

Firefox and broader browsers/devices; selected direct paths and automatic fallback; blocked UDP with TURN TCP/TLS-only; real-browser expired/revoked credentials; interrupted connectivity, host exit/reload/rejoin and network changes; longer sessions and sustained loss/load. Reconnect/ICE restart, credential refresh, prediction/interpolation and host migration are not implemented. One successful workstation↔Runpod relay session does not establish general NAT reliability. Future work is tracked in [BACKLOG.md](../BACKLOG.md).

Room-error diagnostic build `ab9facf` passed connection/setup regressions (HTTP status/code formatting and rejection of arbitrary response text), local Chromium startup/input, publication audit, Pages build completion, hosted HTML/PCK/engine/core/bridge hash comparison and hosted Chromium startup/input. This validates diagnostic presentation and publication, not the cause of the reported room failure.

Connection diagnostics: 17 offline Worker/lobby/diagnostic cases and the Godot connection/setup suite pass; the external Cloudflare operator passes 19 tests. Live two-browser automatic private-lobby relay gameplay passed (replicated movement and dummy HP 12→11), followed by selected-route sampling and a forced-disconnect upload check. Operator retrieval saved browser/room/cleanup entries, including an explicit failure event and transport samples, to ignored `build/diagnostics-latest.json`. Account Observability queries returned 403; the separate-key bounded journal lookup is verified instead. These checks do not establish delivery under lost internet or arbitrary networks.
# In-flight lobby sync regression

The local connection setup suite passes a regression where two prior sync errors are followed by ICE connecting while the third HTTP request is outstanding. A missing-room response preserves the connected peer and hides setup. The Web candidate exports successfully. A live local two-browser run reached connected peers and replicated movement/combat assertions, then timed out collecting selected-route statistics; that run is not a full relay acceptance pass. This verifies the client race fix, not the cause of an unmatched tester screenshot reporting `room_expired`.

Investigation of collected client attempt `bade8722708900aa` found a connection failure after connected-room cleanup; the existing relay harness intentionally closes the host after gameplay checks, so that failure is consistent with test injection, without a definitive per-attempt injection marker. An independent regression reproduced a real lifecycle defect: a sync response during a temporary ICE disconnection could terminate an established session before its ten-second recovery grace. The lobby now retains establishment for each room. Godot 4.7.2 headless connection/setup checks pass for disconnection during an outstanding sync, establishment across polls, grace expiry, reset isolation and the unchanged three-error limit before connection. A separate Web export with matching 4.7.2 templates succeeds; 18 Deno Worker/lobby/diagnostic tests pass. The concurrent-join test now checks the actual rejected seat rather than assuming which caller loses. These are contained local checks, not new live-browser or arbitrary-network acceptance. Evidence is retained in ignored `build/failure-investigation/`; no deployment was performed for this fix.

Diagnostic Web candidate `d02c08e` was pushed to `gh-pages`. Its Pages deployment is still queued/unverified; retain `build/web` until hosted hashes and a hosted runtime check pass. The publication tool reached its 60-second wait deadline without a deployment error.

## Publication tool regression checks

The offline Python deployment suite passes eight tests covering exact-commit completion, failed builds, status API retries, hash mismatch, all-file verification, symlink rejection, lock exclusion and a real bare-Git concurrent-push race. The race leaves the source checkout intact and rejects a stale remote-tip lease. The Worker/diagnostics suites pass 18 tests; the browser ICE helper passes five Deno tests with read access limited to its source. Godot connection/setup regressions and Web export pass. Chromium native text-entry/clipboard checks pass at 1920, 1280, 960 and 854 widths, with actual Wasm movement. These checks do not deploy a new Pages candidate or prove GitHub runner availability.

Failed-attempt diagnostics (`diagnostics-v2`): five browser-adapter contract tests cover unconnected failed pairs, gathering states/candidate counts, scheme/code redaction, bounded history, unavailable stats and stale-peer isolation. Eighteen Worker tests and the Godot connection/setup suite pass. A real Chromium probe using an unreachable STUN name completed gathering with zero usable candidates and emitted no native ICE-server error; its pre-connection states/counts/stats were uploaded and retrieved by diagnostic ID. Numeric 701 handling is covered by deterministic adapter tests, not claimed as observed in that browser probe. The browser smoke/input check also passed. These events narrow the failure stage and do not establish a particular NAT/router defect.

With failed-ICE collection enabled, the first two-browser regression connected and replicated gameplay but timed out reading selected-route statistics. A repeat passed automatic private-lobby signaling, relay/relay route checks, movement/combat, production-helper sampling, diagnostic uploads and an explicit disconnect report. No general NAT reliability claim follows from either bounded test.

## Firebase static deployment

The new Firebase Hosting project/site `ember-bridge-playtest` serves https://ember-bridge-playtest.web.app/. Hosted HTML, engine JS/PCK/Wasm, core Wasm and bridge SHA-256 match the prepared candidate. Hosted Chromium startup and real keyboard movement pass. The Firebase origin receives successful lobby CORS preflight and authenticated directory responses from the existing issuer after its allowlist update. The hosted same-machine two-browser private-lobby test also passes forced relay/relay traffic, replicated movement/combat, diagnostic uploads and terminal-failure reporting. This does not prove a new cross-network route.

Source review checks: 19 Worker/lobby/diagnostic tests, five ICE helper tests and eight publication-tool tests pass. Diagnostic parsing failures remain HTTP 400, while journal exceptions return HTTP 503; the regression covers GitHub and both Firebase origins. The publication secret audit reports no findings.
