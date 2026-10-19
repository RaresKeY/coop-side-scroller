#ifndef EMBER_CORE_V1_H
#define EMBER_CORE_V1_H
#include <stddef.h>
#include <stdint.h>
#if defined(EC_STATIC)
#define EC_API
#elif defined(_WIN32)
#if defined(EMBER_BUILD)
#define EC_API __declspec(dllexport)
#else
#define EC_API __declspec(dllimport)
#endif
#else
#define EC_API __attribute__((visibility("default")))
#endif
#ifdef __cplusplus
extern "C" {
#endif
#define EC_ABI_V1 UINT32_C(0x00010000)
#define EC_PROTOCOL_V1 UINT32_C(1)
#define EC_TICK_HZ UINT32_C(60)
#define EC_MAX_MESSAGE UINT32_C(104)
#define EC_ROLE_HOST UINT32_C(1)
#define EC_ROLE_REPLICA UINT32_C(2)
#define EC_INPUT_JUMP UINT32_C(1)
#define EC_INPUT_ATTACK UINT32_C(2)
#define EC_ANIM_IDLE UINT32_C(0)
#define EC_ANIM_RUN UINT32_C(1)
#define EC_ANIM_JUMP UINT32_C(2)
#define EC_ANIM_ATTACK UINT32_C(3)
#define EC_ANIM_WALK UINT32_C(4)
#define EC_EVENT_JOIN UINT32_C(1)
#define EC_EVENT_LEAVE UINT32_C(2)
#define EC_EVENT_ATTACK UINT32_C(3)
#define EC_EVENT_DAMAGE UINT32_C(4)
#define EC_EVENT_ANIMATION UINT32_C(5)
#define EC_OK INT32_C(0)
#define EC_EMPTY INT32_C(1)
#define EC_ERR_HANDLE (-INT32_C(1))
#define EC_ERR_ARGUMENT (-INT32_C(2))
#define EC_ERR_AUTHORITY (-INT32_C(3))
#define EC_ERR_MESSAGE (-INT32_C(4))
#define EC_ERR_STALE (-INT32_C(5))
#define EC_ERR_CAPACITY (-INT32_C(6))

typedef struct EC_Handle EC_Handle;
/* Host units: 1/1000 reference pixel, origin top-left, +x right, +y down.
   Velocity is milli-pixels per tick. Structs are native ABI views, NOT wire
   data. */
typedef struct EC_Player {
  uint32_t slot, active;
  int32_t x, y, vy, facing;
  uint32_t attack_ticks, attack_id, animation, grounded;
} EC_Player;
typedef struct EC_View {
  uint32_t struct_size, tick, enemy_hp, role, local_slot;
  EC_Player players[2];
  uint32_t snapshot_sequence, rejected_messages, dropped_events,
      dropped_messages;
} EC_View;
typedef struct EC_Event {
  uint32_t tick, type, slot, value;
} EC_Event;

EC_API uint32_t ec_v1_abi_version(void);
EC_API uint32_t ec_v1_protocol_version(void);
/* Core owns handle storage (32 live handles maximum); NULL on bad
   config/exhaustion. Caller owns the lifetime, must destroy once and never
   reuse a destroyed pointer. Calls are externally serialized; no clocks,
   threads, engine objects or allocation API. */
EC_API EC_Handle *ec_v1_create(uint32_t abi, uint32_t role,
                               uint32_t local_slot);
EC_API void ec_v1_destroy(EC_Handle *handle);
EC_API int32_t ec_v1_reset(EC_Handle *handle, uint32_t role,
                           uint32_t local_slot);
EC_API int32_t ec_v1_set_local_input(EC_Handle *handle, int32_t axis_milli,
                                     uint32_t flags);
EC_API int32_t ec_v1_set_peer_active(EC_Handle *handle, uint32_t slot,
                                     uint32_t active);
/* Exactly one fixed tick. Replica ticks emit input messages, never simulate
 * authority. */
EC_API int32_t ec_v1_tick(EC_Handle *handle);
/* sender_slot is authenticated by the TRANSPORT ADAPTER, never trusted from
 * payload. */
EC_API int32_t ec_v1_receive(EC_Handle *handle, uint32_t sender_slot,
                             const uint8_t *bytes, uint32_t size);
/* Copies into caller memory. Buffer-too-small sets required size without
   consuming. EC_EMPTY sets *size=0. No returned pointers into mutable core
   storage. */
EC_API int32_t ec_v1_next_message(EC_Handle *handle, uint8_t *buffer,
                                  uint32_t capacity, uint32_t *size);
EC_API int32_t ec_v1_next_event(EC_Handle *handle, EC_Event *event);
EC_API int32_t ec_v1_read_view(EC_Handle *handle, EC_View *view,
                               uint32_t capacity);
EC_API int32_t ec_v1_reset_dummy(EC_Handle *handle);
/* Narrow numeric bridge for minimal Godot/JS adapters. See specs/c-abi.md.
   Applications with native FFI should prefer the typed functions above. */
EC_API int32_t ec_v1_command(EC_Handle *handle, int32_t operation, int32_t a,
                             int32_t b);
#ifdef __cplusplus
}
#endif
#endif
