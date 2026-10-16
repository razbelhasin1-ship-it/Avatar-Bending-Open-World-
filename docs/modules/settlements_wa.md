# Settlements I — Northern Water Tribe + Southern Air Temple (`settlements_wa`)

The game's first polished vertical-slice city (the **Northern Water Tribe**, with the igloo
villages and fishing camps of the arctic wilds) and the **Southern Air Temple**, built on the
shared settlement framework ([settlements.md](settlements.md): registry, plans, streaming
providers, anchors API, budgets).

| | |
| --- | --- |
| Water Tribe | `src/world/settlements/water_tribe/`: `NwtPlanner` + `NwtDistricts` (layout), `NwtBuilder` (dispatch + extras), recipes `NwtHomes`, `NwtCivic`, `NwtLandmarks`, `NwtPlaces`, `NwtProps`, `NwtStyle`, `SpiritKoi` (Tui and La), `ArcticPlanner` |
| Air Temple | `src/world/settlements/air_temple/`: `SatPlanner` + `SatDistricts` (layout), `SatBuilder`, recipes `SatTowers`, `SatCivic`, `SatPlaces`, `SatProps`, `SatStyle` |
| Settlement ids | `&"northern_water_tribe"`, `&"arctic_villages"`, `&"southern_air_temple"` |
| Tests | `tests/unit/test_settlements_wa.gd` (plans, cell builds, LOD, anchors contract, lookups, determinism, registration / claims / tutorial skip tags, arrival-flight clearance, probe-capsule walk tests over real collision) |
| Playtests | `settlements_wa_tour` (screenshot tour, `VIEWS=a,b`, `PRESET=`), `settlements_wa_walk` (the real player walks bridge, stairs, grand stair, into an interior; `WALKS=`), `settlements_wa_world` (new Air / Water game through the real world scene: arrival flight, spawn on the settlement floor, walk; `ELEMENT=`) |
| Dev scene | `godot --path . -- --scene=res://scenes/dev/settlements_wa.tscn` (RMB look, WASD/QE fly, Shift x6, 1–9 views, T +1 h, N night, P stats) |

Everything is registered by the settlements world hook (`world_hook.gd`) on the world and
tutorial scenes' WorldContent, so the loading screen waits for the buildings and their collision
around the spawn. NPC modules use the anchors API described in [settlements.md](settlements.md).

## Northern Water Tribe (`&"northern_water_tribe"`)

The city fills the bay of the WorldData ring layout: four tiers (harbour, middle, upper, palace)
stepping up from the water towards the glacier, the radial ramps between them, the canals with
their falls, and the sea wall across the bay mouth. `NwtPlanner` builds the structure, then
`NwtDistricts` fills it. One plan: ≈ 2800 pieces, ≈ 1220 anchors, 0.13 s.

