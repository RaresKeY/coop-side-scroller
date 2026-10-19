#include "ember_core.h"
#include <cassert>
#include <cstdio>
#include <cstring>
static EC_View view(EC_Handle *h) {
  EC_View v{};
  assert(ec_v1_read_view(h, &v, sizeof v) == EC_OK);
  return v;
}
static uint32_t drain(EC_Handle *h, uint8_t *bytes) {
  uint32_t n = 0;
  assert(ec_v1_next_message(h, bytes, EC_MAX_MESSAGE, &n) == EC_OK);
  return n;
}
int main() {
  assert(ec_v1_abi_version() == EC_ABI_V1 && ec_v1_protocol_version() == 1);
  assert(!ec_v1_create(0, 1, 1) && !ec_v1_create(EC_ABI_V1, 2, 1));
  auto *host = ec_v1_create(EC_ABI_V1, 1, 1);
  auto *guest = ec_v1_create(EC_ABI_V1, 2, 2);
  assert(host && guest);
  assert(ec_v1_tick(nullptr) == EC_ERR_HANDLE);
  assert(ec_v1_set_peer_active(guest, 2, 1) == EC_ERR_AUTHORITY);
  assert(ec_v1_set_local_input(host, 1001, 0) == EC_ERR_ARGUMENT);
  assert(ec_v1_set_local_input(host, 0, 4) == EC_ERR_ARGUMENT);
  assert(ec_v1_read_view(host, nullptr, 0) == EC_ERR_CAPACITY);
  ec_v1_set_peer_active(host, 2, 1);
  uint8_t bytes[EC_MAX_MESSAGE]{};
  uint32_t size = 0;
  ec_v1_set_local_input(guest, 1000, EC_INPUT_JUMP);
  ec_v1_tick(guest);
  assert(ec_v1_next_message(guest, bytes, 1, &size) == EC_ERR_CAPACITY &&
         size == 24);
  assert(ec_v1_next_message(guest, bytes, sizeof bytes, &size) == EC_OK &&
         size == 24);
  assert(bytes[0] == 'E' && bytes[3] == '1' && bytes[4] == 1 &&
         bytes[16] == 0xe8 && bytes[17] == 3);
  assert(ec_v1_receive(host, 1, bytes, size) == EC_ERR_AUTHORITY);
  assert(ec_v1_receive(host, 2, bytes, size - 1) == EC_ERR_MESSAGE);
  assert(ec_v1_receive(host, 2, bytes, size) == EC_OK);
  assert(ec_v1_receive(host, 2, bytes, size) == EC_ERR_STALE);
  ec_v1_tick(host);
  auto airborne = view(host);
  assert(airborne.players[1].x == 262833 && airborne.players[1].y < 448000 &&
         airborne.players[1].animation == EC_ANIM_JUMP);
  // Stale remote input neutralizes after 18 authority ticks, without requiring
  // a release packet.
  for (int i = 0; i < 20; i++)
    ec_v1_tick(host);
  auto stopped = view(host);
  for (int i = 0; i < 5; i++)
    ec_v1_tick(host);
  assert(view(host).players[1].x == stopped.players[1].x);
  // Feed a real snapshot then reject duplicates/invalid frames atomically.
  uint32_t last_size = 0;
  uint8_t latest[EC_MAX_MESSAGE]{};
  while (ec_v1_next_message(host, bytes, sizeof bytes, &size) == EC_OK) {
    std::memcpy(latest, bytes, size);
    last_size = size;
  }
  assert(last_size == 104);
  assert(ec_v1_receive(guest, 2, latest, last_size) == EC_ERR_AUTHORITY);
  assert(ec_v1_receive(guest, 1, latest, last_size) == EC_OK);
  auto before = view(guest);
  assert(ec_v1_receive(guest, 1, latest, last_size) == EC_ERR_STALE);
  latest[8]++;
  latest[32] = 0x08;
  latest[33] = 0xc3;
  latest[34] = 0x02;
  latest[35] = 0; // first actor x=181000
  latest[24 + 40] = 9;
  assert(ec_v1_receive(guest, 1, latest, last_size) == EC_ERR_MESSAGE);
  auto after = view(guest);
  assert(before.tick == after.tick &&
         before.players[0].x == after.players[0].x &&
         before.players[1].x == after.players[1].x);
  // Staged receives require every byte, even after a prior complete message.
  ec_v1_reset(host, 1, 1);
  ec_v1_set_peer_active(host, 2, 1);
  ec_v1_reset(guest, 2, 2);
  ec_v1_tick(guest);
  size = drain(guest, bytes);
  assert(ec_v1_command(host, 6, 0, 0) == EC_ERR_MESSAGE);
  assert(ec_v1_command(host, 4, 2, size) == EC_OK);
  for (uint32_t i = 0; i < size; i++)
    assert(ec_v1_command(host, 5, i, bytes[i]) == EC_OK);
  assert(ec_v1_command(host, 6, 0, 0) == EC_OK);
  assert(ec_v1_command(host, 6, 0, 0) == EC_ERR_MESSAGE);
  bytes[8]++;
  assert(ec_v1_command(host, 4, 2, size) == EC_OK);
  for (uint32_t i = 0; i + 1 < size; i++) {
    assert(ec_v1_command(host, 5, i, bytes[i]) == EC_OK);
    assert(ec_v1_command(host, 5, i, bytes[i]) == EC_OK);
  }
  assert(ec_v1_command(host, 6, 0, 0) == EC_ERR_MESSAGE);
  assert(ec_v1_receive(host, 2, bytes, size) == EC_OK);
  assert(ec_v1_command(host, 4, 2, size) == EC_OK);
  assert(ec_v1_command(host, 4, 2, 105) == EC_ERR_ARGUMENT);
  assert(ec_v1_command(host, 5, 0, 0) == EC_ERR_ARGUMENT);
  assert(ec_v1_command(host, 6, 0, 0) == EC_ERR_MESSAGE);
  // Sequence comparison accepts wraparound, but not a reordered prior packet.
  ec_v1_reset(host, EC_ROLE_HOST, 1);
  ec_v1_set_peer_active(host, 2, 1);
  ec_v1_reset(guest, EC_ROLE_REPLICA, 2);
  ec_v1_tick(guest);
  size = drain(guest, bytes);
  bytes[8] = 0xfe;
  bytes[9] = 0xff;
  bytes[10] = 0xff;
  bytes[11] = 0xff;
  assert(ec_v1_receive(host, 2, bytes, size) == EC_OK);
  bytes[8] = 1;
  bytes[9] = 0;
  bytes[10] = 0;
  bytes[11] = 0;
  assert(ec_v1_receive(host, 2, bytes, size) == EC_OK);
  bytes[8] = 0;
  assert(ec_v1_receive(host, 2, bytes, size) == EC_ERR_STALE);
  assert(ec_v1_reset_dummy(guest) == EC_ERR_AUTHORITY);
  ec_v1_reset(guest, 2, 2);
  for (int i = 0; i < 100; i++)
    ec_v1_tick(guest);
  assert(view(guest).dropped_messages == 36);
  uint32_t messages = 0;
  while (ec_v1_next_message(guest, bytes, sizeof bytes, &size) == EC_OK)
    messages++;
  assert(messages == 64);
  // Damage lands on the strike frame, not the first anticipation frame.
  ec_v1_reset(host, 1, 1);
  ec_v1_set_local_input(host, 1000, 0);
  for (int i = 0; i < 180; i++)
    ec_v1_tick(host);
  ec_v1_set_local_input(host, 0, EC_INPUT_ATTACK);
  ec_v1_tick(host);
  assert(view(host).players[0].attack_ticks == 24 && view(host).enemy_hp == 12);
  for (int i = 0; i < 14; i++)
    ec_v1_tick(host);
  assert(view(host).enemy_hp == 12);
  ec_v1_tick(host);
  assert(view(host).players[0].attack_ticks == 9 && view(host).enemy_hp == 11);
  ec_v1_set_local_input(host, 0, 0);
  for (int i = 0; i < 13; i++)
    ec_v1_tick(host);
  assert(view(host).enemy_hp == 11);
  // A held jump rises smoothly, falls faster, and a tap produces a lower arc.
  int32_t heights[2]{};
  for (int held = 0; held < 2; held++) {
    ec_v1_reset(host, 1, 1);
    int ascent = 0, descent = 0;
    for (int t = 0; t < 60; t++) {
      ec_v1_set_local_input(host, 0, (held || t == 0) ? EC_INPUT_JUMP : 0);
      ec_v1_tick(host);
      auto p = view(host).players[0];
      if (448000 - p.y > heights[held])
        heights[held] = 448000 - p.y;
      if (!p.grounded) {
        if (p.vy < 0)
          ascent++;
        else
          descent++;
      } else if (t > 0)
        break;
    }
    assert(view(host).players[0].grounded);
    if (held)
      assert(ascent > descent && heights[held] > 50000);
  }
  assert(heights[0] < heights[1] / 2);
  ec_v1_destroy(host);
  ec_v1_destroy(guest);
  EC_Handle *all[32]{};
  for (auto &h : all) {
    h = ec_v1_create(EC_ABI_V1, 1, 1);
    assert(h);
  }
  assert(!ec_v1_create(EC_ABI_V1, 1, 1));
  for (auto *h : all)
    ec_v1_destroy(h);
  std::puts("core contract tests PASS");
}
