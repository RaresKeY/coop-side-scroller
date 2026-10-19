# Ember Bridge — co-op prototype

A small Godot 4.7 side-scroller for experimenting with two-player co-op independently of another game's source. One CraftPix Prototype Saber Fighter is wired to idle, walk, run, jump, attack, hurt and death clips. A compact row lets you inspect clips without importing the full asset collection. The arena, movement and dummy are deliberately simple. No Mangler's Fate code or assets are used.

## Run

On the owning workstation: `./play.sh`. Other machines: import `project.godot` with Godot 4.7. Move with A/D or arrows, jump with Space, attack with J, reset dummy with R. Choose Auto to return from an animation preview to movement-driven clips. This build is silent.

Raw CraftPix art is excluded from public source. The source checkout runs with a small original fallback character. To restore the licensed selection from your own library:

```sh
python3 tools/import_craftpix.py --library ../CraftPix
./play.sh --headless --editor --import --quit
```

The import script needs Python 3; it copies seven character sheets, three button images and the character notice, records hashes and enables mipmaps. This is game integration, not an artwork exporter or AI training/evaluation dataset. See `assets/craftpix-manifest.json` and `THIRD_PARTY_NOTICES.md`.

## Browser P2P

The web build uses WebRTC data channels. Host runs simulation; guest sends bounded movement/jump/attack input. Host sends snapshots at 20 Hz. Browser Host creates an offer; Join opens the code panel. Send codes through your existing private chat:

1. Host: Create offer, wait for your code, select/copy it and send it to guest.
2. Guest: paste offer in the lower field, Accept pasted code, wait for the answer code and send it back.
3. Host: paste answer in lower field, Accept. Wait for connection status.

Keep both tabs active during setup. This manually replaces the signaling service, which is deferred. A public Google STUN endpoint is configured for address discovery; there is **no TURN relay**. Some NAT/firewall combinations will fail. Refresh or Solo resets a session. Codes contain temporary connection details; do not post them publicly.

Native Host/Join uses ENet on UDP 27840 for local/LAN development. To run two native instances on this workstation, explicitly use `godot-podman run --no-lock` for the second instance; `play.sh` normally serializes project launches. Native ENet testing does not establish browser WebRTC or internet connectivity.

## Static site

`./tools/build_web.sh` creates the current candidate in ignored `build/web/`. Serve it locally using `python3 -m http.server 8080 --directory build/web`. Export uses Compatibility rendering and disables threads, allowing ordinary HTTPS GitHub Pages hosting without custom isolation headers. The source branch excludes licensed raw art; the Pages branch contains only the exported playable game and notices. No account credentials belong in either branch.

GitHub Pages is a static host, not a signaling or relay server. Firebase, Supabase and VPS options are assessed in [design/network-options.md](design/network-options.md). Deferred work is in [BACKLOG.md](BACKLOG.md).
