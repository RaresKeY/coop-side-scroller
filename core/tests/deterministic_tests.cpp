#include "ember_deterministic.h"
#include <cassert>
#include <cstdio>
#include <cstring>

namespace {
const uint8_t SESSION[16] = {1, 2, 3, 4};
struct Peer {
  EC_Deterministic *h;
  explicit Peer(uint32_t slot, uint32_t prediction = 12) : h(
      ec_v1_deterministic_create(EC_ABI_V1, slot, SESSION, 0, prediction)) { assert(h); }
  ~Peer() { ec_v1_deterministic_destroy(h); }
  EC_DeterministicStats stats() {
    EC_DeterministicStats s{};
    assert(ec_v1_deterministic_stats(h, &s, sizeof(s)) == 0); return s;
  }
  void input(uint32_t t, int32_t axis, uint32_t flags) {
    assert(ec_v1_deterministic_input(h, t, axis, flags) == 0);
  }
};
void exchange(Peer &a, Peer &b, uint32_t sender, uint32_t first, uint32_t count) {
  uint8_t bytes[80]; int32_t size = ec_v1_deterministic_pack(a.h, first, count, bytes, 80);
  assert(size >= 48);
  assert(ec_v1_deterministic_receive(b.h, sender, bytes, uint32_t(size)) == 0);
}
void drain(Peer &p, uint32_t &events) {
  EC_Event e{};
  while (ec_v1_deterministic_next_event(p.h, &e) == 0) ++events;
}
void basic_and_checkpoint() {
  Peer a(1), b(2); uint32_t events_a = 0, events_b = 0;
  for (uint32_t t = 1; t <= 300; ++t) {
    a.input(t, t < 150 ? 1000 : 0, t % 30 < 4 ? 1 : 2);
    b.input(t, t < 120 ? 1000 : -500, t % 40 < 8 ? 1 : 2);
    exchange(a, b, 1, t, 1); exchange(b, a, 2, t, 1);
    assert(ec_v1_deterministic_advance(a.h, t) == 0);
    assert(ec_v1_deterministic_advance(b.h, t) == 0);
    assert(a.stats().state_hash == b.stats().state_hash);
    drain(a, events_a); drain(b, events_b);
  }
  assert(events_a == events_b && events_a > 10);
  uint8_t cp[140], other[140], packet[80];
  assert(ec_v1_deterministic_save(a.h, cp, 139) == EC_ERR_CAPACITY);
  assert(ec_v1_deterministic_save(a.h, cp, 140) == 140);
  assert(ec_v1_deterministic_save(b.h, other, 140) == 140);
  assert(std::memcmp(cp, other, 140) == 0);
  int32_t size = ec_v1_deterministic_pack(a.h, 0, 0, packet, 80);
  // Reject broken checkpoint atomically and require a new epoch.
  cp[116] ^= 1;
  assert(ec_v1_deterministic_load(b.h, cp, 140, 1, 3) == EC_ERR_MESSAGE);
  assert(b.stats().confirmed_tick == 300);
  cp[116] ^= 1;
  assert(ec_v1_deterministic_load(a.h, cp, 140, 0, 3) == EC_ERR_ARGUMENT);
  assert(ec_v1_deterministic_load(a.h, cp, 140, 1, 3) == 0);
  assert(ec_v1_deterministic_load(b.h, cp, 140, 1, 3) == 0);
  assert(ec_v1_deterministic_receive(b.h, 1, packet, uint32_t(size)) == EC_ERR_MESSAGE);
  size = ec_v1_deterministic_pack(a.h, 0, 0, packet, 80);
  a.input(301, 0, 1); b.input(301, 0, 1);
  exchange(a, b, 1, 301, 1); exchange(b, a, 2, 301, 1);
  assert(ec_v1_deterministic_advance(a.h, 301) == 0);
  assert(ec_v1_deterministic_advance(b.h, 301) == 0);
  assert(a.stats().state_hash == b.stats().state_hash);
  assert(ec_v1_deterministic_receive(b.h, 1, packet, uint32_t(size)) == 0);
  // Original creator can depart at a trusted checkpoint/epoch barrier.
  assert(ec_v1_deterministic_save(b.h, cp, 140) == 140);
  assert(ec_v1_deterministic_load(b.h, cp, 140, 2, 2) == 0);
  for (uint32_t t = 302; t < 620; ++t) {
    b.input(t, -1000, 0); assert(ec_v1_deterministic_advance(b.h, t) == 0);
    drain(b, events_b);
  }
  assert(b.stats().confirmed_tick == 619);
}
void late_inputs_and_lockstep() {
  Peer a(1), b(2, 0); uint32_t n = 0;
  for (uint32_t t = 1; t <= 8; ++t) {
    a.input(t, 1000, 2); b.input(t, -1000, 1);
    assert(ec_v1_deterministic_advance(a.h, t) == 0);
    assert(ec_v1_deterministic_advance(b.h, t) == EC_EMPTY);
  }
  assert(a.stats().tick == 8 && a.stats().confirmed_tick == 0);
  assert(b.stats().tick == 0);
  // Out-of-order input batches converge, with confirmed events exactly once.
  exchange(b, a, 2, 5, 4); exchange(a, b, 1, 5, 4);
  assert(ec_v1_deterministic_advance(a.h, 8) == 0);
  assert(ec_v1_deterministic_advance(b.h, 8) == EC_EMPTY);
  exchange(b, a, 2, 1, 4); exchange(a, b, 1, 1, 4);
  assert(ec_v1_deterministic_advance(a.h, 8) == 0);
  assert(ec_v1_deterministic_advance(b.h, 8) == 0);
  assert(a.stats().state_hash == b.stats().state_hash && a.stats().rollbacks > 0);
  drain(a, n); uint32_t before = n;
  exchange(b, a, 2, 1, 8);
  assert(ec_v1_deterministic_advance(a.h, 8) == 0); drain(a, n);
  assert(n == before);
  // Missing inputs stop bounded prediction; nothing silently drops a jump.
  for (uint32_t t = 9; t <= 21; ++t) a.input(t, 0, 0);
  assert(ec_v1_deterministic_advance(a.h, 21) == EC_EMPTY);
  assert(a.stats().tick == 20);
}
void malformed_and_exhaustion() {
  Peer a(1), b(2); uint8_t packet[80];
  a.input(1, 1000, 1); a.input(2, -1000, 2);
  int32_t size = ec_v1_deterministic_pack(a.h, 1, 2, packet, 80);
  assert(size == 56);
  packet[55] = 1;
  assert(ec_v1_deterministic_receive(b.h, 1, packet, 56) == EC_ERR_MESSAGE);
  assert(b.stats().remote_through == 0); packet[55] = 0;
  assert(ec_v1_deterministic_receive(b.h, 2, packet, 56) == EC_ERR_AUTHORITY);
  assert(ec_v1_deterministic_receive(b.h, 1, packet, 56) == 0);
  packet[48] ^= 8;
  assert(ec_v1_deterministic_receive(b.h, 1, packet, 56) == EC_ERR_CONFLICT);
  assert(ec_v1_deterministic_input(a.h, 4, 0, 0) == EC_ERR_ARGUMENT);
  Peer c(1), d(2);
  assert(!ec_v1_deterministic_create(EC_ABI_V1, 1, SESSION, 0, 0));
}
void desync_stops() {
  Peer a(1), b(2); uint8_t packet[80], checkpoint[140];
  assert(ec_v1_deterministic_save(a.h, checkpoint, 140) == 140);
  assert(ec_v1_deterministic_pack(a.h, 0, 0, packet, 80) == 48);
  packet[40] ^= 1;
  assert(ec_v1_deterministic_receive(b.h, 1, packet, 48) == EC_ERR_DESYNC);
  assert(ec_v1_deterministic_advance(b.h, 1) == EC_ERR_DESYNC);
  assert(b.stats().desync == 1);
  assert(ec_v1_deterministic_load(b.h, checkpoint, 140, 1, 3) == 0);
  assert(b.stats().desync == 0 && b.stats().confirmed_tick == 0);
}
void checkpoint_continuity() {
  Peer a(1), b(2);
  uint32_t ignored = 0;
  auto run = [&](Peer &one, Peer &two, uint32_t tick) {
    uint32_t flags = tick >= 40 && tick < 150 ? 1u : 0u;
    one.input(tick, 1000, flags); two.input(tick, -333, flags);
    exchange(one, two, 1, tick, 1); exchange(two, one, 2, tick, 1);
    assert(ec_v1_deterministic_advance(one.h, tick) == 0);
    assert(ec_v1_deterministic_advance(two.h, tick) == 0);
    drain(one, ignored); drain(two, ignored);
  };
  for (uint32_t t = 1; t <= 90; ++t) run(a, b, t);
  uint8_t checkpoint[140];
  assert(ec_v1_deterministic_save(a.h, checkpoint, 140) == 140);
  Peer c(1), d(2);
  assert(ec_v1_deterministic_load(c.h, checkpoint, 140, 1, 3) == 0);
  assert(ec_v1_deterministic_load(d.h, checkpoint, 140, 1, 3) == 0);
  for (uint32_t t = 91; t <= 180; ++t) {
    run(a, b, t); run(c, d, t);
    assert(a.stats().state_hash == c.stats().state_hash);
    assert(b.stats().state_hash == d.stats().state_hash);
  }
}
void unacknowledged_history_is_retained() {
  Peer a(1), b(2);
  for (uint32_t t = 1; t <= 3; ++t) {
    a.input(t, 0, 0); b.input(t, 0, 0);
    exchange(b, a, 2, t, 1); // B has never received/ACKed A's inputs.
    assert(ec_v1_deterministic_advance(a.h, t) == 0);
  }
  for (uint32_t t = 4; t <= 256; ++t) a.input(t, 0, 0);
  assert(a.stats().confirmed_tick == 3 && a.stats().peer_ack == 0);
  assert(ec_v1_deterministic_input(a.h, 257, 0, 0) == EC_ERR_CAPACITY);
  exchange(a, b, 1, 1, 3); exchange(b, a, 2, 0, 0);
  assert(ec_v1_deterministic_input(a.h, 257, 0, 0) == 0);
}
void retired_packets_are_stale() {
  Peer a(1), b(2); uint8_t old[80]; uint32_t ignored = 0;
  for (uint32_t t = 1; t <= 300; ++t) {
    a.input(t, 0, 0); b.input(t, 0, 0);
    if (t == 1) assert(ec_v1_deterministic_pack(a.h, t, 1, old, 80) == 52);
    exchange(a, b, 1, t, 1);
    // B continues confirming while its recent inputs to A are lost. Its ring
    // now contains unacknowledged tick 257 where old tick 1 used to live.
    if (t <= 240) exchange(b, a, 2, t, 1);
    assert(ec_v1_deterministic_advance(a.h, t) >= 0);
    assert(ec_v1_deterministic_advance(b.h, t) == 0);
    drain(a, ignored); drain(b, ignored);
  }
  assert(b.stats().peer_ack == 240);
  assert(ec_v1_deterministic_receive(b.h, 1, old, 52) == EC_ERR_STALE);
  assert(b.stats().confirmed_tick == 300 && !b.stats().desync);
  // Discarding the ancient packet must not destroy B's retained retransmit.
  assert(ec_v1_deterministic_pack(b.h, 257, 1, old, 80) == 52);
}
void final_tick_packet_boundary() {
  Peer a(1), b(2); uint8_t cp[140], packet[80];
  auto put = [](uint8_t *p, uint32_t value) {
    for (uint32_t i = 0; i < 4; ++i) p[i] = uint8_t(value >> (8 * i));
  };
  auto hash = [](const uint8_t *p, uint32_t size) {
    uint32_t value = 2166136261u;
    for (uint32_t i = 0; i < size; ++i) value = (value ^ p[i]) * 16777619u;
    return value;
  };
  constexpr uint32_t end = 0x7ffffe00;
  assert(ec_v1_deterministic_save(a.h, cp, 140) == 140);
  // A trusted checkpoint places the peers near the tick limit without years
  // of simulated play. Recompute both canonical checksums after editing it.
  put(cp + 28, end - 8); put(cp + 132, hash(cp + 28, 104));
  put(cp + 136, hash(cp, 136));
  assert(ec_v1_deterministic_load(a.h, cp, 140, 1, 3) == 0);
  assert(ec_v1_deterministic_load(b.h, cp, 140, 1, 3) == 0);
  for (uint32_t t = end - 7; t <= end; ++t) {
    a.input(t, 333, 1); b.input(t, -499, 2);
  }
  exchange(a, b, 1, end - 7, 8); exchange(b, a, 2, end - 7, 8);
  assert(ec_v1_deterministic_pack(a.h, end, 1, packet, 80) == 52);
  assert(ec_v1_deterministic_receive(b.h, 1, packet, 52) == 0);
  assert(ec_v1_deterministic_pack(a.h, end, 2, packet, 80) == EC_ERR_ARGUMENT);
  packet[45] = 2;
  assert(ec_v1_deterministic_receive(b.h, 1, packet, 56) == EC_ERR_MESSAGE);
  assert(ec_v1_deterministic_advance(a.h, end) == 0);
  assert(ec_v1_deterministic_advance(b.h, end) == 0);
  assert(a.stats().state_hash == b.stats().state_hash);
  assert(ec_v1_deterministic_input(a.h, end + 1, 0, 0) == EC_ERR_CAPACITY);
}
} // namespace
int main() {
  basic_and_checkpoint(); late_inputs_and_lockstep(); malformed_and_exhaustion(); desync_stops();
  checkpoint_continuity();
  unacknowledged_history_is_retained();
  retired_packets_are_stale(); final_tick_packet_boundary();
  std::puts("Deterministic checkpoint, rollback, lockstep and packet contracts PASS");
}