| Part | What is built (counts from the current bake) |
| --- | --- |
| Sea wall | 32 wall chords across the bay mouth (blind arcade on the ocean face, giant banners, crenellated parapets, braziers on the walk), 4 domed sea towers, the **sea gate**: two colossal towers with ice spires flanking the ship passage under a lintel bridge carrying the walkway and the moon-and-waves emblem |
| Tier steps | ≈ 930 retaining-wall chords on every tier step and along the quay (some carry dwellings with doors, windows and wall lanterns in their face), 9 **grand stairs** over the radial ramps, 2 land gates closing tier ends, 31 city towers with ice spires on the skyline |
| Canals | walls along every canal, 29 **canal bridges** (arched, some with lamps), 4 **canal waterfalls** between the tiers (animated two-layer sheets + plunge foam + a water roar), 97 **moored canoes** |
| Harbour | 11 piers with lamps, 5 ships at anchor, warehouses, fish racks, crates |
| Houses | 9 bands of houses along the tier streets, backing onto the next step: dome homes (snow domes with vestibules), block houses, tower houses, noble houses, warehouses, assembly halls (≈ 820 in total), doors facing the street, some windows lit |
| Civic | 18 plazas with water-emblem mosaics, 4 market rows (≈ 180 stalls with fish / pottery / furs / trinkets), 34 ice sculptures, 300 lamp posts, 56 braziers, 58 blue banner poles, benches |
| Palace | the Chief's palace on its raised platform: domed hall, portico, flanking towers with ice spires, braziers, banners, lit windows |
| Spirit Oasis | a walled garden behind the palace: grass lawn, the pond with **Tui and La** (`SpiritKoi`: the white and the black koi circling each other, faint glow after dark), shade trees, bamboo, shrubs and reeds (VegetationLibrary plants), stone lanterns and a warm always-on light |
| Interiors (enterable) | **healer hut** (healing pool ringed with ice blocks and glowing water, hanging lamp, cots with furs), **training hall** (water basins along the walls, master's dais, banners, water-emblem floor inlay), **family home** (fire pit with a cooking pot, sleeping furs). Interior lights are flagged as interior (shine by day) |

Districts: `nwt_harbor`, `nwt_middle`, `nwt_upper`, `nwt_palace` (tier bands), `nwt_palace`
(the palace itself), `nwt_spirit_oasis`, `nwt_sea_wall`. Anchors: homes at every door,
market stalls, guard posts (stair tops, gates, sea wall, palace), patrols (wall walk,
promenades), trainer and students (training hall), healer, fishers and boats (piers, canoes),
workers (harbour), quest givers (chief, princess at the oasis, harbour master, elders), idlers
on benches and plazas, children on the plazas.

### Arctic villages (`&"arctic_villages"`)

`ArcticPlanner` places igloo villages and fishing camps on flat snow away from roads and POIs
(sites from an offline heightmap scan, re-validated at runtime), each its own district with
anchors (homes, fire, fishers, guards, a quest giver):

* **igloo villages** Frostmere, Whitecrest, Eastwind: igloos with entrance tunnels in a loose
  ring around a fire pit (smoke, embers, crackle), hide tents, drying racks, a banner pole, ice
  lanterns; the lake village cuts ice-fishing holes;
* **fishing camps** Saltwind, Driftfin: a crescent of tents and igloos facing the shore, fish
  racks heavy with fish, crates, a lamp post, canoes pulled up on the beach, a pier where the
  water is deep enough;
* the **Strait Wardens' camp** from the WorldData village record (lookout tower, igloos,
  tents, kayaks).

## Southern Air Temple (`&"southern_air_temple"`)

The temple crowns its mountain on the WorldData ring layout: the Sanctum on the summit, the
courtyard ring, the prayer terraces, the bison landing ring on the cliff edge, the open Cloud
Court on the south side 40 m below the courtyard, and two rock pinnacles joined to the temple by suspended
bridges. `SatPlanner` builds the walls, stairs, edge balustrades and bridges, `SatDistricts`
the rest. One plan: ≈ 615 pieces, ≈ 125 anchors, 0.07 s; 96 m cells.

| Part | What is built |
| --- | --- |
| Great Spire | octagonal podium with four winged halls and corner shrines, a 64 m shaft with window rings and three balconies, a 38 m flared blue-teal cone with a cupola; secondary spires and prayer wheels around it. Reads from kilometres (LOD2) |
| Spires | 32 spire towers (courtyard, terraces, 12 cliff towers rising from below the landing edge): masonry foot down to the terrain, buttress ribs, arched window rings, balconies, banners, flared blue-teal cones with gold finials, some with cupolas |
| Walls and stairs | ≈ 180 retaining-wall chords on every tier step with facades (window rows, balconies, pent roofs, relief arches, banners, air emblems), 10 grand stairs on the radial ramps with 14 gateways (upswept lintels, swirl discs, bells), ≈ 180 balustrade chords along every drop, with stone lamps |
| Sanctuary | podium and portico with the **air-symbol door** (gold rim, swirl, horn tubes), pediment, banners, stone lanterns, incense burners with smoke; a forecourt court with the swirl inlay, statues (seated monk, standing monk, resting sky bison) and gardens |
| Courtyard | monks' dormitories (51) and halls, gardens with **blossom trees** (VegetationLibrary), the **airball court** (poles on pedestals, swirl court), the arrival plaza, benches, **wind chimes** (they ring when the player is near), prayer-flag lines |
| Terraces | 9 terrace spires, houses backing onto the next wall, gardens |
| Bison landing | landing circle, 2 **bison stables** with hay, the pass gate, flags |
| Cliff edge | 6 **meditation pavilions** cantilevered over the drop (gaps in the balustrade), the Glider's Leap pavilion, the Meditation Ledge (spirit motes) |
| Bridges | the two **suspended bridges** to the pinnacles, rebuilt in Air Nomad style in 24 m segments: planks, rope barriers, hangers, prayer-flag poles; walkable with collision |

