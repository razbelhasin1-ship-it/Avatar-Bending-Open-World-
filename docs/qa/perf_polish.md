# QA: perf_polish (wave 4)

Performance and camera polish across modules: shader / pipeline warm-up, the mobile render budget
at the four home spawns, settlement LOD fades, lock-on framing and occluder fades, and the flaky
WorldContent slicing test. Everything below was measured on the CI container: llvmpipe software
Vulkan / GL, 4 cores shared with another agent running Godot at the same time. Frame times are
software-rendering numbers (and noisy); draw calls, primitives and pipeline-compile counts are
what transfers to a real device.

Code: `src/perf/` (new: `ShaderWarmup`, `OccluderFader`, `MeshLods`, `FrameRecorder`,
`RenderCensus`, dither shaders), plus small changes in other modules (listed at the end).
Tests: `tests/unit/test_perf_polish.gd` (15), `tests/unit/test_worldcontent.gd` (slicing test).
Playtests: `perf_polish_budget`, `perf_polish_warmup`, `perf_polish_camera`,
`perf_polish_fade_probe` (`tests/playtest/scenarios/`).

## 1. Shader / pipeline warm-up

**Checked.** First use of every technique in the combat arena (`perf_polish_warmup`: the real
player casts every technique of the element through the input actions, each recorded with
`FrameRecorder`: longest frame, pipelines compiled, pipelines compiled at draw time) without and
with a warm-up, back to back on the same machine.

**Found.** Godot 4.7's ubershaders mean no draw-time *stall* (draw-time compilations were 0 in
both runs on Forward+), but the specialised pipelines of every new FX material / mesh format
were still compiled on first use, and the first casts carried the extra frame time of the shader
compiles: fire, Forward+, first cast of each technique, warm-up **off**: 27 pipelines compiled
during the casts (fire_combo 13, fire_blast 8, flame_guard 2, inferno 2, lightning 2), worst
first-cast frame 555 ms (fire_blast) against 338-373 ms for the same casts a second time.

**Fixed.** `ShaderWarmup` (`src/perf/shader_warmup.gd`): on a private stage beyond the world edge
(`stage_origin()`, never streamed, no NPC / enemy / wildlife reacts) rig-less casters cast every
technique of the player's element plus the light and heavy strikes of the other three elements
(enemy benders) at training posts (hits, blocks, burns, freezes; every other post guards), and
`_common_fx()` spawns every shared one-shot (all `FxBurst` kinds, the four decals, ring, flash,
rock / ice debris, parries and world impacts of all elements) — in front of its own camera for
2.4 game seconds, SFX bus muted, then everything it raised is removed again (projectiles,
constructs, fire rings, ground zones, camera, bus mute).

* World / tutorial: `src/world/game/playable_scene.gd:208` starts it once the ground is ready
  (progress 0.35) so it overlaps content streaming behind the loading overlay; the boot waits for
  it (`wait_done(MAX_SECONDS = 30 s)`) before the player spawns (`:215`). `load_report.warmup`.
* Combat arena: `scenes/dev/combat_arena.gd:63` `_warm_up()` holds the Router fade when the arena
  was entered through a transition (or uses its own black cover with param `warmup`).
* Skipped headless, with the `no_warmup` option / param or the `--no-warmup` user argument.

**Evidence** (`perf_polish_warmup`, ELEMENT=fire, Forward+, 960×540):

| | warm-up off | warm-up on |
| --- | --- | --- |
| pipelines compiled during the first casts | 27 | **0** |
| draw-time compilations during the first casts | 0 | 0 |
| worst first-cast frame | 555 ms (fire_blast) | 419 ms (flame_sweep / inferno) |
| fire_combo / fire_blast first cast, worst frame | 444 / 555 ms | 343 / 390 ms |
| arena ready (incl. warm-up) | 6.9 s | 18.6 s (warm-up 17.7 s, 65 pipelines, 27 frames) |

The warm-up's own 17.7 s are llvmpipe compiling 65 pipelines in software (27 rendered frames);
on a GPU driver that is a fraction of a second, and it is behind the loading screen either way.
In the world (Mobile renderer, mobile preset) the boot's warm-up compiled 150 pipelines (20 of
them at draw time — behind the overlay) for 18 abilities.

The playtest now checks that after the warm-up the first casts compile ≤ 3 pipelines in total.
`test_perf_polish.gd::test_warmup_run_casts_everything_and_cleans_up` forces a full run for each
element headless and checks the program and the cleanup (zones, SFX bus, camera, constructs,
projectiles).

