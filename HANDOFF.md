# Co-op networking milestone

Updated 2026-11-06. Environment: general-x86 (Dev Workbench), /workspace/coop-side-scroller.

## Objective and decisions

Review and patch the co-op networking work until no actionable findings remain. Work in this normal checkout; test both peers on this machine, never Runpod. Preserve the original workstation checkout and transferred work. No push, PR or publication. Keep the shipping host/snapshot game separate from the deterministic experiment.

## State

Branch work/network-review-20261106 contains upstream ae4a046, preserved transferred work bc3e979 and interpolation/test hardening 475e51e. The follow-up review found two browser-probe recovery defects: retries stopped at targets not divisible by twelve, and prolonged packet loss exhausted captured-input history. Both are repaired. Retry timing uses an independent callback clock; capture pauses within a 120-tick lead and never skips a pending input. Two regressions exercise the actual browser fixture and real Wasm. Current specs and review evidence are synchronized. No further actionable self-review findings remain in the reviewed paths; no independent human review is claimed.

## Verification and limits

The follow-up full deterministic suite passed native sanitizers/contracts, twelve impairment cases, checkpoint recovery and 18,000-tick GCC/Clang/Wasm state/checkpoint/event parity, plus the new loss regressions and existing Python checks. Worker/lobby/diagnostics: 27 passed.

Actual same-machine headless Chromium WebRTC passed a 5.5-second injected packet blackout and one lost final packet per direction at tick 599, matching native state/events. Fresh transport reached 840; creator departure and page reload reached 1080 with no desync/event drops. The preceding pass verified Godot ENet, interpolation/pose clocks and NVIDIA Godot/WebGL; those unchanged paths were not rerun in this network-only follow-up.

No live TURN, independent-network, mobile, human-feel or full Godot Web/private-room acceptance is claimed. Private art was not copied; the clone uses fallback art. No new dependencies were downloaded.

## Next action

Continue in this General x86 checkout. Prediction/reconciliation and automatic reconnect/checkpoint negotiation remain future work. Reuse approved project-local test tools under .local/test-tools and the prepared agent-kit runtime. No setup repetition or Runpod tests are needed.

## Evidence

[Review/results](reviews/networking-2026-11-06.md), [experiment contract](specs/deterministic-coop.md), [presentation contract](specs/snapshot-presentation.md), [research](research/networking-models/report.md). Follow-up receipts/reproductions: .local/network-rereview-20261106/. Prior evidence/capture: .local/network-review-20261106/. Build traces: build/deterministic/. Test dependency pins: .local/test-tools/packages.json.
