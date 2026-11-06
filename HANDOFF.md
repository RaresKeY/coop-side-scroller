# Co-op published play session

Updated 2026-11-06. Owning checkout: general-x86 /workspace/coop-side-scroller, branch work/network-review-20261106.

## Objective and decisions

User authorized pushing source and updating GitHub Pages, adding the player-chat TODO, and starting a Terra low agent that only controls a remote player, waits/follows/reacts to the human and stops when told. Both the General x86 environment and human workstation use the public game with Cloudflare TURN; no direct peer route and no Runpod. Preserve the dirty workstation checkout.

## State

Source through ed629e7 is pushed to main. Pages commit 4e157b923a7b912ed5769ab93fdb74b9d2235eb6 is built and every hosted candidate hash verified. Public game build identity is ed629e7924779e562920cbafe1ae4c2c609b5e7c. The chat-window/above-player transparent-backplate request is recorded in BACKLOG.md, not implemented.

The existing expired private invitation was extended seven days without changing its token, and the existing tagged issuer/lobby Worker redeployed; unauthorized/origin/authorized issuance checks returned 401/403/200. No new service or plan was created. Only the tester invitation was transferred privately to the remote browser runtime; management credentials stayed on the workstation.

Remote browser is hosted build, Compatibility TLS 443, relay-only, gathering complete with two relay candidates. Room 817BEB4F / Terra co-op. Terra low agent /root/coop_player has an active wait/follow/interact-until-stop goal, controlling host slot 1 through bounded keyboard actions; human joins as slot 2. Selected-pair/cross-network success remains pending the human joining. The remote browser intentionally uses headless SwiftShader because another workload holds the GPU lease; no performance/GPU claim.

## Verification

Offline secret audit: 577 Git objects, 142 source files and Web export, 22 known values compared, zero findings. Eleven deployment regressions passed. Hosted browser startup, licensed art, real keyboard movement and relay gathering passed. Prior review/contract results remain in reviews/networking-2026-11-06.md. Private art transfer verified 24 file hashes; raw art stays ignored.

General x86 has no Podman; prepared direct Godot runtime built the candidate there. Temporary workstation staging ran the required offline-container audit and project deployment tool, preserving the dirty checkout. Workbench job storage filled, so owned commands/file transfer used existing SSH into the same General x86 container. Completed job records were preserved before removal; other running jobs were untouched.

## Next action and stop

Human opens https://rareskey.github.io/coop-side-scroller/, enters existing playtest key, selects Compatibility (TLS 443), opens Private rooms and joins 817BEB4F. Root forwards stop requests to coop_player and invokes the task-owned player.py stop command. Each action automatically releases keys; session has a bounded ~57-minute lifetime and relay credentials do not auto-refresh.

Control runtime: .local/live-play-20261106/player.py {state|capture|act AXIS JUMP ATTACK SECONDS|stop}. Unix socket only, no public control service. Agent decides actions; no autonomous follower is installed. Current screenshot: .local/live-play-20261106/latest.png. Do not stop unrelated browser/GPU jobs.

## Evidence and remaining work

.local/live-play-20261106/ contains build, controller, relay/setup evidence. Workstation publication receipts/control helper: ~/workspace/.agent-handoffs/coop-live-20261106/. Prior research and reviews remain committed. Actual joined route/play, mobile acceptance and automatic reconnect remain unverified; prediction and chat remain future work.
