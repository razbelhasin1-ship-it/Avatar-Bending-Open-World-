# Settlements (`settlements`)

The cities, temples and villages of the world: architecture built procedurally with the
worldcontent **building kit**, laid out from the WorldData city records, streamed by
**WorldContent** providers, with NPC **anchor data** for the NPC / quest modules.

This page documents the shared framework (`src/world/settlements/common/` + the registry). Each
settlement module adds its own page with its layout, recipes and decisions:

| Module | Settlements | Page |
| --- | --- | --- |
| `settlements_wa` (Settlements I) | Northern Water Tribe (vertical slice), arctic igloo villages + fishing camps, Southern Air Temple | [settlements_wa.md](settlements_wa.md) |
| `settlements_ef` (Settlements II) | Ba Sing Se, Omashu, Earth Kingdom villages (Full Moon Bay, Northreach, Millet Hollow, Cedar Rest), Fire Nation capital, Crimson Harbor, Fire Nation villages (Saltspark, Ashleaf Terraces, Sunflare Isle resort) | [settlements_ef.md](settlements_ef.md) |

| | |
| --- | --- |
| Registry / API | `src/world/settlements/settlements.gd` (`Settlements`, static) |
| World hook | `src/world/settlements/world_hook.gd` (instantiated by `WorldHooks` in the world and tutorial scenes) |
| Framework | `src/world/settlements/common/`: `SettlementPlan`, `SettlementBuilder`, `SettlementProvider`, `SettlementFarProvider`, `SettlementSettings`, `SettlementFx`, `KitCache`, `KitMerger`, `KitX`, `RingLayout` |
| Dev scene | `scenes/dev/settlements_wa.tscn` (`src/world/settlements/dev/settlements_dev.gd`): real world + content + settlements, free-fly camera, named views, `spawn_player()`; `scenes/dev/settlements_ef.tscn` adds the Settlements II views |

## Using it (NPC / quest modules)

```gdscript
Settlements.get_anchors(&"northern_water_tribe", &"market_stall")   # Array[Dictionary]
Settlements.get_anchors(&"", &"quest_giver")                        # every settlement
Settlements.anchors_near(player.global_position, 60.0, &"home")    # closest first
Settlements.get_anchor(&"southern_air_temple_trainer_3")           # by id ({} if unknown)
Settlements.settlement_at(pos)     # &"northern_water_tribe" / &"ba_sing_se" / &"fire_nation_capital" / ... / &""
Settlements.district_at(pos)       # e.g. &"nwt_palace", &"sat_courtyard", &"frostmere", &"fnc_plaza_of_the_sun", &"fn_saltspark"
Settlements.get_info(&"southern_air_temple")   # {id, name, nation, center, radius, districts, pieces, anchors}
```

Plans are built lazily on first use (main thread, deterministic, cached for the run: Water Tribe
≈ 0.15 s, Air Temple ≈ 0.07 s, arctic villages < 0.02 s, Ba Sing Se ≈ 0.35 s, Fire Nation
capital ≈ 0.25 s, the others ≤ 0.15 s) and need only WorldData, so anchors can be queried before
(or without) any geometry streaming. Without baked world data every plan is empty and every
query returns empty results.

Settlement ids: `northern_water_tribe`, `arctic_villages`, `southern_air_temple` (Settlements I);
`ba_sing_se`, `omashu`, `ek_villages`, `fire_nation_capital`, `fire_harbor`, `fn_villages`
(Settlements II). The scattered-site sets (`arctic_villages`, `ek_villages`, `fn_villages`,
`Settlements.SITE_SETS`) have no single centre: `settlement_at` finds them by their districts.

### NPC anchor record

```
{
  id: StringName          # "<settlement>_<kind>_<n>", unique, stable for a given world bake
  settlement: StringName
  kind: StringName        # see the table
  position: Vector3       # world, on the walkable floor where the NPC stands
  yaw: float              # facing (rotation about +Y of a -Z-forward model)
  district: StringName    # district_at(position) when the anchor was made
  tags: Array             # free-form strings: "market", "palace", "meditate", "interior", ...
  # optional, by kind:
  points: PackedVector3Array, loop: bool     # patrol / walk routes
  building: StringName, capacity: int        # homes: the building kind, how many live there
  interior: bool                             # inside an enterable interior
  goods: String                              # market stalls: fish / pottery / furs / trinkets
}
```

