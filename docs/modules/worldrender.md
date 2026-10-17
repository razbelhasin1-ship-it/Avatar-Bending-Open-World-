# World rendering (`worldrender`)

The visual and physical ground of the 8 km world: GPU clipmap terrain, collision streaming,
ocean/lake/canal water, sky with day/night and regional atmosphere, weather, and deformable
snow. One node, `WorldRenderer`, owns all of it.

| | |
| --- | --- |
| Entry point | `src/world/world_renderer.gd` (`WorldRenderer`, Node3D) |
| Terrain | `src/world/terrain/` — `TerrainClipmap`, `ClipmapMeshes`, `HeightBounds`, `TerrainMaterial`, `TerrainNormalBaker`, `TerrainCollision` |
| Water | `src/world/water/` — `WaterSystem`, `WaterWaves`, `BurstPool` |
| Sky | `src/world/sky/` — `SkyController`, `DayNightCycle`, `AtmospherePalettes`, `CloudSea`, `VolcanoSmoke` |
| Weather | `src/world/weather/` — `WeatherSystem`, `WeatherParticles`, `WorldShaderGlobals` |
| Snow | `src/world/snow/snow_trails.gd` (`SnowTrails`) |
| Shaders | `assets/shaders/world/` (terrain, sky, water, cloud sea, precipitation, smoke, snow stamp/refill, bakes) |
| Textures | `assets/textures/world/` (2.6 MB of tiling noise/detail/water/cloud maps; generator `src/world/terrain/texgen/generate_world_textures.py`) |
| Dev scene | `scenes/dev/world_render_test.tscn` (free-fly camera + view presets) |
| Tests | `tests/unit/test_worldrender.gd`; playtests `worldrender_tour`, `worldrender_snow`, `worldrender_terrain_check` |

## Quick start

```gdscript
var world := WorldRenderer.new()
add_child(world)                       # builds terrain, sky, water, weather, snow, collision
world.setup(player, camera)            # focus drives collision/snow/regions, camera drives LOD
await world.wait_until_ready()         # collision under the focus exists (spawn now)
world.set_time_of_day(17.5)
world.set_weather(&"snow", 8.0)
```

`WorldRenderer` owns the scene's **WorldEnvironment, sun and moon**: world scenes must not add
their own. It needs nothing else: without baked world data it renders a flat plane at y = 0.
Run the dev scene: `godot --path . -- --scene=res://scenes/dev/world_render_test.tscn`
(RMB look, WASD/QE fly, Shift fast, 1–9 presets, T +1 h).

## Public API (`WorldRenderer`)

| Method / member | Notes |
| --- | --- |
| `setup(focus: Node3D, camera: Camera3D)` | either may be null (camera → viewport camera, focus → camera) |
| `set_focus(node)` | node driving collision streaming, snow trail window, regional atmosphere/weather |
| `set_time_of_day(h)`, `get_time_of_day()` | hours 0..24; emits `Events.time_of_day_changed` |
| `set_time_scale(hours_per_second)`, `get_time_scale()` | default `1/120` (1 game hour = 2 real minutes); 0 freezes |
| `set_weather(name, transition_s = 10)`, `get_weather()` | `clear cloudy snow blizzard rain ash fog`; locks auto weather; emits `Events.weather_changed` |
| `set_auto_weather(enabled)` | regional weather cycle (on by default) |
| `get_wind() -> Vector2` | x/z wind velocity (m/s) incl. gusts |
| `get_sun()`, `get_moon()`, `get_environment()` | DirectionalLight3Ds / Environment (read; cinematics may override temporarily) |
| `request_collision_around(pos, radius, lifetime_s = 0) -> id` | keep collision near NPC groups/companions/far impacts |
| `move_collision_request(id, pos)`, `release_collision_request(id)` | |
| `is_collision_ready_at(pos) -> bool` | spawns/teleports should wait for it |
| `ensure_collision_now(pos)` | builds the patch under `pos` synchronously (teleport/respawn) |
| `wait_until_ready()` / signal `world_ready_for_play` | collision under the focus ready |
| `splash(pos, strength = 1) -> bool` | ripple ring + foam + spray on the water at `pos` (strength 0.2 pebble … 3 surge); false on land |
| `get_water_surface_height(x, z) -> float` | visible surface incl. ocean swell (-INF = no water); gameplay levels: `WorldData.get_water_height` |
| `get_snow_sink_depth(pos) -> float` | how deep trails pressed the snow (m): lower feet/hooves so they stand in their prints |
| `get_region_weights()`, `get_dominant_region()` | smoothed regional weights at the focus |
| `write_save_state()` | group `&"persist"`: mirrors the clock into `GameState.time_of_day` |
| members `clipmap, collision, water, sky, cycle, weather, precipitation, snow, cloud_sea, volcano_smoke, terrain_material` | subsystems (advanced use, debugging) |

