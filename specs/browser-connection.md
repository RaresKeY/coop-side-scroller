# Browser connection adapter

Owners: `src/main.gd`, `src/connection_codes.gd`, `src/relay_credentials.gd`, `src/private_lobby.gd`, browser text helpers in `adapters/web/ember_core_bridge.js`, and `tests/connections.sh`.

GitHub Pages serves the game. Authenticated [private lobbies](private-lobbies.md) are the normal setup flow; the [TURN issuer](turn-service.md) supplies temporary ICE configuration. WebRTC carries opaque core messages after setup. Native ENet is a separate transport. None of these services or engine objects enter the portable core.

## Modes and lifecycle

Menu selects **Direct + relay fallback** (default), **Relay only (test)**, **Direct only** or **Compatibility (TLS 443)**. Relay modes require the private playtest key. Private room access requires that key in every route mode; direct-only advanced manual pairing can run without it using Google STUN.

**Compatibility (TLS 443)** uses relay-only ICE and retains only issuer-provided `turns:turn.cloudflare.com:443` URLs with absent or TCP transport. Missing TLS credentials fail setup explicitly; no UDP/direct fallback occurs. Both peers should choose this mode to route both access-network legs over TLS/TCP. The TURN relay candidate can still report `protocol: udp`; `relayProtocol: tls` identifies the browser-to-relay transport. TCP head-of-line blocking can increase gameplay latency under packet loss. This mode is a workaround to test, not evidence that a router caused an outage.

Solo/reset/new attempts close the prior connection, invalidate pending HTTP work and clear inbound/outbound signaling codes. Every WebRTC description/candidate callback checks the connection generation, so an old callback cannot mutate a replacement session. Opening Menu temporarily hides unfinished setup; closing Menu restores it. Connected sessions return to gameplay. Setup panels suppress game input.

Initialization, peer creation, offer creation, local/remote description and candidate-add errors end the attempt. Failed lobby setup returns to Menu; advanced manual pairing retains a reason and Start again action. Old outbound codes are unavailable after failure.

Timeouts use adapter monotonic time:

| State | Bound |
| --- | --- |
| Gathering | 30 seconds to finish with a non-empty candidate list |
| Remote description accepted | 60 seconds to connect |
| Established connection reports disconnected | 10-second recovery grace |
| Explicit failed/closed | End the attempt |

A manual host waiting for the guest reply has no additional answer-wait deadline; ICE itself can still fail. There is no automatic reconnect/ICE restart. Error text distinguishes setup stages but is not a reliable diagnosis of a particular router/NAT. Telemetry omits candidate addresses, SDP and credentials.

## Signaling envelope

Both private lobbies and advanced manual pairing use the same versioned envelope. A manual code is standard Base64 of JSON, bounded to 65,536 characters:

| Field | Contract |
| --- | --- |
| `game`, `version`, `protocol` | `ember-coop`, 1, 1 |
| `session` | 32 hexadecimal characters; random 128-bit offer identifier |
| `type` | `offer` or `answer` |
| `sdp` | Starts `v=0`, at most 32,768 characters |
| `ice` | 1–64 `[media,index,candidate]` entries |
| Candidate fields | Media ≤256 characters; finite integral index 0–65535; candidate starts `candidate:` and is ≤4,096 characters |

Fractional JSON indices reject before conversion. The host generates a fresh session ID; the guest echoes it. Answers must match the pending offer/session and signaling state before SDP is applied. The ID correlates attempts, not people. Browser SDP/ICE validation still applies. The lobby HTTP request cap can be reached before the envelope's standalone maximum.

Unversioned early prototype codes are unsupported. Changing the gameplay wire protocol also requires updating the envelope's protocol field. Connection descriptions are private connection metadata, never public room-list content.

## Advanced manual pairing

Host automatically prepares an invitation; Join accepts an invitation and generates a reply. Each side has role-specific Copy/Enter actions. Copy is disabled until gathering finishes, and guest entry is disabled after producing its reply. Wrong-role codes reject. Raw codes remain hidden during ordinary gameplay/setup.

The host sends its invitation, the guest returns a reply, and the host accepts that reply. This diagnostic two-way exchange remains timing-sensitive; the primary lobby automates it. A separate playtest key is still needed when using relay modes.

## Browser text and copy dialogs

Access-key and room-name fields open a browser-native single-line input on click or Enter/Space. The dialog selects existing text, supports Enter to confirm, bounds length, disables autocomplete and masks the access key. Cancel preserves the prior value. Native builds use ordinary engine editing.

Manual connection entry uses a focused browser-native textarea with Continue/Cancel and normal browser paste. It does not read the asynchronous Clipboard API or rely on Godot's cached clipboard. Dialogs are compact and scrollable over a dimmed game, preserving scene context.

Copy waits for Clipboard API acknowledgement. Rejection or no completion within five seconds opens a selectable read-only field with a direct Copy action; a synchronous compatibility fallback is limited to that action. Late API completion cannot dismiss an active fallback. Cancel/Escape/reset clears dialog content, including detached DOM fields, and restores focus. Tab/Shift+Tab can reach the field/buttons. Private text is not logged, persisted or put in URLs.

## Diagnostics and verification

Relay-only mode displays application RTT, actor count, shared dummy HP, core tick, RPC counters and snapshot sequence/age. Ordinary browser play hides this panel. Application ping RTT differs from ICE candidate-pair RTT; snapshot age/gaps do not measure general packet loss.

`tests/connections.sh` checks envelope validation, role/session matching, stale callbacks, reset/Menu transitions, credential validation, simulated WebRTC timeouts and lobby cancellation/cleanup. Simulated ICE states are not NAT evidence. `tests/web.sh --clipboard-check` exercises actual DOM copy/entry, cleanup/focus and gameplay at four desktop sizes. The two-browser and separate-network harnesses exercise actual signaling, routing and replicated combat. See [verification](verification.md) for recorded results and [Runpod testing](../design/runpod-agent-browser.md) for remote test operation.
