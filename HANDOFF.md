# Local text and chat review

Updated 2026-11-06. Objective: review the local font fix and adjacent HUD/chat behavior, patch defects and verify on General x86. User hold: no push/deployment.

Owner: `/workspace/coop-side-scroller`, General x86, branch `work/network-review-20261106`. Preserve the preexisting dirty workstation checkout. Baseline local font fix c898112; this review adds two chat lifecycle/layout fixes.

Decisions: retain speech received before its rendered actor exists, hidden until placement and bounded by its original expiry; clear on departure/reset. Observe the canvas layout only while the Web chat composer is open so late canvas resizing cannot leave its DOM input off-screen. Disconnect on close. Keep the existing font filtering, pixel art, palettes/triangle and simulation/network protocols.

State: both defects reproduced and patched. Native player-chat (pending speaker/expiration included), connection/setup, 12 snapshot-presentation checks and separate ENet host/client names, two messages and both speech plates pass. Three Deno checks pass, including canvas reflow/draft/focus/observer cleanup. Actual fresh Web export passes nine viewport/DPR steps while composing, draft/focus retention, input isolation, Escape/no-send, menu clicks, movement and send/one echo; no runtime-console errors. Final chat/bubble and 854px composer captures inspected. No further findings in the reviewed changes and adjacent integration.

Evidence: `.local/text-rendering-20261106/` — `review-trace-{host,client}.log`, `review-pending-before.log`, `review-browser-before-observer.log` retain failures; `review-after-*.log`, `review-deno.log`, `review-browser-final.log`, `review-final/`, harness and review receipt retain accepted checks. The initial failing unit run was stopped after its missing-bubble assertions caused downstream dictionary errors; the corrected suite exits normally. The first exploratory browser pass used a copied bridge; the final fresh export records its actual payload.

Runtime: reuse prepared Godot4.7/native/Wasm/imports and headless software Chromium through Dev Workbench. No Runpod/dependencies. Hardware/device/font-wide coverage, input-to-display latency, PSS/CPU/peak memory and preparation savings unmeasured.

Next action: user review; keep publication held until explicitly released. Public game9e76f1d, source40ec88d and Pagesbd94a5a are unchanged. Preserve Terra's separate public browser/controller, prepared core/art and evidence. Remove only the generated review Web candidate after retaining its build receipt.