Time persistence: `DayNightCycle` writes `GameState.time_of_day` every frame and the renderer
starts at `GameState.time_of_day`, so save/load keeps the hour with no extra code.

### Hooks for other modules

* **Footprints** — emit `Events.footstep(actor, position, yaw, size, weight, surface)` per foot
  plant (`size` = foot/paw length in m, `weight` 0..1+ where heavy creatures go above 1, `yaw`
  faces -Z at 0, `surface` from `WorldData.get_surface`). Walking vs running spacing comes from
  the emitter; if `actor` is a CharacterBody3D/RigidBody3D its speed > 4 m/s gives longer prints
  with kicked snow. `size >= 0.42` m stamps a paw print (pad + toes), smaller a boot print.
  Depth = `0.035 + 0.09 * weight * sqrt(size / 0.28)` m, capped by `WorldData.get_snow_depth`.
* **Landings** — `Events.landed(actor, position, impact, surface)` with `|impact| >= 3` m/s
  stamps a crater (radius `0.35 + 0.07|v|`, raised lip, scattered chunks) and bursts snow.
  Direct calls: `world.snow.add_footprint(...)`, `world.snow.add_crater(...)`.
* **Bending water** — `world.splash(pos, strength)` for impacts/draws on water surfaces.
* **Wind/weather-aware shaders** — global uniforms below (vegetation sway, cloth, particles).

## Global shader uniforms

Registered at runtime by `WorldShaderGlobals.ensure()` (the renderer calls it in `_init`). A
material created *before* any WorldRenderer exists must call `WorldShaderGlobals.ensure()`
first, otherwise its shader fails with "global uniform does not exist". Declare with
`global uniform <type> <name>;`.

| Name | Type | Meaning |
| --- | --- | --- |
| `wind_direction` | vec2 | normalised x/z direction the wind blows towards |
| `wind_strength` | float | mean wind speed m/s (clear 3, cloudy 6, rain 7, blizzard 17) |
| `wind_gust` | float | 0..1 current gust; multiply sway amplitude by `1 + wind_gust` |
| `wind_time` | float | monotonic sway phase that speeds up with wind — use `sin(wind_time * f + dot(xz, k))` instead of `TIME` |
| `world_wetness` | float | 0..1 rain wetness (darken + gloss) |
| `world_snow_cover` | float | 0..1 fresh snow while snowing (whiten up-facing surfaces) |
| `world_sun_direction` | vec3 | unit vector towards the sun |
| `world_sun_color` | vec4 | linear sun colour × intensity (0 at night) |
| `world_moon_direction` | vec3 | unit vector towards the moon |
| `world_sky_zenith`, `world_sky_horizon`, `world_fog_color` | vec4 | current linear sky/fog colours (cheap fake reflections, unshaded effects) |
| `world_time_of_day` | float | hours 0..24 |
| `world_time` | float | seconds of unpaused world time (animation clock of water/clouds) |

## Terrain

### Geometry clipmap (`TerrainClipmap`, `ClipmapMeshes`)

After M. Savage's geometry clipmaps. Level *l* has spacing `s = s0 · 2^l` and spans
`(4T+1)` cells around an origin snapped to its grid (`floor((cam − 1)/s)·s + 1`, so x/z of every
vertex is `1 + k·s`: odd metres = heightmap texel centres). Pieces per level: 12 (16 at level 0)
`T×T` tiles, a filler cross, an L-shaped **trim** filling the one-cell snap gap to the next level
(4 prebuilt variants, chosen by parity) and a **seam** of degenerate (even, odd, even) triangles
along the next level's hole that closes T-junction cracks. Every piece is its own
RenderingServer instance with a tight AABB from `HeightBounds` (min/max pyramid of 64 m blocks,
built on a worker in ~1 s), so frustum and shadow culling work per piece; pieces entirely
outside the baked square are hidden (the ocean covers them).

