# World content (`worldcontent`)

Everything that stands on the terrain of the open world and is not a settlement: the streaming
framework that builds it around the player without frame hitches, procedural toon vegetation for
every biome, nature features (waterfalls, natural arches, bridges, cave tunnels), structures for
the WorldData points of interest (shrines, ruins, enemy camps, training grounds, docks, vistas,
spirit spots, resource sites, landmarks), road dressing, and the **building kit** that the
settlement builders use for their cities and villages.

| | |
| --- | --- |
| Entry point | `src/world/content/world_content.gd` (`WorldContent`, Node) |
| Framework | `src/world/content/` — `ContentProvider`, `ContentCell`, `CellPayload`, `ContentColliders`, `ContentExclusions`, `ContentHash`, `ContentClaims`, `GeoBuilder`, `TerrainHoles`, `WorldContentDefaults` |
| Vegetation | `src/world/vegetation/` — `VegetationLibrary` (species meshes), `TreeMeshes`, `PlantMeshes`, `VegetationRules` (biome tables), `VegetationScatter` (global 4 m grid), `VegetationProvider`, `ForestFarProvider`, `GroundCoverProvider`, `VegetationSettings`, `VegetationMaterials`, `TerrainPatterns` |
| Nature + POIs | `src/world/props/` — `LandmarkProvider`, `PoiProvider`, `RoadDressingProvider`, `WaterfallBuilder`, `ArchBuilder`, `BridgeBuilder`, `CaveBuilder`, `BoatBuilder`, `PoiStructures`, `PoiSites`, `ResourcePickup`, `PropFx`, `PropSettings` |
| Building kit | `src/world/buildings/` — `BuildingKit`, `KitRoofs`, `KitResult`, `NationPalette`, `BuildingPresets`, `LightBudget` |
| Shaders | `assets/shaders/content/` — vegetation (+ outline), grass, kit_glow, cloth, waterfall, water_foam, mist, cave_veil, `veg_common.gdshaderinc` |
| Dev scenes | `scenes/dev/worldcontent_world.tscn` (real world + content, free-fly camera, view presets, `spawn_player()`), `worldcontent_lineup.tscn` (every species and LOD), `worldcontent_buildings.tscn` (one demo building per nation, day/night) |
| Tests | `tests/unit/test_worldcontent.gd`; playtests `worldcontent_lineup`, `worldcontent_biomes`, `worldcontent_buildings`, `worldcontent_pois`, `worldcontent_flyover` |

## Quick start

```gdscript
var content := WorldContent.new()        # registers the standard providers in _ready
add_child(content)
content.setup(player, camera)            # focus drives streaming, camera drives LOD
await content.wait_until_settled(10.0)   # optional: everything in range is built
```

The world scene adds one `WorldContent` next to its `WorldRenderer`. Without baked world data
nothing is registered that needs it (vegetation, structures) and the node is idle. Set
`use_default_providers = false` before adding it to get an empty framework (tests, custom
scenes) and register your own providers.

Dev scene: `godot --path . -- --scene=res://scenes/dev/worldcontent_world.tscn` (RMB look,
WASD/QE fly, Shift x6, 1–9 view presets, T +1 h, P prints stats). Playtests:
`tools/playtest.sh worldcontent_biomes`, `worldcontent_pois`, `worldcontent_flyover`
(`RENDERER=mobile MOBILE=1` for the phone preset).

## Streaming framework

`WorldContent` keeps, per provider, a square grid of cells (`cell_size`) and loads the cells
whose closest point is within `range_m` of the focus (plus a look-ahead along the focus
velocity), nearest first, higher `priority` first. A cell goes through
`QUEUED → BUILDING → BUILT → INSTANTIATING → ACTIVE` and is released beyond
`range_m + unload_margin`:

1. **Build (worker thread).** `provider.build_cell(cell)` runs on `WorkerThreadPool` (at most
   `max_jobs` at once) and fills a renderer-free `CellPayload`: MultiMesh buffers, mesh arrays,
   static collision, pooled collider records, main-thread callables. All heavy work — sampling
   WorldData, scattering, generating geometry, bucketing colliders — happens here.
2. **Instantiate (main thread, time-sliced).** One payload entry per step (a MultiMeshInstance3D,
   a MeshInstance3D, one static body, one callable) while the frame's budget lasts
   (`frame_budget_usec`, 2.5 ms desktop / 1.6 ms mobile). A frame never runs more than one step
   past the budget.
