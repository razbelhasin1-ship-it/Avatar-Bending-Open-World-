# World data (`worlddata`)

One connected **8192 × 8192 m** world centred on the origin, baked offline by a Python
generator and served at runtime by the `WorldData` autoload.

| | |
| --- | --- |
| Generator | `tools/worldgen/generate_world.py` (+ `tools/worldgen/wg/*`) |
| Baked data | `assets/world/` (≈ 26 MB) |
| Runtime | `src/autoload/world_data.gd` (autoload `WorldData`), helpers in `src/world/data/` |
| Shader include | `src/world/data/world_height.gdshaderinc` |
| Dev scene | `scenes/dev/world_overview.tscn` (`godot --path . -- --scene=res://scenes/dev/world_overview.tscn`) |
| Tests | `tests/unit/test_worlddata.gd`, playtest `tests/playtest/scenarios/worlddata_overview.gd` |

## Conventions

* x ∈ [-4096, 4096] (east = +X), z ∈ [-4096, 4096] (**north = -Z**), 1 unit = 1 m, sea level y = 0.
* **Bearings** in the data are degrees from north, clockwise: 0 = -Z, 90 = +X, 180 = +Z, -90/270 = -X.
  Direction of bearing `b`: `Vector2(sin(b), -cos(b))` in (x, z).
* **Yaw** (spawns, ports, cave mouths) is a rotation about +Y applied to a -Z-forward model:
  `Basis(Vector3.UP, yaw)`; `yaw = -deg_to_rad(bearing)`. Yaw 0 faces north.
* Rasters use the **texel-centre** convention: texel `(i, j)` of an `N × N` map covers the world
  square cell whose centre is `x = -4096 + (i + 0.5) * 8192 / N`, `z = -4096 + (j + 0.5) * 8192 / N`.
  Row `j` grows south (row 0 is the northern edge).

## Geography at a glance