| Settings.detail_level() | 0 (mobile/low) | 1 | 2 (high) | 3 (ultra) |
| --- | --- | --- | --- | --- |
| tile T (cells) | 16 | 20 | 22 | 32 |
| innermost spacing | 0.25 m | 0.25 m | 0.25 m | 0.125 m |

Level count follows `Settings.view_distance_m()` (`levels_for(T, s0, view)`; high = 10 levels,
reach ≈ 5.6 km). Rebuilt on `Events.graphics_settings_changed` when these change.

**Heights** use `world_height()` from `src/world/data/world_height.gdshaderinc` — bit-identical
to `WorldData.get_height` (checked on the GPU by `worldrender_terrain_check`: 4096 probes,
worst 1.9 mm = encoding precision). Levels with spacing ≥ 2 m fetch the single texel (the
bilinear formula returns it exactly there).

**Geomorphing**: odd vertices blend to the midpoint of their coarse edge (or of the
(0,0)–(2,2) diagonal for cell centres; all quads share that diagonal) by
`m = clamp((cheb_dist/s − (T+1+0.3(T−1))) / (2T−0.5 − …))`, measured from the uniform
`clip_center` (also used for snapping, and identical in shadow passes). m = 1 on every seam
vertex, so the fine ring degenerates exactly into the coarse one; `TerrainClipmap.vertex_height()`
mirrors this on the CPU and the unit test checks ring boundaries for cracks.

### Shading (`terrain.gdshader`)

Painterly layering, all in world space:
soil → lush (grass / forest floor / farmland / tundra moss by 4-tap biome weights) → sand
(beach vs black sand/ash) → rock (splat rock ∪ slope from a ~16 m blurred normal; triplanar
pattern on cliffs, downhill streaks at mid distance) → roads (dirt vs paved flags from
`ground.r`) → settlement/temple paving → glacier ice → **snow** (crisp `smoothstep(0.16, 0.40)`
layer, settles in rock crevices first, thins on steep faces, `world_snow_cover` adds fresh snow)
→ wetness. Colours come from per-region palettes (Water Tribe blue-grey, Earth Kingdom
green-gold/ochre, Fire Nation basalt + jungle, Air Temple warm grey + alpine green) blended by
4-tap region weights. Anti-tiling: three world-space macro noise scales, two-scale rotated
pattern sampling, detail faded beyond `detail_distance` (70–220 m by detail level). Normals:
GPU-baked normal map (central differences, RG8 4096² high / 2048² low, mip-biased with
distance so far slopes read smooth) plus detail normals near the camera. Custom `light()`:
soft painterly terminator, tight specular for ice/wet ground, tiny view-dependent snow glints.
Atmospheric perspective comes from the Environment's exponential fog with aerial perspective
(samples the sky radiance, so terrain haze matches the sky).

`TerrainNormalBaker` renders the normal map once (canvas pass over the RG8 heightmap), reads it
back, converts/mipmaps on a worker (~3–9 s on llvmpipe, instant on GPUs). Until then (and in
headless runs) the shader differences the heightmap per pixel — same result, more fetches.

## Collision streaming (`TerrainCollision`)

* 64 m × 64 m `HeightMapShape3D` patches at **1 m** spacing (65² samples, neighbours share
  edges) on `Layers.WORLD`, one StaticBody3D each, keyed by
  `floor((x − (−4095)) / 64)`.
* Samples are the exact `WorldData.get_height` values (texel values + exact bilinear midpoints),
  so collision equals WorldData at every 1 m sample; between samples the physics triangles
  deviate from the bilinear surface by ≤ 1/16 of the local cell twist (p99 ≈ 2.5 cm on walkable
  ground; worst 0.3–3.5 cm over 200 random rays around Ba Sing Se across runs).
* Heights are computed on `WorkerThreadPool` tasks (≤ 3 in flight, nearest first); the main
  thread only creates shapes, ≤ 2 per frame (no hitches).
* Kept within `focus_radius` (150 m) of the focus plus any requests; released with a 64 m
  hysteresis margin.
* The patch under the focus is built synchronously if missing; `is_collision_ready_at()` is true
  one physics frame after a patch entered the space.
* Safety net: a CharacterBody3D/RigidBody3D focus found 1.5 m below the terrain with nothing
  solid under it (caves are fine) is put back on the ground (`body_rescued` signal).

