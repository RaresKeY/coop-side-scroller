# TODO

- [x] Fix false replica attack events when slot 2 rejoins (`core/src/ember_core.cpp`, snapshot attack-ID comparison). Reproduction: slot 2 attacks, leaves, then rejoins idle; spawning resets its attack ID to zero, which differs from the previous lifetime's ID and incorrectly emits `EC_EVENT_ATTACK`. Account for actor lifetime changes when comparing attack IDs, and add a regression test covering attack → leave → idle rejoin.

Implemented locally with native sanitizer and Wasm regressions for attack → leave → idle rejoin, subsequent real attack, and joining during an active attack. Lifetime changes must be observed in snapshots; the wire format is unchanged.
