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

## Local TLS compatibility candidate — 2026-10-19

Prepared with `python3 tools/build_core.py` and `tools/build_web.sh`. `tests/connections.sh` passed, including TLS-only filtering, no non-TLS fallback and unchanged validated credentials. All six browser-diagnostic unit tests passed, including actual counter deltas, missing stats, pair/counter resets and private metadata redaction. Controller security tests and its browser/input/WebGL/game smoke passed.

`tests/browser_lobby_cross_network.py --local-candidate build/web --tls` passed workstation Chromium (RTX 2080 Ti hardware renderer) ↔ disposable Runpod Chrome 141 (intentional llvmpipe). Both peers used relay-only policy, exclusive Cloudflare TLS-443 URLs and selected `relayProtocol: tls`; candidate protocol remained UDP as expected for the relay-side candidate. Automatic Create/Join, signaling cleanup, guest movement/combat (dummy HP 12→10), host movement and matching replica state passed. Selected-pair RTT was 111–113 ms at route capture; later production diagnostic samples reported 108–145 ms. Sampled byte rates were 5,693–6,338 bytes/second per direction, with 51–67 selected-pair packets/second. These counters are not total link traffic or provider billing. All observed diagnostic uploads returned HTTP 200.

Evidence: ignored `build/tls-cross-network.json`, `build/tls-cross-network-host.png`, `build/tls-cross-network-guest.png` and `build/tls-cross-network-run.log`. Candidate PCK SHA-256: `157af04bbf4202fa12787f539991edb2cf38eb3eef10e416a5ab18d2f59e8265`; browser bridge SHA-256: `c50bbe57f5a9da7f454105d34a420fea046f3bfc013160e0b7307ed10115d497`. The report contains all candidate hashes. Local assets were loaded through test browser control with the same-origin service allowlist; no public game or Worker deployment occurred. The owned test pod was deleted after evidence recovery; provider inventory and the private receipt confirmed no remaining pod.

Limits: Chromium only, no firewall-level UDP blocking, no packet-loss comparison, no router/ISP fault diagnosis and no general internet reliability claim. This proves the configured TLS route carries gameplay across these two networks.

## Network incident review — 2026-10-19

### Deployment and incident times

All local times below are Europe/Zurich (UTC+02:00). The player estimated a few minutes after the first Firebase deployment while connecting Switzerland–Spain; this is a search window, not a confirmed session identity. Historical diagnostics contain no geography, hosting site or artifact commit.

| Zurich time | UTC time | Evidence |
|---|---|---|
| 17:02:03 | 15:02:03 | Previous successful Pages artifact `ab9facf` built. |
| 17:49:59 | 15:49:59 | Source commit `a700c19`; its browser bridge matches the first Firebase artifact. This alone does not prove every source file. |
| 17:50:43 | 15:50:43 | Artifact commit `d02c08e` created. Firebase PCK and bridge bytes match this artifact exactly. |
| 17:55:28.498 | 15:55:28.498 | Worker version `1c7c08ad-adef-48a4-b884-e4bb9866e0a2` deployed. |
| 17:56:03.665 | 15:56:03.665 | First/only Firebase live release `1792425363665000`, version `d44aa3ed637b4135`; version created 15:55:52.208 UTC, finalized 15:56:03.396 UTC. |
| 17:56:46–17:56:59 | 15:56:46–15:56:59 | Room `DEB80ADD`: both relay-only clients connected, RTT 157–160 ms, then guest connection failure after room cleanup. Matches the documented forced-disconnect test's pattern, but historical reports lack deterministic test markers. |
| About 17:58–18:05 | About 15:58–16:05 | Working incident search window. Attempts `d9d9e11e5ad366af` and `745869fdc6f85bb4` show successful lobby list requests and leave/visibility events, without recorded room creation/join or RTC start. Lost internet can prevent upload, so this does not exclude another attempt. |
| 18:08:11.112 | 16:08:11.112 | Current Worker version `a4033602-189c-4287-9513-bec815156185` deployed, after the working incident window. |
| 18:13:27 | 16:13:27 | Pages finally completed successful publication of `d02c08e` after failed/delayed builds. Earlier successful Pages artifact differed from Firebase; cached tabs remain uncertain. |