## Water (`WaterSystem`, `water.gdshader`)

* **Ocean**: one radial disc mesh (1.2 m rings near the centre growing ×1.075 to 30 km, 96
  segments, ~21k triangles, one draw call; 64 segments / ~15k on phones — `detail_level() == 0`,
  perf_polish) following the camera. Vertex: 4 Gerstner waves along
  the wind (`water_common.gdshaderinc`), faded with distance and in the shallows. Fragment:
  water column from the heightmap (and the scene depth for objects standing in water), depth
  colour, refraction of the bed, fresnel reflection of the current sky colours, sharp sun
  glints, subsurface glow on crests, shoreline foam bands that run up the beach, whitecaps in
  rough weather, soft intersection edges. Regional colours (arctic dark teal, tropical
  turquoise, …) blend with the region weights; wave height follows the weather.
* **Lakes** (unfrozen) and **canals** (Water Tribe ring canal + spurs, levels 0 / 14.2 m) are
  flat meshes from `WorldData.get_lakes()/get_canals()`; canal vertices carry their flow
  direction. Frozen lakes are terrain (ice).
* **Splash**: 16-slot ring buffer of ripples (x, z, start time, strength) uploaded as a uniform
  array → expanding rings + foam in both materials, and a pooled spray burst (`BurstPool`).
* `get_water_surface_height` mirrors the swell on the CPU (`WaterWaves`).
* Compatibility renderer: refraction and scene-depth edges are disabled (the heightmap column
  gives the same colour and foam).

## Sky, day/night and atmosphere

* `DayNightCycle`: sun rises due east (+X) at 06:00, culminates due south (+Z) at a region-
  blended peak elevation (Water Tribe 32°, Earth Kingdom 58°, Fire Nation 66°, Air Temple 55°),
  sets west at 18:00; the moon runs opposite (1.5 h behind) with an 8-day phase cycle.
  `Events.time_of_day_changed` fires every 0.25 game hours and on every explicit set.
* `AtmospherePalettes`: per region four keyframes (night, twilight, golden, day) of zenith,
  horizon, ground, sun colour/energy, glow, ambient, fog colour/density, cloud lit/shade
  colours, coverage, haze, exposure, saturation, moon energy, stars, aurora — piecewise blended
  by sun elevation, then mixed by region weights sampled on a 380 m ring around the focus and
  eased over a few seconds (no hard borders when travelling).
* `SkyController` applies palette + weather to: the custom sky shader (gradient, sunset glow,
  sun disc + halo, phased cratered moon, rotating twinkling star field + milky band, Water Tribe
  aurora curtains, painterly cumulus with stepped self-shadowing + cirrus, horizon haze), sun and
  moon lights (only one casts shadows; swapped at dusk/dawn), ambient (sky + palette colour),
  exponential fog + aerial perspective, height fog, volumetric fog density (when enabled),
  exposure, saturation, glow. Sky radiance updates incrementally (64/128 px).
* `CloudSea`: ray-marched slab of cloud between 545 and 625 m around the Southern Air Temple
  (terraces 762–822 m and peaks stand above it), thinning where terrain rises into it.
* `VolcanoSmoke`: lit smoke plume with a lava-glow base over the active Fire Nation volcano
  (`fn_burning_maw`), bent by the wind.

## Weather (`WeatherSystem`, `WeatherParticles`)

States and their main effects (all parameters blend smoothly during transitions):

| State | Sky / light | Fog | Particles | Other |
| --- | --- | --- | --- | --- |
| clear | coverage 0.25 | palette | — | wind 3 m/s |
| cloudy | coverage 0.72, sun ×0.55 | ×1.35 | — | wind 6 |
| snow | overcast, sun ×0.42 | ×3, floor 0.0028, sky 55 % | snow | trail refill ×3.5, snow cover 0.65 |
| blizzard | dark overcast, sun ×0.22 | floor 0.02 (white-out), sky 97 % | blizzard streaks + snow | wind 17, gusts, refill ×9, big waves |
| rain | dark overcast | ×2.4 | rain streaks | wetness 1, wind 7 |
| ash | brown overcast | ×3.2, warm tint | ash flakes + glowing embers | |
| fog | — | floor 0.011 + valley height fog | — | calm |

