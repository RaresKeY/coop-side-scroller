# Automatic TLS review

Updated 2026-11-06. Objective: review and patch automatic TLS retry/faster setup until the reviewed change is clean. Publication hold remains: no push/deployment.

Owner: General x86 `/workspace/coop-side-scroller`, branch `work/network-review-20261106`, source base5c3b8e5. Use Dev Workbench; preserve the dirty workstation checkout and Terra's separate public browser/controller. No Runpod or new dependencies.

Decision: validate/publish already-complete gathering before its deadline check, so a delayed frame cannot discard usable connection details. Pending gathering and missing SDP still time out; no candidates retains its own code. Existing one-shot coordinated TLS retry, 10s eligible-first bounds, 30s/60s TLS/manual bounds, 10s established grace and finite polling bursts remain intact. No Worker/core/wire changes.

State: regression reproduced before patch, full native connection/setup suite passes after. Fresh Web export passes healthy, gathering-stall and terminal-failure live lobby/TURN runs, automatic epoch1/TLS443, names, replicated movement and chat echo, without runtime errors. No further findings in reviewed retry/timing and lifecycle integration. Core freshness passes; unchanged Worker/core suites not rerun. Runtime reuses prepared Godot4.7/native/Wasm/imports with isolated direct headless fallback because nested Podman is unavailable; browser uses software rendering.

Evidence: `.local/auto-compat-review-20261106/` — native-before.log, native-final.log, export.log, healthy/, gather/, terminal/, reviewed.patch and receipt.json. Samples15.96s/25.34s/20.74s are bounded same-machine checks, not internet reliability or hardware/input-latency evidence. Generated Web candidate removed after recording its identity; prepared inputs and all evidence retained.

Next: user review of the local patch; publication waits for release of the hold. Public source40ec88d/game9e76f1d/Pagesbd94a5a unchanged.
