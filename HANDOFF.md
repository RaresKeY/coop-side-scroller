# Co-op continuity and room lifecycle milestone

Updated 2026-11-06. Owning checkout: General x86 `/workspace/coop-side-scroller`, branch `work/network-review-20261106`; preserve the dirty workstation checkout.

Objective: repair the human-reported local teleporting regression, compare earlier Runpod/Codex evidence, clear stale room UI and make setup much longer. Keep original colors/local triangle and immediate prediction. No Runpod for this work. User explicitly stopped Terra: controller polling/control and its goal are complete; do not restart it.

Decisions: shipping protocol 3 queues/redundantly sends actual command frames and ACKs only executed frames. Repeated host held-input advancement caused protocol-2 ACK/replay jumps. Both peers must reload. Room lifetime becomes one hour with five-minute abandoned-seat leases; TURN/ICE starts only after the partner joins. Directory errors invalidate old Join buttons, temporary refresh errors retry, definitive expiry restores the directory immediately.

State: native core/Wasm queue/replay checks pass, including batched/lost delivery with zero correction in the bounded scenarios; service and Godot lifecycle regressions pass. Full final build/browser verification and publication are in progress. Source is ready to commit. The old public build remains c64e7be until rollout. Existing Worker is deployed compatibly for protocol 1/2/3 pairs and longer room bounds. Two local Web peers pass TURN, replicated combat/diagnostics and 150 ms batching: 56 guest snapshot updates have zero position correction.

Evidence: `.local/continuity-20261106/` holds native/Wasm, deterministic, Godot, service and browser checks. Workstation `.agent-handoffs/coop-live-20261106/responsiveness/` contains historical Codex-log references and diagnostic 2b494a708eff4277: default ICE failed before establishment, TLS retry connected, subsequent room 404 was normal signaling cleanup. A directory network failure left stale buttons. October-19 Codex logs confirm earlier Runpod/TLS tests and published build 3b59d27; no claim that automated test measured human feel.

Next: finish browser batched-motion/lobby/UI verification, audit/push/deploy, verify hosted hashes/startup/input, refresh this handoff and remove reproducible candidates. Keep Terra stopped. Chat remains a TODO only. No input-to-display or FPS claim; intentional SwiftShader tests and human feel remain distinct.
