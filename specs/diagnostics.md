# Connection diagnostics

Owners: `src/diagnostics.gd`, hooks in `src/main.gd` / `src/private_lobby.gd`, browser route helper in `adapters/web/ember_core_bridge.js`, `server/turn/worker.mjs`, and the external Cloudflare operator's `worker-logs` command.

Each browser lobby entry or new manual connection attempt gets a random 16-hex diagnostic ID. Lobby requests carry it separately from seat credentials. Browser reports identify build `diagnostics-v2` (the endpoint also accepts `diagnostics-v1`) and retain the last 64 sequential events in memory: elapsed time, role, room ID, requested route, HTTP action/status/allowlisted error, connection state, tab visibility, failure category and aggregate RTT/RPC/snapshot-gap/actor counters. The browser helper records ICE gathering/connection state transitions, numeric ICE-server error codes and server scheme only, local candidate counts by type, candidate-pair counts by outcome and aggregate checks sent/responses received. It samples these before connection and drains buffered events before failure teardown, so failed attempts can be investigated. Connected peers also expose selected candidate types, protocol and RTT. Missing/closed-peer stats are reported as unavailable. The helper queue is bounded to 64 events; old peers and delayed old samples cannot contaminate a replacement attempt. A 701 server error is an observation of that server attempt, not a claim that every route failed or a diagnosis of NAT type. No SDP, candidate addresses, access keys, seat tokens, room names, inputs or arbitrary error messages enter reports. Snapshot gaps are not a general packet-loss measurement.

The menu's **Copy connection diagnostics** uses the existing acknowledged clipboard/fallback dialog. Reports survive returning to Menu until the next attempt. Failure messages include the diagnostic ID. Authenticated uploads to `/v1/diagnostics` occur on connection-state changes, failures, leave and 15-second active-game summaries, with one request in flight, an eight-second timeout and at most 240 attempted batches per attempt. Reports are best effort; abrupt tab closure, suspension, expired access and lost internet can prevent delivery. The copyable memory buffer remains useful when uploading fails. Successful batch acknowledgement advances a sequence watermark; later events remain pending.

The endpoint shares the exact Origin allowlist and invitation gate but uses separate rate-limit bindings (20/minute/IP, 120/minute/shared). These are per-location limits, not global budget caps. Strict schema validation rejects unknown fields, arbitrary text, oversized histories and invalid values. Playtest-key holders can submit reports but cannot read stored reports. Browser reports are untrusted diagnostics, not authenticated player identity.

The existing `PrivateLobbies` Durable Object holds a separate journal key, bounded to 256 entries and 256 KiB total, with a seven-day maximum age. Capacity eviction can remove entries earlier. Routine successful directory polls and empty syncs do not occupy the journal. Meaningful lobby actions, signaling publication, readiness, failures and cleanup reasons are retained, alongside browser batches. Room deletion does not delete the journal. Reads and alarms exclude/prune old entries. No additional service or namespace is provisioned. This retention does not describe provider backup retention.

Structured console events also go to enabled Cloudflare Workers Logs; automatic invocation logs are disabled to minimize request metadata. Provider retention/usage remains separate from the journal. Account API log-query access was rejected with HTTP 403; working retrieval therefore uses the private journal, not the Observability API.

Operator reads use a separate random secret in owner-only `~/.config/cloudflare-api/diagnostics-coop-side-scroller-issuer.json`, deployed as `DIAGNOSTIC_READ_TOKEN`. This key is never given to browsers/testers. The existing containerized operator reads it privately:

```sh
cd ~/workspace/tooling/cloudflare-api
./cloudflare worker-logs coop-side-scroller-issuer --minutes 60
./cloudflare worker-logs coop-side-scroller-issuer --attempt 0123456789abcdef --minutes 1440
```

From the game checkout, `python3 tools/read_diagnostics.py [--attempt ID] [--minutes 60]` saves sanitized evidence to ignored `build/diagnostics-latest.json`.

Attempt lookup includes related room events while those links remain in the journal. Output contains sanitized structured diagnostics and can be redirected to ignored `build/` evidence. The read endpoint uses the same rate bounds and currently requires the playtest invitation period to remain valid. Deployments preserve the private read secret. No paid-plan or token-permission change is made.

Tests: `deno test --no-config --allow-read=adapters/web/ember_core_bridge.js tests/ice_diagnostics.test.js`, `./tests/web.sh --ice-diagnostics-check` (real unreachable STUN server with server-error or zero-candidate gathering evidence, unconnected-peer stats, upload and metadata redaction), `server/turn/diagnostics.test.mjs`, journal cases in `server/turn/lobby.test.mjs`, and `tests/connections.sh`. Actual browser upload, retrieval and hosted-build evidence belongs in `specs/verification.md`.
