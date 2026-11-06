#include "ember_core.h"
#include <cassert>
#include <cstdio>
#include <cstring>
#include <vector>
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
static void rejoin_events() {
  auto *h = ec_v1_create(EC_ABI_V1, 1, 1);
  auto *r = ec_v1_create(EC_ABI_V1, 2, 2);
  uint8_t bytes[EC_MAX_MESSAGE]{};
  auto snapshot = [&]() {
    for (int i=0;i<3;i++) assert(ec_v1_tick(h)==EC_OK);
    auto n=drain(h,bytes);
    assert(ec_v1_receive(r,1,bytes,n)==EC_OK);
  };
  auto events = [&](int joins, int leaves, int attacks) {
    EC_Event e{};int j=0,l=0,a=0;
    while(ec_v1_next_event(r,&e)==EC_OK) if(e.slot==2) {
      j+=e.type==EC_EVENT_JOIN;l+=e.type==EC_EVENT_LEAVE;a+=e.type==EC_EVENT_ATTACK;
    }
    assert(j==joins && l==leaves && a==attacks);
  };
  auto attack = [&]() {
    assert(ec_v1_set_local_input(r,0,EC_INPUT_ATTACK)==EC_OK);
    assert(ec_v1_tick(r)==EC_OK);
    auto n=drain(r,bytes);
    assert(ec_v1_receive(h,2,bytes,n)==EC_OK);
  };
  ec_v1_set_peer_active(h,2,1);snapshot();events(1,0,0);
  attack();snapshot();events(0,0,1);
  ec_v1_set_peer_active(h,2,0);snapshot();events(0,1,0);
  ec_v1_set_peer_active(h,2,1);snapshot();events(1,0,0);
  attack();snapshot();events(0,0,1);
  // Joining an already attacking actor still produces its active attack cue.
  ec_v1_reset(r,2,2);snapshot();events(1,0,1);
  ec_v1_destroy(h);ec_v1_destroy(r);
}

