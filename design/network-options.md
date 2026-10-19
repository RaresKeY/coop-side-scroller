# Connection service options

For the current conventional deployment recommendation, router/certificate details and verification gates, read [internet-connectivity.md](internet-connectivity.md).

Decision: static Godot Web game on GitHub Pages; direct WebRTC between a host and one guest. Automatic signaling is deferred; a protected Cloudflare TURN issuer is now deployed (see [service contract](../specs/turn-service.md)). Temporary manual connection-code exchange keeps the first experiment independent of provider accounts. Browser ENet is unavailable; the native UDP route is only a development aid.

| Option | Useful role | Limits / decision |
| --- | --- | --- |
| Firebase Realtime Database | Expiring room records, offers, answers, ICE candidates | Possible signaling adapter; security rules/auth and cleanup required. Spark has a 100 simultaneous-connection limit; storage/download quotas also apply. Do not stream movement through a database by default. |
| Supabase Realtime | Private room signaling via broadcast; auth and optional room metadata | Possible signaling adapter; private channel policy and expiration required. Billing counts messages and peak connections. Do not assume free unlimited 60 Hz state traffic. |
| Small VPS | Small WSS signaling service; optional separate coturn service | Most control and operational responsibility; HTTPS, firewall, credential rotation and bandwidth management. No machine selected or price promised. |
| GitHub Pages | HTML, WASM, PCK and static notices | Cannot run a first-connection service or relay. |

Signaling connects peers; STUN discovers network addresses; TURN carries gameplay traffic if direct connectivity cannot be established. A VPS can host both signaling and TURN, but those remain distinct services. Without TURN, friend co-op cannot promise connectivity on all networks. Host authority simplifies shared state but does not eliminate synchronization, prediction, latency or cheating issues.

Prefer a tiny VPS WSS service if TURN will also be self-hosted; use Firebase/Supabase if their managed auth and room services are already available. No final provider choice is needed to build the animation and transport boundaries.

Verified public documentation, 2026-10-19:

- [Godot web export limitations](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html)
- [Godot WebRTC and signaling](https://docs.godotengine.org/en/stable/tutorials/networking/webrtc.html)
- [Firebase pricing](https://firebase.google.com/pricing) and [database limits](https://firebase.google.com/docs/database/usage/limits)
- [Supabase Realtime pricing](https://supabase.com/docs/guides/realtime/pricing) and [limits](https://supabase.com/docs/guides/realtime/limits)

Quotas/prices can change; recheck at deployment. No estimate here implies an account entitlement or zero relay cost.