| Nation / place | Where | What is there |
| --- | --- | --- |
| Northern Water Tribe | arctic north (z < -2300) | city ringing a circular bay at (-300, -2620): harbour tier (2.5 m), middle (16 m), upper (32 m), palace tier (54 m) on the northern apex; canals + canal falls; sea wall with a gate across the bay mouth; spirit oasis; polar peaks to ~650-700 m; glaciers, ice shelves, crevasse field, frozen lakes |
| Frozen Strait | x 700–1700, z -2500…-1690 | walkable pack-ice land bridge (region `wilds`), Strait Wardens' camp |
| Earth Kingdom | central/east continent | **Ba Sing Se** (2000, 200): outer wall r 700, inner wall r 380, Lower/Middle/Upper Ring, palace (91 m); farmland west of the walls; **Omashu** (380, -420) crowning a mountain inside a chasm, great bridge + rock causeway; Full Moon Bay port (-300, 1700); Northreach harbour; Millet Hollow (farming) and Cedar Rest (forest) villages; mesas + canyons SW; NE range to 800 m; tundra in the north; lakes |
| Fire Nation | SW archipelago | capital in a caldera (-2600, 2600): floor tiers 112–146 m, rim 255–320 m, the *Dragon's Throat* gorge to **Crimson Harbor** (cove at (-1690, 2010)); active volcano island (-1650, 3480); Sunflare resort isle (-3400, 1240); lava fields, ash plains, black-sand beaches, jungle |
| Southern Air Temple | SE peaks | temple on a spire at (2500, 3350): terraces 762/782/802/822 m with open cliff edges, two pinnacles with suspended bridges, the switchback **Pass of a Thousand Steps** from (2050, 2480); peaks to ~1050 m; waterfalls; arch |
| Open sea | elsewhere | small islands (Lantern Isle, Serpent's Watch, Misty Crag, Turtle-crab Atoll, Frostfang, Whalefall) and four ferry routes |

## Runtime API (`WorldData`)

Loading is lazy: the first query (or `load_world()`) loads everything on worker threads and
blocks until done (~0.4 s cold, measured by the unit test; budget 2 s). `load_world_async()`
starts the same work without blocking (call it from the main menu); `Events.world_ready` fires
when it finishes. Without data files (or with `use_flat_world(true)`) every query answers like a
flat grass plane at y = 0, and `height_override` still replaces terrain height for test arenas.

### Terrain

| Method | Notes |
| --- | --- |
| `get_height(x, z) -> float` | bilinear on the 2 m heightmap, formula below |
| `get_normal(x, z) -> Vector3` | central differences one texel apart (same as the shader include) |
| `get_slope_deg(x, z) -> float` | |
| `get_height_block(ox, oz, count_x, count_z, step) -> PackedFloat32Array` | row-major `[j * count_x + i]` = `get_height(ox + i*step, oz + j*step)`; texel-aligned grids (origin on a texel centre, step multiple of 2 m) skip interpolation |
| `fill_height_map_shape(shape, texel_x, texel_z, w, d) -> bool` | native path for collision: fills a `HeightMapShape3D` with texels (2 m spacing); place its `CollisionShape3D` at `texel_block_center(...)` and scale x/z by 2 |
| `texel_block_center(texel_x, texel_z, w, d) -> Vector2` | world x/z centre of that texel block |
| `raycast_terrain(origin, dir, max_dist) -> {hit, position, distance}` | marches the heightfield (no physics needed) |
| `get_bounds() -> Rect2` | |

### Biomes, surfaces, regions

| Method | Notes |
| --- | --- |
| `get_biome(x, z) -> int` | `WorldData.Biome` (OCEAN, BEACH, SNOW, ICE, TUNDRA, GRASSLAND, FOREST, FARMLAND, ROCK, MOUNTAIN, VOLCANIC, ASH, TEMPLE, CITY) |
| `get_surface(pos) -> StringName` | `&"snow" &"ice" &"stone" &"grass" &"dirt" &"sand" &"water" &"ash"`; water when `pos` is at/below a water surface, roads → stone (paved) / dirt, splat refines snow/stone at biome borders |
| `get_snow_depth(x, z) -> float` | metres of loose snow (deeper at altitude, thin on ice/city streets of the Water Tribe) |
| `get_splat(x, z) -> Color` | (snow, rock, lush, sand_ash) weights |
| `get_road(x, z) -> float` | road coverage 0..1 |
| `get_ground_hints(x, z) -> Color` | (paved road, settlement paving, farmland, wetness) |
| `get_region(x, z) -> StringName` | `&"water_tribe" &"earth_kingdom" &"fire_nation" &"air_temple" &"wilds" &"ocean"`; coastal water within 260 m of a nation belongs to it |
| `get_region_name(id) -> String` | display name |

### Water

| Method | Notes |
| --- | --- |
| `get_water_height(x, z) -> float` | canal level, unfrozen lake level, or sea level (0) where the terrain is below it; `-INF` otherwise. Frozen lakes are solid ice (no water) |
| `is_underwater(pos) -> bool` | |
| `find_water_source(pos, radius) -> {found, position, kind, distance}` | registered sources first, then canals, lakes (frozen → `&"ice"`), the sea (ring scan), then snow/ice ground at `pos` |
| `register_water_source(pos, radius, kind) -> int` / `clear_water_sources()` | fountains etc. added by settlement builders |

### Places

| Method | Returns |
| --- | --- |
| `get_pois()`, `get_poi(id)` | POI dictionaries (see below) |
| `get_nearest_poi(pos, type = &"", max_distance = INF)` | nearest POI or `{}` |
| `get_pois_in_radius(pos, radius, type = &"")` | closest first |
| `get_pois_in_region(region_id)` | |
| `get_cities()`, `get_city(id)` | cities/towns with full layout (also villages by id) |
| `get_villages()`, `get_roads()`, `get_ports()`, `get_ferries()` | |
| `get_lakes()`, `get_canals()`, `get_waterfalls()`, `get_bridges()`, `get_arches()` | |
| `get_spawn(element) -> Transform3D` | origin on the ground of the element's home city, basis faces the view |
| `get_arrival_camera(element) -> {start, end: Transform3D, duration, fov_start, fov_end}` | cameras look down -Z; fly from high behind the city down to over the player's shoulder |
| `get_safe_ground(pos) -> Vector3` | nearest dry, walkable (< 32°) point (spiral search up to 256 m, then nearest port quay) |

### Textures (for terrain, water, vegetation, map UI)

| Method | Format |
| --- | --- |
| `get_height_texture()` | 4096² **RG8** raw height code (R = low byte, G = high byte). Read only through `world_height.gdshaderinc` (texelFetch) |
| `get_height_lod_texture(size = 1024)` | RF, mipmapped, normalised: `h = v * (HEIGHT_MAX - HEIGHT_MIN) + HEIGHT_MIN` (far terrain / minimaps) |
| `get_height_image()` | the 4096² `FORMAT_R16` image (shared memory, read-only) |
| `get_splat_texture()` | 2048² RGBA8 splat, mipmapped |
| `get_biome_texture()`, `get_region_texture()` | L8 ids, read with texelFetch |
| `get_road_texture()` | 4096² L8 coverage, mipmapped |
| `get_ground_texture()` | 2048² RGBA8 hints, mipmapped |
| `get_map_texture()` | 2048² painterly parchment map, mipmapped, no text |
| `apply_height_uniforms(material)` | binds `world_height_map` for the include |
| `world_to_map_uv(pos) -> Vector2`, `map_uv_to_world(uv) -> Vector3` | uv (0,0) = north-west corner; valid for every world-covering texture |

## Height sampling (CPU ⇄ GPU contract)

```
height(i, j) = raw_u16(i, j) * 0.03125 - 256.0            # exact in float32 and float64
u  = clamp((x + 4096) / 2 - 0.5, 0, 4095),  v likewise for z
i0 = floor(u), j0 = floor(v), i1 = min(i0 + 1, 4095), j1 = min(j0 + 1, 4095)
fx = u - i0,  fz = v - j0
a  = h00 + (h10 - h00) * fx
b  = h01 + (h11 - h01) * fx
height = a + (b - a) * fz
```

`WorldHeightfield.sample()` and `world_height()` in the include implement exactly this, in this
order. At texel centres (odd metre coordinates) both return the stored value bit-for-bit (the
unit test checks 400 random texels); between texels the only difference is float32 vs float64
rounding of the position (< 1 mm). For pixel-exact CPU/GPU agreement place mesh vertices on
texel centres, as the overview's detail patches do (`WorldPreviewBuilder.build_patch`). Never
sample the RG8 texture with filtering — the include uses `texelFetch` and reassembles the uint16.

```glsl
shader_type spatial;
#include "res://src/world/data/world_height.gdshaderinc"
void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y = world_height(wp.xz) - MODEL_MATRIX[3].y;
}
```
The include also provides `world_height_texel(ivec2)`, `world_normal(xz)` and `world_uv(xz)`.

Collision patches: `get_height_block()` (GDScript loop, ~1 µs/sample) or the native
`fill_height_map_shape()` (`Image.get_region` → `convert(RF)` →
`update_map_data_from_image(img, HEIGHT_MIN, HEIGHT_MAX)`; heights within 1e-4 m).

## Files in `assets/world/`

All data files carry `importer="keep"` `.import` files, so Godot ships the exact bytes and never
re-encodes them (exported as-is; PNG/JPG are decoded at runtime with `Image.load_*_from_buffer`).

| File | Content |
| --- | --- |
| `heightmap.r16.zlib` | 4096² uint16 LE, rows north→south. zlib (RFC 1950) stream: `PackedByteArray.decompress(33554432, FileAccess.COMPRESSION_DEFLATE)` (verified: `COMPRESSION_DEFLATE` expects zlib-wrapped data, `COMPRESSION_GZIP` gzip). `height = raw * 1/32 - 256` → range -256 … 1791.97 m, 3.1 cm steps |
| `splat.png` | 2048² RGBA: **R** snow/ice cover, **G** rock/cliff, **B** lush grass/forest floor, **A** sand (beaches) / ash & black sand (Fire Nation, volcanic). Remainder `1 - sum` = bare soil / dry grass. Weights sum ≤ 1 |
| `biome.png` | 2048² L8 `WorldData.Biome` |
| `region.png` | 1024² L8 index into `REGION_IDS` = [ocean, water_tribe, earth_kingdom, fire_nation, air_temple, wilds] |
| `roads.png` | 4096² L8 road coverage (anti-aliased) |
| `ground.png` | 2048² RGBA: **R** paved road (stone) vs dirt inside road coverage, **G** settlement paving, **B** farmland, **A** wetness (flow accumulation + lake proximity) |
| `map.jpg` | 2048² parchment map: shaded relief, watercolour biome tints, ink coastline + chart ripples, contours, dashed roads and ferry lanes, city footprints, compass rose. **No text** — the UI draws labels at `world_to_map_uv(poi.position)` |
| `world.json` | everything else (schema below) |

## `world.json` schema

Top level: `version, seed, generator, world{size,min,max,sea_level,north}, heightmap{...},
maps{...}, biomes[], regions[{index,id,name}], cities[], villages[], roads[], ports[], ferries[],
lakes[], canals[], waterfalls[], bridges[], arches[], pois[], spawns{}, arrival_cameras{}`.
At runtime vectors are converted: `[x,y,z]` → `Vector3`, `[x,z]` → `Vector2` (for position-like
keys), point lists → `PackedVector3Array`/`PackedVector2Array`, ids/types/kinds/regions → `StringName`.

### Cities (ring layouts)

Every city is described as rings around `ring_center` — the generator flattens the terrain with
exactly these numbers, so settlement builders can rebuild retaining walls, stairs and gates
where the terrain steps.

```
{id, name, region, kind: capital|city|town|temple, center: [x,y,z], radius, layout: "rings",
 ring_center: [x,z],
 tiers: [{id, name, r_inner, r_outer, height, arc: [b0,b1] | null}],   # arc = bearing range
 ramps: [{bearing, width, length}],      # radial ramps crossing every tier step at that bearing
 gates: [{id, bearing, position: [x,y,z], width, ...}],
 palace: {position, radius, height}, ...}
```
Between two adjacent tiers the terrain is a vertical step (retaining wall) except inside a ramp,
where it rises linearly over `length` metres centred on the boundary.

* **northern_water_tribe** — `harbor{center,radius:300,floor:-10,water_level:0}` (the bay is the
  harbour), `sea_wall{points[[x,z]], height:42, thickness:24, base:-7, gate{center,width}}`
  (a shallow sill is raised under it), `canals` (ids), `canal_falls[{position,top,bottom,bearing,width}]`
  where middle-tier canals (level 14.2) spill into harbour canals (level 0), `spirit_oasis{position,
  radius, pond_radius, pond_level}`, palace platform.
* **ba_sing_se** — `base_height`, `districts` (= tiers: palace 91, upper_ring 86, middle_ring 67,
  lower_ring 60, agrarian 58), `walls[{id, radius, height, thickness}]` (outer 700, inner 380, middle
  262, upper 150), `gates[{id, bearing, position (on the outer wall), inner_gate, outside}]`,
  `avenues[{gate, points[[x,y,z]], width}]`. The agrarian ring is farmland (gentle ±1 m undulation).
* **omashu** — tiers (gate 160 → palace 222), `chasm{r_inner, r_outer, floor}`, `rim{r_inner, r_outer,
  height}`, gates `bridge` (east, needs the `omashu_great_bridge` structure) and `causeway` (a natural
  rock causeway — always walkable), `causeway{a,b,width}`.
* **fire_nation_capital** — tiers on the caldera floor (112 → 146), `caldera{floor_radius, rim_radius,
  rim_height_min/max}`, `gorge{name, bearing, width, inner, outer}` (the Dragon's Throat road).
* **fire_harbor** — tiers around the cove (3/16/32/52 m), `harbor{...}`, gates `gate` (gorge road),
  `north`, `south`.
* **southern_air_temple** — tiers 762–822 with arcs (landing and prayer terraces open to the sky),
  `pinnacles[{id, position, radius}]`, `bridges` (ids).

### Other records

* **villages** `{id, name, region, kind, center, radius, pad_height, terraces?[{radius,height}]}` —
  kinds: port_town, farming_village, forest_village, fishing_village, tea_village, resort, dock, camp.
* **roads** `{id, name, kind: main|minor, width, surface: stone|dirt, points[[x,y,z]], length, grade?}` —
  points every few metres (simplified), heights are the flattened road surface. The air pass is a
  separate constant-grade road `air_pass_switchbacks`.
* **ports** `{id, name, region, settlement, quay[x,y,z] (dry land), berth[x,0,z] (≥3 m water), yaw (faces the berth)}`.
* **ferries** `{id, from, to (port ids), points[[x,z]] (over water), length, duration (s at 9 m/s)}`.
* **lakes** `{id, name, center[x,level,z], radius (bounding), level, frozen, polygon[[x,z]]}` — includes
  waterfall plunge pools and the spirit pond.
* **canals** `{id, points[[x,z]], width, level, bed, tier}`.
* **waterfalls** `{id, name, frozen, top[x,y,z], bottom[x,y,z], height, width, pool}` — placed on real
  cliffs found in the terrain; the lip is notched and a plunge pool carved.
* **bridges** `{id, name, kind: stone|suspended, a, b, width, deck_height? sag?}` — structures for the
  settlement builders (the terrain does not contain them).
* **arches** `{id, name, a, b, width, apex_height}` — natural rock arches to be built as meshes.
* **pois** `{id, name, type, position (on the ground), region, radius, description, yaw?,
  underground?, entrance?, tunnel?[[x,y,z]]}` — types: shrine, ruin, cave, training_ground, landmark,
  vista, spirit_spot, camp, resource, waterfall, dock, village, bridge. Caves face out of their cliff
  (`yaw`) and carry a descending tunnel path below the terrain.
* **spawns** `{water|earth|fire|air: {position, yaw, bearing}}`.
* **arrival_cameras** `{element: {start{position, look_at}, end{position, look_at}, duration, fov_start, fov_end}}`.

## Generator

```
python3 tools/worldgen/generate_world.py [--seed 1337] [--quick] [--out assets/world]
```
Deterministic per seed (seeded numpy RNG, integer-hash noise, sequential `bincount` accumulation).
Full run ≈ 3.5 min on this container (numpy, scipy, pillow only); `--quick` uses ¼ of the erosion
droplets. Preview PNGs go to `tools/worldgen/preview/` (git-ignored): base, eroded, final relief,
biomes, regions, splat, map.

Pipeline (`wg/` modules):
1. **layout** — hand-authored geography: landmass polygons, bays, mountain-range spines, named peaks,
   ice shelves, glaciers, crevasse fields, plateaus/canyons, city ring layouts, villages, lakes,
   road waypoints, ports, ferries. **pois** — POI catalogue, waterfall hints, arches.
2. **terrain** (1024², 8 m) — landmass signed distance + multi-scale warped coast noise (damped where
   harbours need precision), coast profiles (beach vs cliff), shelves and sea floor; ridged-multifractal
   ranges along spines, rounded summits, region-specific hills, terraced mesas with canyons, Omashu's
   mountain, the caldera (radial gullies, rim, gorge), volcano island, Air spire + pass face, arctic
   ice shelves / U-shaped glaciers / crevasses, pack-ice strait.
3. **erosion** — 700 k vectorised droplets (Beyer 2015 model, per-step cell-change cap to avoid
   parallel-droplet pits) + thermal talus relaxation; summits re-raised to their authored heights;
   high ground unsharp-masked.
4. Bicubic upsample to 4096² + slope-dependent rock detail.
5. **cities / temple / features** — ring-tier flattening with radial ramps (EDT-blended into the
   terrain), bays, canals, sea-wall sill, spirit pond, pinnacles, villages, natural lakes (irregular
   outline, bowl bed, eased banks), waterfalls on real cliffs.
6. **routes** — roads path-found with Dijkstra on an 8 m grid (grade, roughness, city and water costs,
   reuse bonus), smoothed, grade-limited to ~15 % and flattened into the terrain (cut/fill benches);
   ferries routed over water away from coasts.
7. **classify** — regions (with 260 m coastal waters), biomes, splat (+ regional snowlines), ground hints.
8. **export** + **mapart**.

To change the world, edit `wg/layout.py` / `wg/pois.py` and re-run; the runtime and tests need no
changes as long as the formats stay the same.

## Design decisions

* **RG8 raw height texture + include, not RF.** Exact on every renderer (Forward+ and Compatibility),
  half the memory of RF, and no float conversion pass in GDScript at load. A filtered RF LOD texture is
  available separately for far terrain.
* **Ring layouts as the city contract.** Concentric tiers with bearing arcs and radial ramps describe
  Ba Sing Se, the Water Tribe amphitheatre, Omashu, the caldera capital, the harbour and the temple
  with a handful of numbers that both the generator and the builders evaluate identically.
* **Frozen lakes are solid.** They are terrain flattened to the ice surface (biome ICE), so walking on
  them needs no extra collision; waterbenders still get `&"ice"` from `find_water_source`.
* **Data maps use `importer="keep"`.** Godot's texture importer would recompress/premultiply/
  fix-alpha-border the data. Keeping the PNGs raw guarantees exact ids/weights at runtime.
* **Lazy, threaded load.** Nothing loads at boot (the main menu stays fast); the first query or
  `load_world_async()` loads 7 files in parallel through `WorkerThreadPool`.

## Performance

* Load: ~0.4 s cold (heightmap inflate + 5 PNG decodes + JSON in parallel). Memory ≈ 85 MB CPU
  (32 MB heights, 16 MB roads, 16 MB splat, 16 MB ground, 4 MB biome, 1 MB region) + textures on demand.
* `get_height` ≈ 1 µs; `get_water_height` uses a 512 m bucket index over lakes/canals;
  `get_height_block` 65×65 ≈ 2 ms (aligned); `fill_height_map_shape` native.

## Known limitations

* Bridges, arches, walls, the sea wall and buildings are records, not terrain: settlement/prop builders
  must construct them (Omashu stays reachable through its rock causeway meanwhile).
* No rivers yet (valleys, lakes, waterfalls and canals only); wetness marks drainage lines.
* Height quantisation is 1/32 m; on very gentle slopes normals show sub-degree stepping.