Districts: `sat_sanctum`, `sat_sanctuary`, `sat_airball_court`, `sat_bison_stables`,
`sat_courtyard`, `sat_terraces`, `sat_landing`, `sat_lower_court` (the Cloud Court),
`sat_arrival`, and one per pinnacle (`sat_<pinnacle id>`). Anchors: homes, trainer (airball court, sanctum,
Meditation Ledge), quest givers (abbot, elder at the sanctuary door, greeter at the arrival plaza, librarian / cook, stable keeper, gatekeeper), students,
gardeners, workers, idlers and meditators, children (airball court), patrols (monks' walks, a
bridge crossing), bison stalls and landing spots.

## Night

Windows (amber panes with mullions by day), lanterns, braziers and torches use the kit_glow
shader (brighter at night) and budgeted point lights near the camera. To make the cities read
at night from afar without hundreds of lights, every cell also carries **night glow sprites**
(`night_glow.gdshader`): additive camera-facing billboards that fade in at dusk and grow
slightly with distance — exactly on the LOD0 lamps and lit windows up to `lod1_end`, and on
`piece_glows()` spots beyond. They collapse to nothing by day. See the screenshots
`settlements_wa_nwt_aurora` / `nwt_night` / `sat_night_far` / `sat_sunset`.

## Performance

