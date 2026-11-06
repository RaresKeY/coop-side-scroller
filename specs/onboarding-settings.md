# Invite onboarding and Settings

Owners: `src/invite_gate.gd`, menu/input routing in `src/main.gd`, `EmberInviteField` in `adapters/web/ember_core_bridge.js`, Worker invite verification and `tools/invite_verifier.py`. Checks: `tests/invite_gate.gd`, `tests/invite_field.test.js`, `tests/browser_onboarding.py`, Worker tests and `tests/test_invite_verifier.py`.

## Requested flow

Browser players first see a separate centered playtest-invite screen with one masked key field and Continue. The main menu and Settings are unavailable until a valid response. Main menu contains Play solo and Private rooms; it contains no key, connection route, advanced pairing or diagnostics controls. Native ENet development remains available without internet invitation validation.

Settings is anchored at the bottom left. It contains the connection route, collapsed Manual connection (advanced) Host/Join actions, Copy connection diagnostics, Use another invite and Close. Its content scrolls within the panel when expanded. Opening it hides other setup panels, blocks gameplay/chat input and remembers the previous view. Closing restores that view or current pending connection setup. Coordinated TLS retries never draw a second panel over Settings. Switching invites ends the current session, clears its key/chat and returns to the initial screen.

The UI reuses the adopted CraftPix RPG pack's existing dark bronze button/frame artwork as nine-slice styles. No cold library originals are downloaded or added to source. Instructions remain visible during gameplay; they hide during setup/Settings to keep the header clear.

## Key lifetime and validation

The browser field is a real password input in a form with `autocomplete=current-password`, initial focus, IME/paste and Enter submission. Tab reaches Continue and cycles back. These [password-field semantics](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/input/password) support the user's browser/password manager; actual autofill/save behavior depends on that manager and user choice.

The game stores no invite in localStorage, sessionStorage, cookies, URLs, files, logs or diagnostics. The original key remains in page/session memory only for authenticated HTTPS requests. Successful validation clears both native and DOM entry fields, including detached DOM references. Closing/replacing the screen clears its field/callback/observer. Forget/scene exit clears the session credential. This is not a claim of immediate zeroization of browser/engine garbage-collected memory or control over an external password manager.

Validation uses the existing authenticated lobby List request: no new service, endpoint, TURN issuance or gameplay core operation. Keys are 32–128 printable ASCII characters after trimming. HTTP is bounded to 10 seconds and 70 KB, with no redirects. Loading disables duplicate entry/submission. Invalid/expired, origin-denied, rate-limit, network and malformed service responses retain a usable gate with bounded explanations; arbitrary body text never appears. Only a 200 response with numeric version 1 and an Array of rooms unlocks menus. Separate UI/request generations reject detached input, canceled responses and old responses during replacement attempts.

## Server verifier

Existing invitations are random 256-bit capabilities, not human-chosen passwords. The Worker requires a lowercase 64-hex SHA-256 verifier in `PLAYTEST_TOKEN_SHA256`. It hashes the presented original invite and compares fixed-length digests; sending the stored digest does not authenticate. Missing/malformed hash configuration or a retained nonempty legacy `PLAYTEST_TOKEN` binding fails closed. Expiry, Origin, limiter, diagnostic-read authority and no-store responses remain enforced.

Fast one-way verifiers fit high-entropy random tokens; human-chosen passwords require a password KDF. This distinction follows [OWASP's random verifier guidance](https://cheatsheetseries.owasp.org/cheatsheets/Session_Management_Cheat_Sheet.html#server-side-session-token-storage) and [password storage guidance](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html). The client never stores a digest as a reusable replacement credential.

## Rollout boundary

The local code is prepared; this change does not deploy or migrate the live Worker. Before rolling out the new Worker:

1. Retain the original invite only in a password manager/protected secret system; hashing cannot recover it later.
2. Run `python3 tools/invite_verifier.py` in a terminal. Input is masked and output contains only the verifier. For automation, `--stdin` requires a protected pipe; keys must never appear in argv.
3. Provision `PLAYTEST_TOKEN_SHA256` as the Worker secret, and remove the legacy plaintext `PLAYTEST_TOKEN` binding. Preserve expiry, provider secrets and limiters. Existing operator deployment code/configuration must use this new binding rather than reintroducing the legacy one.
4. Retire legacy plaintext operator/test invitation files after secure retention. The project browser tools now read masked input or an explicitly protected stdin pipe and no longer read a plaintext invitation JSON.
5. Verify live acceptance/rejection and then publish the reviewed page separately. No rollout is implied by local tests.

Pure local UI checks use a fixed public fixture and deterministic List responses. They exercise the real Godot HTTP bridge but do not prove production service configuration, live TURN routes, third-party password-manager integration or broader device support.
