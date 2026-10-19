# Private playtest lobbies

Owners: `src/private_lobby.gd`, browser menus in `src/main.gd`, `server/turn/worker.mjs` (`PrivateLobbies`), `server/turn/lobby.test.mjs` and `tests/browser_relay.py --lobby`.

## User flow

Enter the private playtest key in the masked menu field once per page load, select a route, and open **Private rooms**. Create a named room or click Join on a listed room. The list is available only to key holders. Both peers automatically obtain temporary TURN credentials (unless direct-only is explicitly selected) and exchange versioned SDP/ICE. No manual invitation/reply copying is required. A displayed eight-hex-character room ID distinguishes names; it is not a password and cannot authorize access by itself.

Back / leave room cancels setup and removes the room best-effort. Menu temporarily hides a pending lobby; closing Menu restores it. Solo invalidates pending HTTP results and RTC callbacks. Setup panels suppress gameplay input. List refresh preserves existing buttons/focus when contents are unchanged; long room names clip within a scroll list. Manual pairing remains behind **Manual connection (advanced)** for diagnostics and existing tests. Native ENet and the two-keyboard lab are unchanged.

## Service contract

The existing tagged credential Worker also accepts `POST /v1/lobby` over HTTPS. Every action requires the same Origin allowlist, bearer playtest key and server-enforced key expiry as `/v1/ice`. CORS preflight permits POST, Authorization and Content-Type. No key, seat token or SDP is placed in URLs, page storage, source, logs or public listings. Responses are no-store. Public Pages contains only endpoint addresses.

JSON requests have `version:1` and `action:list|create|join|sync|leave`, bounded to 65,536 bytes. `create` uses a trimmed room name (1–32 characters, no ASCII controls) and a client-generated random 128-bit `seat`; retries with the same host seat are idempotent. `join` supplies an eight-uppercase-hex `id` and a new random seat. `sync`/`leave` require the reserved seat. Sync may supply a versioned Base64 `signal` and Boolean `ready`; replies include the partner's signal, player count and completion state. Signal bodies reuse the manual envelope's game/version/protocol/role/session/SDP/candidate limits. The total request bound may be reached before the envelope maximum. Offers and answers are immutable after publication; mismatched answer sessions reject.

One SQLite Durable Object named `private-playtest-v1` serializes reservations with `blockConcurrencyWhile`. It holds at most 32 setup rooms and exactly two seats per room. Each room is stored under its own key, comfortably below SQLite’s 2 MB value cap even with two maximum-size signals; a directory-wide value could exceed that cap. Only changed room records are written. Initial single-value records migrate on access without dropping reserved seats or signals. Full rooms disappear from listings, and simultaneous third joins reject. Seat ownership is separate from the shared tester key: another key holder cannot read a room's signals or delete it merely by knowing its listed ID. A shared key does not provide individual tester identity, bans or trust between invited testers.

Visible directories poll every five seconds; setup peers sync every two seconds, with no overlapping requests per client. Explicit Refresh retries listing errors. Three setup sync failures return to setup. HTTP has a ten-second timeout, bounded responses and no redirects. The directory's per-location limits are 120 requests/minute/IP and 600/minute/shared key, separate from the existing TURN issuance limits. These are not global budget caps. An open directory can generate approximately 720 requests/hour/viewer; setup normally lasts seconds. Hibernating WebSockets are deferred if usage justifies them.

Rooms have a 90-second lease for each occupied seat and a ten-minute absolute setup lifetime. Reads prune expired rooms; a Durable Object alarm also cleans abandoned rooms. Background-tab suspension can expire an unfinished room. Leaving either seat closes setup; create a fresh room to retry. Once both browsers report connected, the directory deletes the room and its signals. A remaining peer treats an absent room after connection as completed cleanup, not a gameplay failure. Lost responses are safe to retry for list/join/sync/leave/create with the same seat. The UI cancels failed entry attempts; an uncertain create expires by lease.

Active storage deletion is not a promise about Cloudflare's provider-level backups/SQLite recovery retention. Only bounded ephemeral signaling is stored; account keys and TURN credentials never enter the directory. The Worker receives scoped TURN secrets separately for issuance.

## Engine and network boundaries

The service carries connection setup only. WebRTC data channels carry gameplay directly where possible, or through TURN when required. The C++ core remains host-authoritative, transport-independent and engine-independent. Every browser has its own Wasm core. No simulation, clocks, rendering, input capture or physics moved to Cloudflare. Signaling availability is unnecessary after connection; TURN may still be needed for the session's traffic.

No host migration, reconnect/ICE restart, individual accounts, public lobby discovery, password-per-room, join-by-link, TCP-only acceptance or broad NAT reliability guarantee is implemented. Host exit ends play. The tester key still needs one private transfer and expires under the existing invitation policy.

## Deployment and verification

Use the existing operator's tagged deployment with `--lobbies`:

```sh
cd ~/workspace/tooling/cloudflare-api
./bin/build
./cloudflare test
./cloudflare worker-deploy coop-side-scroller-issuer --script ember-coop-credentials --source /absolute/path/coop-side-scroller/server/turn/worker.mjs --lobbies
./cloudflare worker-probe coop-side-scroller-issuer
```

The operator adds the `LOBBIES` binding, lobby rate limiters and initial `ember-lobbies-v1` migration using `new_sqlite_classes`. It checks the existing binding type/class and does not repeat namespace creation or remove bindings accidentally. The settings endpoint does not expose the migration tag. No paid plan or unrelated service is changed. Runtime dependencies remain package-free.

```sh
deno test --no-config server/turn/worker.test.mjs server/turn/lobby.test.mjs
# Prepared Web build, actual game and live protected backend:
gamescope --backend headless -W 960 -H 540 -w 960 -h 540 --xwayland-count 1 -- python3 tests/browser_relay.py --lobby
```

Thirteen offline Worker tests cover auth/origin/expiry, concurrent joins, capacity, idempotent creation, membership isolation, malformed/immutable signals, session mismatch, lease/alarm cleanup, connected deletion, migration and all 32 rooms carrying near-maximum-size signals. Live two-window Chromium lobby→relay movement/combat passes with independent cores, relay/relay candidates, bidirectional bytes and shared HP 12→11 (126–149 ms ICE RTT in the first run). This verifies the deployed SQLite binding as well as automatic signaling. Previous separate-network manual-pairing acceptance remains historical; a new cross-network/Firefox lobby run is not claimed.

Provider references: [SQLite value limits](https://developers.cloudflare.com/durable-objects/platform/limits/), [SQLite storage and alarms](https://developers.cloudflare.com/durable-objects/api/sqlite-storage-api/), [migration contracts](https://developers.cloudflare.com/durable-objects/reference/durable-objects-migrations/), [plan availability](https://developers.cloudflare.com/durable-objects/platform/pricing/). SQLite Durable Objects are available on Workers Free; actual usage still needs monitoring.
