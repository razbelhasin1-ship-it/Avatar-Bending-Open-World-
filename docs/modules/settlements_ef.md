# Settlements II — Earth Kingdom + Fire Nation (`settlements_ef`)

The great cities of the Earth Kingdom and the Fire Nation and their villages, built on the shared
settlement framework ([settlements.md](settlements.md): registry, plans, streaming providers,
anchors API, budgets) and the worldcontent building kit, laid out from the WorldData city and
village records.

| | |
| --- | --- |
| Earth Kingdom | `src/world/settlements/earth_kingdom/`: `BssPlanner` + `BssDistricts` + `BssFarmland` (Ba Sing Se), `OmashuPlanner` + `OmashuCity`, `EkVillagePlanner` + `EkVillages`, `EkRingPlanner` (EK house hooks), `EkBuilder` (dispatch + extras + glows), recipes `EkWalls`, `EkHomes`, `EkCivic`, `EkPlaces`, `EkPalace`, `EkFarm` (+ `EkSpinner`), `EkProps`, `EkStyle` |
| Fire Nation | `src/world/settlements/fire_nation/`: `FncPlanner` (capital), `FhPlanner` (Crimson Harbor), `FnVillagePlanner`, `FnRingPlanner` (FN house hooks, street lights, courtyard trees), `FnBuilder`, recipes `FnWalls`, `FnHomes`, `FnCivic`, `FnPalace`, `FnHarbor`, `FnPlaces`, `FnVillage`, `FnStyle` |
| Shared (common, added) | `RingCityPlanner` (ring-city bands + measured step walls), `SettlementLayout` (footprint fits / reserve, terrain face search, chords), `ArrivalClearance` (the arrival camera path), `RoofsLite` (cheap curved roofs); `KitX` additions (`emblem_earth`, `emblem_fire`, `prism_x`, banner `res`), `SettlementFx.PLANTS` + oak / palm / tropical |
| Settlement ids | `&"ba_sing_se"`, `&"omashu"`, `&"ek_villages"` (Full Moon Bay, Northreach, Millet Hollow, Cedar Rest), `&"fire_nation_capital"`, `&"fire_harbor"` (Crimson Harbor), `&"fn_villages"` (Saltspark, Ashleaf Terraces, Sunflare Isle) |
| Tests | `tests/unit/test_settlements_ef.gd` (19 tests: plan counts, every cell builds at every LOD with budgets, anchors contract, lookups, claims + the tutorial's kata-grounds skip tag, the earth / fire arrival flights swept against the cities' collision, the spawns, probe-capsule walks over wall stairs, gates, grand stairs, interiors, the Omashu bridge, the gorge stair + gatehouse, the palace axis, harbour stairs, piers and gates) |
| Playtests | `settlements_ef_tour` (screenshot tour, `VIEWS=a,b`, `PRESET=`, `HOUR=`), `settlements_ef_world` (new Earth / Fire game through the real world scene: arrival flight, spawn inside the city on real ground, walk; `ELEMENT=earth|fire`) |
| Dev scene | `godot --path . -- --scene=res://scenes/dev/settlements_ef.tscn` (as `settlements_wa`: RMB look, WASD/QE fly, Shift x6, T +1 h, N night, P stats; F1–F12 + `set_view(name)` for the views in `ef_dev.gd`) |

All six ids are registered by the settlements world hook with the Settlements I ones. The
tutorial passes `skip_tags = [&"airball_court", &"flame_kata_grounds"]` so its own training
grounds replace the Air Temple court and the capital's Flame Kata Grounds.

## Ba Sing Se (`&"ba_sing_se"`)

The WorldData ring layout: the Outer Wall (r ≈ 700), the Agrarian Zone, the Inner Wall (r ≈
400), the Lower / Middle / Upper Rings and the palace, five avenues with gates. One plan:
≈ 2960 pieces, ≈ 1740 anchors, 112 cells, ≈ 0.35 s.

