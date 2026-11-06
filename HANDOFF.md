# Multiline chat editor

Updated2026-11-06. Objective: multiline typing and scrolling contained inside the game window. Owner: General x86 `/workspace/coop-side-scroller`, branch `work/network-review-20261106`, source base921f8d9 (already pushed to the same origin branch). These new changes remain local; page deployment is unchanged.

Decisions: wrapping Web textarea/native TextEdit grow to four lines, then scroll internally. Enter sends, Shift+Enter adds LF, Escape cancels. Browser-measured height reserves engine/footer space; wheel events stay inside the editor and layout preserves draft/focus/scroll. Keep200-character messages; allow LF/normalize CRLF while names and other control validation stay strict. Speech labels cap at eight lines with ellipsis; history retains full text. No core/Worker/RPC-shape changes.

State: native player-chat and connection/setup contracts, two Deno checks, real independent ENet peer multiline echoes, core freshness and fresh Web export pass. Final3 browser run passes eight desktop/DPR cases, bounded wrapping/scroll, draft/focus retention, wheel/layout scroll retention, Shift+Enter/Enter/Escape and typing isolation with zero runtime errors. Captures inspected. Two live browser peer attempts stop at Network unavailable while listing rooms; TURN delivery remains unverified here.

Runtime/evidence: prepared Godot4.7/native/Wasm/art imports via Dev Workbench, isolated direct headless fallback (nested Podman unavailable), software Chromium, no Runpod/new dependencies. `.local/chat-multiline-20261106/` holds before/, final3/, native logs, ENet logs, peer failure captures, export identity, reviewed.patch and receipt.json. Failed fixtures/harness assumption and interrupted workbench job are retained. The workbench process set restarted during validation; this task did not restart Terra. No hardware/input-latency claim.

Next: user review of local changes; live TURN recheck when room requests work, and any push/deployment only as subsequently requested. Generated Web candidate removed after saving identity; prepared inputs/evidence retained.
