// Shared integer rules for the shipping snapshot adapter and deterministic lab.
#pragma once
#include "ember_core.h"
namespace ember_sim {
struct Input { int32_t axis; uint32_t flags; };
inline int32_t clamp(int32_t x, int32_t lo, int32_t hi) { return x < lo ? lo : x > hi ? hi : x; }
inline int32_t absolute(int32_t x) { return x < 0 ? -x : x; }
template<class World, class Sink>
void step(World &world, const Input (&inputs)[2], Sink sink) {
  world.tick++;
  for (uint32_t i = 0; i < 2; i++) {
    auto &p = world.players[i];
    if (!p.active)
      continue;
    const auto in = inputs[i];
    p.x = clamp(p.x + (2833 * in.axis) / 1000, 24000, 936000);
    if (in.axis)
      p.facing = in.axis > 0 ? 1 : -1;
    uint32_t jump = (in.flags & EC_INPUT_JUMP) != 0;
    if (jump && !world.held_jump[i] && p.grounded)
      p.vy = -6000;
    world.held_jump[i] = jump;
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
      sink(EC_EVENT_ATTACK, p.slot, p.attack_id);
    }
    // The downstroke reaches the target at tick 15, before recovery.
    if (p.attack_ticks == 9) {
      int32_t dx = 720000 - p.x;
      if (world.enemy_hp && absolute(dx) < 65000 &&
          absolute(p.y - 448000) < 45000 &&
          (dx == 0 || (dx > 0 ? 1 : -1) == p.facing)) {
        world.enemy_hp--;
        sink(EC_EVENT_DAMAGE, p.slot, world.enemy_hp);
      }
    }
    uint32_t anim = p.attack_ticks ? EC_ANIM_ATTACK
                    : !p.grounded  ? EC_ANIM_JUMP
                    : in.axis
                        ? (absolute(in.axis) < 500 ? EC_ANIM_WALK : EC_ANIM_RUN)
                        : EC_ANIM_IDLE;
    if (anim != p.animation) {
      p.animation = anim;
      sink(EC_EVENT_ANIMATION, p.slot, anim);
    }
  }
}
} // namespace ember_sim