| Part | What is built |
| --- | --- |
| Outer / Inner Wall | battered stone chords per ~20 m (plinth, string course, grooves, merlons with copings, inner parapet, buttresses, arrow slits, doorways, lanterns, green-gold banners tilted to the batter), bastions (`wall_tower`), a **great gate** on every avenue (twin towers, lintel with the earth emblem, open leaves, gate hall with two hip roofs, giant banners), wall stairs up to the wall walk clockwise of each gate (one chord past the gatehouse, infill against the battered face, a landing through a gap in the inner parapet), patrols on the wall walks |
| Agrarian Zone | fields from the WorldData farm tiles, 30 hamlets (farmhouses, granary, haystacks, orchards), 18 windmills and 15 water wheels with spinning sails / wheels (`EkSpinner`, near only), canals along the avenues with footbridges, oak rows, scarecrows, field huts, carts, Yuelan Lake pier with rowboats |
| Lower Ring | dense row houses / tenements / shacks on ring bands with lanes, markets with stalls along the avenues, the **tea shop** (enterable) |
| Middle Ring | crenellated ring wall on the measured step, town houses, courtyard houses, teahouses, plazas (fountain, incense burner), parks, the **earthbending training hall** (enterable) |
| Upper Ring | balustraded ring wall, mansions in gardens, cypress-lined ring avenue, the overlook where the earth arrival lands (the spawn) |
| Palace | podium, three-tiered green-gold throne hall, side halls, gate, pagodas, gardens, the palace-edge balustrade; grand stairs + ramp cheeks over the avenue ramps, paifang gate arches |

## Omashu (`&"omashu"`)

The mountain city: the King's Summit, High / Market / Gate Terraces stepped up the mountain in
sandstone, nine grand stairs over the ramps, the edge wall along the chasm with bastions and two
gatehouses, the **Great Bridge** (claimed from the generic bridge builder; a walkable deck with a
gentle hump from inside the bridge gatehouse to the far rim, crenellated parapets, lanterns,
piers down to the chasm floor), three **mail chutes** spiralling down from the summit (support
pillars except over stair avenues) to the chute station at the WorldData landmark, the palace
facing the bridge, markets, plazas, patrols. ≈ 1580 pieces, 877 anchors.

## Earth Kingdom villages (`&"ek_villages"`)

One district each: **Full Moon Bay** and **Northreach** (port towns: market square, house rings,
the inward retaining wall of the upper terrace with grand stairs, harbour quays with stairs,
piers, sampans, boathouses, fish racks, a lighthouse, warehouses; the ferry landing kept clear),
**Millet Hollow** (farmsteads round the green, granaries, a windmill, vegetable plots,
orchards), **Cedar Rest** (timber houses round a shrine, a sawmill, lumber piles, cedars).

## Fire Nation capital (`&"fire_nation_capital"`)

The caldera city: the palace tier (146 m), the Palace Terrace (138), the Noble Quarter (124)
and the Lower City (112) on the caldera floor, four ramps (0 / 57 / 120 / 240), the Dragon's
Throat gorge at bearing 57. One plan: ≈ 2070 pieces, ≈ 1430 anchors, 41 cells, ≈ 0.25 s.