Auto mode draws the next state from the dominant region's table after 4–12 real minutes:
Water Tribe {clear, cloudy, snow, blizzard, fog}, Earth Kingdom {clear, cloudy, rain, fog},
Fire Nation {clear, cloudy, rain, ash}, Air Temple {clear, cloudy, fog, snow}, wilds/ocean
mixes. A state the region does not allow is replaced within ~30 s (flying from a blizzard to
the Fire Nation clears it). Wind veers slowly with smooth layered gusts and drives the global
uniforms.

Precipitation: one GPUParticles3D per kind with a custom particle shader that keeps particles in
a box wrapped around the camera (never runs out, never piles up), drifts them with the wind,
hides them below the terrain and fades them at the box faces; streaks are stretched along
velocity in the draw shader and lit by the sky colours. Counts (snow 7k, blizzard 14k, rain 9k,
ash 3.6k) × `Settings.effects_scale()`; intensity via `amount_ratio`.

## Snow deformation (`SnowTrails`)

* **Trail map**: RGBA8 SubViewport render target, toroidally addressed (`uv = xz / size`,
  repeat), 3.2 cm texels; 512² (detail 0), 1024² (1–2, 32.8 m window) or 2048² (3). Channels:
  **R** compression depth / 0.5 m, **G** raised rim (× 8 cm), **B** loose scatter chunks (× 3.5 cm).
  The window recentres on the focus when it moved 1/8 of its size; only the strips that
  scrolled in are cleared.
* **Stamping**: each print is a rotated canvas rect drawn with `snow_stamp.gdshader` (boot = fore
  + heel + waist SDF with tread and deeper heel/toe; paw = pad + 4 toes + claws; crater =
  irregular bowl + lip + chunk ring). The item copies its rect to the back buffer first and the
  shader max-blends (`depth = max(old, new)`, a fresh print presses older rims flat). Items are
  only submitted on frames with work (`UPDATE_ONCE`), ≤ 48 stamps per frame.
* **Persistence**: every stamp also lives in a CPU ring buffer (4096). Prints are redrawn when
  the window scrolls back over them, `get_sink_depth()` answers from it, and refill is a single
  clock: remaining depth = `depth0 − (clock − clock0)`. The GPU applies the same refill as
  `max(old − n/255, 0)` passes every 0.5 s. Base refill: full 0.5 m in 240 s; weather multiplies
  it (snow ×3.5, blizzard ×9).
* **Terrain**: the vertex shader displaces only where the snow layer is present, low-pass
  filtered to the mesh spacing (no faceting); the fragment uses a 1.5-texel gradient of the full
  map for the print walls, tints compressed snow darker blue, brightens rims and draws chunks.
* **Puffs**: pooled one-shot snow bursts (`BurstPool`, 10 emitters) on steps (kicked forward when
  running) and landings near the camera.
* Collision stays on the undisturbed snow surface; animation lowers feet by
  `get_snow_sink_depth()` to stand in the print.

## Settings integration

| Setting | Effect |
| --- | --- |
| `view_distance_m()` | clipmap levels (reach) |
| `detail_level()` | clipmap tile size/spacing, terrain detail distance, normal map 2048/4096, snow trail resolution, sky radiance size, water wave fade distance |
| `effects_scale()` | precipitation counts, spray/puff bursts, smoke puffs |
| `configure_environment()` | SSAO/SSIL/SDFGI/glow/volumetric toggles on the owned Environment |
| `configure_sun()` | shadow enable/distance/splits on sun and moon |
| `Events.graphics_settings_changed` | all of the above re-applied (snow trail resolution applies on the next scene load) |

## Performance (llvmpipe software Vulkan, 960×540, 4 shared CPU cores, "high" preset)

Relative numbers only — software rendering of every pixel on the CPU.

| View | Frame time | Draw calls | Primitives (all passes) |
| --- | --- | --- | --- |
| Air Temple above the cloud sea | 250–290 ms | 37 | 79 k |
| Distant vista (LOD) | 270–350 ms | 35 | 63 k |
| Water Tribe coast | 300–520 ms | 74–77 | 89–107 k |
| Ba Sing Se golden hour | 320–440 ms | 82–101 | 118–346 k |

At 1280×720 the same views take 290–880 ms (volcano sunset 290 ms, vista 380 ms, Water Tribe
500 ms, blizzard 880 ms).
| Blizzard (14k particles) | 440–490 ms | 114 | 268 k |

