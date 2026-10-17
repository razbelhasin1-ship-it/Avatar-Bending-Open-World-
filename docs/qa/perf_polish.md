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
them at draw time — behind the overlay) for 18 abilities, overlapping the content streaming:
the measured loads grew from 7.0-17.9 s to 11.2-21.9 s (warm-up 7.0-13.5 s) on llvmpipe; on
Compatibility / llvmpipe the Water Tribe warm-up hit the 30 s cap (`MAX_SECONDS`, the boot then
continues; whatever was not compiled compiles on first use as before).

The playtest now checks that after the warm-up the first casts compile ≤ 3 pipelines in total.
`test_perf_polish.gd::test_warmup_run_casts_everything_and_cleans_up` forces a full run for each
element headless and checks the program and the cleanup (zones, SFX bus, camera, constructs,
projectiles).

**Remaining.** Godot's export-time shader baker (`shader_baker/enabled` export option) would also
remove the shader-source compile on first launch; left off because it is an export-pipeline
change (mobile module's presets) that could not be verified on a device here. The persistent
pipeline cache already keeps the pipelines between launches.

## 2. Mobile render budget at the four home spawns

**Checked.** `perf_polish_budget` (MOBILE=1, mobile preset with render scale 0.75, 1280×720):
a new game at each home spawn in the real world scene, the content allowed to settle, then the
camera turned to four directions (90° apart), each sampled for 2 s (renderer counters: draw
calls, primitives, shadow pass) plus a frustum-culled census of what is drawn by provider / LOD
(`RenderCensus`); `BREAKDOWN=1` hides one group at a time (terrain, water, each content provider,
each settlement LOD part, NPCs, player, companion) and records the renderer's drop, and measures
the same frame with mesh LODs off / 4× coarser. Numbers below are the **worst of the four views**
(main pass; shadow pass in its own column, as in docs/modules/mobile.md).

**Found** (before, Mobile renderer): 972k-1055k primitives and 210-409 draw calls per view.
Where it went (census + renderer breakdown): settlement LOD1 meshes drew the ink-outline pass
(invisible beyond 60 m, but every triangle twice), the whole LOD0 band was full detail out to
100 m, LOD1 used the regular kit, cities had up to four surfaces per merged mesh, night-glow
MultiMeshes were submitted by day, every garden species/LOD MultiMesh drew at any distance
(~85 draws at the Fire Nation spawn), far impostor forests ~80k triangles at Ba Sing Se, and no
procedural mesh had LOD index buffers (characters: 12.7k triangles each at any distance).

**Fixed** (phones only unless noted; `SettlementSettings` keys, table in
docs/modules/settlements.md):

| Change | Where |
| --- | --- |
| LOD1 / LOD2 without the ink outline pass (all presets) | `nation_palette.gd:115`, `kit_result.gd:84-93`, `settlement_provider.gd:70-73`, `settlement_far_provider.gd:56-63` |
| LOD1 built from the silhouette recipes (`lod1_kit` 2), merged into one surface (`merge_far`, `KitMerger.slot_map`) | `settlement_provider.gd:18, 233-260`, `kit_merger.gd` |
| LOD0 as quadrant HLOD under LOD1: full detail only in the camera's quadrant (≤ 46.8 m from a quadrant centre), kit LOD 1 elsewhere; collision / lights identical to desktop | `settlement_provider.gd:74-92, 150-227` |
| LOD0 band ends at the cell half diagonal + 6 m (96.5 m), LOD1 band at 220 m (was 300) | `settlement_settings.gd:29-31, 91-95` |
| Automatic mesh LODs (`MeshLods`, built on the workers) on settlement meshes; mid quadrants / LOD1 `lod_bias` 0.25, silhouettes 0.15 | `src/perf/mesh_lods.gd`, `world_content.gd:705-714`, `settlement_settings.gd:72-78` |
| Full-detail ice without the outline pass (`flat_ice`) | `kit_result.gd:87-90`, `settlement_provider.gd:85` |
| Night-glow MultiMeshes `night_only`: not submitted while the sun is up (all presets) | `settlement_fx.gd:155-157`, `world_content.gd:767-790` |
| Garden plant MultiMeshes limited to their species/LOD band (all presets), 170 m on phones | `settlement_fx.gd:86-110` |
| Far impostor forests thinned to 55 % (`far_density`) | `vegetation_settings.gd:38`, `forest_far_provider.gd:49-63` |
| Character bodies with mesh LODs (all presets; 6.4k / 3.2k / 1.6k / 0.8k levels) | `character_mesh_builder.gd:42-88` |
| Ocean disc 64 segments (~15k triangles instead of ~24k) | `water_system.gd:52-54` |

**Evidence — Mobile renderer** (`perf_polish_budget`, worst view; frame times are llvmpipe with
another Godot instance on the same cores):

| spawn | draws before → after | primitives before → after | shadow draws | shadow primitives | frame (llvmpipe) |
| --- | --- | --- | --- | --- | --- |
| water | 210 → **170** | 998k → **246k** | 75 → 78 | 399k → 153k | 424 → 356 ms |
|  load | total 17.9 s → 21.9 s (warm-up 13.5 s) | | | | |
| earth | 403 → **196** | 1055k → **231k** | 102 → 108 | 445k → 142k | 417 → 568 ms |
|  load | total 9.4 s → 14.6 s (warm-up 7.0 s) | | | | |
| fire | 409 → **141** | 1038k → **188k** | 74 → 87 | 288k → 141k | 392 → 376 ms |
|  load | total 10.1 s → 14.0 s (warm-up 7.2 s) | | | | |
| air | 265 → **133** | 972k → **169k** | 76 → 73 | 539k → 100k | 415 → 339 ms |
|  load | total 7.0 s → 11.2 s (warm-up 6.9 s) | | | | |

Renderer breakdown at the Water Tribe spawn (worst view, after): near settlement 130k
primitives (full-detail quadrants ~84k incl. outline, mid quadrants ~12k, LOD1 ~30k), far
silhouettes 44k / 33 draws, terrain 36k / 85 draws (the clipmap's fixed tiles), ocean 16k,
companion 12k, the NPCs 10k (mesh LODs: the census counts 174k of character triangles at LOD 0),
player 5k. Mesh LODs on vs off in that view: 246k vs 492k primitives.

**Evidence — Compatibility renderer** (same scenario, `RENDERER=gl_compatibility`; before =
the base commit 35255d9 run with the same scenario):

| spawn | draws before → after | primitives before → after | shadow draws | shadow primitives | frame (llvmpipe) |
| --- | --- | --- | --- | --- | --- |
| water | 494 → **318** | 998k → **246k** | 0 → 0 | 399k → 153k | 1120 → 896 ms |
|  load | total 9.1 s → 35.2 s (warm-up 30.0 s) | | | | |
| earth | 703 → **366** | 1055k → **231k** | 0 → 0 | 445k → 142k | 1067 → 881 ms |
|  load | total 12.5 s → 19.6 s (warm-up 11.8 s) | | | | |
| fire | 683 → **301** | 1038k → **188k** | 0 → 0 | 288k → 141k | 1011 → 806 ms |
|  load | total 10.9 s → 18.2 s (warm-up 10.1 s) | | | | |
| air | 483 → **247** | 972k → **169k** | 0 → 0 | 539k → 100k | 1065 → 809 ms |
|  load | total 7.6 s → 13.2 s (warm-up 8.7 s) | | | | |

Primitives are identical to the Mobile renderer (same geometry, culling and LOD selection).
Compatibility reports about twice the draw calls: it draws shadowed geometry again in a light
pass and, on llvmpipe, a depth prepass (phone GPUs — Mali, Adreno, PowerVR, Apple — have the
prepass disabled by default, `rendering/driver/depth_prepass/disable_for_vendors`), so its draw
count is not comparable to the 200 budget; the reduction is what transfers.

Screenshots: `budget_water_before_after.png`, `budget_earth_before_after.png` (before above,
after below; same views).

**Remaining.**
* Margins are thin: water 246k (4k under), earth 196 draws (4 under). The NPC director can put
  up to 10 NPCs in view and weather / combat FX add on top; the budget holds for the spawn
  views measured, not for every corner of every city.
* On phones the mid-distance buildings use the silhouette recipes (e.g. Ba Sing Se's tiered
  halls lose their red columns beyond ~100 m) and ice has no ink line near the camera.
* Shadow pass: 100k-153k primitives remain (LOD0 quadrants cast); not part of the budget.
* Terrain clipmap (81-85 draws) and the per-sub-cell silhouettes (33-48 draws) are the largest
  fixed draw costs; merging silhouettes would break the exact LOD1 → LOD2 hand-over.
* Loading takes 4-5 s longer on llvmpipe because of the warm-up (section 1).

## 3. Settlement LOD fades

**Checked.** `perf_polish_fade_probe`: two overlapping "LOD" blocks (toon + ink outline) handing
over at 60 m with a 10 m margin, `VISIBILITY_RANGE_FADE_DISABLED` (hysteresis) beside
`VISIBILITY_RANGE_FADE_SELF`, camera at 45 / 56 / 60 / 64 / 75 m.

**Found.** The fade-self cross-fade is clean on Forward+ (blended colours, no holes, no sorting
artefacts on the outlined blocks; the blend runs over [end, end + margin]); the hard switch pops.
Both LODs draw inside the band (transparent pass), so it costs draw calls there.

**Fixed.** Desktop presets (`fade_margin` 12 m, `src/world/settlements/common/settlement_settings.gd:72`):
LOD0 → LOD1 (`settlement_provider.gd:97-105`) and LOD1 → silhouette (`settlement_far_provider.gd:56-63`,
same AABB and margin as LOD1, so the two fades meet) cross-fade instead of popping. Phones keep
hard switches (no doubled draws in the band) — their hand-overs sit at 74-97 m / 220 m behind the
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

All minimal and additive; defaults keep the previous behaviour unless noted. Documented in the
owning module's doc.

| File | Change | Module doc |
| --- | --- | --- |
| `src/world/content/world_content.gd` | `night_only` MultiMeshes (hidden by day, `is_night()`, `_update_night()` every 0.5 s), `vis_parent` (HLOD), `fade` and `lod_bias` from the payload, LOD index buffers passed to `add_surface_from_arrays` | worldcontent.md |
| `src/world/content/cell_payload.gd` | stores `fade`, `night_only`, `vis_parent`, `lod_bias` | worldcontent.md |
| `src/world/buildings/nation_palette.gd` | `material(slot, outline = true)`: outline-less twins of solid / ice | settlements.md |
| `src/world/buildings/kit_result.gd` | `add_to_payload` opts `outline`, `flat_slots`, `lods`, `fade`, `vis_parent`, `lod_bias` | settlements.md |
| `src/world/settlements/common/settlement_settings.gd` | phone keys `lod1_kit`, `merge_far`, `lod0_tight`, `quad_lod0`, `mesh_lods`, `far_lod_bias`, `sil_lod_bias`, `flat_ice`; phone `lod1_end` 300 → 220 m; `fade_margin`; `lod0_end_for()` | settlements.md |
| `src/world/settlements/common/settlement_provider.gd` | quadrant HLOD LOD0 on phones (`build_quads`), outline-less LOD1, `MERGED_SLOTS`, desktop cross-fades | settlements.md |
| `src/world/settlements/common/settlement_far_provider.gd` | outline-less, merged on phones, mesh LODs, desktop fades | settlements.md |
| `src/world/settlements/common/kit_merger.gd` | `slot_map` (fold surfaces into one) | settlements.md |
| `src/world/settlements/common/settlement_fx.gd` | glows `night_only`; garden plant ranges per band, capped at 170 m on phones | settlements.md |
| `src/world/vegetation/vegetation_settings.gd`, `forest_far_provider.gd` | `far_density` (0.55 on phones) | worldcontent.md |
| `src/characters/mesh/character_mesh_builder.gd` | `with_lods()`: automatic mesh LODs on every character body | characters.md |
| `assets/shaders/creatures/creature_common.gdshaderinc`, `creature_skin`, `fur_shell`, `membrane`, `creature_eye`, `creature_outline` `.gdshader` | `occlusion_fade` instance uniform (index 3) + Bayer discard | creatures.md |
| `src/player/player_camera.gd` | close-quarters lock framing (`lock_close`, `lock_side`, `close_framing`), `occluders` child | player.md |
| `src/world/game/playable_scene.gd` | warm-up during the loading hold, `load_report.warmup` | worldscene.md |
| `scenes/dev/combat_arena.gd` | `_warm_up()` behind the held fade / cover, params `warmup` / `no_warmup` | bending.md |
| `src/world/water/water_system.gd` | phone ocean disc 64 segments | worldrender.md |
| `tests/unit/test_worldcontent.gd` | robust budget-slicing test (section 5) | worldcontent.md |
| `docs/modules/{settlements,worldcontent,worldrender,characters,creatures,player,worldscene,bending,mobile}.md` | perf_polish notes | — |