| Part | What is built |
| --- | --- |
| Tier walls | basalt retaining walls on the measured step faces: red frieze with gold edges, flame-tipped merlons, brazier niches, red flame banners (`fn_tier_wall`, style `crenel`); the palace enclosure is red plaster under black tile coping with a gold band (style `palace`) |
| Stairs | a basalt grand stair over every ramp of every step (red-gold copings, brazier pillars at the foot and top); on the palace step the stairs cover the step itself (the ramps climb on into the palace tier as gentle terrain slopes) |
| Royal Palace | the axis from the **Plaza of the Sun** (sun monument: gold sun with flame rays on a column in a ring of great braziers, embers, crackle): a grand stair up the palace step, the three-opening **gate pavilion** with dragon statues, the courtyard of flame pillars, the three-level podium with its stair, the **throne hall** (deep red porch, gold doors and flame emblems, three black roofs with gold ridges and flame finials, two spire towers rising out of the podium); side halls between the ramps, the royal garden with the turtle-duck pond |
| Palace Terrace | townhouses and noble houses on three bands, temples, gardens, the fire element's **spawn plaza** (braziers behind the player, nothing ahead), street lamps and braziers |
| Noble Quarter | walled noble compounds (gate, main hall on a podium, side hall, turtle-duck pond, courtyard trees batched per block), the **Flame Kata Grounds** (scorched drill yard, braziers, practice posts, master's dais; `spec.tag = &"flame_kata_grounds"`), the **firebending dojo** and a **noble's house** (enterable, interior lights), gardens |
| Lower City | dense houses (cream / ochre / red-washed walls, charcoal and red tiles, shop fronts with awnings), townhouses, markets along the four avenues, plazas with a great brazier or a dragon statue, radial lanes |
| Dragon's Throat | a stair from the Lower City down into the gorge (a landing over the crumbling lip of the caldera floor, the foot on the road where it bends), a gate arch at the top; the **gatehouse** across the gorge (twin basalt towers with black-roofed watch pavilions, flame emblem lintel, iron-studded leaves, giant banners, braziers) and curtain walls climbing the gorge sides |

## Crimson Harbor (`&"fire_harbor"`)

The navy port: the basin (r < 160, floor −9), the Quayside (3), the Lantern Steps (16), the
Harbor Market (32) and the Admiralty Tier (52) rising outward on the west half; the ramps of the
gate road run as twins side by side. ≈ 1270 pieces, ≈ 580 anchors, 23 cells.

| Part | What is built |
| --- | --- |
| Basin | basalt quay chords on the measured basin edge (mooring rings, bollards), 7 stone piers with the Fire Navy's **ironclad warships** moored alongside (riveted dark steel, ram bow, red sheer stripe, command tower, smokestacks with smoke on some, catapult, flags) and 3 more at anchor (clear of the Full Moon Bay ferry's route), two **moles** over the shoals framing the harbour mouth with **watchtowers** (lantern rooms) |
| Quayside | cranes along the quay edge (jibs over the water), coal heaps, crates, carts, sooty warehouses on two bands; dock workers |
| Lantern Steps / Harbor Market | house bands, **lantern strings** across the streets (red paper lanterns), lamps and braziers, the market street with two rows of stalls |
| Admiralty | the admiralty hall with flame pillars and a parade ground over the harbour, officers' houses with courtyard trees, a harbour watchtower |
| Walls, gates | inward-facing tier walls (the lower side is the basin), grand stairs per ramp (one wide stair where the twin ramps overlap at the quay), the town wall along the upper edge with **three gatehouses**; short stairs with landings where the gate-road terrain steps up at the passage |
| Ferry | the port quay and the ferry's berth (worldscene FerryDock / FerryBoat) stay clear (tested); the `fn_crimson_harbor` dock POI is claimed |

## Fire Nation villages (`&"fn_villages"`)

* **Saltspark** (fishing village): fishers' huts and houses round a brazier square, salt
  evaporation pans on the seaward side, fish racks, boats drawn up, a fire shrine.
* **Ashleaf Terraces** (tea village): tea farmers' houses round the square, rings of clipped
  tea hedges on the outer pad, drying sheds, a fire shrine, tea pickers.
* **Sunflare Isle** (resort): a lawn court with the great garden and a temple pavilion, hot
  springs with steam, thatched cabanas, palm rows, white villas with red verandas on the upper
  terrace, stone stairs up the terrace slope, lanterns.

## Data formats (`plan.data`)

| key | settlements | value |
| --- | --- | --- |
| `spawn`, `spawn_yaw` | BSS, capital | the element's WorldData spawn inside the city |
| `palace` | BSS, Omashu, capital | `{center, yaw, ...}` (capital: `courtyard`, `throne_hall`) |
| `stairs` | all ring cities | `[{bearing, foot, top}]` grand stairs (walk tests) |
| `gates` | BSS, Omashu, harbor | `[{id, bearing, position, inside, outside, ...}]` |
| `wall_stairs` | BSS | `[{wall, foot, top, path: PackedVector3Array, bearing}]` |
| `interiors` | BSS, capital | `[{kind, position, yaw, d}]` (enterable buildings) |
| `bridge` | Omashu | `{city, rim, yaw}` |
| `gorge_gate` | capital | `{position, yaw, inside, outside, stair_top, stair_foot}` |
| `kata` | capital | `{position, yaw}` of the Flame Kata Grounds |
| `ferry_quay`, `ferry_berth` | harbor | the kept-clear ferry landing |
| `<tier>_faces` | ring cities | measured step faces `[[bearing, r], ...]` |
| `exclusions`, `claims` | | keep-out circles, claimed WorldData features (`omashu_great_bridge`, `ek_mail_chutes`, `fn_crimson_harbor`, EK dock POIs) |

Anchor kinds used here: `home`, `market_stall` (with `goods`), `guard_post`, `patrol`,
`trainer`, `student`, `quest_giver` (Earth King, Fire Lord, herald, gatekeepers, harbour master,
admiral, elders, sages, resort keeper — see `tags`), `worker` (docks, cranes, salt pans, tea),
`fisher`, `gardener`, `idle`, `child_play`; interior anchors carry `interior: true` and
`building`.