**Remaining.** Godot's export-time shader baker (`shader_baker/enabled` export option) would also
remove the shader-source compile on first launch; left off because it is an export-pipeline
change (mobile module's presets) that could not be verified on a device here. The persistent
pipeline cache already keeps the pipelines between launches.

## 2. Mobile render budget at the four home spawns

BUDGET_SECTION

## 3. Settlement LOD fades

**Checked.** `perf_polish_fade_probe`: two overlapping "LOD" blocks (toon + ink outline) handing
over at 60 m with a 10 m margin, `VISIBILITY_RANGE_FADE_DISABLED` (hysteresis) beside
`VISIBILITY_RANGE_FADE_SELF`, camera at 45 / 56 / 60 / 64 / 75 m.

**Found.** The fade-self cross-fade is clean on Forward+ (blended colours, no holes, no sorting
artefacts on the outlined blocks; the blend runs over [end, end + margin]); the hard switch pops.
Both LODs draw inside the band (transparent pass), so it costs draw calls there.

**Fixed.** Desktop presets (`fade_margin` 12 m, `src/world/settlements/common/settlement_settings.gd:68`):
LOD0 → LOD1 (`settlement_provider.gd:96-104`) and LOD1 → silhouette (`settlement_far_provider.gd:56-62`,
same AABB and margin as LOD1, so the two fades meet) cross-fade instead of popping. Phones keep
hard switches (no doubled draws in the band) — their hand-overs sit at 74-97 m / 300 m behind the
quadrant HLOD anyway. `test_perf_polish.gd::test_desktop_lod_handovers_cross_fade` checks the
modes and bands per preset. Vegetation already used per-instance dithered LOD bands.

**Remaining.** Not judged on Compatibility (desktop presets use Forward+).

## 4. Camera: lock-on close quarters, occluders

**Checked.** `perf_polish_camera`: a bandit brawler fights the invulnerable, locked-on player in
the enemy arena for 9 s, once with the new close framing off (`PlayerCamera.close_framing =
false`, the old camera) and once on; every frame records whether the attacker's chest is hidden
behind the player's body (sight line camera → attacker within 0.42 m of the player's axis) or off
screen, and the yaw (reversals of the yaw rate = jitter). Then an NPC and the companion are put
on the line camera → player.

**Found.** With the old framing the close attacker stood behind the player model for most of the
fight: visible in only 24 % of the frames with the brawler within 3.5 m.

**Fixed.**
* `src/player/player_camera.gd:252-266`: below 4.8 m the view swings up to 30° off the
  player → target axis (full at 2.2 m), pulls back 0.9 m, lifts 6° and aims a bit more at the
  target. The side is chosen once (the side the camera already leans to) and kept until the
  target backs off past 5.5 m, so it never flips; everything is smoothed (rates 4-5 /s).
* `src/perf/occluder_fader.gd` (`PlayerCamera.occluders`): rays lens → knees / chest / head plus a
  lens sphere against NPC, companion and wildlife bodies; hit bodies dither out to 72 % over
  0.15 s and back over 0.3 s. Toon materials get per-surface dither twins
  (`src/perf/shaders/toon_dither.gdshader`, `outline_dither.gdshader`, same uniforms, 4×4 Bayer
  discard); creatures use the new `occlusion_fade` instance uniform
  (`assets/shaders/creatures/creature_common.gdshaderinc:42-51`, discard at the top of skin, fur
  shell, membrane, eye and outline shaders). Shared materials are never touched; owner overrides
  (hit flash) are respected and restored.

**Evidence** (`perf_polish_camera`, Forward+):

| | framing off (old) | framing on |
| --- | --- | --- |
| frames with the brawler < 3.5 m | 68 | 69 |
| attacker visible (not behind the player, on screen) | 24 % | **100 %** |
| yaw-rate reversals per second | 0.11 | 0.11 |
| largest yaw step per frame | 4.07° | 4.23° |

NPC on the line: fade 0.72 after 0.8 s, restored (own materials back) after stepping away;
polar bear dog on the line: fade 0.72 including every fur shell, back to 0 once moved. Unit
tests: `test_occluder_between_camera_and_player_fades_and_restores`,
`test_dither_twin_copies_the_toon_look`, `test_lock_on_close_target_stays_in_view`.

**Remaining.** Enemies are not faded (they are the fight; the close framing keeps them beside
the player instead). Settlement walls between camera and player still pull the camera in (the
existing collision cast), as before.

## 5. Flaky `test_worldcontent::test_main_thread_budget_slices_instantiation`

**Found.** The test judged WorldContent's per-frame main-thread time by wall clock. With another
Godot instance (or any load) on the 4 shared cores the OS preempts the main thread in the middle
of a 1.5 ms step, and the frame's wall time balloons for reasons that say nothing about the
framework: it failed intermittently under load.

**Fixed** (`tests/unit/test_worldcontent.gd:239-327`, no tolerance loosened):
* Deterministic part, judged on every run whatever the load: a step only starts while the 2 ms
  budget lasts, so at most ceil(2000 / 1500) = 2 steps per frame (`GridProvider.steps_by_frame`),
  the work is spread over > 5 frames, it settles, and no cell build ran on the main thread.
* Wall-clock part only on frames the OS did not preempt: `PreemptProbe` nodes before and after
  WorldContent read `nonvoluntary_ctxt_switches` of the main thread
  (`/proc/thread-self/status`), and the provider's busy-wait step records gaps > 400 µs. Samples
  are pooled over up to three fresh runs until 24 clean frames exist; judged with the original
  bounds (median ≤ budget + one step + 0.5 ms, ≤ 10 % of frames over budget + one step +
  overhead, worst < 3× that, framework overhead p25 < 1 ms). If fewer than 8 clean frames exist
  the wall-clock part is reported as not judged (the deterministic part still runs).

**Evidence.** Passed repeatedly with 3, 4 and 6 CPU hogs running; a mutation that lets a step
start while `elapsed < budget * 3` fails the deterministic check every time.

## Other modules touched (foundation_changes)

FOUNDATION_SECTION
