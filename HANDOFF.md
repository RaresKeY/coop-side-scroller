# Local font rendering correction

Updated 2026-11-06. Objective: fix broken title/chat text at fractional window and DPI scales. User instruction: do not push yet.

Owner: General x86 `/workspace/coop-side-scroller`, branch `work/network-review-20261106`, source base40ec88d. Preserve the preexisting dirty workstation checkout.

Decision: dynamic fonts inherit linear filtering from a full-viewport HUD Control; world name/speech labels opt in explicitly. Existing font, sizes, positions, nearest-filtered world art and character shader are preserved. No network/core/Worker change.

State: patched and verified locally. No push or deployment; public game9e76f1d and Pagesbd94a5a remain unchanged. Native player-chat, connection/setup and12 snapshot-presentation checks pass. Actual Web before/after nine-case viewport/DPR sequence, movement, Enter/type/send/one echo and clean runtime console pass. Inspected title/footer/chat/speech captures; a static terrain strip is pixel-identical. Prepared tools/imports and headless software rendering reused on General x86; no Runpod/new dependencies. Hardware/device coverage and input-to-display latency unmeasured.

Evidence: `.local/text-rendering-20261106/`; workstation `.agent-handoffs/coop-live-20261106/text-rendering/` with `before-after-text.png`, full captures and browser/native logs.

Next action: wait for user review and explicit release of the publication hold. Terra's gameplay browser is separate and still uses the public build; current room/controller state belongs in the external milestone/receipt.
