#include "ember_deterministic.h"
#include "simulation.h"

namespace {
constexpr uint32_t HISTORY = EC_DETERMINISTIC_HISTORY, LAST_TICK = 0x7ffffe00;
struct World {
  uint32_t tick, enemy_hp;
  EC_Player players[2];
  uint32_t held_jump[2];
  ember_sim::Input last[2];
};
struct Frame {
  uint32_t tick, mask, hash, peer_hash;
  bool hashed, peer_hashed;
  ember_sim::Input inputs[2];
};
bool equal(ember_sim::Input a, ember_sim::Input b) {
  return a.axis == b.axis && a.flags == b.flags;
}
void put(uint8_t *p, uint32_t n) {
  for (uint32_t i = 0; i < 4; ++i) p[i] = uint8_t(n >> (i * 8));
}
uint32_t get(const uint8_t *p) {
  uint32_t n = 0;
  for (uint32_t i = 0; i < 4; ++i) n |= uint32_t(p[i]) << (i * 8);
  return n;
}
int32_t signed_get(const uint8_t *p) {
  uint32_t n = get(p);
  return n <= INT32_MAX ? int32_t(n) : -1 - int32_t(UINT32_MAX - n);
}
void pack_input(uint8_t *p, ember_sim::Input in) {
  uint32_t axis = uint32_t(in.axis);
  p[0] = uint8_t(axis); p[1] = uint8_t(axis >> 8);
  p[2] = uint8_t(in.flags); p[3] = 0;
}
ember_sim::Input unpack_input(const uint8_t *p) {
  int32_t axis = int32_t(uint32_t(p[0]) | (uint32_t(p[1]) << 8));
  if (axis >= 32768) axis -= 65536;
  return {axis, p[2]};
}
bool valid_input(ember_sim::Input in) {
  return in.axis >= -1000 && in.axis <= 1000 && in.flags <= 3;
}
uint32_t hash_bytes(const uint8_t *p, uint32_t size) {
  uint32_t hash = 2166136261u;
  for (uint32_t i = 0; i < size; ++i) hash = (hash ^ p[i]) * 16777619u;
  return hash;
}
void spawn(World &w, uint32_t i) {
  w.players[i] = {i + 1, 1, i ? 260000 : 180000, 448000, 0, 1,
                  0, 0, EC_ANIM_IDLE, 1};
  w.held_jump[i] = 0; w.last[i] = {};
}
void write_world(const World &w, uint8_t *b) {
  put(b, w.tick); put(b + 4, w.enemy_hp);
  for (uint32_t i = 0; i < 2; ++i) {
    const auto &p = w.players[i]; auto *s = b + 8 + i * 40;
    put(s, p.slot); put(s + 4, p.active); put(s + 8, uint32_t(p.x));
    put(s + 12, uint32_t(p.y)); put(s + 16, uint32_t(p.vy));
    put(s + 20, uint32_t(p.facing)); put(s + 24, p.attack_ticks);
    put(s + 28, p.attack_id); put(s + 32, p.animation); put(s + 36, p.grounded);
    put(b + 88 + i * 4, w.held_jump[i]);
    pack_input(b + 96 + i * 4, w.last[i]);
  }
}
bool read_world(World &w, const uint8_t *b) {
  w.tick = get(b); w.enemy_hp = get(b + 4);
  if (w.tick > LAST_TICK || w.enemy_hp > 12) return false;
  for (uint32_t i = 0; i < 2; ++i) {
    auto &p = w.players[i]; const auto *s = b + 8 + i * 40;
    p = {get(s), get(s + 4), signed_get(s + 8), signed_get(s + 12),
         signed_get(s + 16), signed_get(s + 20), get(s + 24), get(s + 28),
         get(s + 32), get(s + 36)};
    w.held_jump[i] = get(b + 88 + i * 4);
    w.last[i] = unpack_input(b + 96 + i * 4);
    if (p.slot != i + 1 || p.active > 1 || p.x < 24000 || p.x > 936000 ||
        p.y < -2000000 || p.y > 448000 || p.vy < -20000 || p.vy > 20000 ||
        (p.facing != -1 && p.facing != 1) || p.attack_ticks > 24 ||
        p.animation > 4 || p.grounded > 1 || w.held_jump[i] > 1 ||
        !valid_input(w.last[i]) || b[99 + i * 4]) return false;
  }
  return true;
}
uint32_t world_hash(const World &w) {
  uint8_t b[104]; write_world(w, b); return hash_bytes(b, sizeof(b));
}
} // namespace