## Night

Lamps, lanterns, lit windows and braziers become near night glows; far cells use the builders'
`piece_glows` (braziers, lamp posts, lantern strings, gate towers, palace windows, watchtowers,
warship lanterns). The Fire Nation braziers are deep orange-red glow geometry with budgeted
lights; embers rise over the palace's flame pillars, the Plaza of the Sun and the kata grounds.

## Performance (measured, `test_settlements_ef`, high preset)

| id | cells | worst cell build | LOD0 tris avg / max | LOD1 avg | LOD2 avg |
| --- | --- | --- | --- | --- | --- |
| ba_sing_se | 112 | 175 ms | 22.0k / 72k | 6.0k | 0.8k |
| omashu | 28 | 148 ms | 44.1k / 95k | 13.1k | 2.0k |
| ek_villages | 34 | 55 ms | 23.2k / 60k | 8.1k | 1.0k |
| fire_nation_capital | 41 | 134 ms | 33.1k / 81k | 13.8k | 1.9k |
| fire_harbor | 23 | 98 ms | 30.6k / 86k | 12.2k | 1.4k |
| fn_villages | 18 | 48 ms | 10.7k / 35k | 4.0k | 0.8k |

Cells build on worker threads (the frame never waits); archetypes (`arch`) are cached per LOD
and merged. LOD0 draws only to `lod0_end` (110–300 m), LOD1 to `lod1_end`, the 4x far cells
carry the silhouettes (Ba Sing Se's walls, the caldera city, the harbour) to the view distance.
Low preset / Mobile and Compatibility renderers render the same content with the smaller
budgets of `SettlementSettings`.

## Decisions

* **Measured terrain, not nominal radii.** The world generator blends tier steps and ramps
  into the heightmap; walls stand on the faces found by `SettlementLayout.face_r` (binary
  search for the mid height, smoothed over neighbouring chords), stairs on the ramps the
  generator carved. Where the terrain is rough (the gorge mouth below the caldera floor, the
  harbour gate roads) a stair gets a **landing** 0.15 m above the higher floor and starts on
  the road itself.
* **Retaining walls both ways.** `RingCityPlanner.step_wall` faces the lower side whichever
  way it lies (cities step down outward, Crimson Harbor and the terraced villages step down
  inward).
* **Arrival flights.** `ArrivalClearance` replays the arrival cinematic's Bezier; planners only
  place tall pieces where the camera passes ≥ 6 m clear (tested with a swept 1.2 m sphere
  against the cities' real collision for earth and fire).
* **Walk tests drive the layout.** The probe-capsule walker (copied from Settlements I) found
  real problems that are fixed: wall stairs boxed in by gatehouses, a gap between Omashu's
  gatehouse and the bridge deck, chute pillars and pagodas on stair landings, the palace
  stair ending short of the palace floor, a house band across a gate passage, the admiralty on
  an avenue, the merged harbour stair over a cliff strip.
* **Twin ramps.** Crimson Harbor's gate road has two ramps 3° apart: one wide stair where they
  overlap (at the quay), separate stairs where a cliff strip divides them.
* **Batched courtyard trees.** Noble compound trees are collected into one `tree_row` piece per
  64 m block and species (one MultiMesh node instead of one per house).
* **Fire colours.** The kit's glow shader brightens emission ×2.6 at night; FN flames use deep
  red-orange vertex colours so they stay fiery instead of washing to white.

## Known issues / next steps

* Brazier flames still read pale yellow at night close up (the shared glow shader's night
  energy); far glows are fine.
* The Fire Lord's palace is modest against the 900 m caldera: the palace tier (r 55) is cut by
  four terrain ramps from r 30, so the podium (56 × 46 m) fits between them; its corners sit
  over the ramps' upper ends (a skirt hides the gap).
* Omashu's badgermole statue reads as a blob; Millet Hollow and Cedar Rest are sparse with
  bare paving; Full Moon Bay's harbour is plain.
* Mail chutes have no support pillar where they span a stair avenue.
* The WorldData ferry route Crimson Harbor → Sunflare is a straight line over the town (the
  travel system's concern).
* Arrival clearance removes some houses under the flights (south of the BSS palace, east of the
  FN palace), leaving open plazas there.
