# Networking service decision

## Selected architecture

The current deployment uses GitHub Pages for static game files and Cloudflare for protected room signaling and TURN credential issuance. A SQLite Durable Object holds the private room directory and bounded offer/answer exchange. WebRTC carries gameplay directly or through Cloudflare TURN. The host browser owns simulation; Cloudflare does not run the C++ game core.

See [architecture](../specs/architecture.md), [private lobbies](../specs/private-lobbies.md) and [TURN service](../specs/turn-service.md) for the implemented contracts. Provider selection is settled for this prototype; deploying a VPS or adding Firebase/Supabase is not outstanding work.

## Alternatives retained for future decisions

| Option considered | Possible role | What would justify revisiting it |
| --- | --- | --- |
| Firebase Realtime Database | Authenticated, expiring signaling records | A project already using Firebase identity/data services; still requires a separate TURN service |
| Supabase Realtime | Private signaling channels and room metadata | A project already using Supabase identity/data services; still requires a separate TURN service |
| VPS signaling plus coturn | Self-managed connection setup and relay | Networking/control requirements that warrant owning certificates, firewall, updates, credentials and bandwidth operations |
| Managed Cloudflare services (selected) | Protected private directory, signaling and temporary managed TURN access | Implemented with the user's configured operator; evaluate measured usage before changing providers |

Old provider quotas and speculative price estimates are intentionally not maintained here. Recheck the selected service's current limits and actual account usage before a purchase or architecture change. None of these options implies unlimited free relay traffic.

## Decisions worth retaining

- Manual offer/reply exchange isolated WebRTC and TURN from signaling during early tests. It remains under **Manual connection (advanced)** for diagnostics; ordinary players use private rooms.
- Signaling, relay and simulation remain separate responsibilities. Switching room storage or relay providers does not change the core ABI or gameplay messages.
- HTTP polling was sufficient for bounded, short-lived two-player setup. WebSockets are a future operational choice, not a missing requirement for automatic connection.
- Directory storage changed from one aggregate value to per-room values so 32 rooms with near-maximum signals fit the storage value limit. Migration preserves existing reservations; the regression remains in `server/turn/lobby.test.mjs`.
- A historical direct-only attempt gathered no candidates. That described one environment and motivated relay validation; it does not establish that direct WebRTC is generally broken. Subsequent forced-relay and automatic-lobby tests passed across two networks.

Earlier implementation/deployment chronology remains in Git history. Current limitations belong in [the backlog](../BACKLOG.md), and current test claims belong in [verification](../specs/verification.md).
