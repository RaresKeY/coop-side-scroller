# Runpod agent browser: setup and smoke test

Use this separate browser controller for programmatic remote testing of Ember Bridge. It avoids the clipboard and streamed-desktop input problems encountered with the manual Firefox desktop. It does not change the game's pairing or network protocol.

## Existing template and tooling

- Private Runpod template: **Agent Browser Controller**, ID `jd3i2gy4au`.
- Local tooling: `~/workspace/tooling/runpod-browser` (independent repository).
- Controller implementation, API contract and image digest: that tooling project's `README.md` and `specs/`.
- Runtime: offscreen Chrome on Xvfb, using Mesa llvmpipe software rendering.
- Pod: secure CPU3 compute-optimized, 2 vCPUs, 4 GB RAM, 10 GB disposable disk; no persistent volume.
- Only the authenticated controller on `8888/http` is exposed through Runpod HTTPS. Raw CDP, ChromeDriver and X display ports are not exposed.

The template already exists. Do not run `manage.py template` again for ordinary testing. Its source is embedded in the private template; deploying needs no game publication or custom image upload. The user's **Disposable Firefox Browser** template remains separate and unchanged.

## Deploy, test and clean up

Run on the configured workstation:

```sh
cd ~/workspace/tooling/runpod-browser
python3 -m unittest -v test_controller.py
python3 manage.py deploy
python3 manage.py status
python3 smoke.py
python3 manage.py delete
```

Deployment creates a fresh controller token and saves the private connection receipt automatically. `smoke.py` exercises the public game at `https://rareskey.github.io/coop-side-scroller/`. Delete the disposable pod after testing; the template remains available. Compute pricing observed on 2026-10-19 was approximately $0.06/hour plus storage. This workflow does not schedule automatic shutdown.

If a creation request fails ambiguously, inspect the Runpod console and private receipt before retrying. Do not create duplicate pods or templates blindly. The helper refuses duplicate creation when an owned resource is already recorded, and deletion checks the exact saved pod ID and expected name.

## Programmatic control

Run Python from the tooling directory. The client loads credentials privately; no token belongs in a command line, URL or script:

```python
from client import Browser
from pathlib import Path
import time

browser = Browser()
browser.navigate('https://rareskey.github.io/coop-side-scroller/')

deadline = time.monotonic() + 90
while not browser.evaluate('globalThis.EmberCoreWeb?.diagnostics().calls > 120'):
    if time.monotonic() > deadline:
        raise RuntimeError('Game startup timed out')
    time.sleep(1)

state = browser.evaluate('EmberCoreWeb.diagnostics()')
# Close the setup menu / choose Play solo before testing gameplay input.
# Use the live canvas rectangle to convert scene coordinates to browser pixels.
point = browser.evaluate("""(() => {
    const r = document.querySelector('canvas').getBoundingClientRect();
    const scale = Math.min(r.width / 960, r.height / 540);
    return {x: r.x + (r.width - 960 * scale) / 2 + 160 * scale,
            y: r.y + (r.height - 540 * scale) / 2 + 172 * scale};
})()""")
browser.click(point['x'], point['y'])
browser.key('d')
try:
    time.sleep(0.5)
finally:
    browser.key('d', False)
browser.screenshot(Path('/tmp/ember-runpod.png'))
```

The scene coordinates above match the public build used for the smoke test; update them if its menu layout changes. Key hold duration includes control-request latency and is not a precise simulation-tick measurement. `Browser.command(method, params)` also supports selected CDP methods for text insertion, input, screenshots, network emulation and pre-navigation instrumentation. See the controller's allowlist before extending a test.

For two-peer testing, `tests/browser_cross_network.py` in the game project now drives the workstation host and Runpod guest, instruments before navigation, and exchanges connection descriptions in memory through the guided UI. It accounts for aspect-fit letterboxing when converting game coordinates; the native DOM dialog uses browser pixels directly. Godot masked text fields need key events, while the native DOM code field supports `Input.insertText`. Do not infer human clipboard success from this automated boundary.

## Credentials and access

