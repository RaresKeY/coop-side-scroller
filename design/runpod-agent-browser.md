# Separate-network browser testing

The game uses the dedicated controller at `~/workspace/tooling/runpod-browser` for automated Runpod testing. That independent project owns the controller implementation, image/template, credentials and pod lifecycle. Its `specs/` and CLI are the operator source of truth. Operate only resources owned by this harness; preserve unrelated browser resources.

## Deployment and test sequence

On the configured workstation, inspect the saved receipt, existing resources and current rates before creating an owned test pod. Reuse the existing **Agent Browser Controller** template; ordinary tests must not create another template. The recorded configuration is CPU3 compute-optimized, 2 vCPUs/4 GB RAM, 10 GB disposable disk and no persistent volume. Current availability/pricing must be checked at execution time.

```sh
cd ~/workspace/tooling/runpod-browser
python3 manage.py status
python3 manage.py catalog
python3 -m unittest -v test_controller.py
# Explicit allocation after resource inspection:
python3 manage.py deploy
python3 manage.py status
python3 smoke.py
```

The controller runs Chrome offscreen on Xvfb with intentional Mesa llvmpipe rendering. It exposes only bearer-protected HTTPS on the Runpod proxy; raw CDP/ChromeDriver/display ports are not public. Wait for application readiness, not only pod RUNNING status. The smoke checks controller authorization, actual input, WebGL2 and public-game movement; it is not itself a co-op test.

Then run the actual lobby test from the game checkout:

```sh
cd ~/workspace/coop-side-scroller
gamescope --backend headless -W 960 -H 540 -w 960 -h 540 --xwayland-count 1 -- python3 tests/browser_lobby_cross_network.py
```

Both peers load the public Pages game; no local export is required. The workstation browser uses hardware rendering. The remote browser uses the separate controller and software rendering. The harness creates its own room, joins only the captured room ID, and verifies automatic signaling, independent cores, signaling cleanup, relay routing and replicated movement/combat. It accepts both the older Godot key field and current native DOM key entry.

`tests/browser_cross_network.py` exercises advanced manual pairing instead, capturing outgoing Copy text in memory and entering it through the native dialog. Neither harness tests the streamed Firefox desktop clipboard. Browser game coordinates account for aspect-fit letterboxing; DOM dialog coordinates use browser pixels directly. Remote key holds include controller request latency and are not exact tick durations.

Inspect `build/lobby-cross-network-latest.json` for the current result and recover the report/screenshots before teardown. Gamescope's exit code alone is insufficient. After testing, delete only the saved owned controller pod:

```sh
cd ~/workspace/tooling/runpod-browser
python3 manage.py delete
```

Deletion verifies the exact saved ID/name and retains the template. Preserve unrelated pods and volumes. If creation fails ambiguously, inspect remote state before retrying; do not allocate duplicates. The workflow has no automatic shutdown schedule, so teardown remains an explicit operator step.

## Credentials and control boundary

The account key remains in `~/.runpod/config.toml`; the per-pod controller receipt remains in owner-only `~/.config/runpod-browser/receipt.json`. The game harness reads the playtest key from the separate Cloudflare access file. Values must not enter argv, URLs, logs, screenshots or this repository.

`client.Browser` provides authenticated navigation, allowed CDP commands, input and screenshots. The API is trusted-operator control: page evaluation can execute JavaScript and issue browser requests, so the initial navigation allowlist is not a network sandbox. Use a dedicated disposable profile. The client supplies a browser-compatible User-Agent because Runpod's proxy rejected Python's default during initial integration.

No cloud resources are created/deleted by the game harness itself. Controller code/image changes belong to its owning repository and need its smoke checks; they are not game adapter changes.

## Evidence and limits

Automatic lobby Create/Join and forced-relay combat passed workstation↔Runpod Chrome against Pages `8cf749d`: ICE RTT 218–228 ms, HP 12→9 and matching final positions. The earlier manual route also passed. [Verification](../specs/verification.md#separate-network-private-lobby) owns the complete acceptance record and evidence paths.

Those published-build tests do not establish Firefox compatibility, manual remote-desktop clipboard success, direct-path reachability or general NAT reliability. The later unpublished TLS-only candidate test is recorded in `specs/verification.md`; firewall-level blocked-UDP operation remains untested. Disposable pod IDs and live resource status are operational state, not permanent architecture; read the current private receipt/provider state when resuming work.

## Unpublished local candidate

`tests/browser_lobby_cross_network.py --local-candidate build/web --tls` loads a prepared candidate into both disposable browsers through CDP. `tests/browser_candidate.py` transfers game assets in bounded chunks; the remote transfer uses the authenticated controller. It reuses only the large hosted Godot engine Wasm after checking its SHA-256 against the local file, supplies local fetch responses and loads the local HTML/JavaScript. The bridge's script-relative core URL is made absolute for its test-only Blob script. The Pages origin is retained for the existing service allowlist, but no hosting files or backend services are changed. Reports record candidate hashes and selected relay protocol.

The TLS assertion checks exclusive TLS-443 configuration and actual selected `relayProtocol: tls` on both peers, plus gameplay and production diagnostic rates. This is not a firewall-level blocked-UDP test. The remote test closes its page through the controller navigation API before explicit pod deletion.

Candidate tests also verify embedded build context against `build-info.json`, mark reports `test=runpod`, capture sanitized diagnostic schema/attempt/context/status, and require accepted uploads with at most one legacy-schema rejection per page. Browser-only harnesses mark `test=browser`; old hosted builds cannot upload this new context. Candidate engine reuse is hash-checked; reports preserve exact transferred-file hashes.

Relay acceptance uses whole-transport byte totals separately from the selected-pair route metadata, since incoming traffic can be accounted to another pair. The lobby harness accepts missing build context on legacy public builds; candidate builds still require matching metadata. Browser relay tests permit only one explicit v3 `invalid_diagnostics` rejection followed by successful legacy uploads.