3. **Release.** Cells out of range are torn down inside the same budget; MultiMeshInstance3D and
   MeshInstance3D nodes are pooled and reused, audio loops stopped, pooled colliders released.

Determinism: every cell has a seed `ContentHash.hash4(provider.seed, provider id, x, y)` and
`cell.rng()`; vegetation additionally uses a *global* scatter grid (`VegetationScatter`, 4 m)
so neighbouring cells, the near and far providers and re-loads always agree plant for plant.

Collision for scattered content (tree trunks, boulders) is **pooled**: payload colliders are
records bucketed into 16 m squares on the worker; `ContentColliders` keeps physics bodies only
within `colliders.radius` (48 m desktop, 36 m mobile) of the focus, up to `max_bodies`.
Structures use always-on static bodies (`CellPayload.add_static_boxes/faces`).

Exclusions: `add_exclusion(center, radius, mask, soft)`, `add_exclusion_capsule(a, b, radius,
mask, soft)`, `add_exclusion_ring(center, inner, outer, mask, soft)` register keep-out areas
(tags `TAG_TREES`, `TAG_GRASS`, `TAG_ROCKS`, `TAG_PROPS`). Each cell build captures the immutable
snapshot (`cell.exclusions`) current when it was queued; adding or removing an area refreshes the
cells it touches. `WorldContentDefaults` registers cities (built tiers; Ba Sing Se's agrarian
ring keeps its farmland with only the wall kept clear), villages, POI footprints, waterfalls,
bridges, arch feet and cave mouths.

### Public API (`WorldContent`)

| Method / member | Notes |
| --- | --- |
| `setup(focus, camera = null)`, `set_focus(node)` | focus drives streaming; camera (default: viewport camera) is the LOD reference |
| `register_provider(p)`, `unregister_provider(id)`, `get_provider(id)`, `get_providers()` | ids are unique; registering configures the provider and starts streaming its cells |
| `refresh(id = &"")`, `refresh_area(rect, ids = [])` | rebuild all / some cells (e.g. after a settlement changed the ground) |
| `get_cell(id, coord)`, `get_cells(id)` | live `ContentCell`s (`root` node, `payload.data`, `user`) |
| `load_now(pos = INF, max_ms = 30000) -> bool` | synchronous: builds everything in range of `pos` (loading screens, teleports, tests) |
| `is_settled()`, `wait_until_settled(timeout)`, signal `settled` | nothing queued/building/instantiating |
| signals `cell_ready(id, coord)`, `cell_released(id, coord)` | |
| `add_exclusion*`, `remove_exclusion(id)`, `get_exclusions()` | see above |
| `get_stats()`, `reset_stats()` | per provider cells/active/instances, main-thread µs (last/max/avg), build ms, step/scan/update maxima (with the provider that caused them), collider and node counts |
| `frame_budget_usec`, `max_jobs`, `update_interval`, `predict_seconds`, `colliders` | tunables (set from Settings on `Events.graphics_settings_changed`) |
| `use_default_providers` | set false before `add_child` for an empty framework |
| `is_night()` | night-only MultiMeshes shown (sun luminance below 0.46, hysteresis to 0.5) |

Payload options added by perf_polish (wave 4, `docs/qa/perf_polish.md`):

* `CellPayload.add_multimesh(..., {"night_only": true})` — drawn only at night (window and lantern
  glows; `WorldContent._update_night()` checks the sun colour every 0.5 s).
* `add_multimesh` / `add_mesh_surfaces` `"fade"` — `GeometryInstance3D.VisibilityRangeFadeMode`
  for the visibility range (the margin becomes the cross-fade band instead of a hysteresis).
* `add_mesh_surfaces` `"vis_parent"` — tag of an earlier mesh of the same cell that becomes the
  `visibility_parent` (HLOD: the child shows only while the parent is hidden for being too close).
* Surfaces may carry a third element, a `{lod_size: PackedInt32Array}` dictionary of LOD index
  buffers (`MeshLods.for_arrays()`, built on the worker), passed to `add_surface_from_arrays`.
* `add_mesh_surfaces` `"lod_bias"` — `GeometryInstance3D.lod_bias` of the mesh (< 1 = coarser mesh
  LODs sooner; reset to 1 for pooled nodes).
