# Speech bubble tail milestone

Updated 2026-11-06. Objective delivered: off-center bottom speech triangle dynamically aimed at the speaking player, with review/patch through verified release.

Owner General x86 `/workspace/coop-side-scroller`, branch `work/network-review-20261106`. Preserve dirty workstation checkout and active Terra session. No Runpod/new dependencies/Node/npm. Reuse prepared Godot4.7/native/Wasm tooling; direct native fallback and intentional headless software browser.

Decisions: adapter-owned speech_bubble draws one continuous translucent body/tail, avoiding an opacity seam. Tip follows rendered head after spacing, with bounded24-unit length, horizontal/vertical bounds, and footprint reservation so tails do not cover neighboring text. Lifetime belongs to the bubble. Review also fixed directory reads swallowing Join/Create clicks: separate read busy/generation, retire old callbacks before membership and on close. Wire/RPC/core unchanged.

State: source/game build8397e5aba94aa2a09b68550e0b6778def8a1ed10 pushed and live. Pages95dcd9f24e2744d39ad073b905cc817220cba35f completed; all hosted candidate hashes match. Secret audit and11 publication tests passed. Final metadata-only source update follows; no new game export needed.

Verification: native chat geometry/lifecycle, connection/setup pending-read Join regression and12 snapshot checks pass. Actual local and hosted Web peers pass names/chat/echo/input isolation plus standing/stacked/moving/jumping tail captures. Hosted Join succeeds with a real directory response delayed4seconds, and runtime-console checks are clean. Four sizes inspected; short speech naturally expires during long capture matrix. Two pre-fix browser join failures retained. Hardware FPS/input-to-display latency, geographic-network behavior and device coverage are unmeasured; human visual/play acceptance remains.

Evidence `.local/speech-tail-20261106/`; workstation `.agent-handoffs/coop-live-20261106/speech-tail/` and `hosted/`. External milestone and receipt carry actual private runtime/room ownership. Terra's existing control-only wait/follow/react/chat-until-stop goal/browser remains active on the previous compatible presentation build; no forced restart.

Next: user reloads to see tails and reviews in play. Preserve Terra unless stopped or its bounded lifetime expires. Remove only generated Web candidates/publication staging after hosted proof; preserve native/Wasm prep, immutable private art and evidence.