static void prediction_contracts() {
  auto *h=ec_v1_create(EC_ABI_V1,1,1), *g=ec_v1_create(EC_ABI_V1,2,2);
  assert(h&&g);ec_v1_set_peer_active(h,2,1);
  uint8_t b[EC_MAX_MESSAGE]{}, delayed[EC_MAX_MESSAGE]{};uint32_t size=0;
  auto receive_latest=[&]() {
    while(ec_v1_next_message(h,b,sizeof b,&size)==EC_OK)
      assert(ec_v1_receive(g,1,b,size)==EC_OK);
  };
  for(int i=0;i<3;++i)ec_v1_tick(h);
  receive_latest();
  for(int i=0;i<60;++i) {
    auto prior=view(g);auto authority=view(h);
    ec_v1_set_local_input(g,1000,i<45?EC_INPUT_JUMP:0);
    ec_v1_tick(g);auto predicted=view(g);
    assert(predicted.players[1].x==prior.players[1].x+2833);
    assert(view(h).players[1].x==authority.players[1].x);
    if(!i)assert(predicted.players[1].y<448000 && predicted.players[1].animation==EC_ANIM_JUMP);
    size=drain(g,b);assert(ec_v1_receive(h,2,b,size)==EC_OK);ec_v1_tick(h);
    receive_latest();
    assert(view(g).players[1].x==view(h).players[1].x);
    assert(view(g).players[1].y==view(h).players[1].y);
  }
  assert(view(g).players[1].grounded); // Held jump did not restart at reconciliation.
  // Delay a real snapshot while newer local input continues. ACKed frames
  // disappear; the unacknowledged suffix replays exactly once.
  ec_v1_set_local_input(g,-1000,0);
  for(int i=0;i<6;++i) {
    ec_v1_tick(g);size=drain(g,b);assert(ec_v1_receive(h,2,b,size)==EC_OK);ec_v1_tick(h);
    while(ec_v1_next_message(h,b,sizeof b,&size)==EC_OK)
      if(i==2)std::memcpy(delayed,b,size);
  }
  auto before=view(g);
  assert(ec_v1_receive(g,1,delayed,sizeof delayed)==EC_OK);
  assert(view(g).players[1].x==before.players[1].x);
  assert(ec_v1_receive(g,1,delayed,sizeof delayed)==EC_ERR_STALE);
  auto put=[](uint8_t *p,uint32_t n){for(int i=0;i<4;++i)p[i]=uint8_t(n>>(i*8));};
  delayed[8]++;put(delayed+104,67); // Only 66 local inputs have been produced.
  assert(ec_v1_receive(g,1,delayed,sizeof delayed)==EC_ERR_MESSAGE);
  assert(view(g).players[1].x==before.players[1].x);
  put(delayed+104,63);put(delayed+108,4);
  assert(ec_v1_receive(g,1,delayed,sizeof delayed)==EC_ERR_MESSAGE);
  put(delayed+108,2);put(delayed+72,700000);
  assert(ec_v1_receive(g,1,delayed,sizeof delayed)==EC_OK);
  assert(view(g).players[1].x==700000-3*2833); // Correction plus pending inputs.
  delayed[3]='1';delayed[8]++;
  assert(ec_v1_receive(g,1,delayed,sizeof delayed)==EC_ERR_MESSAGE);
  // Prediction is bounded during an outage and never causes confirmed damage.
  EC_Event confirmed{};while(ec_v1_next_event(g,&confirmed)==EC_OK){}
  ec_v1_set_local_input(g,0,EC_INPUT_ATTACK);
  for(int i=0;i<128;++i){ec_v1_tick(g);drain(g,b);}
  auto frozen=view(g);
  for(int i=0;i<100;++i){ec_v1_tick(g);drain(g,b);}
  assert(view(g).players[1].attack_ticks==frozen.players[1].attack_ticks);
  assert(view(g).enemy_hp==view(h).enemy_hp);
  assert(ec_v1_next_event(g,&confirmed)==EC_EMPTY);
  // A fresh authoritative view clears exhausted speculation, then input
  // responds again on its next fixed tick.
  for(int i=0;i<3;++i)ec_v1_tick(h);
  receive_latest();
  auto resumed=view(g);ec_v1_set_local_input(g,-1000,0);ec_v1_tick(g);
  assert(view(g).players[1].x==resumed.players[1].x-2833);
  // A tap's press packet may be lost, or superseded before the host ticks.
  for(int lost=0;lost<2;++lost) {
    ec_v1_reset(h,1,1);ec_v1_set_peer_active(h,2,1);ec_v1_reset(g,2,2);
    ec_v1_set_local_input(g,0,EC_INPUT_JUMP|EC_INPUT_ATTACK);ec_v1_tick(g);size=drain(g,b);
    if(!lost)assert(ec_v1_receive(h,2,b,size)==EC_OK);
    ec_v1_set_local_input(g,0,0);ec_v1_tick(g);size=drain(g,b);
    assert(ec_v1_receive(h,2,b,size)==EC_OK);ec_v1_tick(h);
    assert(view(h).players[1].y<448000 && view(h).players[1].attack_id==1);
    assert(ec_v1_receive(h,2,b,size)==EC_ERR_STALE);
    for(int i=0;i<60;++i){ec_v1_tick(g);size=drain(g,b);ec_v1_receive(h,2,b,size);ec_v1_tick(h);}
    assert(view(h).players[1].grounded && view(h).players[1].attack_id==1);
  }
  ec_v1_reset(h,1,1);ec_v1_set_peer_active(h,2,1);ec_v1_reset(g,2,2);
  ec_v1_tick(g);size=drain(g,b);put(b+24,UINT32_MAX);put(b+28,UINT32_MAX);
  assert(ec_v1_receive(h,2,b,size)==EC_OK);ec_v1_tick(h);
  for(int i=0;i<60;++i){ec_v1_tick(g);size=drain(g,b);put(b+24,UINT32_MAX);put(b+28,UINT32_MAX);ec_v1_receive(h,2,b,size);ec_v1_tick(h);}
  put(b+8,62);put(b+24,0);put(b+28,0);
  assert(ec_v1_receive(h,2,b,size)==EC_OK);ec_v1_tick(h);
  assert(view(h).players[1].attack_id==2 && !view(h).players[1].grounded);
  ec_v1_destroy(g);ec_v1_destroy(h);
}