* Vegetation: `far_density` (0.55 on phones) thins the far impostor forests deterministically
  (`ContentHash.unit2(211, gx, gz)`).

### Writing a provider (`register_provider`)

Settlement, NPC, enemy-camp and wildlife spawners plug in the same way. A provider declares a
grid and builds cells; WorldContent does the threading, slicing, pooling and recycling.

```gdscript
class_name CampfireProvider
extends ContentProvider
## Example: a campfire with a light and crackle every ~200 m on grassland.

const LOG := preload("res://assets/meshes/props/log.tres")      # any shared Mesh resource

var _range := 300.0


func _init() -> void:
	id = &"campfires"
	cell_size = 256.0
	priority = 3                 # higher loads first
	unload_margin = 64.0


## Main thread: read Settings here (also on Events.graphics_settings_changed).
## Return true when existing cells are now stale (they are rebuilt).
func configure() -> bool:
	var old := _range
	_range = 200.0 if Settings.detail_level() == 0 else 300.0
	range_m = _range
	return old != _range


## Main thread, cheap: skip cells that can never have content.
func wants_cell(coord: Vector2i) -> bool:
	var c := rect_of(coord).get_center()
	return WorldData.get_biome(c.x, c.y) == WorldData.Biome.GRASSLAND


## WORKER THREAD: pure data only (WorldData, math, shared resources). Deterministic.
func build_cell(cell: ContentCell) -> void:
	var p := CellPayload.new()
	var rng := cell.rng()
	var x := cell.rect.position.x + rng.randf() * cell_size
	var z := cell.rect.position.y + rng.randf() * cell_size
	var ground := Vector3(x, WorldData.get_height(x, z), z)
	var local := ground - cell.origin()                    # payload space = cell root
	var buf := PackedFloat32Array()
	for k in 4:
		CellPayload.write_instance(buf, Transform3D(Basis(Vector3.UP, k * PI * 0.5), local))
	p.add_multimesh(LOG, null, buf, 4, AABB(local - Vector3(2, 1, 2), Vector3(4, 3, 4)), {"vis_end": _range})
	p.add_collider(&"cylinder", Transform3D(Basis(), ground + Vector3(0, 0.3, 0)), Vector3(1.0, 0.6, 0))
	p.add_call(func(c: ContentCell) -> void:              # main thread, nodes under c.root
		var light := LightBudget.make_light({"position": local + Vector3(0, 1, 0), "color": Color(1, 0.6, 0.3),
			"range": 10.0, "energy": 2.0, "priority": 1})
		c.root.add_child(light)
		var id := Audio.play_loop(&"fire_loop", null, -8.0, 1.0, ground)
		if id > 0:
			c.loops.append(id))                           # stopped automatically on release
	p.data["fire"] = ground                               # kept with the cell
	cell.payload = p


## Optional hooks: tick() (each scan), update_cell(cell, distance), release_cell(cell),
## instantiate_step(cell) for custom main-thread work (call super for the default).
```

```gdscript
world_content.register_provider(CampfireProvider.new())
```

Rules for `build_cell`: deterministic from `cell.coord` / `cell.seed` / `cell.rng()`;
thread-safe (no nodes, no Settings, no RenderingServer; shared Mesh/Material resources created
on the main thread are fine); bounded (a few ms; split big content into more cells). Payload
transforms are relative to the cell root (`cell.origin()`: cell centre at y = 0), collider
transforms are world space. MultiMesh buffers use Godot's layout (`CellPayload.write_instance`).
Spawners that need nodes (NPCs, enemies, interactables) create them in an `add_call` callable or
in `instantiate_step`, under `cell.root`, so they are freed with the cell.

`ContentClaims.claim(feature_id, owner)` hands a WorldData feature (a bridge, a cave, a POI
structure) to another system: `LandmarkProvider` and `PoiProvider` skip claimed ids and refresh
automatically.

## Vegetation

| Species | Where | LODs |
| --- | --- | --- |
| `pine_snow` (2 variants), `fir`, `snag` | Water Tribe, taiga, snowline | LOD0 (outline), LOD1, far impostor |
| `oak`, `maple`, `cypress`, `bamboo` clumps, `hedge` | Earth Kingdom forests, meadows, farmland borders | " |
| `tropical`, `banyan` (aerial roots), `palm` (2), `fern` | Fire Nation jungle and beaches | " |
| `charred`, `lava_rock` (glowing veins) | volcanic slopes, ash fields | " |
| `blossom` | Air Temple gardens, EK groves | " |
| `shrub`, `shrub_snow`, `rock`, `rock_snow`, `rock_moss`, `ice_chunk`, `serac`, `driftwood`, `log_moss` | everywhere by biome | LOD0, LOD1 |
| `grass`, `grass_tall`, `tuft`, `flowers_warm/cool/white`, `reeds`, `wheat`, `rice` | ground cover (32 m cells) | 1 |

