# Prototype contract

`src/main.gd` owns the scene, compact native controls, one flat scrolling arena and shared melee dummy. Movement is clamped to a 1920-pixel stage. Gravity and ground contact are simplified scalar simulation, not CharacterBody2D collision. There is no RPG inventory, map system or audio.

Seven CraftPix saber-fighter clips use 128×128 AtlasTexture regions, nearest filtering and 2× scale. Auto selects idle/run/jump/attack from simulation; inspection buttons override visuals only, including hurt/death. Nonlooping previews hold their final frame. Without private assets, an original five-frame placeholder keeps public source runnable.

Host simulates at the default 60 Hz physics rate, including guest movement, gravity, attack cooldown, range/facing checks and enemy HP. Guest sends bounded axis and held jump/attack flags on unreliable ordered channel 1. Input older than 300 ms neutralizes on host. Host transmits complete actor dictionaries and dummy HP/x every third physics frame on channel 2. Guest displays snapshots directly, without interpolation/prediction. RPC authority restricts snapshots to host and accepts inputs only from a known connected player.

Native transport: ENet UDP 27840, one guest. Web transport: WebRTCMultiplayerPeer, host ID 1 / guest ID 2. Manual base64 JSON codes contain SDP and gathered ICE. STUN is public Google STUN; no TURN or automatic signaling. Browser WebRTC has not yet been established across independent networks. Reset closes the old peer and clears actor/sprite state. Client failure, host departure and timeouts return to solo. GUI text entry suppresses movement keys.

`--test-host` / `--test-client` are finite native integration modes; successful runs establish a localhost peer exchange only. `--capture` saves a finite native GPU preview. No public internet reliability, anti-cheat, browser compatibility matrix or production latency guarantee is implied.