The existing Runpod account key remains in `~/.runpod/config.toml`. The tool's receipt is in owner-only `~/.config/runpod-browser/receipt.json`. Never copy either file's contents into this project, screenshots, logs or chat. The template itself contains no account key or shared controller password. For manual console deployment, a fresh secret `BROWSER_CONTROL_TOKEN` of at least 32 characters is required; the helper handles this automatically.

All controller requests require bearer authentication. Browser-origin requests and token query parameters reject. The API is for trusted operators: page evaluation can execute arbitrary JavaScript and issue browser requests; the navigation allowlist is not a complete network sandbox. Use a dedicated disposable browser, never a personal profile. The client supplies a browser-compatible User-Agent because the Runpod proxy rejected Python's default with Cloudflare 1010/403.

## Verified scope

On 2026-10-19, a fresh remote instance passed:

- Authenticated HTTPS access and unauthorized-request rejection.
- Real mouse clicks, text insertion and key down/up events.
- WebGL2 with `ANGLE (Mesa, llvmpipe (LLVM 20.1.2 256 bits), OpenGL 4.5)`.
- Public Godot/Wasm game startup and player movement; core tick advanced 71 to 161, and player X advanced 180000 to 460467 in core milli-units.
- Full-scene screenshot inspection.

Sanitized evidence is retained locally in the tooling project's ignored `build/smoke.json` and `build/runpod-game-smoke.png`. The smoke pod was deleted afterward; the private template remains.

This smoke did **not** verify cross-network co-op, TURN routing, replicated combat, Firefox compatibility or GPU performance. Initial headless browser attempts failed WebGL2 initialization; the accepted template uses Xvfb and Mesa. No game source, GitHub deployment, signaling service or relay deployment was changed by this controller setup.

## Cross-network co-op follow-up

The public game passed `tests/browser_cross_network.py` on 2026-10-19: independent workstation and Runpod Wasm cores, relay-only configuration, relay/relay selected candidates on both, guest movement/combat, host movement replicated back, and matching HP 10 after guest attacks. Observed candidate-pair RTT was 161–179 ms. Sanitized game-project evidence is in ignored `build/cross-network.json` and two full-scene captures; both were visually inspected.

Run from the game checkout after explicit controller deployment:

```sh
gamescope --backend headless -W 960 -H 540 -w 960 -h 540 --xwayland-count 1 -- python3 tests/browser_cross_network.py
```

The harness does not own deployment/deletion. Remove the owned disposable pod afterward with `python3 manage.py delete` in the controller project. The manual Firefox desktop remains a separate user-owned resource; inspect its current status and preserve it. Automated copying is captured in memory; this does not verify the Firefox remote clipboard, general NAT reachability, direct routes, or blocked-UDP/TLS-only relay. Private lobby signaling is now deployed and tested as described below.


## Automatic lobby cross-network test

`tests/browser_lobby_cross_network.py` exercises the public private-room UI instead of exchanging offer/reply codes. It uses the same controller receipt and explicit deploy/delete lifecycle. Run it under the Gamescope command above with that filename. It supports both the original Godot access field and the newer native DOM key-entry dialog. It creates its own room and joins only that room's captured ID, then checks independent cores, room cleanup, forced-relay routing, guest combat and movement in both directions.

The 2026-10-19 run against Pages `8cf749d` passed: relay/relay on both, ICE RTT 218–228 ms, HP 12→9 on both and matching final positions. Native DOM access entry was used on both browsers. The full-scene captures were visually inspected. See [private lobby acceptance](../specs/private-lobbies.md#separate-network-lobby-acceptance) for evidence and limitations. The owned controller pod `n2sfsl0xy7g2nj` was deleted afterward; manual Firefox pod `7whu5iynn96q3d` remained running and untouched.

Reports are sanitized: `build/lobby-cross-network-latest.json` records the current attempt and `build/lobby-cross-network.json` retains the last success. Inspect the report rather than relying on Gamescope's process status. No browser-controller key, playtest key, TURN credential, SDP or candidate address belongs in these files. No Firefox or general NAT-reliability claim follows from this Chrome test.