struct EC_Deterministic {
  bool live;
  uint8_t session[16];
  uint32_t epoch, local, prediction, mask, local_through, remote_through, peer_ack;
  uint32_t stalls, rollbacks, resimulated, rejected, desync, dirty, correction;
  World confirmed, predicted;
  Frame frames[HISTORY];
  EC_Event events[64];
  uint32_t event_head, event_count, dropped_events;
};
namespace {
EC_Deterministic handles[4]{};
bool valid(EC_Deterministic *h) {
  for (auto &slot : handles) if (&slot == h) return slot.live;
  return false;
}
int32_t reject(EC_Deterministic *h, int32_t result) {
  ++h->rejected; return result;
}
Frame &frame(EC_Deterministic *h, uint32_t tick) {
  auto &f = h->frames[tick % HISTORY];
  if (f.tick != tick) { f = {}; f.tick = tick; }
  return f;
}
bool available(EC_Deterministic *h, uint32_t tick) {
  if (!tick || tick > LAST_TICK || tick > h->confirmed.tick + HISTORY - 1)
    return false;
  const auto &f = h->frames[tick % HISTORY];
  return f.tick == tick || !f.tick ||
      (f.tick < h->confirmed.tick &&
       (!(h->mask & (1u << (2 - h->local))) || f.tick <= h->peer_ack));
}
void emit(EC_Deterministic *h, uint32_t type, uint32_t slot, uint32_t value) {
  if (h->event_count == 64) { ++h->dropped_events; return; }
  h->events[(h->event_head + h->event_count++) % 64] =
      {h->confirmed.tick, type, slot, value};
}
void step(World &w, const ember_sim::Input (&inputs)[2]) {
  w.last[0] = inputs[0]; w.last[1] = inputs[1];
  ember_sim::step(w, inputs, [](uint32_t, uint32_t, uint32_t) {});
}
World predict(EC_Deterministic *h, uint32_t target) {
  World w = h->confirmed;
  uint32_t limit = h->confirmed.tick + h->prediction;
  if (target > limit) target = limit;
  while (w.tick < target) {
    const auto &f = h->frames[(w.tick + 1) % HISTORY];
    if (f.tick != w.tick + 1 || !(f.mask & (1u << (h->local - 1)))) break;
    ember_sim::Input inputs[2];
    for (uint32_t i = 0; i < 2; ++i)
      inputs[i] = !(h->mask & (1u << i)) ? ember_sim::Input{} :
          (f.mask & (1u << i)) ? f.inputs[i] : w.last[i];
    step(w, inputs);
  }
  return w;
}
bool same_session(EC_Deterministic *h, const uint8_t *b) {
  for (uint32_t i = 0; i < 16; ++i) if (h->session[i] != b[i]) return false;
  return true;
}
void store_remote(EC_Deterministic *h, uint32_t tick, ember_sim::Input in) {
  auto &f = frame(h, tick); uint32_t index = 2 - h->local;
  if (!(f.mask & (1u << index)) && tick <= h->predicted.tick) {
    // Conservative rewind marker; the corrected position is measured in advance.
    if (!h->dirty || tick < h->dirty) h->dirty = tick;
  }
  f.inputs[index] = in; f.mask |= 1u << index;
}
} // namespace

