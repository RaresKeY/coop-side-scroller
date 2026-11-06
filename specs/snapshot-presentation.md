# Snapshot presentation

## Human input

Continue co-op networking in the General x86 clone, use same-machine tests without Runpod, compare conventional networking and review/patch the code. The bounded interpolation implementation is an agent-selected continuation of the recorded backlog.

## Observed implementation

`src/snapshot_interpolator.gd` buffers up to 32 accepted snapshot views. Host fixed ticks are unwrapped into a local timeline. The nominal render delay is six ticks (100 ms at 60 Hz). A monotonic render cursor interpolates x/y between known snapshots and holds the newest available position during packet gaps; it never extrapolates.

`src/main.gd` submits views only after successful replica receives. Only remote actors are delayed: guest slot 2 retains current authoritative position until local prediction is implemented. HP, membership, facing, animation state and events remain authoritative/current. This is an adapter presentation buffer, not another movement solver.

Known membership changes or a receive gap over 500 ms reset the trajectory; connection/session reset clears the buffer. Duplicate or backward ticks cannot replace history. Uint32 host tick wrap remains continuous. A leave/rejoin entirely between snapshots remains unobservable without a wire lifetime identifier.

`update_sprites` still calls CharacterView.present at 60 Hz, because that method advances pose and landing clocks. The render callback only calls `update_sprite_positions`; higher display FPS therefore does not speed up animations.

## Verification

`tests/snapshot_interpolator.gd` checks interpolation, local-slot exclusion, copied state, jitter, loss/hold, suspension, rejoin, wrap, history bounds and session reset. `tests/snapshot_presentation.gd` exercises the real main/CharacterView integration with synthetic frame textures, preserving core state and fixed pose timing across repeated render updates.

Run after explicit core preparation/import with a compatible Godot 4.7 runtime:

```sh
godot --headless --path . --script tests/snapshot_interpolator.gd
godot --headless --path . --script tests/snapshot_presentation.gd
```

Current dated results and runtime limits are in [verification](verification.md). Private CraftPix art is not required by these fixtures.

## AI Inferred and limits

Six ticks is a bounded initial policy, not measured optimal latency or human acceptance. Render smoothing trades remote visual delay for continuity. Local prediction/reconciliation, adaptive delay, full visual-state interpolation, host migration and automatic reconnect remain separate work.