| kind | meaning |
| --- | --- |
| `home` | outside a dwelling's door, facing out (capacity = residents) |
| `market_stall` | behind a stall counter, facing the street |
| `guard_post` | standing post (stair tops, gates, sea wall, palace) |
| `patrol` | a route (`points`, `loop`): wall walks, promenades, monks' walks, a bridge crossing |
| `trainer` | a master's spot (training hall dais, airball court, sanctum, meditation ledge) |
| `quest_giver` | characters worth talking to: chief, princess at the oasis, harbour master, elders, abbot, stable keeper, gatekeeper, librarian... (tags say who) |
| `healer`, `student`, `worker`, `fisher`, `gardener` | occupations at their workplace |
| `idle` | benches, view points, meditation spots (`meditate`), pilgrims |
| `child_play` | plazas, the airball court |
| `boat` | canoes / ships (a fisher may sit in them) |
| `bison_stall`, `bison_landing` | where a sky bison rests / lands |

## Architecture

```
WorldData city record ──> Planner (per settlement) ──> SettlementPlan (pieces, anchors, districts, data)
                                                             │ read-only, thread-safe
                       SettlementProvider (near, 96–128 m cells) ──> LOD0 + LOD1 meshes, collision, lights, extras
                       SettlementFarProvider (4x cells)          ──> LOD2 silhouettes
                                 │ worker threads
                       SettlementBuilder.build_piece(kit, piece) ──> recipe libraries (BuildingKit)
```

* **Plan** (`SettlementPlan`): pieces `{kind, pos, yaw, spec, lod, arch, r}`, anchors, districts
  (circles), an occupancy grid (`reserve`, `reserve_line`, `is_free`, `place`) used by the
  planners to avoid overlaps, a cell index (`cell_pieces`, `sub_cells`), and `data` for extras
  (`exclusions` → WorldContent keep-out circles, `claims` → `ContentClaims`).
* **Pieces** are built in their own frame (origin = ground anchor, -Z = front). `lod` is the
  coarsest LOD that still draws the piece (0 near only, 1 + mid, 2 + far silhouette). Pieces with
  an `arch` key are archetypes: built once per LOD (`KitCache`, keyed `"<nation>|<arch>|<lod>"`)
  and merged with their transform (`KitMerger`, native packed-array transforms). The key must
  encode every spec value the recipe reads (variants, dimensions), otherwise whichever worker
  builds first wins.
* **Near provider** (`SettlementProvider`): per cell on a worker: all pieces merged into one
  mesh per LOD with ≤ 4 material surfaces (solid / ice / glow / cloth); LOD0 (full detail,
  shadows) up to `lod0_end`, LOD1 (simplified) to `lod1_end`. Both share one AABB
  (`KitMerger.normalize_aabb` → `SettlementPlan.cell_aabb`) so the visibility ranges hand over at
  the same distance. **No visibility margins** on any hand-over: Godot's margin hysteresis keeps
  a freshly created, not-yet-visible instance hidden inside the whole margin band, so two LODs
  with margins leave a cell invisible while the camera sits in the band (regression test
  `test_lod_handover_has_no_gap`). Collision (boxes + trimesh of LOD0) is attached only within
  `collision_range` of the focus (+40 m hysteresis). Lights: the highest-priority `cell_lights`
  per cell become `LightBudget` lights. Piece extras (particles, sounds, nodes, markers) are
  created on the main thread.
* **Night glows** (`night_glow.gdshader`, `SettlementFx.add_glows`): one MultiMesh of additive,
  camera-facing sprites per cell that fade in at dusk (from the `world_sun_color` global), grow
  slightly with distance and collapse to nothing by day, so a lit city sparkles from kilometres
  without real lights. Near cells (0 – `lod1_end`) draw a glow on every LOD0 light record that
  is not an interior light, plus every glow-only record (`KitX.glow`: lit windows, unlit
  lanterns via `KitX.lantern`), so glows sit exactly on the lamps and panes. Far cells
  (`lod1_end` – `far_end`) draw the builder's `piece_glows(piece)` (approximate spots are fine
  there). Glow-only records are filtered out before lights are budgeted.
* **Far provider** (`SettlementFarProvider`): 4x larger cells, one small mesh per near sub-cell
  sharing its AABB, from `lod1_end` to `far_end` (the Settings view distance, 1.5–6 km), no
  collision / shadows / lights (but night glows).
