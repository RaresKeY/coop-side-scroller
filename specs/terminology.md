# Plain-language and technical terms

Use the plain-language name in player instructions where practical; use the technical term in contracts and code. Existing identifiers are shown for orientation, not as a request to rename the implementation. [Architecture](architecture.md) defines ownership and [C ABI](c-abi.md) defines exact types/messages.

## Game and engine

| Plain-language name | Technical term / identifier | Meaning in this project |
| --- | --- | --- |
| Shared game rules | Portable simulation core, `core/` | C++ movement, combat, input validation, authority and state messages |
| Engine connector | Adapter / facade | Connects core calls to Godot, input devices, rendering and transport |
| Library interface | C ABI, `ec_v1_*` | Versioned binary call contract with fixed-width fields and explicit ownership |
| Game instance reference | Opaque `EC_Handle` | Core-owned storage whose lifetime the caller manages; never a network identity |
| Browser-compiled library | WebAssembly / Wasm | Separate core module with its own memory; Godot has different Wasm memory |
| Desktop engine connector | GDExtension | Native Godot bridge to the C ABI |
| One game step | Fixed tick, `ec_v1_tick` | One 60 Hz host simulation step; replica ticks produce input messages |
| Drawing one image | Render frame | Presentation work; not necessarily one simulation tick or snapshot |
| Position units | Milli-reference-pixels | 1,000 units per reference pixel; origin top-left, +x right, +y down |
| Player's ground point | Feet anchor | Position used for the character, distinct from sprite-sheet rectangle origin |
| Animation choice | Logical animation state/event | Chosen by the core; sprite frame selection and playback belong to the engine |
| Temporary copied state | View, `EC_View` | Caller-owned copy for rendering; not network serialization or authority |

## Players and messages

| Plain-language name | Technical term / identifier | Meaning in this project |
| --- | --- | --- |
| Hosting player | Host authority, role 1 / slot 1 | Resolves game rules on that player's computer; trusted for gameplay |
| Joining player | Guest / replica; `client` in Godot | Sends inputs and displays host snapshots; role 2 / slot 2 |
| Connected partner | Peer / transport peer ID | Connection identity mapped by the adapter to a core slot |
| Player slot | Core slot | Stable slot 1 or 2; not an arbitrary transport ID or lobby seat token |
| Controls being held | Input state | Horizontal axis [-1000,1000], jump/attack flags; not a requested position |
| Latest shared state | Snapshot | Validated host state sent at 20 Hz; not a reliable history of every event |
| Packet order number | Sequence number | Separate uint32 counters for inputs and snapshots; modular wrap rules apply |
| Game message | Serialized gameplay payload | Explicit little-endian bytes; no raw native struct or engine object |
| Send/receive mechanism | Transport | Browser WebRTC or native ENet; carries gameplay bytes outside the core |
| Computer-to-computer play | Peer-to-peer / P2P | Describes endpoints/routes; does not remove host authority or imply no relay |
| Smoother remote motion | Interpolation / prediction / reconciliation | Different techniques; none is implemented in the current replica |

## Connection setup and access

| Plain-language name | Technical term / identifier | Meaning in this project |
| --- | --- | --- |
| Private game list | Lobby directory | Authorized setup rooms, not active-game state or a public server browser |
| Room label | Room name | User-visible text; not a secret or authorization |
| Room reference | Room ID | Eight-hex locator; knowing it alone does not grant seat ownership |
| Room membership secret | Seat token | Random 128-bit credential for that room member's sync/leave operations |
| Playtest access code | Shared bearer playtest key | Grants lobby access and temporary relay issuance; not account administration |
| Temporary relay login | TURN username/credential | Short-lived relay allocation access issued by the protected endpoint |
| Relay issuing secret | Scoped TURN key token | Server-side credential used to mint temporary relay credentials |
| Account management key | Cloudflare API token | Operator-only account actions; never supplied to the game |
| Connection report reference | Diagnostic attempt ID | Correlates reports; not a password or verified player identity |
| Private report-reading key | `DIAGNOSTIC_READ_TOKEN` | Operator-only journal access in the diagnostics implementation |
| Automatic connection exchange | Signaling | Sends offer/answer/candidates through the room service; does not simulate gameplay |
| Host invitation / guest reply | SDP/ICE envelope | Versioned connection description; advanced manual flow encodes it as Base64 |
| Attempt matching value | Signaling session ID | Matches an answer to an offer; distinct from room, seat and diagnostic IDs |
| Available connection address | ICE candidate | Potential route; its existence is not evidence that connection succeeded |
| Route selection | ICE | Tests candidate pairs; selected-pair statistics identify the route actually used |
| Address discovery | STUN | Helps discover mapped addresses; does not relay gameplay |
| Traffic forwarding | TURN relay | Forwards encrypted peer traffic; does not run game rules |
| Direct connection | Direct WebRTC route | Gameplay avoids TURN; hosted signaling may still be used |
| Forced relay test | `iceTransportPolicy: relay` | Requests relay candidates; verify the selected route rather than assuming success |
| Browser origin restriction | CORS / Origin allowlist | Additional request restriction; not a substitute for bearer authentication |
| Text encoding | Base64 | Encoding only; does not encrypt or hide connection metadata |

## Timing, evidence and publication

| Plain-language name | Technical term / identifier | Meaning in this project |
| --- | --- | --- |
| Round-trip delay | RTT | Time out and back; application ping and ICE statistics measure different layers |
| Age of received state | Snapshot age | Time since receipt; not network RTT or the age of all host simulation work |
| Missed state numbers | Snapshot sequence gaps | Observed gaps; not a percentage of all network packets lost |
| Added test delay | Latency injection | Outgoing application queues in the native lab, not OS packet shaping |
| Stay-alive deadline | Room lease | Per-seat setup inactivity bound; separate from absolute room lifetime |
| Access expiry | Playtest invitation expiry | Stops future authorized service requests; not automatic revocation of already issued TURN credentials |
| Relay expiry | TURN credential TTL | Lifetime of issued credentials; refresh/ICE restart is not implemented |
| Temporary attempt marker | Connection generation | Local cancellation guard against delayed callbacks from prior sessions |
| Safe connection report | Allowlisted diagnostics | Selected metadata only; untrusted client evidence rather than authoritative game state |
| Static game website | GitHub Pages | Downloads HTML/engine/assets/core Wasm; does not execute the backend |
| Service endpoint | Cloudflare Worker | Authorizes setup/credentials/reports; no gameplay simulation |
| Serialized room storage | Durable Object | Coordinates bounded room records and the diagnostics journal |
| Source version | `main` commit | Code/docs identity; separate from the exported playable artifact |
| Published game version | `gh-pages` commit / artifact hashes | Identity of served export bytes; current source alone does not prove what is live |
| Checked behavior | Recorded acceptance | Specific build, route, browser and test conditions; not universal support |

Reserve “server” for a qualified meaning: **host player**, **signaling service**, **TURN relay**, or **static web host**. Reserve “key/code/token” for the specific credential or locator above. These distinctions matter when sharing access, diagnosing connection failures and evaluating authority.
