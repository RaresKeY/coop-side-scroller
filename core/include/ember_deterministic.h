#ifndef EMBER_DETERMINISTIC_V1_H
#define EMBER_DETERMINISTIC_V1_H
#include "ember_core.h"
#ifdef __cplusplus
extern "C" {
#endif
/* Additive experimental API; its EDI1/EDC1 formats remain separate from shipping EC03. */
#define EC_DETERMINISTIC_RULES UINT32_C(1)
#define EC_DETERMINISTIC_HISTORY UINT32_C(256)
#define EC_DETERMINISTIC_PACKET UINT32_C(80)
#define EC_DETERMINISTIC_CHECKPOINT UINT32_C(140)
#define EC_ERR_CONFLICT (-INT32_C(7))
#define EC_ERR_DESYNC (-INT32_C(8))
typedef struct EC_Deterministic EC_Deterministic;
typedef struct EC_DeterministicStats {
  uint32_t struct_size, tick, confirmed_tick, state_hash, peer_ack;
  uint32_t stalls, rollbacks, resimulated_ticks, rejected, desync;
  uint32_t max_correction, dropped_events, local_through, remote_through;
} EC_DeterministicStats;
/* Four handles, explicit 128-bit session, epoch and local slot. prediction=0
   selects lockstep; 1..12 bounds speculative ticks. No clocks/transports. */
EC_API EC_Deterministic *ec_v1_deterministic_create(uint32_t abi,
    uint32_t local_slot, const uint8_t *session, uint32_t epoch,
    uint32_t prediction);
EC_API void ec_v1_deterministic_destroy(EC_Deterministic *handle);
/* Local frames must be contiguous, beginning at checkpoint tick+1. */
EC_API int32_t ec_v1_deterministic_input(EC_Deterministic *handle,
    uint32_t tick, int32_t axis, uint32_t flags);
/* target is a desired simulation tick, not wall time. EC_EMPTY means stalled.
   Confirmed events are emitted once; speculative events are suppressed. */
EC_API int32_t ec_v1_deterministic_advance(EC_Deterministic *handle,
    uint32_t target);
EC_API int32_t ec_v1_deterministic_read_view(EC_Deterministic *handle,
    EC_View *view, uint32_t capacity);
EC_API int32_t ec_v1_deterministic_stats(EC_Deterministic *handle,
    EC_DeterministicStats *stats, uint32_t capacity);
EC_API int32_t ec_v1_deterministic_next_event(EC_Deterministic *handle,
    EC_Event *event);
/* EDI1 packets contain 0..8 compact contiguous inputs plus ACK/hash. The
   adapter schedules new batches and retransmission of unacknowledged frames.
   A zero count is an ACK/hash heartbeat. Caller authenticates sender_slot. */
EC_API int32_t ec_v1_deterministic_pack(EC_Deterministic *handle,
    uint32_t first_tick, uint32_t count, uint8_t *bytes, uint32_t capacity);
EC_API int32_t ec_v1_deterministic_receive(EC_Deterministic *handle,
    uint32_t sender_slot, const uint8_t *bytes, uint32_t size);
/* Save confirmed state only. load is an explicit trusted recovery barrier:
   same session/rules, strictly newer epoch than handle AND checkpoint;
   active_mask=1..3 must contain local slot. Old packets cannot enter it.
   The adapter must coordinate the checkpoint/epoch/membership on both peers. */
EC_API int32_t ec_v1_deterministic_save(EC_Deterministic *handle,
    uint8_t *bytes, uint32_t capacity);
EC_API int32_t ec_v1_deterministic_load(EC_Deterministic *handle,
    const uint8_t *bytes, uint32_t size, uint32_t new_epoch,
    uint32_t active_mask);
#ifdef __cplusplus
}
#endif
#endif