* **Registration** (`Settlements.register(content, opts)`): near + far provider per settlement,
  keep-out exclusions, claims. opts: `only` (ids), `skip_tags` (pieces whose `spec.tag` is listed
  are left out — the tutorial skips the Air Temple's `airball_court` and the Fire Nation
  capital's `flame_kata_grounds` where it dresses its own training grounds).
  `Settlements.unregister(content)`.
* **World hook** (`world_hook.gd`): `world_setup(scene)` registers everything on the scene's
  WorldContent before the player spawns, so the loading screen waits for the buildings (and
  their collision) around the spawn.

### Budgets (`SettlementSettings`, from `Settings.detail_level()` / `view_distance_m()`)

| key | low (mobile) | medium | high | ultra |
| --- | --- | --- | --- | --- |
| `lod0_end` (full detail, props, lights, shadows) | 100 m | 160 m | 220 m | 300 m |
| `lod1_end` (simplified buildings; casts shadows from medium up) | 300 m | 600 m | 800 m | 1100 m |
| `far_end` (silhouettes) | view distance, clamped 1.5–6 km | | | |
| `collision_range` (+40 m hysteresis) | 90 m | 110 m | 120 m | 140 m |
| `cell_lights` | 6 | 10 | 14 | 18 |

`LightBudget` additionally keeps only the nearest 4/8/14/22 kit lights enabled.

## Shared helpers

| Helper | What |
| --- | --- |
| `RingLayout` | polar helpers for the WorldData ring-layout cities: `from_city(id)`, `point(r, bearing, y)`, `polar(x, z)`, `tier_at`, `ramp_at`, `dir`, `yaw_of`, `half_angle`, `arc_len` |
| `KitX` | extra kit pieces: nation emblems (`emblem_water`, `emblem_air`), `icicles`, rounded `merlons`, block `joints`, arched `doorway` with curtain, `window` (lit panes get mullions + a glow record; `lit_window_color`), `banner` with emblems, `inner_dome`, `grass_tuft`, prayer `flag_string`, flat floor inlays (`ribbon`, `swirl_inlay`, `water_inlay`), `glow` (glow-only record), `lantern` (kit lantern + glow when unlit) |
| `KitX` (Settlements II) | `emblem_earth`, `emblem_fire`, banner emblems `&"earth"` / `&"fire"` with a `res` (detail) factor for giant banners, `prism_x` (an extruded profile along x: battered walls, towers) |
| `RingCityPlanner` | base of the ring-city planners: polar helpers, avenue gaps, `step_wall` (retaining-wall chords on the measured, smoothed face of a tier step, facing the lower side either way, nation recipe via `wall_kind`), `band` (rows of houses along a ring street with nation hooks `house_footprint` / `house_height` / `house_piece` / `house_anchors`) |
| `SettlementLayout` | `world(pos, yaw, local)`, `yaw_dir`, `fits` / `reserve_rect` (rotated footprints against the plan's occupancy grid), `pick` (weighted), `face_r` (terrain step face by binary search), `ground_range`, `chords` |
| `ArrivalClearance` | the new-game arrival camera path of an element (the cinematic's Bezier); `ok(x, z, radius, top)` keeps tall pieces clear of it |
| `RoofsLite` | cheap curved hip / gable / pent roofs (upturned eaves, soffits, ridges) for the many small buildings |
| `KitCache`, `KitMerger` | archetype cache, fast merging (see above) |
| `SettlementFx` | main-thread resources the workers reference (waterfall sheet materials, vegetation materials, the night-glow material; `prepare()`), `vegetation_node(items, origin)` (garden trees / shrubs / flowers as VegetationLibrary MultiMeshes with the open-world shaders), `add_glows` / `glows_from_lights` (night glows, see above), `warm_light` |

## Adding a settlement

1. A planner (`src/world/settlements/<name>/<x>_planner.gd`) returning a `SettlementPlan` from
   `WorldData.get_city(id)` (use `RingLayout`; measure the terrain where the generator blended
   steps, see settlements_wa "decisions").
2. A `SettlementBuilder` subclass dispatching `build_piece(kit, piece)` to recipe libraries;
   optionally `piece_extras` / `piece_payload`, and `piece_glows` (far night glows). Use
   `KitX.window(..., lit = true)`, `KitX.lantern` and `KitX.glow` in recipes so near glows land
   on the right spots.
3. Add the id to `Settlements.ALL` and the two `match` blocks in `Settlements.plan()` /
   `builder()`.
4. Tests: plan counts, cell build budget, walk tests (`tests/unit/test_settlements_wa.gd` and
   `test_settlements_ef.gd` have the probe-capsule walker: `_walk_world` + `_walk`; record the
   stairs / gates / interiors in `plan.data` so the tests can walk them), a screenshot tour view
   in the dev scene. Ring cities can extend `RingCityPlanner` (see `EkRingPlanner`,
   `FnRingPlanner`).
