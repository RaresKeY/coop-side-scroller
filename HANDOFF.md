# Local player marker correction

Updated 2026-11-06. Objective: restore the original yellow downward triangle above the local character; the user clarified square was a typo.

Owner General x86 `/workspace/coop-side-scroller`, branch `work/network-review-20261106`. Preserve dirty workstation checkout. Restore only the original three-vertex player marker; its color, ownership, position and the dynamic speech tails remain unchanged.

State: game build9e76f1d prepared clean; native12 snapshot-presentation checks and actual local browser render/input/runtime-console checks pass. Publication audit and11 deployment tests pass. Source/Pages publication awaits workstation authentication; concrete pending action and ownership are in external receipt. Next resume authorized push/deploy, verify exact hosted hashes and screenshot/input, then remove candidate/staging. No Runpod/new dependencies, reuse Godot4.7/native/Wasm and headless software browser.

Evidence `.local/player-marker-20261106/`, selected workstation `.agent-handoffs/coop-live-20261106/player-marker/`. Current prior hosted build8397e5a/Pages95dcd9f; previous speech-tail and directory Join fixes remain intact.

Terra reported its one-hour room expiry, no partner joined; idle without automatic recreation. Preserve its owned browser/control role until told otherwise or bounded runtime ends. Actual runtime ownership belongs in external receipt.
