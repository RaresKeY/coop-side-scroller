# Co-op responsiveness milestone

Updated 2026-11-06. Owning checkout: General x86 `/workspace/coop-side-scroller`, branch `work/network-review-20261106`. Preserve the dirty workstation checkout.

## Objective and decisions

Both players must receive immediate local input/animation response, regardless of who hosts. The shared C++ core predicts the guest locally and reconciles host acknowledgements; authority and confirmed world effects remain on the host. Shipping protocol 2 requires both peers to reload. Each view keeps its own character's original colors, tints the partner and shows a gold local triangle. The RPG chat/above-player transparent backplate request remains a TODO in BACKLOG.md.

## State

Implementation and focused native/Wasm/Godot/ENet checks pass. The existing tagged Worker now accepts separate matching protocol-1/2 signaling pairs; issuance checks pass 401/403/200. Browser delayed-snapshot verification passes: first local tick moves and selects run animation without a new accepted snapshot. The full private-lobby relay/relay, replicated combat (HP 12→11), diagnostic upload and intentional disconnect checks pass. Source/game build c64e7beba57718a58addb6c88c804201c4f5f800 is pushed to main; Pages deployment 568941cef6176f2fc913a5719306aa6d62a565d4 is built and every hosted hash matches. Fresh hosted startup/real keyboard input checks pass. Public URL: https://rareskey.github.io/coop-side-scroller/. This later documentation commit does not change the deployed game identity. No new services or Runpod resources. Workbench job storage is full; existing SSH enters the same General x86 container. Other jobs and the occupied GPU lease remain untouched.

## Next action

Human reloads the public page, enters the existing playtest key, selects Compatibility (TLS 443) and joins room **1FC4ABE6 / Terra co-op** through Private rooms. `/root/coop_player` is the user-requested Terra low controller with an active wait/follow/interact-until-stop goal, resumed and waiting for the human. The replacement browser is root exec session 21405; gathering completed with relay candidates. Human is guest slot 2; Terra is host slot 1. Forward a stop request and stop only the owned browser. Use `.local/live-play-20261106/player.py {state|capture|act AXIS JUMP ATTACK SECONDS|stop}`; bounded keyboard actions release all keys. No automatic follower algorithm.

## Evidence and limits

`.local/responsiveness-20261106/`: core/deterministic/service/Godot/ENet logs and successful browser proof. `.local/live-play-20261106/`: prior actual human route/play; selected local relay/TLS with approximately 142 ms RTT. Earlier rooms/browsers are retired; only the replacement runtime is owned by this session. Rooms have an absolute ten-minute lifetime. Current rendering is intentional headless SwiftShader; no input-to-display or FPS improvement is claimed from CDP/core observations. Native tests do not establish human feel. Prediction corrections, remote players and authoritative effects retain network latency. Automatic reconnect and mobile acceptance remain unverified.

Workstation evidence: `~/workspace/.agent-handoffs/coop-live-20261106/responsiveness/` contains deployment/audit/test logs, source build metadata, browser proof, relay screenshots and manifest. Reproducible Web candidate/staging can be removed after this receipt; retain native/Wasm preparation, private art, runtime and evidence.
