# Speech bubble tail milestone

Updated 2026-11-06. Objective: dynamic bottom speech triangle, offset sideways and aimed at the speaking player; review/patch until clean.

Owner General x86 `/workspace/coop-side-scroller`, branch `work/network-review-20261106`. Preserve dirty workstation checkout and active Terra play session. No Runpod. Reuse prepared Godot4.7/native/Wasm tooling, direct native fallback (no nested Podman); headless software browser for checks because GPU is owned elsewhere.

Decision: adapter presentation only. New speech_bubble draws body/tail as one translucent outline, points toward rendered head after spacing, reserves24px tail footprint and clamps slanted tips to bubble width. Tail lifetime belongs to the bubble; no external nodes or networking change.

State: implementation/review complete, ready for commit. Native chat/setup/presentation checks and actual Web standing/stacked/moving/jumping captures pass. Review also patched directory reads swallowing Join/Create clicks; independent read generation fences late callbacks. Earlier two browser join failures retained. Next clean export, audited source/Pages publication and hosted check (including deliberately held directory read during Join). Preserve active old-build Terra browser; adapter RPC/wire compatibility is unchanged, so no forced runtime replacement. Refresh final source/deployment/evidence after proof.

Evidence `.local/speech-tail-20261106/`; preceding chat evidence `.local/chat-20261106/` and external `.agent-handoffs/coop-live-20261106/chat/`. Existing Terra runtime details in external receipt; do not stop or recreate it without need/request.