Private journal retrieval retained 187 entries spanning 15:26:36–16:47:07 UTC. Report labels `diagnostics-v1/v2` identify schemas, not commits. Firebase PCK SHA-256: `d440f6f93522174168c084d717276b46ab2da2da6e2374eea8d90b96302ab9c3`; bridge: `e5f072072a6d79527d38d4e25b9ea2e87d5efa0869b9c82b0e7255412095b17a`. Sanitized API history and downloaded artifact hashes are retained in ignored `build/network-review/`; journal snapshot in `build/diagnostics-investigation-before.json`.

Cloudflare Observability query returned HTTP 403/provider code 10000 with the existing token. No permissions were changed. The archived authenticated dashboard capture `build/diagnostics-browser-20261019T154043Z/` covers 15:23:50–15:33:23 UTC, before this window; its zero dashboard errors are not incident evidence. The journal and deployment history were accessible. No evidence establishes a router crash, ISP block, a Switzerland–Spain route or a game-caused whole-network outage.

[TP-Link's router guidance](https://www.tp-link.com/us/support/faq/2658/) documents packet-threshold flood protection and legitimate clients being blocked. This makes router filtering a plausible hypothesis, conditional on router logs/model; it is not this incident's diagnosis. [Cloudflare documents TURN TLS on port 443](https://developers.cloudflare.com/realtime/turn/generate-credentials/), supporting the explicit compatibility option. Prefer comparing automatic and TLS-only sessions and checking router blocked-host/WAN link logs at the incident time; do not disable router protection globally on this evidence. Browser offline hints and selected-pair rates cannot identify an ISP outage.

Review found bounded application queues (256 adapter packets), fixed core send cadence and no demonstrated runaway send loop. Independent fixes address late HTTP attempt attribution, earliest room/journal alarm scheduling and inherited-property diagnostic event validation; none is claimed as the outage cause. Build metadata and synthetic-test attribution close demonstrated gaps in the incident evidence. Public deployment remains unchanged during this local investigation.

### Candidate verification and cleanup

The final candidate (source HEAD `eec7a83`, dirty working tree; built 16:59:11 UTC) has gameplay payload digest `8ecba88bc79b8402f701b7ea50649af5766a70a69ff0b0b65c216efad4933a6c`. Native/Web preparation, connection setup checks, eight browser-diagnostic unit tests, 22 Worker tests, nine offline publication tests and the report regression test passed. Build-manifest hashes match the actual payload; publication preflight accepts only the named manifest, not arbitrary JSON. Publication audit found no secrets.

The final workstation–Runpod Chrome run passed automatic lobby pairing/cleanup, replicated movement and combat (HP 12→10 on both peers), exclusive TLS-443 configuration, selected relay/TLS on both peers, matching build context and `runpod` markers. Samples measured 153/176 ms RTT, 5,764–6,142 bytes/second and 53–63 packets/second per direction at the ICE transport scope. Local rendering used hardware NVIDIA; remote Chrome 141 used software Mesa. This does not test the player's router/ISP, geographically reproduce Switzerland–Spain, block UDP at the firewall or establish general internet reliability.

The current v2 Worker rejected the first v3 upload once per browser (HTTP 400); each then uploaded legacy reports successfully (HTTP 200). Private-journal readback confirms attempts `dd519d820fb7fe88` and `05197ddd8e040769`, without failure events. Full build/test/traffic metadata remains local until the prepared v3 Worker is published. Sanitized evidence, screenshots, final manifest and journal readback are in `build/network-review/`.

Earlier checks exposed two harness/measurement limits: remote key pulses stopped just outside combat range (shortened pulses, retained the same gameplay assertions), and selected candidate-pair inbound counters could be zero despite working replicated gameplay. The final run recorded bytes on another candidate pair as well; diagnostics now preserve selected-pair counters separately from whole-transport counters, with independent rate baselines. These observations do not establish the incident cause.

Owned pod `his0rdmkc6q9wg` was deleted after evidence retrieval; API inventory returned no remaining pods. Dedicated reusable template `jd3i2gy4au` remains; no persistent volume was created. No public game/Worker deployment or source commit was made.

### Follow-up: exact 123-record failure window

Filtering the archived journal through 18:34 Zurich reproduces the supplied count exactly: 123 records, three client connection failures (`bade8722708900aa`, `8f4bd346fb2fa3b5`, `73e9e9e0cf80a2a8`) and one gathering failure (`949a5cd16cb1eed0`). The gathering attempt ID exactly matches the retained successful intentional unreachable-STUN probe in `build/failed-ice-browser.json`; it is a synthetic test, not evidence of a player's failed connection. The three connection failures remain consistent with the relay harness's explicit host-close probe, but lack deterministic injection markers in the historical journal.

For latest room `DEB80ADD`, cleanup occurred at 17:56:57.095 Zurich. The guest's sync returned 200 at 17:56:57.124. The **host** then received sync 404 at 17:56:58.959; the **guest** failure batch arrived at 17:56:59.366, followed by guest leave 404 at 17:56:59.406. Combining different peers into a single request/failure sequence incorrectly suggests a direct guest-404 cause. The report's `protocol=udp` describes the candidate; it cannot establish browser-to-TURN relay transport without `relayProtocol`.

Source commit `a700c19` already contains the sticky-established cleanup guard. Current deterministic Godot tests confirm that room errors after connection do not close gameplay, including connection during an outstanding sync and temporary disconnection before its response; the ten-second transport grace still expires normally, and never-connected setup still fails after three sync errors. The follow-up adds explicit lobby-end and pre-teardown failure-source/state/establishment diagnostics, with v2 projection and strict v3 validation. The seven diagnostic-schema cases, connection suite and refreshed native/Web build pass. Exact historical records are preserved in `build/network-review/cleanup-journal-123.json`.

No new Runpod pod was needed for these deterministic lifecycle/diagnostic checks; inventory was empty. The previous cross-network test and deletion remain the latest Runpod evidence, not validation of these subsequent diagnostic additions. Public deployment remains unchanged.

### Review and TODO safety fixes

The review's Wasm-handle alias and the TODO's false replica attack on idle rejoin both failed targeted pre-fix tests. Exact live-handle membership now precedes Wasm destruction; invalid/coercible values and duplicate destruction are no-ops. Replica attack comparisons now account for observed actor lifetimes while preserving cues for a new actor already attacking. Native ASan/UBSan tests, C consumer, standalone example, 600-tick native/Wasm trace parity, Wasm rejoin regressions and the production-bridge real-Wasm handle test pass. No ABI/wire change or general cross-platform determinism claim follows.

The existing alarm fix also passes the review's extended public-handler reproduction: 45 uploads over 675 seconds, with an abandoned room removed at 90 seconds. All 24 Worker tests pass. Evidence: `build/network-review/{handle-before,rejoin-before,safety-core,safety-worker}.log`. Patches and refreshed build remain local; no pod allocation or deployment was required.

### Final local diff review

Review covered the core rejoin fix, Wasm handle guard, TURN route filtering, diagnostic collector/schema, room retention, build metadata and modified browser harnesses. Additional fixes serialize Godot stats sampling, complete every helper callback (JSON null for unavailable/superseded samples), reject out-of-order route/counter completions, preserve the sampling role through teardown, and reject coercible non-string build metadata. Regressions cover delayed old-peer and out-of-order same-peer samples. The older browser harness now tolerates the explicit one-time v3→v2 rejection, accepts absent metadata only for legacy public builds, and uses whole-transport traffic for relay acceptance.

Checks passed: 24 Worker cases, nine ICE-helper cases plus the real-Wasm handle case, ten Python tests, Godot connection/lifecycle checks, refreshed Web export and a local two-browser live relay/replicated-combat/room-cleanup/intentional-disconnect run against the existing service. The v3 first upload returned the expected 400, then legacy uploads returned 200. This is same-workstation browser evidence, not a fresh Runpod or geographic-network test. Earlier native sanitizer/Wasm rejoin regressions remain applicable to the unchanged core patch. Logs are retained under `build/network-review/review-*`. No new service or pod was created, and no deployment or commit was made.

A final harness pass exposed a host-only upload wait after forced browser-peer closure: the guest delivered the terminal failure while no new host upload arrived within that arbitrary window. The test now requires a newly uploaded failure from either peer (not a preexisting event), still rejects unexpected upload errors, and records the injected host-close timestamp and both attempt IDs. This changes test attribution, not connection teardown behavior.
