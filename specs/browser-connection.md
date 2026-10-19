# Browser connection setup

Owners: `src/connection_codes.gd`, WebRTC setup/state handling in `src/main.gd`, and `tests/connections.sh`. Conventional architecture, network/certificate requirements and deferred deployment gates are in [the connectivity study](../design/internet-connectivity.md).

## Current boundary

GitHub Pages serves static HTTPS game files. Browser peers use manual offer/answer/ICE exchange with the protected [Cloudflare TURN service](turn-service.md), or explicit direct-only Google STUN mode. Automatic signaling and a general internet-connectivity guarantee remain absent. Native ENet is a separate direct UDP lab transport. All of this remains outside the portable simulation core.

The menu selects direct + relay fallback, relay-only testing, or direct-only. Relay modes require a private invitation in the masked menu field. Reset/solo/new sessions clear old inbound and outbound codes. There are no new gameplay controls or animation selectors.

## Manual code contract

A code is standard Base64 of JSON, limited to 65,536 characters. The envelope requires `game="ember-coop"`, `version=1`, `protocol=1`, a 32-hex-character random `session` identifier, `type="offer"|"answer"`, SDP starting `v=0` with maximum 32,768 characters and 1–64 ICE candidates. Each candidate is `[media,index,candidate]`: media string ≤256 characters, finite integral index [0,65535], and candidate string starting `candidate:` with maximum 4,096 characters. JSON numeric indices may deserialize as floats; fractions reject before conversion. Browser SDP/ICE validation still applies after envelope checks.

Host generates a new 128-bit random session identifier for each offer. Guest echoes that identifier in its answer. An answer must match the currently pending host offer and its signaling state; stale answers and mismatched versions reject before applying network state. The identifier correlates attempts; it does not authenticate the player. Codes contain connection information and should be exchanged privately. Old unversioned prototype codes reject; both ends must use this build's format. Changing the core wire protocol also requires updating this adapter protocol field.

## Failure behavior

Check initialize/create-peer/create-offer/local-description/remote-description/candidate-add return codes. On failure, close the session and return to solo simulation. Browser pairing stays visible with the reason and a Start again action; native setup returns to its menu. Do not leave stale outbound codes available to copy.

Use adapter monotonic milliseconds: gathering must finish with a non-empty candidate list within 30 seconds; after accepting a remote description, connection has 60 seconds; an established connection reporting disconnected has a 10-second recovery grace. Explicit failed/closed state ends the attempt. A host waiting for the user to return an answer does not time out merely because the offer was copied some time ago. Automatic reconnect/ICE restart is deferred. WebRTC timeout handling does not use the native ENet timeout branch.

Timeout/failure messages distinguish gathering failure from direct-connection failure and identify credential/network setup failures. These diagnoses are guidance, not reliable classification of a specific NAT/router problem. No candidate IPs, SDP or relay secrets are printed in telemetry.

## Evidence

`tests/connections.sh` exercises envelope round trips, incompatible/malformed/oversized fields, fractional ICE indices, stale-code cleanup, invalid/unsolicited/mismatched answer rejection, simulated ICE states and gathering/connect/disconnect deadlines, established-connection grace, indefinite host answer waiting, and failure return to setup. These simulated states do not test NAT traversal. Native network/lab checks cover retained ENet behavior. `tests/web.sh --connection-setup` additionally captures actual browser Host setup; this captures setup rather than asserting connectivity. Web export and Chromium smoke checks cover browser startup/gameplay; The two-window actual Godot relay test passes movement/combat with independent Wasm cores and selected relay/relay candidates; separate-network acceptance is tracked separately in the service spec.

## Clipboard and browser test HUD

Browser copying waits for Clipboard API acknowledgement. If that API rejects or does not settle within five seconds, a small browser-native dialog requests a direct Copy click; its synchronous compatibility fallback is limited to that user action. Cancel/Escape/reset clears the private code and restores focus. The dialog never stores or logs the code. Ordinary paste denial still points to the lower input field.

Relay-only test mode shows RTT, actor count, shared dummy HP, core tick, RPC counters and snapshot age/sequence. Ordinary browser play hides this debug panel; the native independent-process lab is unchanged. These are application ping timings, distinct from ICE candidate-pair RTT.

## Guided manual pairing

Host creates its invitation automatically; Join cannot create an offer. Each side sees a two-step instruction and role-specific Copy invitation/Copy reply and Enter guest reply/Enter host invitation actions. Copy is disabled until ICE gathering finishes; guest entry is disabled once its reply is generated. Role mismatches reject before applying SDP. Raw encoded codes are hidden in the browser UI; the versioned wire envelope is unchanged.

Entering a code opens a focused browser-native textarea with Continue/Cancel. This uses ordinary browser paste, not async Clipboard API reads or Godot's cached clipboard. Remote desktop users can first transfer text through their desktop clipboard panel. Copy fallback exposes a selectable read-only textarea as well as its direct Copy button. Reset cancels open dialogs; private code contents are not saved, logged or put in URLs.

This remains a manual two-way exchange and does not prevent ICE failure while the guest waits for the host to accept its reply. A guided UI is not a substitute for signaling. Short room codes, automatic offer/answer exchange and retry/re-signaling require an expiring protected signaling service; they are deferred in BACKLOG.md. Cross-network Firefox acceptance is still unverified.
