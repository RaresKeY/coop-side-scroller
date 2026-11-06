# Co-op names and chat milestone

Updated 2026-11-06. Owning checkout General x86 `/workspace/coop-side-scroller`, branch `work/network-review-20261106`; preserve dirty workstation checkout. No Runpod.

Objective: named players and Terra, remote name tags/local yellow square, top-right scrollable translucent Enter chat, both-view sender bubbles, and Terra describing actions/questions/conversation. User explicitly answered **Resume Terra with chat after deployment**; the previously completed stop goal does not prohibit the new requested run.

Implementation is complete and ready for publication: reliable authenticated adapter metadata with replay/session/size/rate bounds; native and inline browser composer, safe literal text, bounded history, non-overlapping expiring bubbles, name entry on create/join, envelope version 2/core EC03 unchanged. Old/new adapter versions cannot pair. Worker support for envelope 2 is deployed; publish the final reviewed Worker source together with the client.

Final native unit/JS/service/real ENet checks pass. Local Web names/chat/sender echo/input suppression, inspected four-size captures, separated bubbles, TURN/combat/diagnostics, snapshot blackout and zero-correction batched snapshots pass. Earlier harness focus/early-exit failures are retained. Next: clean export, audit/push/Pages deployment and exact hosted hashes, hosted social/continuity check, launch updated Terra browser, resume existing /root/coop_player with real-keyboard say-stdin and user-requested wait/follow/interact-until-stop goal. Keep code-editing out of Terra's role.

Remote evidence `.local/chat-20261106/`; local receipts `.agent-handoffs/coop-live-20261106/chat/`. Ignored player.py supports state/capture/act/say/say-stdin/stop, chosen name Terra, last12 observed messages, input cleanup,4h runtime. Check helper py_compile then copy to local handoff. Final runtime must use public new build, Compatibility TLS443, no direct peer route. Refresh this handoff and external milestone with new build/room/session after verification.
