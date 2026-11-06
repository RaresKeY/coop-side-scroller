import {createDeterministicPeer} from '../adapters/web/deterministic_peer.mjs';
const root = new URL('../', import.meta.url);
const module = await WebAssembly.compile(await Deno.readFile(new URL('build/wasm/ember_core.wasm', root)));
const traces = JSON.parse(await Deno.readTextFile(new URL('build/deterministic/native-traces.json', root)));
const check = (test, reason) => { if (!test) throw new Error(reason); };
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const session = Uint8Array.from({length: 16}, (_, i) => i + 1);
// Creation owns the validated identity even if the caller reuses its buffer
// while asynchronous Wasm instantiation is still pending.
const callerSession = session.slice();
const pendingPeer = createDeterministicPeer({module, slot: 1, session: callerSession});
callerSession.fill(0);
const ownedPeer = await pendingPeer;
try { check(same([...ownedPeer.pack(0, 0).slice(4, 20)], [...session]), 'session ownership'); }
finally { ownedPeer.close(); }
function controls(tick, slot, seed) {
  const value = (Math.imul(tick, 1103515245) + slot * 12345 + Math.imul(seed, 2654435761)) >>> 0;
  let axis = [1000, -1000, 333, -499, 0, 1000][(Math.floor(tick / 73) + seed + slot) % 6];
  if (tick < 170) axis = 1000;
  return [axis, (tick % 47 < 7 ? 1 : 0) | (value & 8 ? 2 : 0)];
}
let total = 0;
for (const trace of traces) {
  const peers = await Promise.all([1, 2].map(slot => createDeterministicPeer({module, slot, session, prediction: slot === 1 ? 0 : 12})));
  let checkpointIndex = 0, eventIndex = 0;
  try {
    for (let tick = 1; tick <= trace.ticks; ++tick) {
      for (let i = 0; i < 2; ++i) check(peers[i].input(tick, ...controls(tick, i + 1, trace.seed)) === 0, 'input');
      for (let i = 0; i < 2; ++i) check(peers[1 - i].receive(i + 1, peers[i].pack(tick, 1)) === 0, 'receive');
      for (const p of peers) check(p.advance(tick) === 0, 'advance');
      check(peers.every(p => p.stats().state_hash === trace.hashes[tick - 1]), 'native/Wasm state hash at ' + tick);
      const events = peers.map(p => p.events());
      check(same(events[0], events[1]), 'peer events');
      for (const event of events[0])
        check(same(Object.values(event), trace.events[eventIndex++]), 'native/Wasm confirmed events');
      if (tick % 997 === 0)
        check(same([...peers[0].save()], trace.checkpoints[checkpointIndex++]), 'native/Wasm checkpoint bytes');
    }
    check(eventIndex === trace.events.length, 'event count');
    check(same([...peers[0].save()], trace.final), 'final checkpoint bytes');
    check(peers[0].load(peers[0].save(), 1) === 0, 'Wasm recovery barrier');
    for (const bad of [1.2, '1', NaN, Infinity, 2 ** 32 + 1]) {
      let rejected = false;
      try { peers[0].input(bad, 0, 0); } catch { rejected = true; }
      check(rejected, 'coercible tick accepted');
    }
    total += trace.ticks;
  } finally { for (const p of peers) p.close(); }
  let closedRejected = false;
  try { peers[0].stats(); } catch { closedRejected = true; }
  check(closedRejected, 'closed adapter accepted');
}
console.log('Deterministic GCC/Clang/Wasm state, checkpoint and event parity PASS:', total, 'ticks');
