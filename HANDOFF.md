# Co-op responsiveness milestone

Updated 2026-11-06. Owning checkout: General x86 `/workspace/coop-side-scroller`, branch `work/network-review-20261106`. Preserve the dirty workstation checkout.

## Objective and decisions

Both players must receive immediate local input/animation response, regardless of who hosts. The shared C++ core predicts the guest locally and reconciles host acknowledgements; authority and confirmed world effects remain on the host. Shipping protocol 2 requires both peers to reload. Each view keeps its own character's original colors, tints the partner and shows a gold local triangle. The RPG chat/above-player transparent backplate request remains a TODO in BACKLOG.md.

## State

Implementation and focused native/Wasm/Godot/ENet checks pass. The existing tagged Worker now accepts separate matching protocol-1/2 signaling pairs; issuance checks pass 401/403/200. Browser delayed-snapshot verification passes: first local tick moves and selects run animation without a new accepted snapshot. The full private-lobby relay/relay, replicated combat (HP 12→11), diagnostic upload and intentional disconnect checks pass. Pages rollout is in progress. No new services or Runpod resources. Workbench job storage is full; existing SSH enters the same General x86 container. Other jobs and the occupied GPU lease remain untouched.

## Next action

Complete the two-browser delayed-snapshot check, audit/push/deploy the Web candidate, verify hosted hashes/startup/input and restart the remote play browser. `/root/coop_player` is the user-requested Terra low controller with an active wait/follow/interact-until-stop goal, currently paused for rollout. Resume with a replacement room only after publication. Forward a stop request and stop only the owned browser. Use `.local/live-play-20261106/player.py {state|capture|act AXIS JUMP ATTACK SECONDS|stop}`; bounded keyboard actions release all keys. No automatic follower algorithm.

## Evidence and limits

`.local/responsiveness-20261106/`: core/deterministic/service/Godot/ENet logs and pending browser proof. `.local/live-play-20261106/`: prior actual human route/play; selected local relay/TLS with approximately 142 ms RTT. Room E415CFA0 and the old browser are retired for rollout. Rooms have an absolute ten-minute lifetime. Current rendering is intentional headless SwiftShader; no input-to-display or FPS improvement is claimed from CDP/core observations. Native tests do not establish human feel. Prediction corrections, remote players and authoritative effects retain network latency. Automatic reconnect and mobile acceptance remain unverified.
