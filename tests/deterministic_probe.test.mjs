// Exercise the actual browser fixture with real Wasm, controlled clocks and loss.
const root = new URL('../', import.meta.url);
const wasm = await Deno.readFile(new URL('build/wasm/ember_core.wasm', root));
const html = await Deno.readTextFile(new URL('tests/deterministic_browser.html', root));
const script = html.split('<script type="module">')[1].split('</script>')[0]
  .replace("'/adapters/web/deterministic_peer.mjs'",
    JSON.stringify(new URL('adapters/web/deterministic_peer.mjs', root).href));
const check = (ok, reason) => { if (!ok) throw new Error(reason); };
let imports = 0;

async function fixture(run) {
  const names = ['fetch', 'document', 'RTCPeerConnection', 'setInterval', 'clearInterval', 'probe'];
  const original = new Map(names.map(name => [name, Object.getOwnPropertyDescriptor(globalThis, name)]));
  const timers = new Map(), channels = [], probes = [], pending = [];
  let timerId = 0, dropping = () => false;
  class Connection {
    iceGatheringState = 'complete';
    localDescription = {sdp: '', toJSON: () => ({type: 'offer', sdp: ''})};
    createDataChannel() {
      const index = channels.length;
      const channel = {readyState: 'open', bufferedAmount: 0,
        send(packet) { if (!dropping(index, packet)) pending.push([1 - index, packet.slice()]); }};
      channels.push(channel);
      return channel;
    }
    async createOffer() { return {type: 'offer', sdp: ''}; }
    async setLocalDescription() {}
    close() {}
  }
  Object.assign(globalThis, {
    fetch: () => Promise.resolve(new Response(wasm)),
    document: {querySelector: () => ({textContent: ''})},
    RTCPeerConnection: Connection,
    setInterval: callback => { const id = ++timerId; timers.set(id, callback); return id; },
    clearInterval: id => timers.delete(id),
  });
  try {
    for (const slot of [1, 2]) {
      await import('data:text/javascript,' + encodeURIComponent(script + '\n// fixture ' + ++imports));
      const probe = globalThis.probe;
      probes.push(probe);
      await probe.prepare(slot);
      await probe.connect([], false);
    }
    const step = () => {
      for (const callback of [...timers.values()]) callback();
      while (pending.length) {
        const [destination, packet] = pending.shift();
        channels[destination].onmessage({data: packet.buffer});
      }
      for (const p of probes) check(p.status().error === null, p.status().error);
    };
    await run({probes, step, loss: policy => { dropping = policy; }});
  } finally {
    for (const p of probes) p.close();
    for (const [name, descriptor] of original) {
      if (descriptor) Object.defineProperty(globalThis, name, descriptor);
      else delete globalThis[name];
    }
  }
}

function converge(probes, step, end, budget) {
  for (let i = 0; i < budget; i++) {
    step();
    if (probes.every(p => p.status().confirmed_tick === end)) {
      check(JSON.stringify(probes[0].save()) === JSON.stringify(probes[1].save()), 'checkpoint divergence');
      check(JSON.stringify(probes[0].eventTrace()) === JSON.stringify(probes[1].eventTrace()), 'event divergence');
      check(probes.every(p => !p.status().desync && !p.status().dropped_events), 'lost events or desync');
      return;
    }
  }
  throw new Error('No convergence: ' + JSON.stringify(probes.map(p => p.status())));
}

Deno.test('browser probe retries lost final inputs after a non-multiple-of-12 target', () =>
  fixture(({probes, step, loss}) => {
    const dropped = [0, 0], end = 599;
    loss((source, packet) => {
      const view = new DataView(packet.buffer, packet.byteOffset, packet.byteLength);
      const count = view.getUint8(45), last = view.getUint32(28, true) + count - 1;
      if (count && last === end && !dropped[source]) { dropped[source]++; return true; }
      return false;
    });
    for (const p of probes) p.start(end);
    converge(probes, step, end, end + 500);
    check(dropped.every(count => count === 1), 'tail loss was not exercised');
  }));

Deno.test('browser probe pauses contiguous input capture through a long blackout', () =>
  fixture(({probes, step, loss}) => {
    loss(() => true);
    for (const p of probes) p.start(401);
    for (let i = 0; i < 600; i++) step();
    check(probes.every(p => p.status().local_through <= 120), 'capture lead is unbounded');
    check(probes.every(p => p.status().tick === 12 && p.status().confirmed_tick === 0), 'prediction bound');
    loss(() => false);
    converge(probes, step, 401, 3000);
  }));
