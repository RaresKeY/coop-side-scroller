# Deferred work

- Investigate browser ICE environment: Chromium here returned zero candidates in Godot and an independent plain RTCPeerConnection probe; offer/answer codes exchanged but peers did not connect. Retest on an ordinary browser/network before validating the WebRTC transport.
- Automatic first connection: pick a signaling provider after manual browser P2P is proven on two independent networks. Exchange SDP/ICE only, with expiring private rooms, pair limits, authorization, rate limiting and cleanup. No provider credentials or paid account configured.
- TURN fallback: deferred explicitly. Deploy coturn or a managed equivalent, temporary credentials, restricted allocation and bandwidth budgets. TURN relays WebRTC; a generic UDP relay is not interchangeable with ENet or TURN.
- Test Chrome/Firefox and separate PCs/networks, failed NAT traversal, joining/leaving/rejoining and latency/loss. Localhost checks do not prove internet reliability.
- Guest interpolation and prediction/reconciliation. Present guest snapshots are visibly coarse under latency; no rollback or host migration.
- Integrate into a real game's movement, collision, enemies and animation state only after the owning engine/source contracts are available. This prototype is not a drop-in multiplayer retrofit.
- Shared enemy hit feedback, snapshot event IDs, action tick sequencing, packet size limits and prolonged loss tests.
- Touch controls, gamepad bindings, accessibility/layout beyond the desktop prototype, game audio and proper platform collision.
- Add network loss/jitter simulation and a browser-to-browser lab after the deferred WebRTC/ICE environment work. Native independent-process lab currently provides delay injection and live RTT/debug.
