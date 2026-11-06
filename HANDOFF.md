# Co-op movement continuity and room lifecycle

Updated 2026-11-06. Owning checkout: General x86 `/workspace/coop-side-scroller`, branch `work/network-review-20261106`. Preserve the dirty workstation checkout.

## Objective and decisions

Repair local teleporting introduced by today's prediction, compare earlier Codex/Runpod evidence, clear stale room UI and extend setup. Protocol 3 queues actual command frames and ACKs executed inputs only, with eight-frame redundancy and bounded queues. Room lifetime is one hour, abandoned-seat lease five minutes. The host starts TURN/ICE when a partner joins. Failed refresh invalidates Join buttons; definitive expiry returns to the directory. Both players must reload.

## State

Game/source build f16fa90c19e68badb7e17b46facd02150c347fd5 is published at https://rareskey.github.io/coop-side-scroller/, Pages 47d3a721c4e1b565e92877706aa03a542e03555e. All hosted candidate hashes match. This later documentation commit leaves that deployed game identity intact. The existing tagged Worker is deployed with longer bounds and separate matching protocol-1/2/3 pairs. No new services or Runpod resources.

Terra was explicitly stopped: browser/control/polling ended and its goal is complete. Do not restart it. No live player room is offered. Chat remains a TODO only.

## Verification and evidence

Core ASan/UBSan, C11, native/Wasm 82,176-byte parity, queued-input/loss regressions, deterministic 18,000-tick cross-compiler parity/twelve scenarios, Godot presentation/lifecycle, 29 service tests and real two-process ENet pass. A local two-browser 150ms-batch run measured 56 snapshots with zero displacement correction. The final exact-build hosted run measures 90 zero-correction snapshots, real keyboard movement/attack, replicated combat, TURN traffic, diagnostic upload and forced disconnect. Directory failure/recovery renders at 854/960/1280/1920 widths. Eleven deployment regressions and publication secret audit pass. Earlier harness timing/combat failures are retained and described in specs/verification.md.

Remote evidence: `.local/continuity-20261106/`; workstation receipts/captures: `~/workspace/.agent-handoffs/coop-live-20261106/continuity/`. Prior diagnostic 2b494a708eff4277 shows default ICE failure then a successful TLS retry; a later room 404 is normal connected cleanup. A separate network error left stale directory buttons. Earlier Codex logs confirm October-19 Runpod tests/published 3b59d27 without today's prediction path. The batching reproduction isolated the new regression (8–23-pixel corrections).

## Next action and limits

Human reloads both players and evaluates movement feel; Terra stays stopped unless explicitly requested again. No FPS or input-to-display claim: finite browsers use intentional SwiftShader. Severe loss beyond the redundant window can still require authoritative correction; full reconnect/mobile acceptance remain unverified. Reproducible Web candidate/publication staging is removed after verified evidence retention. Keep native/Wasm preparation, private art and selected logs/captures. Workbench job storage is full; existing SSH operates the same General x86 container without touching other jobs/GPU workloads.
