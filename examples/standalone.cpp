#include "ember_core.h"
#include <cstdio>
#include <cstdlib>
static void require(bool value) {
  if (!value)
    std::abort();
}
static void transfer(EC_Handle *from, EC_Handle *to, uint32_t sender) {
  uint8_t bytes[EC_MAX_MESSAGE];
  uint32_t size;
  while (ec_v1_next_message(from, bytes, sizeof bytes, &size) == EC_OK)
    require(ec_v1_receive(to, sender, bytes, size) == EC_OK);
  EC_Event event;
  while (ec_v1_next_event(from, &event) == EC_OK) {
  } // Host chooses its own event callbacks.
}
int main() {
  auto *host = ec_v1_create(EC_ABI_V1, EC_ROLE_HOST, 1);
  auto *guest = ec_v1_create(EC_ABI_V1, EC_ROLE_REPLICA, 2);
  require(host && guest);
  require(ec_v1_set_peer_active(host, 2, 1) == EC_OK);
  for (uint32_t tick = 0; tick < 600; tick++) {
    ec_v1_set_local_input(guest, tick < 144 ? 1000 : 0, EC_INPUT_ATTACK);
    ec_v1_tick(guest);
    transfer(guest, host, 2);
    ec_v1_set_local_input(host, 0, 0);
    ec_v1_tick(host);
    transfer(host, guest, 1);
  }
  EC_View a{}, b{};
  ec_v1_read_view(host, &a, sizeof a);
  ec_v1_read_view(guest, &b, sizeof b);
  require(a.enemy_hp == 0 && b.enemy_hp == 0 &&
          a.players[1].x == b.players[1].x);
  std::printf(
      "standalone PASS: tick=%u host/guest HP=%u/%u guest_x=%d milli-pixels\n",
      a.tick, a.enemy_hp, b.enemy_hp, b.players[1].x);
  ec_v1_destroy(guest);
  ec_v1_destroy(host);
}
