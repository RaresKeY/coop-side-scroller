# Automatic TLS fallback and faster setup

Updated 2026-11-06. Objective: automatically retry eligible failed private-room connections through TLS compatibility and reduce setup delays. User hold: no push/deployment.

Owner: General x86 `/workspace/coop-side-scroller`, branch `work/network-review-20261106`, source base bcee6f5. Use Dev Workbench; preserve the preexisting dirty workstation checkout. No Runpod/new dependencies.

Decisions: remove the retry button; queue one coordinated epoch-1 TLS retry on allowlisted initial transport failures, retaining the room and getting fresh credentials/signaling. Initial eligible gathering/connect bounds are10s; TLS/manual bounds remain30s/60s, established recovery10s and room lifetime one hour. Ready signaling and queued retry wake sync immediately, including in-flight completion. Use500ms polling for a bounded8s per epoch, otherwise2s. Access/rate/unsupported errors stop with their HTTP/error code. Skip terminal peers when an answer races the frame poll. No Worker/core/wire change.

Verified: expanded native connection/setup contracts (eligibility, in-flight races, cancellation, shorter first/full TLS bounds, polling budget and error codes), player-chat and12 snapshot checks pass; all30 Worker/lobby/diagnostic checks pass. Actual independent Web peers through the live service/TURN pass healthy setup, injected gathering stall and injected terminal failure, names, replicated movement and chat echo. Both failure cases reach relay/TLS443 without retry clicks; final terminal run has no runtime errors. Matched healthy sample improved21.88s to13.79s with19 signaling requests in each; one pair of samples is not a general internet guarantee.

Evidence: `.local/auto-compat-20261106/` — baseline/, after-healthy/, after-gather/, final-terminal/, native-final logs, worker-contracts.log, browser harness and receipt.json. Retain earlier harness configuration failures and the first terminal case's closed-peer errors; the final corrected injection/adapter guard passes. Runtime inputs are reused; browser rendering is headless software. Hardware/device coverage, geographic behavior, percentiles, input-to-display latency and resource savings unmeasured.

Next: user review and explicit release of publication hold. Public source40ec88d/game9e76f1d/Pagesbd94a5a unchanged. Preserve Terra's separate public browser/controller, prepared native/Wasm/art and evidence. Remove only the generated Web candidate after recording hashes.
