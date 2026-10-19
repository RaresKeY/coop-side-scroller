# Character presentation and scene frame audit

Owners: `src/character_view.gd`, `shaders/pixel_superscale.gdshader`, integration in `src/main.gd`, `tests/character_view.gd`, `tests/pixel_sampling.gd`, `tests/animation_capture.gd` and `tools/animation_report.py`.

## Size, atlas regions and anchors

Character display scale is 1×: standing height is approximately 67 reference pixels, just over two 32-pixel tiles. The original fallback sprite uses display scale 1.5×. The training dummy is 64 pixels tall, with a health bar above it. World units and floor rules are defined in [portable core](portable-core.md).

CraftPix PNGs and source-library art remain untouched and retain their manifest hashes. Idle/walk/run/hurt/dead use their original 128×128 atlas cells. Jump uses source-frame-specific foot anchors to avoid adding the sheet's baked vertical offsets to the actual physical trajectory: y anchors are `[128,128,128,128,128,119,108,106,109,118,117,128,128,128,128,128,128]`, x=64. Run/walk retain their authored gait/flight-phase foot movement with baseline 128.

Attack artwork crosses nominal cell boundaries. Old uniform slicing cropped frame 0/3/4 blade tips and displayed those pieces as detached fragments in frames 1/4. Runtime AtlasTexture rectangles `(x,y,width,height)` now are `(0,0,148,128)`, `(148,0,108,128)`, `(256,0,128,128)`, `(384,0,148,128)`, `(536,0,128,128)`. All saber pixels, including the old effect-only sixth cell's tail, belong to their correct five poses. Genuine authored detached slash trails in frame 3 are retained.

Attack's body anchor is source cell x=76, feet y=111, removing its unwanted 12-pixel body translation relative to idle. Offset is computed from the actual rectangle size, and mirrored offsets preserve the same world anchor in both directions. No recentering by bounding box occurs at runtime; that would make sword motion drag the body around.

## Automatic timing

The core still supplies logical idle/run/jump/attack/walk states, attack ID/cooldown and grounded/velocity state. The renderer owns frame selection and presentation follow-through; it never computes authority, damage or player movement. No animation-selection UI has been added.

The Godot adapter presents once per 60 Hz physics callback. Idle breathes at 6 fps, walk plays at 12 fps and run at 24 fps. Attack uses all five frames across the existing 24 ticks, with durations **3/5/3/4/9 ticks**: anticipation, lift, apex, downstroke and contact/recovery. C++ applies damage once at age 15 ticks (250 ms), when the blade reaches the dummy, rather than on the first anticipation frame. Repeated held attacks retain the 24-tick cadence. Frame timing is renderer-owned; hit eligibility is core-owned.

Jump frames follow real velocity: frames 0–2 are short takeoff poses; 3–7 follow rising velocity; frame 8 covers the apex; 9–12 follow descent. On an observed ground-contact transition, idle presentation plays the cosmetic landing/recovery sequence `13,14,15,16,16,14,13,12,0`, one tick each, then resumes idle. Movement/attacks immediately take precedence; there is no landing input lock or added simulation state. A jump that is already falling when an attack ends does not replay takeoff. Hurt/dead remain reserved clips, visually audited but not activated by this prototype's gameplay.

C++ jump tuning is in [portable-core.md](portable-core.md). All 17 jump source frames occur in the tested held-jump plus landing playback. Tap jumps may skip poses. Replica observations can coalesce frame/state transitions at the 20 Hz snapshot cadence; no new network interpolation or rollback is claimed.

## Runtime superscaling

Pocket Salvage's scene preview was reviewed locally: it displays stored 8× nearest-replicated derivatives at one-eighth local scale with runtime linear filtering. This game uses the corresponding UV remap on the **original** texture in a small CanvasItem shader, followed by one explicit bilinear sample. It creates no enlarged PNGs/textures, full-scene supersampling target or additional full-screen pass. Frame bounds clamp samples to the selected atlas rectangle, and vertex tint is preserved without multiplying the source texture twice. Uniform bounds update only when a clip/frame changes.

Sampling is scene-local to character sprites with linear filtering; imported mipmaps remain enabled and other texture/UI defaults remain unchanged. At ordinary/fractional magnification the shader emulates the narrow edge blend of an 8× nearest copy sampled linearly. This is pixel replication/filtering, not generated detail or a guarantee against minification aliasing. The source sheets total 3.875 MiB of RGBA texels before mipmaps; 8× copies would require 248 MiB for the same uncompressed texels. These are arithmetic storage budgets, not measured VRAM allocations or frame-time gains.

Reference: [Godot CanvasItem shader built-ins](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/canvas_item_shader.html). No code or assets were copied from Pocket Salvage.

## Verification and retained evidence

`./tests/animations.sh` requires the licensed imported selection, current prepared C++ core, installed Pillow and the normal Godot/Gamescope runtime. It runs playback/anchor assertions, a GPU sampling comparison and full-scene capture; it adds no product inspection controls. It saves 122 full 960×540 scene captures (61 retained frames × two directions), 79 actual core-driven jump/attack ticks and the playback trace under ignored `build/animation-after/`. The report tool creates labelled scene-context contact sheets while retaining every full scene.

The capture pass and all individual frame/contact sheets were inspected on NVIDIA RTX 2080 Ti / Godot 4.7. Core-driven contact sheets confirm the quicker fall, grounded landing and damage flash only at the visible contact phase. The GPU reference compares six cases (idle, attack and run, both facings) at fractional position/1.37× scale against temporary in-memory 8× nearest copies sampled linearly: maximum channel difference **0** in the tested images. A deliberately shifted reference produces a mismatch, confirming the comparison rejects incorrect alignment. That is bounded sampling evidence, not a full browser/GPU matrix or performance benchmark.