static void input_queue_validation() {
  auto *h=ec_v1_create(EC_ABI_V1,1,1), *g=ec_v1_create(EC_ABI_V1,2,2);
  ec_v1_set_peer_active(h,2,1);
  uint8_t b[EC_MAX_MESSAGE]{};uint32_t size=0;
  ec_v1_tick(g);size=drain(g,b);
  b[32]=0;assert(ec_v1_receive(h,2,b,size)==EC_ERR_MESSAGE);
  b[32]=1;b[40]=4;assert(ec_v1_receive(h,2,b,size)==EC_ERR_MESSAGE);
  b[40]=0;b[36]=1;assert(ec_v1_receive(h,2,b,size)==EC_ERR_MESSAGE); // Last frame/header disagreement.
  b[36]=0;assert(ec_v1_receive(h,2,b,size)==EC_OK);
  for(int i=1;i<128;++i){ec_v1_tick(g);size=drain(g,b);assert(ec_v1_receive(h,2,b,size)==EC_OK);}
  ec_v1_tick(g);size=drain(g,b);assert(ec_v1_receive(h,2,b,size)==EC_ERR_CAPACITY);
  ec_v1_tick(h);
  assert(ec_v1_receive(h,2,b,size)==EC_OK); // Rejection didn't advance the receive sequence.
  ec_v1_set_peer_active(h,2,0);ec_v1_set_peer_active(h,2,1);ec_v1_tick(h);
  assert(view(h).players[1].x==260000 && view(h).players[1].animation==EC_ANIM_IDLE);
  ec_v1_destroy(g);ec_v1_destroy(h);
}

// The reported regression needs delayed, batched delivery, not an immediate
// one-input/one-host-tick loop. Every accepted frame must run exactly once.
static void batched_prediction() {
  struct Packet { int due; uint32_t sender, size; uint8_t bytes[EC_MAX_MESSAGE]; };
  for (int batch : {1, 3, 6, 9}) for (int loss : {0, 1}) {
    auto *h=ec_v1_create(EC_ABI_V1,1,1), *g=ec_v1_create(EC_ABI_V1,2,2);
    ec_v1_set_peer_active(h,2,1);
    std::vector<Packet> wire;
    auto emit=[&](EC_Handle *source, int tick, uint32_t sender) {
      Packet p{};p.sender=sender;p.due=((tick+5+batch-1)/batch)*batch;
      while(ec_v1_next_message(source,p.bytes,sizeof p.bytes,&p.size)==EC_OK)
        // Two consecutive lost inputs and snapshots recover from redundancy.
        if (!loss || tick%37<12 || tick%37>13) wire.push_back(p);
    };
    for (int tick=0;tick<360;++tick) {
      for (auto it=wire.begin();it!=wire.end();) {
        if(it->due>tick){++it;continue;}
        const auto before=view(g);
        assert(ec_v1_receive(it->sender==1?g:h,it->sender,it->bytes,it->size)==EC_OK);
        const auto after=view(g);
        if(it->sender==1 && tick>30) {
          assert(after.players[1].x==before.players[1].x);
          assert(after.players[1].y==before.players[1].y);
          assert(after.players[1].animation==before.players[1].animation);
        }
        it=wire.erase(it);
      }
      const int axis=tick>=30&&tick<120?1000:tick>=160&&tick<220?-1000:0;
      ec_v1_set_local_input(g,axis,((tick%53>=13&&tick%53<30)?EC_INPUT_JUMP:0) | ((tick%101>=20&&tick%101<70)?EC_INPUT_ATTACK:0));
      ec_v1_tick(g);emit(g,tick,2);ec_v1_tick(h);emit(h,tick,1);
    }
    ec_v1_destroy(g);ec_v1_destroy(h);
  }
}

int main() {
  prediction_contracts();
  batched_prediction();
  input_queue_validation();
  rejoin_events();
  assert(ec_v1_abi_version() == EC_ABI_V1 && ec_v1_protocol_version() == 3);
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
         size == 44);
  assert(ec_v1_next_message(guest, bytes, sizeof bytes, &size) == EC_OK &&
         size == 44);
  assert(bytes[0] == 'E' && bytes[3] == '3' && bytes[4] == 1 &&
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
  assert(last_size == 112);
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
  assert(ec_v1_command(host, 4, 2, 113) == EC_ERR_ARGUMENT);
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
