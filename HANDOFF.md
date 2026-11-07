# Published invite onboarding and Settings

Updated 2026-11-07. Objective: push and deploy the reviewed invite-first UI and hash-only playtest authentication. Owner: General x86 `/workspace/coop-side-scroller`, branch `work/network-review-20261106`.

State: game source `b42ceb1` is pushed; Pages `5265099dcf6c6406bdc43bfb09c539a2d18eb7d7` is built and every hosted file matches. Hosted invite login and actual keyboard movement pass. The existing Cloudflare Worker is deployed with only `PLAYTEST_TOKEN_SHA256`; retained plaintext binding explicitly deleted and live auth/List/digest-replay checks pass. Original invite unchanged and retained in the encrypted workstation password vault; operator/history/General test metadata is hash-only. Main/Firebase are unchanged.

Decisions: preserve the existing provider keys, lobby namespace, rate limits and diagnostic authority. Future operator deployments use hash metadata and remove a retained legacy binding after successful upload. Browser tests receive the original via a protected transient pipe, never argv or a plaintext file. Existing operator changes were already dirty; preserve them and the local rollout patch in that normal checkout.

Verification: 11 publication tests, 27 offline operator tests, fresh clean-source Web export, four-size UI checks with zero runtime errors, offline secret audit, all hosted hashes and two hosted login/movement checks pass. Two-browser TURN remains unverified: both attempts end during host gathering despite successful HTTP and two relay candidates. The harness wait now covers the existing TLS lifecycle; do not report relay gameplay acceptance. Third-party password-manager save/autofill is untested.

Next: user can refresh and play at https://rareskey.github.io/coop-side-scroller/. Investigate live ICE gathering separately if the user's session also fails. No Runpod/new dependencies or Terra restart. Game execution stays on General x86; the existing workstation operator owns credential administration and the offline audit.

Evidence: `.local/release-20261107/` logs/receipts, retained relay failures/captures, audit inventory and build identity; `build/onboarding/release/` UI captures. Reproducible Web candidate removed after byte/runtime verification; prepared native/Wasm/art inputs retained.
