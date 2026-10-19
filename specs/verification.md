# Verification boundaries

- Godot 4.7 import, script loading and single-thread Web export passed with the managed runtime.
- Native finite two-process localhost test (`tests/network.sh`) passed: guest received both actors, moved to the dummy and attacked; authoritative dummy HP fell from 12 to 4 and was replicated back to guest. Host observed connection and guest departure. This does not establish internet connectivity.
- A rendered native Gamescope run and Chromium web run displayed the actual CraftPix character and imported UI. The current gameplay screen removes clip controls and moves setup to onboarding/menus. The browser downloaded and started the WASM/PCK. The visual check was at 960×540; no mobile or full browser matrix is claimed.
- Independent-process network lab (`tests/lab.sh`) passed with 50 ms delay each way: both control schemes moved different actors, guest attacks reduced shared dummy HP from 12 to 1, guest snapshots and measured RTT were received. GPU logs selected NVIDIA RTX 2080 Ti in the controller and both workers. Worker screenshots include live telemetry; observed RTT was roughly 103–166 ms across runs. These are loopback measurements, not internet latency estimates.
- Manual browser offer/answer and clipboard controls were exercised. End-to-end browser gameplay did not connect: ICE candidates were empty. A separate plain RTCPeerConnection test also returned zero candidates with gathering complete. Cause in this environment is unresolved; it is not evidence of a working internet P2P path. The UI now reports missing candidates rather than a ready connection code.
- GitHub repository is public; Pages is configured to `gh-pages` root and returned HTTP 200. Hosted runtime verification and candidate byte matching should accompany each deployment.

No signaling service or TURN relay was deployed. Their provider choice, cost and operational verification remain deferred.
