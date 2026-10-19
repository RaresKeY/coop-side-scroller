# Co-op Side Scroller

Read `specs/_readme.md` before changes. This is a focused single-character Godot web/P2P prototype. Preserve its small scope and keep specs synchronized.

Use executable root `./play.sh` through the shared Godot Podman runtime. `tools/build_web.sh` explicitly prepares the single-thread Web export. Normal play does not export. Automated rendered runs use headless Gamescope, muted/Dummy audio and hardware GPU. `--capture` is finite; native `--test-host` and `--test-client` are finite localhost transport checks.

Public source must exclude `assets/private/`, imported caches and build candidates. CraftPix raw art remains private; the importer and hash manifest are public. Do not add a project license. Publishing must keep playable compiled assets in the static site, separate from source art. Signaling server and TURN relay work are explicitly deferred in BACKLOG.md. Do not deploy services or claim reliable internet co-op from local tests.
