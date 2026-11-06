# No-game-server Cloudflare budget

Checked against official documentation on 2026-10-21. [Realtime pricing](https://developers.cloudflare.com/realtime/sfu/platform/pricing/) advertises 1,000 decimal GB/month shared by TURN and SFU, then $0.05/GB outgoing. [TURN metering](https://developers.cloudflare.com/realtime/turn/faq/) counts Cloudflare-to-TURN-client traffic, including TURN overhead. Direct peer traffic uses none of that gameplay relay allowance. Recheck terms and actual account usage before operating at scale; this is not a purchase, account-plan audit or provider usage measurement.

## Planning tool

`python3 tools/network_budget.py --billed-kbytes-per-second 12 --match-hours 10000` takes TOTAL provider-metered outgoing kB/s across both players, not a single direction or core payload. Decimal units are used. One match-hour means two players playing for one hour. The default reserves 200 GB of the shared allowance; `--other-gb` accounts for other SFU/TURN workloads. Exit code 2 means the planned traffic exceeds the remaining planning budget. This does not block provider traffic or enforce a spending cap.

`GB per match-hour = total billed bytes/second * 3600 / 1,000,000,000`.

Inputs and calculated outputs must be finite and representable; extreme values outside that numeric range produce a CLI argument error rather than nonstandard JSON or a division-by-zero failure.

| Assumed total metered egress | GB per match-hour | Match-hours in 1,000 GB | Match-hours after 200 GB reserve |
| --- | --- | --- | --- |
| 5 kB/s | 0.018 | 55,556 | 44,444 |
| 12 kB/s | 0.0432 | 23,148 | 18,519 |
| 20 kB/s | 0.072 | 13,889 | 11,111 |

These are arithmetic scenarios, not measured capacity or guaranteed free play. Recorded game transport rates near 6 kB/s per direction are not provider billing. Voice/video, retransmission, keepalives, recovery and other account workloads must be counted when present.

## Protocol comparison

The current core emits 24-byte guest inputs at 60 Hz and 104-byte snapshots at 20 Hz: 3,520 core payload bytes/second across a match, before engine/WebRTC/TURN framing and ping traffic. Sending two unchanged 24-byte input streams would be 2,880 bytes/second: only an 18% payload reduction for this small world.

The experimental protocol uses a 48-byte identity/epoch/ACK/hash header and four bytes per tick input. Sending two or four ticks per batch reduces packet frequency. The lab measures encoded bytes and retransmission separately for both batching settings. Its packet-loss model counts attempted encoded sends; it does not measure WebRTC/TURN overhead or billed traffic. Four-tick batching can reduce bytes while increasing remote prediction/correction and missing-input stalls. Choose based on gameplay measurements, not payload size alone.

## Separate service quotas and operational limits

[Workers Free](https://developers.cloudflare.com/workers/platform/pricing/) advertises 100,000 requests/day and 10 ms CPU/invocation. [SQLite Durable Objects Free](https://developers.cloudflare.com/durable-objects/platform/pricing/) separately advertises 100,000 compute requests/day, 13,000 GB-s duration/day, 100,000 rows written/day, five million rows read/day and 5 GB stored. Incoming WebSocket messages have a billing conversion documented there; this does not make storage writes or active simulation free. These quotas are shared with other relevant account workloads. Free DO operations fail after a daily limit is exceeded.

Keep per-tick gameplay off Workers/DOs. Setup, reconnect signaling, diagnostics, abandoned-room polling and optional checkpoint writes still need their own measured budgets. An open room directory currently polls every five seconds (about 720 requests/hour/viewer); an unused tab can exhaust request quotas without any relay gameplay. Hibernating WebSockets and bounded/inactive polling are candidates if measured usage warrants them.

Temporary credential issuance limits do not enforce a relay-byte cap after credentials have been issued. Client-side bandwidth limits cannot constrain a hostile client holding credentials. Short credential lifetimes, authenticated/global issuance reservations, usage monitoring and refusal of new sessions provide safeguards, but cannot honestly guarantee zero charges without an enforceable provider/account cutoff and accounting for already-issued credentials. The experiment adds a planning calculator, not that cutoff; no account setting, Worker deployment, TURN key or paid plan was changed.