Meshes are generated once at startup on worker threads (`VegetationLibrary.build_async()`, ~1 s)
from `TreeMeshes`/`PlantMeshes` with `GeoBuilder` and cached. Vertex conventions: `COLOR.rgb`
linear albedo, `COLOR.a` tint mask; `UV.x` sway weight, `UV.y` foliage weight; `UV2.x` cap weight
(snow/moss/ash), `UV2.y` ember weight; instance custom = (tint rgb, random). The vegetation
shaders sway with the world wind globals (`world_wind`, gusts), fade per instance with dithering
between LOD bands (no popping), and the near LOD0 subset gets an ink outline pass.

Rules (`VegetationRules`): per region group (WT/EK/FN/AT) and biome a table of tree / small /
rock densities and species mixes; then lushness (splat), groves (macro noise), snowline, rock
cover, slope limits, roads (none within the road map), settlement paving, farmland (trees only on
plot borders as hedges), water (none in or at the edge of water), exclusion zones.

Providers: `VegetationProvider` (256 m cells: trees with LOD0 subsets per 32 m block rebuilt as
the camera moves, LOD1, shadow-only proxies, shrubs, rocks, pooled trunk/boulder colliders),
`ForestFarProvider` (512 m cells: a thinned, scaled-up impostor subset of exactly the same trees
so forests read at 1–1.6 km), `GroundCoverProvider` (32 m cells: grass clumps, flowers, reeds,
crops following the terrain shader's farm plots; density and range by Settings; fades by
distance; no grass when flying high).

| Budget (`VegetationSettings`) | mobile/low | medium | high | ultra |
| --- | --- | --- | --- | --- |
| trees end (`tree_range`) | 72 m | 132 m | 210 m | 330 m |
| LOD0 + outline (`tree_lod0`) | 32 m | 45 m | 60 m | 90 m |
| far impostors end (`far_range`) | 450 m | 780 m | 1200 m | 1600 m |
| shrubs/rocks (`small_range`) | 60 m | 110 m | 175 m | 275 m |
| grass (`grass_range`) | 30 m | 45 m | 60 m | 85 m |
| vegetation shadows within | 40 m | 70 m | 110 m | 160 m |
| tree density | 0.59 | 0.75 | 1.0 | 1.3 |
| shrub/grass density | 0.25 | 0.55 | 1.0 | 1.5 |

## Nature features and POI structures

`LandmarkProvider` (1 km cells, range 0.9 × view distance, 1.2–3 km) builds from WorldData:

* **Waterfalls** (`WaterfallBuilder`): the water leaves the notched lip and falls on a ballistic
  path pushed clear of the cliff (terrain sampled along the fall), as two layered, widening,
  animated sheets (`waterfall.gdshader`: accelerating streaks, lip and plunge foam), a plunge-foam
  disc, wet boulders, mist puffs (`GPUParticles3D`, count × `Settings.effects_scale()`) and a
  positional roar (Audio loop). The frozen cascade is a glossy ice curtain with columns and
  icicles.
* **Natural arches** (`ArchBuilder`): a faceted rock span on a Bézier whose crown reaches the
  recorded apex, thick buried feet, sediment strata, moss/snow tops, trimesh collision (walk over
  it), scree boulders.
* **Bridges** (`BridgeBuilder`): suspended rope-and-plank bridges on a sagging deck with rope
  rails, hangers, pylons and prayer flags (`deck_y(a, b, sag, t)`; near the anchors the planks
  rest on the ground where the sag would dip under it, so there is no step on or off), and
  arched stone bridges with parapets, lanterns and piers. Decks are walkable trimesh; rope
  bridges have invisible railing barriers.
