# Co-op Side Scroller

Read `specs/_readme.md` before changes. This is a portable C++ co-op core with a focused single-character Godot web/native reference adapter. Preserve its small scope and keep specs synchronized.

Shared rules/authority/messages belong in the engine-independent `core/`, behind `ec_v1_*` C ABI; keep engine APIs, rendering, input capture, clocks and transports in adapters. Read `specs/c-abi.md` and `specs/portable-core.md` before core changes. Never reintroduce a GDScript simulation or manual animation selection.

Explicitly prepare with `python3 tools/build_core.py`; `--check` only checks freshness. Use executable root `./play.sh` through the shared Godot Podman runtime. `tools/build_web.sh` explicitly prepares the single-thread Web export. Normal play does not export. `./play-labs.sh` opens the compact native network chooser; `./play-labs.sh pair` opens separate host/guest processes. See `specs/network-lab.md` for control routing and owned teardown. Keep gameplay UI simple; no animation inspection controls. Automated rendered runs use headless Gamescope, muted/Dummy audio and hardware GPU. `--capture` is finite; native `--test-host` and `--test-client` are finite localhost transport checks.

Public source must exclude `assets/private/`, imported caches and build candidates. CraftPix raw art remains private; the importer and hash manifest are public. Do not add a project license. Publishing must keep playable compiled assets in the static site, separate from source art. Signaling server and TURN relay work are explicitly deferred in BACKLOG.md. Do not deploy services or claim reliable internet co-op from local tests.
