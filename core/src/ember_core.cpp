#include "ember_core.h"

static_assert(sizeof(EC_Player) == 40, "C ABI player layout");
static_assert(sizeof(EC_View) == 116, "C ABI view layout");
static_assert(sizeof(EC_Event) == 16, "C ABI event layout");

namespace {
constexpr uint32_t MESSAGE_CAP = 64, EVENT_CAP = 64, SNAPSHOT_SIZE = 104;
struct Message {
  uint32_t size;
  uint8_t bytes[EC_MAX_MESSAGE];
};
struct Input {
  int32_t axis;
  uint32_t flags, sequence, at;
  bool seen;
};
} // namespace
struct EC_Handle {
  bool live;
  uint32_t role, local_slot, tick, input_sequence, snapshot_sequence;
  uint32_t last_snapshot, rejected, dropped_events, dropped_messages, enemy_hp;
  bool snapshot_seen;
  EC_Player players[2];
  Input inputs[2];
  uint32_t held_jump[2];
  Message messages[MESSAGE_CAP];
  uint32_t message_head, message_count;
  EC_Event events[EVENT_CAP];
  uint32_t event_head, event_count;
  uint8_t staging[EC_MAX_MESSAGE];
  uint32_t staging_size, staging_sender, staging_count;
  bool staging_written[EC_MAX_MESSAGE];
};
namespace {
EC_Handle handles[32]{};
bool valid(EC_Handle *h) {
  for (auto &slot : handles)
    if (&slot == h)
      return slot.live;
  return false;
}
bool newer(uint32_t a, uint32_t b) {
  uint32_t d = a - b;
  return d && d < UINT32_C(0x80000000);
}
int32_t clamp(int32_t x, int32_t lo, int32_t hi) {
  return x < lo ? lo : x > hi ? hi : x;
}
int32_t absolute(int32_t x) { return x < 0 ? -x : x; }
void put(uint8_t *p, uint32_t n) {
  for (uint32_t i = 0; i < 4; i++)
    p[i] = uint8_t(n >> (8 * i));
}
uint32_t get(const uint8_t *p) {
  uint32_t n = 0;
  for (uint32_t i = 0; i < 4; i++)
    n |= uint32_t(p[i]) << (8 * i);
  return n;
}
int32_t signed_get(const uint8_t *p) {
  uint32_t n = get(p);
  return n <= INT32_MAX ? int32_t(n) : -1 - int32_t(UINT32_MAX - n);
}
void emit(EC_Handle *h, uint32_t type, uint32_t slot, uint32_t value) {
  if (h->event_count == EVENT_CAP) {
    h->dropped_events++;
    return;
  }
  h->events[(h->event_head + h->event_count++) % EVENT_CAP] = {h->tick, type,
                                                               slot, value};
}
Message *message(EC_Handle *h, uint32_t size, uint32_t type, uint32_t seq) {
  if (h->message_count == MESSAGE_CAP) {
    h->dropped_messages++;
    return nullptr;
  }
  auto *m = &h->messages[(h->message_head + h->message_count++) % MESSAGE_CAP];
  m->size = size;
  m->bytes[0] = 'E';
  m->bytes[1] = 'C';
  m->bytes[2] = '0';
  m->bytes[3] = '1';
  put(m->bytes + 4, type);
  put(m->bytes + 8, seq);
  return m;
}
void spawn(EC_Handle *h, uint32_t index) {
  h->players[index] = {
      index + 1,    1, index ? 260000 : 180000, 448000, 0, 1, 0, 0,
      EC_ANIM_IDLE, 1};
  h->inputs[index] = {0, 0, 0, h->tick, false};
  h->held_jump[index] = 0;
  emit(h, EC_EVENT_JOIN, index + 1, 0);
}
void write_snapshot(EC_Handle *h) {
  auto *m = message(h, SNAPSHOT_SIZE, 2, ++h->snapshot_sequence);
  if (!m)
    return;
  put(m->bytes + 12, h->tick);
  put(m->bytes + 16, h->enemy_hp);
  put(m->bytes + 20, 2);
  for (uint32_t i = 0; i < 2; i++) {
    const auto &p = h->players[i];
    auto *b = m->bytes + 24 + i * 40;
    put(b, p.slot);
    put(b + 4, p.active);
    put(b + 8, uint32_t(p.x));
    put(b + 12, uint32_t(p.y));
    put(b + 16, uint32_t(p.vy));
    put(b + 20, uint32_t(p.facing));
    put(b + 24, p.attack_ticks);
    put(b + 28, p.attack_id);
    put(b + 32, p.animation);
    put(b + 36, p.grounded);
  }
}
int32_t reject(EC_Handle *h, int32_t code) {
  h->rejected++;
  return code;
}
} // namespace
extern "C" {
uint32_t ec_v1_abi_version(void) { return EC_ABI_V1; }
uint32_t ec_v1_protocol_version(void) { return EC_PROTOCOL_V1; }
EC_Handle *ec_v1_create(uint32_t abi, uint32_t role, uint32_t local) {
  if (abi != EC_ABI_V1 || (role != EC_ROLE_HOST && role != EC_ROLE_REPLICA) ||
      local != role)
    return nullptr;
  for (auto &slot : handles)
    if (!slot.live) {
      slot.live = true;
      ec_v1_reset(&slot, role, local);
      return &slot;
    }
  return nullptr;
}
void ec_v1_destroy(EC_Handle *h) {
  if (valid(h))
    h->live = false;
}
int32_t ec_v1_reset(EC_Handle *h, uint32_t role, uint32_t local) {
  if (!valid(h))
    return EC_ERR_HANDLE;
  if ((role != EC_ROLE_HOST && role != EC_ROLE_REPLICA) || local != role)
    return EC_ERR_ARGUMENT;
  *h = EC_Handle{};
  h->live = true;
  h->role = role;
  h->local_slot = local;
  h->enemy_hp = 12;
  for (uint32_t i = 0; i < 2; i++)
    h->players[i].slot = i + 1;
  if (role == EC_ROLE_HOST)
    spawn(h, 0);
  return EC_OK;
}
int32_t ec_v1_set_local_input(EC_Handle *h, int32_t axis, uint32_t flags) {
  if (!valid(h))
    return EC_ERR_HANDLE;
  if (axis < -1000 || axis > 1000 || flags > 3)
    return EC_ERR_ARGUMENT;
  auto &in = h->inputs[h->local_slot - 1];
  in.axis = axis;
  in.flags = flags;
  in.at = h->tick;
  return EC_OK;
}
int32_t ec_v1_set_peer_active(EC_Handle *h, uint32_t slot, uint32_t active) {
  if (!valid(h))
    return EC_ERR_HANDLE;
  if (h->role != EC_ROLE_HOST)
    return EC_ERR_AUTHORITY;
  if (slot != 2 || active > 1)
    return EC_ERR_ARGUMENT;
  if (active && !h->players[1].active)
    spawn(h, 1);
  if (!active && h->players[1].active) {
    h->players[1].active = 0;
    h->inputs[1] = {};
    emit(h, EC_EVENT_LEAVE, 2, 0);
  }
  return EC_OK;
}
int32_t ec_v1_tick(EC_Handle *h) {
  if (!valid(h))
    return EC_ERR_HANDLE;
  if (h->role == EC_ROLE_REPLICA) {
    const auto &in = h->inputs[1];
    auto *m = message(h, 24, 1, ++h->input_sequence);
    if (m) {
      put(m->bytes + 12, 2);
      put(m->bytes + 16, uint32_t(in.axis));
      put(m->bytes + 20, in.flags);
    }
    return EC_OK;
  }
  h->tick++;
  for (uint32_t i = 0; i < 2; i++) {
    auto &p = h->players[i];
    if (!p.active)
      continue;
    auto in = h->inputs[i];
    if (i && h->tick - in.at > 18) {
      in.axis = 0;
      in.flags = 0;
    }
    p.x = clamp(p.x + (2833 * in.axis) / 1000, 24000, 936000);
    if (in.axis)
      p.facing = in.axis > 0 ? 1 : -1;
    uint32_t jump = (in.flags & EC_INPUT_JUMP) != 0;
    if (jump && !h->held_jump[i] && p.grounded)
      p.vy = -6000;
    h->held_jump[i] = jump;
    // Variable-height rise, a short apex and a quicker fall.
    if (!jump && p.vy < -2400)
      p.vy = -2400;
    p.vy += p.vy < 0 ? 300 : 500;
    p.y += p.vy;
    if (p.y >= 448000) {
      p.y = 448000;
      p.vy = 0;
      p.grounded = 1;
    } else
      p.grounded = 0;
    if (p.attack_ticks)
      p.attack_ticks--;
    if ((in.flags & EC_INPUT_ATTACK) && !p.attack_ticks) {
      p.attack_ticks = 24;
      p.attack_id++;
      emit(h, EC_EVENT_ATTACK, p.slot, p.attack_id);
    }
    // The downstroke reaches the target at tick 15, before recovery.
    if (p.attack_ticks == 9) {
      int32_t dx = 720000 - p.x;
      if (h->enemy_hp && absolute(dx) < 65000 &&
          absolute(p.y - 448000) < 45000 &&
          (dx == 0 || (dx > 0 ? 1 : -1) == p.facing)) {
        h->enemy_hp--;
        emit(h, EC_EVENT_DAMAGE, p.slot, h->enemy_hp);
      }
    }
    uint32_t anim = p.attack_ticks ? EC_ANIM_ATTACK
                    : !p.grounded  ? EC_ANIM_JUMP
                    : in.axis
                        ? (absolute(in.axis) < 500 ? EC_ANIM_WALK : EC_ANIM_RUN)
                        : EC_ANIM_IDLE;
    if (anim != p.animation) {
      p.animation = anim;
      emit(h, EC_EVENT_ANIMATION, p.slot, anim);
    }
  }
  if (h->tick % 3 == 0)
    write_snapshot(h);
  return EC_OK;
}
int32_t ec_v1_receive(EC_Handle *h, uint32_t sender, const uint8_t *b,
                      uint32_t size) {
  if (!valid(h))
    return EC_ERR_HANDLE;
  if (!b || size < 12 || size > EC_MAX_MESSAGE || b[0] != 'E' || b[1] != 'C' ||
      b[2] != '0' || b[3] != '1')
    return reject(h, EC_ERR_MESSAGE);
  uint32_t type = get(b + 4), seq = get(b + 8);
  if (type == 1) {
    if (h->role != EC_ROLE_HOST || sender != 2)
      return reject(h, EC_ERR_AUTHORITY);
    if (size != 24 || get(b + 12) != 2 || !h->players[1].active)
      return reject(h, EC_ERR_MESSAGE);
    int32_t axis = signed_get(b + 16);
    uint32_t flags = get(b + 20);
    if (axis < -1000 || axis > 1000 || flags > 3)
      return reject(h, EC_ERR_MESSAGE);
    auto &in = h->inputs[1];
    if (in.seen && !newer(seq, in.sequence))
      return reject(h, EC_ERR_STALE);
    in = {axis, flags, seq, h->tick, true};
    return EC_OK;
  }
  if (type != 2 || h->role != EC_ROLE_REPLICA || sender != 1)
    return reject(h, EC_ERR_AUTHORITY);
  if (size != SNAPSHOT_SIZE || get(b + 20) != 2 || get(b + 16) > 12)
    return reject(h, EC_ERR_MESSAGE);
  if (h->snapshot_seen && !newer(seq, h->last_snapshot))
    return reject(h, EC_ERR_STALE);
  EC_Player pending[2]{};
  for (uint32_t i = 0; i < 2; i++) {
    auto *s = b + 24 + i * 40;
    auto &p = pending[i];
    p.slot = get(s);
    p.active = get(s + 4);
    p.x = signed_get(s + 8);
    p.y = signed_get(s + 12);
    p.vy = signed_get(s + 16);
    p.facing = signed_get(s + 20);
    p.attack_ticks = get(s + 24);
    p.attack_id = get(s + 28);
    p.animation = get(s + 32);
    p.grounded = get(s + 36);
    if (p.slot != i + 1 || p.active > 1 ||
        (p.active && (p.x < 24000 || p.x > 936000 || p.y < -2000000 ||
                      p.y > 448000 || p.vy < -20000 || p.vy > 20000 ||
                      (p.facing != 1 && p.facing != -1))) ||
        p.attack_ticks > 24 || p.animation > EC_ANIM_WALK || p.grounded > 1)
      return reject(h, EC_ERR_MESSAGE);
  }
  uint32_t previous_hp = h->enemy_hp;
  h->tick = get(b + 12);
  h->enemy_hp = get(b + 16);
  for (uint32_t i = 0; i < 2; i++) {
    const auto previous = h->players[i];
    h->players[i] = pending[i];
    const auto &p = pending[i];
    if (p.active && !previous.active)
      emit(h, EC_EVENT_JOIN, p.slot, 0);
    if (!p.active && previous.active)
      emit(h, EC_EVENT_LEAVE, p.slot, 0);
    // Attack IDs belong to an actor lifetime; an idle respawn resets to zero.
    if (p.active && ((previous.active && p.attack_id != previous.attack_id) ||
                     (!previous.active && p.attack_ticks > 0)))
      emit(h, EC_EVENT_ATTACK, p.slot, p.attack_id);
    if (p.active && p.animation != previous.animation)
      emit(h, EC_EVENT_ANIMATION, p.slot, p.animation);
  }
  if (h->enemy_hp < previous_hp)
    emit(h, EC_EVENT_DAMAGE, 0, h->enemy_hp);
  h->last_snapshot = seq;
  h->snapshot_seen = true;
  h->snapshot_sequence = seq;
  return EC_OK;
}
int32_t ec_v1_next_message(EC_Handle *h, uint8_t *buffer, uint32_t capacity,
                           uint32_t *size) {
  if (!valid(h))
    return EC_ERR_HANDLE;
  if (!size)
    return EC_ERR_ARGUMENT;
  if (!h->message_count) {
    *size = 0;
    return EC_EMPTY;
  }
  const auto &m = h->messages[h->message_head];
  *size = m.size;
  if (capacity < m.size || !buffer)
    return EC_ERR_CAPACITY;
  for (uint32_t i = 0; i < m.size; i++)
    buffer[i] = m.bytes[i];
  h->message_head = (h->message_head + 1) % MESSAGE_CAP;
  h->message_count--;
  return EC_OK;
}
int32_t ec_v1_next_event(EC_Handle *h, EC_Event *event) {
  if (!valid(h))
    return EC_ERR_HANDLE;
  if (!event)
    return EC_ERR_ARGUMENT;
  if (!h->event_count)
    return EC_EMPTY;
  *event = h->events[h->event_head];
  h->event_head = (h->event_head + 1) % EVENT_CAP;
  h->event_count--;
  return EC_OK;
}
int32_t ec_v1_read_view(EC_Handle *h, EC_View *view, uint32_t capacity) {
  if (!valid(h))
    return EC_ERR_HANDLE;
  if (!view || capacity < sizeof(EC_View))
    return EC_ERR_CAPACITY;
  *view = EC_View{};
  view->struct_size = sizeof(EC_View);
  view->tick = h->tick;
  view->enemy_hp = h->enemy_hp;
  view->role = h->role;
  view->local_slot = h->local_slot;
  for (uint32_t i = 0; i < 2; i++)
    view->players[i] = h->players[i];
  view->snapshot_sequence = h->snapshot_sequence;
  view->rejected_messages = h->rejected;
  view->dropped_events = h->dropped_events;
  view->dropped_messages = h->dropped_messages;
  return EC_OK;
}
int32_t ec_v1_reset_dummy(EC_Handle *h) {
  if (!valid(h))
    return EC_ERR_HANDLE;
  if (h->role != EC_ROLE_HOST)
    return EC_ERR_AUTHORITY;
  h->enemy_hp = 12;
  return EC_OK;
}
int32_t ec_v1_command(EC_Handle *h, int32_t op, int32_t a, int32_t b) {
  if (!valid(h))
    return EC_ERR_HANDLE;
  switch (op) {
  case 0:
    return ec_v1_reset(h, uint32_t(a), uint32_t(b));
  case 1:
    return ec_v1_set_local_input(h, a, uint32_t(b));
  case 2:
    return ec_v1_tick(h);
  case 3:
    return ec_v1_set_peer_active(h, uint32_t(a), uint32_t(b));
  case 4:
    h->staging_size = 0;
    h->staging_count = 0;
    for (auto &written : h->staging_written)
      written = false;
    if (b < 12 || uint32_t(b) > EC_MAX_MESSAGE)
      return EC_ERR_ARGUMENT;
    h->staging_size = uint32_t(b);
    h->staging_sender = uint32_t(a);
    return EC_OK;
  case 5:
    if (a < 0 || uint32_t(a) >= h->staging_size || b < 0 || b > 255)
      return EC_ERR_ARGUMENT;
    if (!h->staging_written[uint32_t(a)]) {
      h->staging_written[uint32_t(a)] = true;
      h->staging_count++;
    }
    h->staging[uint32_t(a)] = uint8_t(b);
    return EC_OK;
  case 6: {
    uint32_t size = h->staging_size;
    // Finish consumes the stage, including failed attempts.
    h->staging_size = 0;
    if (!size || h->staging_count != size)
      return reject(h, EC_ERR_MESSAGE);
    return ec_v1_receive(h, h->staging_sender, h->staging, size);
  }
  case 7:
    return h->message_count ? int32_t(h->messages[h->message_head].size) : 0;
  case 8:
    if (!h->message_count || a < 0 ||
        uint32_t(a) >= h->messages[h->message_head].size)
      return EC_ERR_ARGUMENT;
    return h->messages[h->message_head].bytes[uint32_t(a)];
  case 9:
    if (!h->message_count)
      return EC_EMPTY;
    h->message_head = (h->message_head + 1) % MESSAGE_CAP;
    h->message_count--;
    return EC_OK;
  case 10: {
    const EC_Player *p =
        (b >= 1 && b <= 2) ? &h->players[uint32_t(b) - 1] : nullptr;
    switch (a) {
    case 0:
      return int32_t(h->tick);
    case 1:
      return int32_t(h->enemy_hp);
    case 11:
      return int32_t(h->snapshot_sequence);
    case 12:
      return int32_t(h->rejected);
    case 13:
      return int32_t(h->dropped_events);
    case 14:
      return int32_t(h->dropped_messages);
    default:
      break;
    }
    if (!p)
      return EC_ERR_ARGUMENT;
    switch (a) {
    case 2:
      return int32_t(p->active);
    case 3:
      return p->x;
    case 4:
      return p->y;
    case 5:
      return p->vy;
    case 6:
      return p->facing;
    case 7:
      return int32_t(p->attack_ticks);
    case 8:
      return int32_t(p->attack_id);
    case 9:
      return int32_t(p->animation);
    case 10:
      return int32_t(p->grounded);
    default:
      return EC_ERR_ARGUMENT;
    }
  }
  case 11:
    return ec_v1_reset_dummy(h);
  case 12: {
    if (!h->event_count)
      return 0;
    const auto &e = h->events[h->event_head];
    switch (a) {
    case 0:
      return int32_t(e.type);
    case 1:
      return int32_t(e.slot);
    case 2:
      return int32_t(e.value);
    case 3:
      return int32_t(e.tick);
    default:
      return EC_ERR_ARGUMENT;
    }
  }
  case 13:
    if (!h->event_count)
      return EC_EMPTY;
    h->event_head = (h->event_head + 1) % EVENT_CAP;
    h->event_count--;
    return EC_OK;
  case 14:
    return int32_t(EC_ABI_V1);
  default:
    return EC_ERR_ARGUMENT;
  }
}
}
