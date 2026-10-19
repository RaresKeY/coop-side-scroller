# Protected TURN credential service

Owners: `server/turn/worker.mjs`, `src/relay_credentials.gd`, browser setup in `src/main.gd`. Account administration is owned separately by `~/workspace/tooling/cloudflare-api`; its private configuration is outside both repositories.

## Contract and deployment

`POST https://ember-coop-credentials.ember-bridge-playtests.workers.dev/v1/ice` accepts an empty body and `Authorization: Bearer <private playtest invitation>`. Allowed origins are the exact GitHub Pages origin and fixed development origin `http://127.0.0.1:27841`. CORS is additional restriction, not authentication. OPTIONS permits only POST/Authorization. No GET, URL credentials, wildcard origins, cookies, analytics or credential logging.

The prototype invitation is random 256-bit access with seven-day server-enforced expiry. It is held privately in `~/.config/cloudflare-api/access-coop-side-scroller-issuer.json`; distribute only to intended testers. The game uses a masked menu field and memory only, with no persistence or URL parameter. This is a friends-only prototype bearer gate, not individual user accounts. The Worker receives scoped TURN key secrets; the account API token never enters the Worker or browser.

Successful JSON: `{version:1, iceServers:[{urls:[...],username:...,credential:...}], expiresAt:<Unix seconds>}`. Credentials last 3600 seconds, minted on each new connection. Response is `Cache-Control: no-store, private`. Only Cloudflare STUN/TURN addresses with ports 3478/5349/443/80 and UDP/TCP are forwarded. Port 53 is filtered for browser compatibility. The Godot adapter validates the bounded response, URL list and expiry before WebRTC initialization. Master tokens and invitations are never returned.

Failures: 400 body, 401 bearer, 403 origin/expired invitation, 404 path, 405 method, 429 rate limit, 502 upstream, 503 incomplete setup/limiter unavailable. Provider bodies/exceptions are withheld; only bounded status/stage classifications may be returned. Outbound issuance has an eight-second timeout and 64 KiB response cap. `redirect: manual` rejects 3xx responses without forwarding Authorization; Workers does not implement Fetch's `error` redirect mode.

Workers rate-limit bindings apply 12 requests/minute/IP and 24 authenticated requests/minute/invitation. These are permissive, eventually consistent per-location limits, **not a global spending cap**. Invitation leakage still enables relay usage until expiry/revocation. Provider billing/usage monitoring and stronger individual identity/global budgets remain operator work before a broader release. No paid plan was enabled by this implementation.

## Browser behavior

Menu selects Direct + relay fallback (default), Relay only (test), or Direct only (no invitation, Google STUN). Host/Join obtains fresh ICE configuration asynchronously before creating the peer. Solo/reset invalidates pending requests so stale replies cannot create a session. The simulation/C ABI does not know about HTTP, credentials, WebRTC or Cloudflare. Each page owns its own Wasm core. Signaling normally uses the authenticated [private lobby service](private-lobbies.md) in the same Worker; advanced manual pairing is retained.

Do not promise one-hour uninterrupted sessions: refresh/ICE restart is not implemented. Start a fresh session before credential expiry. TURN improves NAT reachability, but corporate filtering can still block all routes. Native ENet does not use TURN.

## Operator commands and tests

From the Cloudflare operator project:

```sh
./bin/build
./cloudflare test
./cloudflare worker-check coop-side-scroller-issuer
./cloudflare worker-probe coop-side-scroller-issuer
./cloudflare worker-deploy coop-side-scroller-issuer --script ember-coop-credentials --source /absolute/path/coop-side-scroller/server/turn/worker.mjs --lobbies
```

Deployment checks ownership tags before replacing a Worker and uses API multipart bindings directly; no Wrangler or JavaScript packages. Secrets remain in owner-only config and secret bindings. Do not rerun key creation to recover a failed operation: inspect remote state/private journal first.

From the game project:

```sh
deno test --no-config server/turn/worker.test.mjs
python3 tools/audit_publication.py
# Prepared Web export; actual two-page game test, offscreen:
gamescope --backend headless -W 960 -H 540 -w 960 -h 540 --xwayland-count 1 -- python3 tests/browser_relay.py
```

The audit scans every locally stored Git object (including other branches/unreachable objects), public source candidates and the Web export for known private Cloudflare/Runpod values and their Base64 representations and selected credential signatures. Comparison happens inside an offline read-only container; only locations/counts are printed. This is a scoped audit, not proof against every possible unknown secret format. Raw CraftPix files must remain ignored; compiled game resources may contain licensed art.

Live endpoint checks passed 2026-10-19: unauthorized 401, wrong origin 403, authorized 200 with temporary ICE and no-store. Five offline Worker tests and sixteen operator tests pass. The two-window Chromium game test passes: both selected candidate types are relay, bytes flow in both directions, independent cores each have two actors, and guest combat reduces the replicated dummy from HP 12 to 11. Observed RTT was 132–180 ms in one run. Separate-network acceptance is recorded separately; endpoint issuance alone does not prove a usable relay.

Sources: [Cloudflare temporary credentials](https://developers.cloudflare.com/realtime/turn/generate-credentials/), [Worker redirect modes](https://developers.cloudflare.com/workers/runtime-apis/request/), [rate-limit semantics](https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/).

2026-10-19 separate-network follow-up: `tests/browser_cross_network.py` passes workstation host ↔ Runpod Chrome guest against the public game, with selected relay/relay candidates on both peers, bidirectional traffic, independent Wasm cores, movement and shared HP 12→10. Observed ICE RTT was 161–179 ms. This uses automated in-memory code transfer and does not verify Firefox clipboard handling, direct connectivity or blocked-UDP/TLS-only operation. Evidence and remaining limits are in [verification](verification.md). The publication audit also compares the dedicated controller's external private receipt when present, and accurately reports whether a local Web export exists.