Same tour per renderer at 960×540: Forward+ 265–880 ms (1280×720), Mobile 170–430 ms,
Compatibility 115–395 ms (Compatibility issues ~1.5–2.5× more draw calls: no depth-prepass
merging, per-light passes).

Breakdown (toggling subsystems, Water Tribe/Ba Sing Se): terrain ≈ 45–55 % (vertex work runs in
the depth prepass, colour pass and shadow cascades), volumetric fog + SSAO (user settings) 15–
25 %, sun shadows 10–20 %, water ≈ 5–10 %, cloud sea/smoke < 5 %. The Compatibility renderer
runs the same views at 120–260 ms. Clipmap at "high": 10 levels, 152 pieces (≈ 40–60 drawn
after culling), 129 k triangles if every piece were visible (tile 22).

## Testing

* `tools/test.sh worldrender` — 15 tests: shader height formula mirror vs CPU, collision heights
  vs WorldData (exact at samples, twist bound elsewhere), clipmap mesh structure/winding, level
  snapping and reach, crack-free ring boundaries, height bounds conservative, collision
  streaming readiness/requests/unloading/budget, fall-through safety net, day/night clock + sun
  path + persistence + events, palettes, weather transitions/events/region rules, snow stamping
  depth/refill/events, wave mirror, full WorldRenderer API integration.
* `tools/playtest.sh worldrender_tour [out] [WxH]` — every nation (Water Tribe day/blizzard/
  night, Ba Sing Se golden hour, Fire Nation caldera + volcano, Air Temple cloud sea, shoreline,
  vista, canal, splash) with frame time/draw calls per view. `--views=a,b` limits it.
* `tools/playtest.sh worldrender_snow` — synthetic walker: walking/running prints, landing
  crater, heavy creature paws, close-ups at ~3 m, refill during snowfall.
* `tools/playtest.sh worldrender_terrain_check` — GPU height readback vs CPU, collision rays,
  LOD vista + wireframe.
* `RENDERER=gl_compatibility tools/playtest.sh worldrender_tour` and `RENDERER=mobile ...` —
  the full tour passes on all three renderers.

Shader rule followed everywhere: no implicit-derivative `texture()` inside per-pixel branches
or loops (explicit `textureGrad`/`textureLod` instead). The original cloud-sea march broke this
and crashed llvmpipe's Mobile-renderer JIT; the fixed-trip, explicit-LOD version runs on all
renderers.

## Design decisions

* **Clipmap over chunked LOD**: constant vertex budget, no CPU mesh generation, exact heights
  from the shared texture; per-piece instances keep culling granular.
* **Exact heights everywhere**: visuals, collision samples and `WorldData` use one formula; the
  only deviation is physics triangulation between 1 m samples (cm-level). 1 m collision costs
  4× the samples of 2 m but cuts the visual/physics mismatch 4× (p99 11 → 2.5 cm).
* **Trail map as a cache of a CPU stamp list**: unlimited persistence beyond the window,
  consistent refill, cheap sink queries; GPU work only on frames with new prints.
* **Max-blend via back-buffer copies** (canvas items) instead of compute: works on all three
  renderers including Compatibility/WebGL.
* **Palette keyframes per region**: art-directable, testable data; regions blend smoothly.
* **Custom precipitation particle shader** (wrapped box) instead of emitters following the
  camera: stable density at any speed, terrain-aware, one draw call per kind.

## Known limitations

* No terrain holes yet (cave entrances on cliff faces must be built as geometry in front of the
  terrain; tunnels below the surface are fine and the safety net ignores bodies with ground
  under them).
* Precipitation is not occluded by roofs/overhangs (only by the terrain).
* City tier steps are vertical in the 2 m heightmap and look stair-stepped until the settlement
  builders cover them with retaining walls.
* Waterfalls (`WorldData.get_waterfalls()`) are not rendered yet.
* The snow trail resolution is chosen when the node enters the tree.

## Wave 4 (bughunt_world, docs/qa/bughunt_world.md)

* `WaterSystem.build_inland_water` builds the lake meshes from `WorldRecords.lake_surface_polygon`,
  the same outline `WorldData.get_water_height` now tests (gameplay water = drawn water; before, a
  lake's bounding circle made dry ground beside lakes and below falls pools "deep water").