* **Cave mouths** (`CaveBuilder`): the recorded tunnel is re-anchored where the hillside rises
  over half the opening (`CaveBuilder.anchor`; mouths below water are lifted out). An inward-facing
  rock tube (collision in both windings) follows it into the hill; a rocky portal frames the
  opening, a dark veil hides where the terrain surface cuts the tube, and a `TerrainHoles` capsule
  removes the heightfield collision there so the player can walk in. Interiors darken with depth
  and get style features (glowing ice, lava veins, glowing moss, lantern posts) and budgeted
  lights. Markers: groups `&"cave_entrance"`, `&"cave_end"`.

`PoiProvider` (256 m cells, range 0.35 × view distance) builds `PoiStructures` per POI type,
styled by the nation of the region, at LOD0 (full detail, lights, collision) handing over to a
simplified LOD1 at `poi_lod0`:

| Type | Structure | Markers / extras |
| --- | --- | --- |
| `shrine` | per-nation shrine (EK pavilion, FN temple + brazier, WT ice dome, AN stupa) with offerings, incense smoke | group `&"shrine"` (respawn point in front) |
| `ruin` | broken enclosure, columns, rubble, moss; a slanted broken tower ("tower" ids), a stepped temple with a broken colonnade ("temple"), or a fallen gate arch | `&"ruin_loot"` |
| `camp` | tents (ridge / yurt / tipi by nation) around a fire pit with light and smoke, palisade with gate and flag, crates, weapon rack | `&"enemy_spawn"` × tents, `&"camp_center"` |
| `training_ground` | paved floor with curb and mats, entrance gate, master's pavilion, straw dummies, element props (EK stone blocks, FN braziers, WT ice pillars, AN airball poles), racks | `&"training_dummy"`, `&"trainer_spot"` |
| `dock` | pier from the nearest shoreline (`PoiSites.find_shore`) with a T-head, piles, lanterns, cargo, moored boats, boat shed | `&"dock_berth"` |
| `vista` | overlook terrace with railing, cairn, bench, prayer flag | `&"vista"` |
| `spirit_spot` | glowing standing-stone circle around a heart stone or a spirit tree, spirit motes / vent steam, light | `&"spirit_spot"`, pickup `spirit_blossom` |
| `resource` | quarry outcrops studded with glowing jade crystals (or ore), cut-block stacks, a wooden hoist; a beached whale skeleton (skull, spine, arching ribs) for whale bone; a worker's lean-to | `ResourcePickup`s (`jade_shard`, `whale_bone`, `iron_ore`) |
| `landmark` | lighthouse (`lantern_isle`), gatehouse straddling the nearest road (`*_gate`, `PoiStructures.nearest_road`), otherwise a carved stele with lanterns | — |

POIs inside city tiers (landmarks: inside the whole city radius) and, except docks, inside
village footprints belong to the settlement builders and are skipped; so are `village`,
`waterfall`, `cave` and `bridge` POIs (LandmarkProvider) and natural landmark areas (basins,
lakes, canyons...). All markers are `Marker3D`s in their group and in `&"world_markers"` with meta
`poi` = POI id: `get_tree().get_nodes_in_group(&"enemy_spawn")`.

