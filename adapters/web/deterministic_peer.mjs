// Experimental typed Wasm adapter. Each peer owns a separate Wasm instance.
// No rendering, simulation rules, transport, credentials or clock live here.
const integer = (value, low, high, label) => {
  if (!Number.isInteger(value) || value < low || value > high) throw new TypeError(label);
  return value;
};
const statsFields = ['struct_size', 'tick', 'confirmed_tick', 'state_hash', 'peer_ack',
  'stalls', 'rollbacks', 'resimulated_ticks', 'rejected', 'desync', 'max_correction',
  'dropped_events', 'local_through', 'remote_through'];
const actorFields = ['slot', 'active', 'x', 'y', 'vy', 'facing', 'attack_ticks',
  'attack_id', 'animation', 'grounded'];

export async function createDeterministicPeer({module, slot, prediction = 12,
    session, epoch = 0}) {
  integer(slot, 1, 2, 'slot'); integer(prediction, 0, 12, 'prediction');
  integer(epoch, 0, 0xfffffffe, 'epoch');
  if (!(session instanceof Uint8Array) || session.length !== 16 || !session.some(x => x))
    throw new TypeError('session');
  if (!(module instanceof WebAssembly.Module) || WebAssembly.Module.imports(module).length)
    throw new TypeError('import-free Wasm module required');
  const ownedSession = session.slice();
  const instance = await WebAssembly.instantiate(module, {});
  const api = instance.exports, base = Number(api.__heap_base.value);
  if (base + 2048 > api.memory.buffer.byteLength) throw new Error('Wasm scratch capacity');
  const memory = new Uint8Array(api.memory.buffer), view = new DataView(api.memory.buffer);
  const call = (operation, ...args) => api['ec_v1_deterministic_' + operation](...args);
  memory.set(ownedSession, base);
  const handle = call('create', 0x10000, slot, base, epoch, prediction);
  if (!handle) throw new Error('Deterministic core creation failed');
  let live = true;
  const owned = () => { if (!live) throw new Error('Closed deterministic peer'); };
  const bytes = (value, limit) => {
    if (!(value instanceof Uint8Array) || value.length > limit) throw new TypeError('bytes');
    memory.set(value, base);
    return value.length;
  };
  return Object.freeze({
    input(tick, axis, flags) {
      owned(); integer(tick, 1, 0x7ffffe00, 'tick'); integer(axis, -1000, 1000, 'axis');
      integer(flags, 0, 3, 'flags');
      return call('input', handle, tick, axis, flags);
    },
    advance(tick) {
      owned(); integer(tick, 0, 0x7ffffe00, 'tick');
      return call('advance', handle, tick);
    },
    stats() {
      owned();
      if (call('stats', handle, base, 56)) throw new Error('Stats copy failed');
      return Object.fromEntries(statsFields.map((name, i) => [name, view.getUint32(base + i * 4, true)]));
    },
    actors() {
      owned();
      if (call('read_view', handle, base, 116)) throw new Error('View copy failed');
      return [0, 1].map(i => Object.fromEntries(actorFields.map((name, j) =>
        [name, ['x', 'y', 'vy', 'facing'].includes(name)
          ? view.getInt32(base + 20 + i * 40 + j * 4, true)
          : view.getUint32(base + 20 + i * 40 + j * 4, true)])));
    },
    events() {
      owned(); const result = [];
      while (call('next_event', handle, base) === 0)
        result.push(Object.fromEntries(['tick', 'type', 'slot', 'value'].map((name, i) =>
          [name, view.getUint32(base + i * 4, true)])));
      return result;
    },
    pack(first, count) {
      owned(); integer(first, 0, 0x7ffffe00, 'first'); integer(count, 0, 8, 'count');
      const size = call('pack', handle, first, count, base, 80);
      if (size < 0) throw new Error('Packet encoding failed: ' + size);
      return memory.slice(base, base + size);
    },
    receive(sender, packet) {
      owned(); integer(sender, 1, 2, 'sender');
      return call('receive', handle, sender, base, bytes(packet, 80));
    },
    save() {
      owned(); const size = call('save', handle, base, 140);
      if (size !== 140) throw new Error('Checkpoint save failed: ' + size);
      return memory.slice(base, base + size);
    },
    load(checkpoint, newEpoch, activeMask = 3) {
      owned(); integer(newEpoch, 1, 0xfffffffe, 'epoch'); integer(activeMask, 1, 3, 'mask');
      return call('load', handle, base, bytes(checkpoint, 140), newEpoch, activeMask);
    },
    close() { if (live) { call('destroy', handle); live = false; } },
  });
}
