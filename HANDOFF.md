# Co-op networking milestone

Updated 2026-11-06. Environment: general-x86 (Dev Workbench), /workspace/coop-side-scroller.

## Objective and decisions

Continue the co-op project here, research conventional networking differences and review/patch until clean. Test both peers on this machine; no Runpod. Preserve the original workstation checkout and all transferred uncommitted work. Keep the host snapshot game and deterministic experiment distinct. No publication or PR.

## State

Imported baseline ae4a046 plus the existing deterministic experiment is preserved in bc3e979 on work/network-review-20261106. Implemented bounded remote-actor position interpolation, preserving local guest latency, authoritative state and 60 Hz animation clocks. Patched CDP deadline handling and added explicit local-only/headless browser probe modes without relaxing the default NVIDIA gate. Research and current contracts/backlog are synchronized.

Review found and repaired local-actor delay, render-driven animation timing and premature CDP timeouts. The final changed paths have no remaining actionable self-review findings. This is not an independent human review.

## Verification and limits

Native sanitizer/core/Wasm, 18,000-tick deterministic cross-compiler parity and simulated impairment/recovery, 19 service tests, four CTests, 13 interpolation checks, seven real-main presentation checks, CDP/HTTP regressions, actual local ENet and actual local Chromium WebRTC passed. Godot and browser WebGL verified NVIDIA GTX 960. Browser recovery/reload reached tick 1080; the gameplay capture was opened.

Initial tool/ICE/GPU failures are retained in evidence, with successful fixes distinguished. The GPU browser uses the project-local NVIDIA GLES wrapper with software desktop composition; the WebGL renderer remains hardware. Private art was not copied; the clone uses fallback art. No live TURN, independent-network, mobile, human-feel or full Godot Web room-flow acceptance is claimed.

## Next action

Continue from this General x86 checkout. Local prediction/reconciliation and automatic reconnect/checkpoint negotiation remain explicit future work. Do not repeat setup or move tests to Runpod. Approved native test tools are retained under .local/test-tools, with package hashes and wrappers; no JavaScript packages or system installations were added.

## Evidence

[Review/results](reviews/networking-2026-11-06.md), [presentation contract](specs/snapshot-presentation.md), [research comparison](research/networking-models/report.md), [source ledger](research/networking-models/sources.md). Central research snapshot: /workspace/research/studies/game-networking-models-2026-11-06/. Ignored runtime receipts/logs/capture: .local/network-review-20261106/; compiled receipts/traces: build/. One preexisting completed workbench job was archived to /workspace/.coop-bootstrap-preserved-job-cc71d04c17c44dc8.json to free a job slot; other job history was preserved.