`ResourcePickup` (extends the player module's `Interactable`): `item_id`, `count`,
`display_name`, `respawn_time`; `interact()` calls `GameState.add_item`, shows a HUD toast
(`Events.notify`), hides the model and regrows; `PoiProvider.harvested` remembers harvests across
cell reloads.

`RoadDressingProvider` (256 m cells, 160–420 m) dresses roads outside settlements from each road's
arc length: lanterns every 28 m (alternating sides) in a 220 m approach band around villages and
cities (EK/FN post lanterns, AN stone lanterns, WT ice lanterns), split-rail fences where the
roadside is farmland, signposts with an arrow per branch at junctions, milestones every 400 m.

| Budget (`PropSettings`) | low | medium | high | ultra |
| --- | --- | --- | --- | --- |
| POI structures end (`poi_range`) | 525 m | 910 m | 1400 m | 1400 m |
| POI LOD0 → LOD1 (`poi_lod0`) | 70 m | 100 m | 140 m | 200 m |
| landmarks (`landmark_range`) | 1350 m | 2340 m | 3000 m | 3000 m |
| cave interiors (`cave_range`) | 450 m | 600 m | 800 m | 1000 m |
| road dressing (`road_range`) | 160 m | 220 m | 300 m | 420 m |
| kit lights (`LightBudget.max_lights`) | 4 | 8 | 14 | 22 |

## Building kit (for the settlement builders)

The kit turns architectural intent into a few draw calls: geometry is accumulated per material
**slot** in `GeoBuilder` arrays with vertex colours from the nation **palette**, so a whole cell of
buildings is one mesh with ≤ 4 surfaces. Everything except `instantiate`/`make_mesh` is
thread-safe — build whole districts on a worker inside `build_cell`.

```gdscript
NationPalette.prepare_materials()                         # once, main thread
var kit := BuildingKit.new(NationPalette.get_palette(&"earth_kingdom"), 0, seed)   # lod 0/1/2
kit.push(BuildingKit.at(Vector3(10, 0, 4), yaw))          # local frame; -Z = front
kit.box(Vector3(0, 0.3, 0), Vector3(10, 0.6, 8), &"base")                 # centre + size, collides
kit.wall(Vector3(-5, 0.6, -4), Vector3(5, 0.6, -4), 3.2, 0.4, {"openings": [
	{"t": 0.5, "width": 1.6, "height": 2.4, "kind": &"door", "leaf": &"open"},
	{"t": 0.2, "width": 1.0, "height": 1.0, "sill": 1.0, "kind": &"window"}]})
KitRoofs.hip(kit, Vector3(0, 3.8, 0), 10.0, 8.0, 3.0, {"curve": 0.5, "ornaments": true})
kit.lantern(Vector3(2, 0.6, -4.6), {"style": &"stone"})
kit.banner(Transform3D(Basis(), Vector3(-3, 3.6, -4.3)), 0.7, 2.2)
kit.pop()
var res := kit.build()                                    # KitResult
res.add_to_payload(payload, Transform3D(Basis(), pos - cell.origin()), {"vis_end": 600.0})  # streamed
add_child(res.instantiate({"name": "Hall"}))              # or as nodes (main thread)
```

**Frames and colours.** `push(t)/pop()` nest local frames; `BuildingKit.at(pos, yaw)`. Colours are
palette *roles* (`wall wall_alt base stone stone_dark trim trim_alt roof roof_alt roof_under ridge
wood wood_dark floor door window cloth cloth_alt metal accent glow ice snow interior`) or explicit
`Color`s; `color_jitter` varies pieces slightly. `NationPalette.nation_for_region(region)` maps a
WorldData region to `&"water_tribe" / &"earth_kingdom" / &"fire_nation" / &"air_nomads" /
&"neutral"`.

**Slots** (`kit.g(slot)` → `GeoBuilder`): `&"solid"` (vertex-coloured toon + ink outline),
`&"glow"` (emissive, brighter at night, UV.y = flicker), `&"cloth"` (two-sided, wind ripple),
`&"ice"` (glossy toon). `kit.default_slot = &"ice"` builds ice architecture with every primitive.

**Primitives** (all in the current frame; `collide` adds box/trimesh collision):

| Call | Notes |
| --- | --- |
| `box(center, size, role, collide = true, slot, skip)`, `box_t(t, size, role, collide, slot)` | `skip` bit mask drops hidden faces |
| `beam(a, b, w, h, role, collide = false)` | posts, rafters, rails |
| `slab(poly2d, y0, y1, role, collide, top_role)` | extruded footprint (any polygon) |
| `cylinder(base, height, radius, role, sides, collide, top_radius, slot)` | drums, towers, piles |
| `column(pos, height, radius, role, style, base_role)` | `&"round"`, `&"square"`, `&"ice"`; plinth + capital |
| `wall(a, b, height, thickness, opts)` | opts: `role base_role cap_role cap crenels{width,gap,height} openings[{t,width,height,sill,kind door/window/gate,frame_role,leaf none/closed/open,round}] piers skip_ends` |
| `wall_loop(points, height, thickness, opts, closed)` | walls around a footprint (mitred corners) |
| `stairs(bottom, top, width, opts)`, `ramp(bottom, top, width, thickness, role)` | stairs collide as a ramp (walkable) |
| `railing(points, height, opts)` | posts + rails (`spacing`, `rails`, `collide`) |
| `door(t, width, height, opts)`, `window(t, width, height, opts)`, `arch(a, b, height, thickness, depth, role)` | framed openings for free-standing frames |
| `lantern(pos, opts)` | styles `paper post stone ice brazier wall`; records a light (`light`, `range`, `energy`, `color`) |
| `brazier(pos, opts)`, `add_light(pos, color, range, energy, priority)` | lights become budgeted OmniLight3Ds |
| `banner(t, width, length, opts)`, `flag(t, pole_h, width, height, opts)` | cloth slot, wind shader |
| `ornament(pos, kind, size, role, dir)` | `finial horn orb spike` |
| `collide_box(center, size, basis)`, `collide_faces(pts)`, `collide_quad(a, b, c, d)` | extra collision |
| `mark(name, t)` | named transform (doors, NPC spots) → `KitResult.markers` |

**Roofs** (`KitRoofs`, `center` = footprint centre at eave height, `w`/`d` = wall footprint):
`hip(kit, c, w, d, h, {overhang, curve (upturned eaves), concave, role, alt_role, ornaments})`,
`gable(...)`, `cone(kit, c, r, h, {sides, flare, role, alt_role, trim_role, finial})`,
`dome(kit, c, r, {squash, role, rib_role, block_lines, slot})`,
`flat(kit, c, w, d, {parapet, crenels, icicles, role, slot})`,
`pagoda(kit, c, w, d, tiers, opts) -> top`. Roofs collide as trimesh.

**Presets** (`BuildingPresets`, origin = ground centre, -Z = front): `house(kit, t, {w, d,
floors, floor_h, base_h, roof, roof_h, door, windows, interior, porch, lanterns, banners,
wall_role, roof_role})`, signature halls `ek_hall`, `fn_temple`, `wt_hall`, `an_tower`,
`gatehouse`, `wall_run(points, {height, thickness, crenels, towers, tower_roof})`, `watchtower`,
`tent({style ridge/yurt/tipi})`, `shrine`, `demo(kit, t)`. Markers `&"door"`, `&"interior"`,
`&"top"`. Simple interiors: `interior: true` hollows the ground floor (floor, ceiling, open door,
low table, cushions, shelf, lamp).

**LOD.** Build the same building at `lod` 0 (full), 1 (no small ornaments, coarser roofs and
cylinders, railings as slabs) and 2 (silhouette), and hand over with visibility ranges
(`add_to_payload(..., {"vis_begin", "vis_end"})`); `KitResult.merge(other, t)` merges results so
a cell of buildings stays one mesh per LOD.

**Lights.** `LightBudget` keeps only the nearest `max_lights()` kit lights enabled (4/8/14/22 by
detail), fades them in with darkness and distance (≤ 70 m) and never casts shadows; emissive
glow geometry reads at any distance. Light records with `"interior": true` (cave and tunnel
lights; set it on `kit.lights` entries for windowless interiors) also shine by day.

**Other builders available to settlements:** `BridgeBuilder.stone/suspended(kit, a, b, width,
...)`, `BoatBuilder.rowboat/sampan/kayak/ferry(kit)` and `BoatBuilder.ferry_node(nation)` (a
ready ferry Node3D with deck collision and meta `deck`), `PoiStructures` helpers, `CaveBuilder`.

Demo: `scenes/dev/worldcontent_buildings.tscn` (one signature building per nation on a plaza;
playtest `worldcontent_buildings` shoots day, night lanterns and an interior).

## Performance

Measured with the playtests on the CI machine (llvmpipe software Vulkan, 4 shared cores,
960×540) — absolute frame times are the software renderer's; the per-frame content cost and the
counts are what matter.

PERF_TABLE

Decisions that keep it cheap: MultiMesh per cell and species (one draw call per cell/species/LOD),
per-instance dithered LOD bands instead of node swaps, CPU-bucketed LOD0 subsets with capacity
buffers (`visible_instance_count`) so the near detail follows the camera without rebuilding
buffers, shadow-only LOD1 proxies within the shadow range, vertex-coloured kit geometry (≤ 4
surfaces per cell), pooled nodes and colliders, worker-thread builds with main-thread slicing,
Settings-driven ranges and densities, and lights through `LightBudget`.

## Foundation / cross-module changes

* `assets/shaders/toon.gdshader`: omni/spot lights no longer add an unattenuated shadow-side fill
  (blocky light squares at night); directional behaviour unchanged.
* `src/world/terrain/terrain_collision.gd`: punches `TerrainHoles` into heightfield patches (NaN
  = hole in Jolt) and rebuilds live patches when holes change.
* `src/player/player_camera.gd`: the keep-above-terrain clamp is skipped while the player is
  underground (cave tunnels); the collision cast keeps the camera inside the tube.

## Known issues

KNOWN_ISSUES