extern "C" {
EC_Deterministic *ec_v1_deterministic_create(uint32_t abi, uint32_t local,
    const uint8_t *session, uint32_t epoch, uint32_t prediction) {
  if (abi != EC_ABI_V1 || local < 1 || local > 2 || !session ||
      epoch == UINT32_MAX || prediction > 12) return nullptr;
  uint32_t nonzero = 0;
  for (uint32_t i = 0; i < 16; ++i) nonzero |= session[i];
  if (!nonzero) return nullptr;
  for (auto &h : handles) if (!h.live) {
    h = {}; h.live = true; h.local = local; h.epoch = epoch;
    h.prediction = prediction; h.mask = 3; h.confirmed.enemy_hp = 12;
    for (uint32_t i = 0; i < 16; ++i) h.session[i] = session[i];
    spawn(h.confirmed, 0); spawn(h.confirmed, 1); h.predicted = h.confirmed;
    return &h;
  }
  return nullptr;
}
void ec_v1_deterministic_destroy(EC_Deterministic *h) {
  if (valid(h)) h->live = false;
}
int32_t ec_v1_deterministic_input(EC_Deterministic *h, uint32_t tick,
    int32_t axis, uint32_t flags) {
  if (!valid(h)) return EC_ERR_HANDLE;
  if (h->desync) return EC_ERR_DESYNC;
  if (!valid_input({axis, flags}) || tick != h->local_through + 1)
    return reject(h, EC_ERR_ARGUMENT);
  if (!available(h, tick)) return reject(h, EC_ERR_CAPACITY);
  auto &f = frame(h, tick); f.inputs[h->local - 1] = {axis, flags};
  f.mask |= 1u << (h->local - 1); h->local_through = tick;
  return EC_OK;
}
int32_t ec_v1_deterministic_advance(EC_Deterministic *h, uint32_t target) {
  if (!valid(h)) return EC_ERR_HANDLE;
  if (h->desync) return EC_ERR_DESYNC;
  if (target < h->confirmed.tick || target > LAST_TICK)
    return reject(h, EC_ERR_ARGUMENT);
  if (h->dirty) {
    World corrected = predict(h, h->predicted.tick);
    if (corrected.tick == h->predicted.tick) {
      bool changed = world_hash(corrected) != world_hash(h->predicted);
      if (changed) ++h->rollbacks;
      for (uint32_t i = 0; i < 2; ++i) {
        uint32_t delta = uint32_t(ember_sim::absolute(
            corrected.players[i].x - h->predicted.players[i].x));
        if (delta > h->correction) h->correction = delta;
      }
    }
    h->dirty = 0;
  }
  while (h->confirmed.tick < target) {
    auto &f = h->frames[(h->confirmed.tick + 1) % HISTORY];
    if (f.tick != h->confirmed.tick + 1 || (f.mask & h->mask) != h->mask) break;
    ember_sim::Input inputs[2];
    for (uint32_t i = 0; i < 2; ++i)
      inputs[i] = (h->mask & (1u << i)) ? f.inputs[i] : ember_sim::Input{};
    h->confirmed.last[0] = inputs[0]; h->confirmed.last[1] = inputs[1];
    ember_sim::step(h->confirmed, inputs,
        [h](uint32_t type, uint32_t slot, uint32_t value) { emit(h, type, slot, value); });
    f.hash = world_hash(h->confirmed); f.hashed = true;
    if (f.peer_hashed && f.peer_hash != f.hash) {
      h->desync = 1; h->predicted = h->confirmed; return EC_ERR_DESYNC;
    }
  }
  h->predicted = predict(h, target);
  h->resimulated += h->predicted.tick - h->confirmed.tick;
  if (h->predicted.tick < target) { ++h->stalls; return EC_EMPTY; }
  return EC_OK;
}
int32_t ec_v1_deterministic_read_view(EC_Deterministic *h, EC_View *v,
    uint32_t capacity) {
  if (!valid(h)) return EC_ERR_HANDLE;
  if (!v || capacity < sizeof(*v)) return EC_ERR_CAPACITY;
  *v = {}; v->struct_size = sizeof(*v); v->tick = h->predicted.tick;
  v->enemy_hp = h->predicted.enemy_hp; v->role = h->prediction ? 4 : 3;
  v->local_slot = h->local; v->snapshot_sequence = h->confirmed.tick;
  v->rejected_messages = h->rejected; v->dropped_events = h->dropped_events;
  for (uint32_t i = 0; i < 2; ++i) v->players[i] = h->predicted.players[i];
  return EC_OK;
}
int32_t ec_v1_deterministic_stats(EC_Deterministic *h, EC_DeterministicStats *s,
    uint32_t capacity) {
  if (!valid(h)) return EC_ERR_HANDLE;
  if (!s || capacity < sizeof(*s)) return EC_ERR_CAPACITY;
  *s = {sizeof(*s), h->predicted.tick, h->confirmed.tick, world_hash(h->confirmed),
        h->peer_ack, h->stalls, h->rollbacks, h->resimulated, h->rejected,
        h->desync, h->correction, h->dropped_events, h->local_through,
        h->remote_through};
  return EC_OK;
}
int32_t ec_v1_deterministic_next_event(EC_Deterministic *h, EC_Event *event) {
  if (!valid(h)) return EC_ERR_HANDLE;
  if (!event) return EC_ERR_ARGUMENT;
  if (!h->event_count) return EC_EMPTY;
  *event = h->events[h->event_head]; h->event_head = (h->event_head + 1) % 64;
  --h->event_count; return EC_OK;
}
int32_t ec_v1_deterministic_pack(EC_Deterministic *h, uint32_t first,
    uint32_t count, uint8_t *b, uint32_t capacity) {
  if (!valid(h)) return EC_ERR_HANDLE;
  if (h->desync) return EC_ERR_DESYNC;
  if (count > 8 || (count && (!first || first > LAST_TICK - (count - 1) ||
      first + count - 1 > h->local_through))) return EC_ERR_ARGUMENT;
  uint32_t size = 48 + count * 4;
  if (!b || capacity < size) return EC_ERR_CAPACITY;
  for (uint32_t i = 0; i < count; ++i) {
    const auto &f = h->frames[(first + i) % HISTORY];
    if (f.tick != first + i || !(f.mask & (1u << (h->local - 1))))
      return EC_ERR_STALE;
  }
  b[0] = 'E'; b[1] = 'D'; b[2] = 'I'; b[3] = '1';
  for (uint32_t i = 0; i < 16; ++i) b[4 + i] = h->session[i];
  put(b + 20, h->epoch); put(b + 24, EC_DETERMINISTIC_RULES);
  put(b + 28, count ? first : 0); put(b + 32, h->remote_through);
  put(b + 36, h->confirmed.tick); put(b + 40, world_hash(h->confirmed));
  b[44] = uint8_t(h->local); b[45] = uint8_t(count); b[46] = b[47] = 0;
  for (uint32_t i = 0; i < count; ++i)
    pack_input(b + 48 + i * 4, h->frames[(first + i) % HISTORY].inputs[h->local - 1]);
  return int32_t(size);
}
int32_t ec_v1_deterministic_receive(EC_Deterministic *h, uint32_t sender,
    const uint8_t *b, uint32_t size) {
  if (!valid(h)) return EC_ERR_HANDLE;
  if (h->desync) return EC_ERR_DESYNC;
  if (sender != 3 - h->local || !(h->mask & (1u << (sender - 1))))
    return reject(h, EC_ERR_AUTHORITY);
  if (!b || size < 48 || size > EC_DETERMINISTIC_PACKET || b[0] != 'E' ||
      b[1] != 'D' || b[2] != 'I' || b[3] != '1' || !same_session(h, b + 4) ||
      get(b + 20) != h->epoch || get(b + 24) != EC_DETERMINISTIC_RULES ||
      b[44] != sender || b[45] > 8 || size != 48u + b[45] * 4u || b[46] || b[47])
    return reject(h, EC_ERR_MESSAGE);
  uint32_t first = get(b + 28), ack = get(b + 32), ht = get(b + 36);
  uint32_t hash = get(b + 40), count = b[45], bit = 1u << (sender - 1);
  if ((count && (!first || first > LAST_TICK - (count - 1))) || (!count && first) ||
      ack > h->local_through || ht > ack || ht > h->confirmed.tick + HISTORY - 1)
    return reject(h, EC_ERR_MESSAGE);
  if (ht && ht + HISTORY <= h->confirmed.tick) return reject(h, EC_ERR_STALE);
  for (uint32_t i = 0; i < count; ++i) {
    uint32_t tick = first + i; const auto &f = h->frames[tick % HISTORY];
    auto in = unpack_input(b + 48 + i * 4);
    if (!valid_input(in) || b[51 + i * 4]) return reject(h, EC_ERR_MESSAGE);
    if (tick <= h->confirmed.tick && (f.tick != tick || !(f.mask & bit)))
      return reject(h, EC_ERR_STALE);
    if (!available(h, tick)) return reject(h, EC_ERR_CAPACITY);
    if (f.tick == tick && (f.mask & bit) && !equal(f.inputs[sender - 1], in))
      return reject(h, EC_ERR_CONFLICT);
  }
  if (ht <= h->confirmed.tick) {
    uint32_t expected = 0;
    if (ht == h->confirmed.tick) expected = world_hash(h->confirmed);
    else if (ht && h->frames[ht % HISTORY].tick == ht && h->frames[ht % HISTORY].hashed)
      expected = h->frames[ht % HISTORY].hash;
    // Tick zero is comparable only before the first checkpoint/session progress.
    else if (ht) return reject(h, EC_ERR_STALE);
    if ((ht || !h->confirmed.tick) && expected != hash) {
      h->desync = 1; return reject(h, EC_ERR_DESYNC);
    }
  } else {
    if (!available(h, ht)) return reject(h, EC_ERR_CAPACITY);
    const auto &f = h->frames[ht % HISTORY];
    if (f.tick == ht && f.peer_hashed && f.peer_hash != hash)
      return reject(h, EC_ERR_CONFLICT);
  }
  for (uint32_t i = 0; i < count; ++i)
    store_remote(h, first + i, unpack_input(b + 48 + i * 4));
  if (ack > h->peer_ack) h->peer_ack = ack;
  if (ht > h->confirmed.tick) {
    auto &f = frame(h, ht); f.peer_hash = hash; f.peer_hashed = true;
  }
  while (h->remote_through < LAST_TICK) {
    const auto &f = h->frames[(h->remote_through + 1) % HISTORY];
    if (f.tick != h->remote_through + 1 || !(f.mask & bit)) break;
    ++h->remote_through;
  }
  return EC_OK;
}
int32_t ec_v1_deterministic_save(EC_Deterministic *h, uint8_t *b, uint32_t cap) {
  if (!valid(h)) return EC_ERR_HANDLE;
  if (h->desync) return EC_ERR_DESYNC;
  if (!b || cap < EC_DETERMINISTIC_CHECKPOINT) return EC_ERR_CAPACITY;
  b[0] = 'E'; b[1] = 'D'; b[2] = 'C'; b[3] = '1';
  for (uint32_t i = 0; i < 16; ++i) b[4 + i] = h->session[i];
  put(b + 20, h->epoch); put(b + 24, EC_DETERMINISTIC_RULES);
  write_world(h->confirmed, b + 28); put(b + 132, world_hash(h->confirmed));
  put(b + 136, hash_bytes(b, 136)); return EC_DETERMINISTIC_CHECKPOINT;
}
int32_t ec_v1_deterministic_load(EC_Deterministic *h, const uint8_t *b,
    uint32_t size, uint32_t epoch, uint32_t mask) {
  if (!valid(h)) return EC_ERR_HANDLE;
  if (!b || size != EC_DETERMINISTIC_CHECKPOINT || b[0] != 'E' || b[1] != 'D' ||
      b[2] != 'C' || b[3] != '1' || !same_session(h, b + 4) ||
      get(b + 24) != EC_DETERMINISTIC_RULES || get(b + 136) != hash_bytes(b, 136))
    return reject(h, EC_ERR_MESSAGE);
  if (epoch <= h->epoch || epoch <= get(b + 20) || epoch == UINT32_MAX ||
      !mask || mask > 3 || !(mask & (1u << (h->local - 1))))
    return reject(h, EC_ERR_ARGUMENT);
  World w{};
  if (!read_world(w, b + 28) || world_hash(w) != get(b + 132))
    return reject(h, EC_ERR_MESSAGE);
  for (uint32_t i = 0; i < 2; ++i) {
    if (mask & (1u << i)) { if (!w.players[i].active) spawn(w, i); }
    else { w.players[i].active = 0; w.held_jump[i] = 0; w.last[i] = {}; }
  }
  uint32_t local = h->local, prediction = h->prediction;
  uint8_t session[16];
  for (uint32_t i = 0; i < 16; ++i) session[i] = h->session[i];
  *h = EC_Deterministic{}; h->live = true; h->local = local;
  h->prediction = prediction; h->epoch = epoch; h->mask = mask;
  for (uint32_t i = 0; i < 16; ++i) h->session[i] = session[i];
  h->confirmed = h->predicted = w;
  h->local_through = h->remote_through = h->peer_ack = w.tick;
  // Reordered packets can still carry the recovery barrier's hash after we
  // advance. Retain it exactly like hashes of subsequent confirmed frames.
  auto &barrier = frame(h, w.tick);
  barrier.hash = world_hash(w); barrier.hashed = true;
  return EC_OK;
}
} // extern C
