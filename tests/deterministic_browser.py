#!/usr/bin/env python3
"""Finite two-page Wasm/DataChannel probe under headless Gamescope.

--relay uses only the existing protected TURN issuer, not a new service. This
tests the experimental adapter, not Godot integration or automatic lobby rejoin.
"""
import argparse
import contextlib
import functools
import http.server
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import threading
import time
import urllib.request

from browser_cdp import CDP, QuietHandler

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.deterministic_lab import Peer, controls, library, trace


class Handler(QuietHandler):
    def send_head(self):
        if self.path.split('?')[0] not in {
            '/tests/deterministic_browser.html', '/adapters/web/deterministic_peer.mjs',
            '/build/wasm/ember_core.wasm',
        }:
            self.send_error(404)
            return None
        return super().send_head()


def wait(check, seconds=20):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        value = check()
        if value:
            return value
        time.sleep(.1)
    raise TimeoutError('Deterministic browser probe deadline')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--relay', action='store_true')
    args = parser.parse_args()
    if not os.environ.get('WAYLAND_DISPLAY') and not os.environ.get('DISPLAY'):
        parser.error('Run under gamescope --backend headless; see specs/deterministic-coop.md')
    out = ROOT / 'build/deterministic'
    out.mkdir(parents=True, exist_ok=True)
    report_path = out / ('browser-relay.json' if args.relay else 'browser-direct.json')
    report_path.unlink(missing_ok=True)
    subprocess.run([sys.executable, str(ROOT / 'tools/build_core.py'), '--check'], check=True)
    api = library(ROOT / 'build/native/libember_core.so')
    reference = trace(api, 840)
    signal.signal(signal.SIGTERM, lambda *_: (_ for _ in ()).throw(SystemExit(143)))
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 27841 if args.relay else 0),
        functools.partial(Handler, directory=str(ROOT)))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    url = f'http://127.0.0.1:{server.server_port}/tests/deterministic_browser.html'
    pages = []
    with contextlib.ExitStack() as resources:
        resources.callback(server.server_close)
        resources.callback(server.shutdown)
        profile = resources.enter_context(tempfile.TemporaryDirectory(prefix='ember-deterministic-browser-'))
        log = resources.enter_context((out / 'browser-console.log').open('w'))
        browser = subprocess.Popen(['chromium', '--ozone-platform=x11', '--mute-audio',
            '--no-first-run', '--no-default-browser-check', '--remote-debugging-port=0',
            '--disable-background-timer-throttling', '--disable-renderer-backgrounding',
            '--remote-allow-origins=*', f'--user-data-dir={profile}', 'about:blank'], stdout=log, stderr=log)
        control = None
        try:
            port_file = Path(profile) / 'DevToolsActivePort'
            wait(port_file.exists)
            base = f'http://127.0.0.1:{int(port_file.read_text().splitlines()[0])}'
            control = CDP(json.load(urllib.request.urlopen(base + '/json/version'))['webSocketDebuggerUrl'])
            for _ in range(2):
                target = control.call('Target.createTarget', {'url': 'about:blank'})['targetId']
                tabs = json.load(urllib.request.urlopen(base + '/json/list'))
                page = CDP(next(t for t in tabs if t['id'] == target)['webSocketDebuggerUrl'])
                pages.append(page)
                page.call('Runtime.enable'); page.call('Page.navigate', {'url': url})
                wait(lambda: page.evaluate('!!globalThis.probe'))
            renderer = pages[0].evaluate("""(()=>{const gl=document.createElement('canvas').getContext('webgl');
              return gl?.getParameter(gl.getExtension('WEBGL_debug_renderer_info').UNMASKED_RENDERER_WEBGL)})()""")
            assert renderer and 'NVIDIA' in renderer, renderer
            for slot, p in enumerate(pages, 1):
                # Superseded asynchronous setup must not replace a fresh peer.
                settled = p.evaluate(f'Promise.allSettled([probe.prepare({3 - slot}),probe.prepare({slot})]).then(results=>results.map(r=>r.status))')
                assert settled == ['rejected', 'fulfilled'], settled

            def ice(page):
                if not args.relay:
                    return [{'urls': ['stun:stun.cloudflare.com:3478']}]
                invitation = json.loads((Path.home() / '.config/cloudflare-api/access-coop-side-scroller-issuer.json').read_text())['token']
                # Secret stays in memory; no URL, page storage, report or logs.
                result = page.evaluate("""(async()=>{const response=await fetch(
                  'https://ember-coop-credentials.ember-bridge-playtests.workers.dev/v1/ice',
                  {method:'POST',headers:{Authorization:'Bearer '+""" + json.dumps(invitation) + """}});
                  if(!response.ok)throw new Error('ICE issuance HTTP '+response.status);
                  return (await response.json()).iceServers;})()""")
                return result

            def connect():
                offer = pages[0].evaluate('probe.connect(' + json.dumps(ice(pages[0])) + ',' + json.dumps(args.relay) + ')')
                answer = pages[1].evaluate('probe.connect(' + json.dumps(ice(pages[1])) + ',' + json.dumps(args.relay) + ',' + json.dumps(offer) + ')')
                pages[0].evaluate('probe.answer(' + json.dumps(answer) + ')')
                try:
                    wait(lambda: all(p.evaluate('probe.status().ready') == 'open' for p in pages), 30)
                except TimeoutError:
                    raise AssertionError({'setup': [p.evaluate('probe.status()') for p in pages]}) from None

            def run(end, begin=0):
                for p in pages:
                    p.evaluate(f'probe.start({end})')

                def complete():
                    state = [p.evaluate('probe.status()') for p in pages]
                    assert all(not s['error'] for s in state), state
                    return state if all(s['confirmed_tick'] == end for s in state) else None

                state = wait(complete, 35)
                checkpoints = [p.evaluate('probe.stop()') for p in pages]
                assert checkpoints[0] == checkpoints[1]
                assert state[0]['state_hash'] == state[1]['state_hash']
                assert state[0]['state_hash'] == reference['hashes'][end - 1]
                expected_events = [e for e in reference['events'] if begin < e[0] <= end]
                for p, s in zip(pages, state):
                    assert not s['desync'] and not s['dropped_events'], s
                    assert p.evaluate('probe.eventTrace()') == expected_events, 'Native/browser confirmed events differ'
                routes = [p.evaluate('probe.route()') for p in pages]
                if args.relay:
                    assert all(r['local'] == 'relay' and r['remote'] == 'relay' for r in routes), routes
                return {'end_tick': end, 'peers': state, 'routes': routes}, checkpoints[0]

            connect()
            first, checkpoint = run(600)
            print('Deterministic real DataChannel convergence PASS', flush=True)
            # Recreate both Wasm instances and the transport; same checkpoint,
            # fresh epoch. This is an explicit test-controlled recovery barrier.
            for slot, p in enumerate(pages, 1):
                p.evaluate(f'probe.prepare({slot},' + json.dumps(checkpoint) + ',1)')
            connect()
            second, checkpoint = run(840, 600)
            pages[0].evaluate('probe.close()')
            pages[1].evaluate('probe.prepare(2,' + json.dumps(checkpoint) + ',2,2)')
            solo = pages[1].evaluate('probe.solo(1080)')
            assert solo['confirmed_tick'] == 1080 and solo['error'] is None
            oracle = Peer(api, 2, 0)
            try:
                oracle.load(bytes(checkpoint), 2, 2)
                for tick in range(841, 1081):
                    assert oracle.input(tick, controls(tick, 2)) == 0
                    oracle.advance(tick)
                assert solo['state_hash'] == oracle.stats().state_hash
                assert not solo['dropped_events'] and not solo['desync']
                assert pages[1].evaluate('probe.save()') == list(oracle.save())
                assert pages[1].evaluate('probe.eventTrace()') == [list(e) for e in oracle.events]
            finally:
                oracle.close()
            pages[1].evaluate('probe.persist();probe.close()')
            pages[1].call('Page.navigate', {'url': url})
            wait(lambda: pages[1].evaluate('!!globalThis.probe'))
            restored = pages[1].evaluate('probe.restoreLocal()')
            assert restored['state_hash'] == solo['state_hash'] and restored['confirmed_tick'] == 1080
            assert all(not p.errors for p in pages), [p.errors for p in pages]
            report = {'result': 'pass', 'transport': 'Cloudflare TURN' if args.relay else 'local direct WebRTC',
                'renderer': renderer, 'initial': first, 'fresh_transport_recovery': second,
                'creator_departure_solo_tick': solo['confirmed_tick'], 'local_reload_tick': restored['confirmed_tick'],
                'boundary': 'Two local Chromium pages, experimental adapter; recovery coordinated by test, background throttling disabled; transport counters are not provider billing'}
            report_path.write_text(json.dumps(report, indent=2) + '\n')
            print(json.dumps(report, indent=2), flush=True)
        finally:
            for p in pages:
                try:
                    p.evaluate("probe?.close();localStorage.removeItem('deterministic-probe-checkpoint')")
                except Exception:
                    pass
                p.socket.close()
            if control:
                control.socket.close()
            browser.terminate()
            try:
                browser.wait(timeout=5)
            except subprocess.TimeoutExpired:
                browser.kill(); browser.wait(timeout=5)


if __name__ == '__main__':
    main()
