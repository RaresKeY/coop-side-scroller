# Remaining work

The implemented baseline is in [architecture](specs/architecture.md); recorded acceptance is in [verification](specs/verification.md). These are possible next increments, not prerequisites for the working private lobby prototype.

## Connectivity and service operation

- Broaden acceptance beyond workstation↔Runpod Chrome forced relay: Firefox, other physical PCs/networks, selected direct paths, direct-to-relay fallback, UDP blocked with TURN TCP/TLS, and latency/loss. Test invalid/expired/revoked access, host exit, reload/rejoin, sleep and network changes in real browsers.
- Add reconnect/ICE restart, re-signaling and temporary credential refresh if sessions need recovery or longer lifetimes. Host migration is separate work.
- Measure polling and relay usage before broader access. Current per-location request limits are not a global spending cap. Add global budgets/stronger abuse controls as needed; per-tester identity and revocation are separate from the shared key.
- Consider invite links and hibernating WebSockets if usability or measured polling usage warrants them. Private room listing, Create/Join and automatic signaling are already implemented.
- Self-hosted signaling/coturn is an alternative only if requirements justify replacing managed services. No VPS deployment is needed for the current architecture. Such a change needs temporary credentials, public networking, relay ports, TLS/renewal, monitoring and bandwidth controls.

## Gameplay and portability

- Add guest interpolation and prediction/reconciliation; current replicas display 20 Hz authoritative snapshots without smoothing or rollback.
- Evaluate reliable gameplay event IDs/acknowledgements, action-tick reconciliation and prolonged loss handling. Existing input/snapshot sequencing does not make events a reliable stream.
- Integrate real level collision, enemies and game-specific movement through explicit core/adapter contracts. This prototype is not a drop-in multiplayer retrofit for another game.
- Add Unity/Unreal/custom-engine and additional OS adapters only against concrete target requirements. Current integration guidance is not implementation evidence.
- Broaden native/Wasm parity traces across compilers, architectures and inputs before making any stronger determinism claim.

## Tools and presentation

- Add loss/jitter controls and an interactive browser network lab. The native two-process lab already provides both keyboard schemes, delay injection and live diagnostics; browser automation already covers two-network lobby gameplay.
- Extend input/layout acceptance to touch, gamepads and accessibility use cases beyond the tested desktop controls.
- Add audio and broader gameplay/level presentation when they enter the prototype's scope.