| | Water Tribe | Air Temple | Arctic |
| --- | --- | --- | --- |
| near cells (LOD0 + LOD1) | 54 × 128 m | 32 × 96 m | 11 × 128 m (5 sites + wardens' camp) |
| plan | 2807 pieces, 1224 anchors, 0.13 s | 615 pieces, 126 anchors, 0.07 s | 94 pieces, 92 anchors |
| LOD0 triangles per cell | avg 53 k, max 114 k | avg 42 k, max 104 k | max 7 k |
| LOD1 / LOD2 triangles per cell | avg 17 k / 3.4 k | avg 6.6 k / 1.5 k | – |
| worst cell build (one worker, llvmpipe CI box) | 70–90 ms (≈ 110 ms with every worker busy) | 140–150 ms | < 15 ms |

* One mesh per cell per LOD with ≤ 4 material surfaces (solid / ice / glow / cloth), so a cell
  costs a handful of draw calls; LOD1 is ≈ 1/5 of LOD0, LOD2 a few thousand triangles per
  128 m sub-cell. The Great Spire, sea gate, palace and spire cones are LOD2 silhouettes up to
  the view distance (1.5–6 km).
* Collision only where walkable (wall tops, streets, stairs, bridges, piers, floors, interiors
  — boxes + LOD0 trimesh faces; no decor collision), attached only within `collision_range` of
  the focus.
* Lights: ≤ `cell_lights` (6–18) per cell, of which LightBudget enables the nearest 4–22.
  Night glows are one MultiMesh per cell (no lights, no shadows).
* Mobile (`PRESET=low`, Mobile renderer): LOD0 to 110 m, LOD1 to 420 m, 6 lights per cell —
  checked with `RENDERER=mobile MOBILE=1 PRESET=low` and `RENDERER=gl_compatibility` tours.

## Decisions

* **Terrain truth.** The generator blends the tier steps of the ring layout, so the nominal
  tier radii are not where the slope is. The planners measure the terrain along every bearing
  (`face_r`) and stand the wall faces on the measured foot, read the wall heights from the
  terrain, and treat a gentle measured slope as a ramp (stairs, no wall). No floating or buried
  walls, no gaps behind them.
* **Arrival flight.** The air element's arrival cinematic flies low past the Great Spire.
  `SatPlanner.cam_ok()` replicates the cinematic's Bézier path from the WorldData arrival camera
  and rejects (or shrinks: spire scales 1 / 0.72 / 0.5) any piece that would rise into it;
  `test_air_arrival_flight_is_clear` sweeps a sphere along the path through the real collision.
* **Bridges.** The LandmarkProvider's generic bridges at the temple are claimed
  (`ContentClaims`: `at_bridge_west`, `at_bridge_east`, plus `at_meditation_ledge`) and rebuilt
  in segments whose deck follows a slope-limited profile (≤ 0.4 m/m, raise-only passes) shared
  by the planner and the recipe (`SatPlanner.deck_profile` / `deck_y`), so deck, collision and
  abutments agree; the temple end starts on the measured wall face.
* **Tutorial.** The airball court pieces carry `spec.tag = &"airball_court"`; the tutorial scene
  registers the Air Temple with `skip_tags` so its training ground stands there instead.
* **Canal inset.** Canal walls stand 0.5 m inside the canal edge: coarse terrain LODs show the
  carved bank slope above the waterline at the wall foot otherwise.
* **Archetype keys** encode every spec value a recipe reads (variant, length, height, depth,
  rails...) or whichever worker builds first wins (`KitCache`).
* **No visibility margins** on LOD hand-overs (see settlements.md): Godot's hysteresis hid
  whole cells whose centre sat in the margin band.
* **Interiors** are single-sided kit domes and boxes, so they get inner shells; their lights
  are interior-flagged (on by day, not turned into night glows).
* **Keep-outs.** The arctic sites and the Air Temple pinnacles publish exclusion circles
  (`plan.data.exclusions`) so open-world trees, rocks and props stay out of them.

## Tests and playtests

```
tools/test.sh test_settlements_wa
VIEWS=nwt_bay,nwt_gate,nwt_canal,nwt_palace,nwt_oasis,nwt_interior,nwt_aurora tools/playtest.sh settlements_wa_tour out 960x540
VIEWS=sat_far,sat_courtyard,sat_terrace,sat_bridge,sat_door,sat_sunset,sat_night_far tools/playtest.sh settlements_wa_tour out 960x540
tools/playtest.sh settlements_wa_walk out 960x540
ELEMENT=air tools/playtest.sh settlements_wa_world out 960x540
```

* Unit: plan counts and kinds, every cell of every settlement builds (LOD0 / LOD1 / LOD2, LOD2
  lighter; the stats above), cell build budget, no LOD margins, anchors contract (unique ids,
  required keys, every kind present, patrol routes), `settlement_at` / `district_at`,
  determinism, registration (providers, claims, skip tags, unregister), tutorial tag,
  arrival-flight clearance, and **probe-capsule walk tests over the real collision** (terrain
  heightmap + cell bodies; step ≤ 0.42 m, drop ≤ 1.2 m, slope ≤ 46°, capsule clearance): the
  Air Temple stairs, sanctum gateway, landing and both bridges; the 9 grand stairs; all 29
  canal bridges, the piers and the three interiors; out of both new-game spawns (air, water)
  in four directions.
* Playtests: the screenshot tour (any preset / renderer), the real player walking a bridge, a
  stair, a grand stair and into the healer hut, and a new game per element through the real
  world scene (hook registered, spawn on the settlement floor with no safety floor, walking).

## Known issues / next steps

* Performance numbers come from the software renderer (llvmpipe) on the CI box; no real
  phone was profiled. Water Tribe LOD0 cells are heavy (avg 53 k, max 114 k triangles); mobile
  relies on the 110 m LOD0 range.
* LOD hand-overs pop (no cross-fade). Far night glows use approximate spots, so glows shift
  slightly at `lod1_end`.
* Anchors are data only: no NPCs are spawned here (NPC module). The stables and landing have
  bison anchors but no bison (companions module).
* Interiors are open doorways (no doors, no interior reverb zone); canoes and ships do not bob.
