# Invite onboarding and Settings

Updated 2026-11-07. Objective: separate invite-only onboarding, password-style key handling with hash-only server verification, and compact CraftPix Settings. Owner: General x86 `/workspace/coop-side-scroller`, branch `work/network-review-20261106`, source base `ef13685`. Changes remain local; origin and deployments are unchanged.

Decisions: browser players validate the key before the main menu; native ENet development skips the gate. The game retains the original key only in session memory, with no game-owned persistence. A real DOM password form supports external password managers. Existing random 256-bit invitations use a SHA-256 server verifier; human-chosen passwords are unsupported. Bottom-left Settings owns routes, collapsed manual pairing, diagnostics and invite replacement. Reuse existing CraftPix art.

State: reviewed and patched response typing, stale callbacks, hidden chat availability, diagnostic copy initialization and Settings/setup overlap. Final 20 Python, 34 Deno, three native suites, core freshness, fresh Web export, real two-process ENet named multiline chat and four-size browser/clipboard checks pass. Final UI runtime errors: zero. A supplemental managed-launcher timeout was resolved with the established isolated direct Godot fallback. Failed attempts remain in evidence.

Next: live rollout requires provision of `PLAYTEST_TOKEN_SHA256`, deletion of plaintext `PLAYTEST_TOKEN`, external operator configuration changes and retirement of legacy plaintext invite files after secure retention. Then verify live auth/TURN before a separately requested page publish. No push/deployment or secret migration occurred. Third-party password-manager save/autofill and live TURN acceptance remain unverified.

Evidence: `.local/onboarding-20261107/` logs, reviewed.patch, build-info.json and receipt.json; `build/onboarding/accepted/` result and captures. Prepared Godot 4.7/native/Wasm/art inputs retained; generated Web candidate removed after identity capture. Dev Workbench only, software Chromium, no Runpod or new dependencies. Prior multiline-chat evidence remains in `.local/chat-multiline-20261106/`.
