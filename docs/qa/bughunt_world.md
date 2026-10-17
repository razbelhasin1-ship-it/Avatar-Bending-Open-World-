# QA wave 4 — adversarial world bug hunt (`bughunt_world`)

Focus: the world, streaming, settlements, NPCs / quests, UI, save / settings and mobile. Method:
read the code of those modules critically (freed-instance access, typed reads of untrusted data,
save atomicity, quest state that outlives a quest or a reload, dialogue routing, held input when
a menu takes over, water / collision queries that disagree with what is drawn), then let the
**real player** loose on the real world with InputMap actions only: fast travel to every map
point, walk every main street / ramp / stair and every gate of every ring city, stand at every
quest prop / target / named NPC, watch every city's crowd, and fly the dragon twice across all
four nations while recording memory, node counts and frame times. Every suspicion was reproduced
(unit test or playtest), fixed at its root with the smallest change and kept as a regression test
(`tests/unit/test_bughunt_world.gd`, 15 tests; each fails on the old code - an expectation or the
runner's SCRIPT ERROR log check - except the settings / dialogue guards for refuted suspicions).

| # | Bug | Verdict | Fix (file:line) |
| --- | --- | --- | --- |
| 1 | Gameplay lake water used the lake's bounding radius while the renderer draws a (grown) polygon: dry ground inside the radius but under the lake level counted as deep water. Below the Thundering Steps falls the outlet gorge lies 15-18 m under the pool level: a player walking down it "swam" and was pulled up to the surface, 15 m into the air (y 62.9 -> 67.0 in the repro); companions, safe ground and travel treated dry land as lake | confirmed | water only inside the drawn outline and above the ground: `WorldRecords.lake_surface_polygon` (`src/world/data/world_records.gd:138`, cached at :153-158), `WorldData.get_water_height` (`src/autoload/world_data.gd:361-366`); the renderer uses the same polygon (`src/world/water/water_system.gd:221`) |
| 2 | The Water Tribe's two land gates could not be walked through: the Middle Tier's 1.3 m edge parapet ran straight through both gatehouse passages, and outside the east gate a 1.7 m ditch with a ~42 degree inner bank crosses the passage | confirmed (walk audit) | the edge walls leave the gatehouse's gap (`src/world/settlements/water_tribe/nwt_planner.gd:16, 317`); a low bridge over a dip outside a gate (`src/world/settlements/water_tribe/nwt_districts.gd:105-120`) |
| 3 | Air Temple stairs walled off: the 220 ramp kept its bearing 220 while the wall spans work in -180..180, so it got no gap - the courtyard and sanctum walls ran across both of its stairs (the walker stopped half way up, against a wall). Beside every other stair the ramp's side slopes pushed the wall face out at the gap end only: the chord next to the gap ran 15-28 degrees off and its deep body narrowed the sanctum stairs to 0.5-2 m | confirmed (walk audit) | bearings wrapped (`src/world/settlements/air_temple/sat_planner.gd:158`); default face over a stair gap (`sat_planner.gd:253-266`) |
| 4 | A swimmer could not climb out of the Water Tribe ring canal: the climb-out only tested a 1.8 m lift from the swimmer's feet (ledges ~0.5 m over the water) while the canal walkways stand 1.9 m over it behind a curb - the walker fell in at the end of the -100 ramp walk and swam forever | confirmed (walk audit) | `try_swim_exit` also tries a lift to `CLIMB_OUT_MAX` (2.3 m) over the surface, both lifts checked for head room and the ledge (`src/player/player_motor.gd:23, 343-362`) |
| 5 | Quest props picked up came back after every reload: the taken lists (`GameState.quests[q]["taken"]`) return from JSON as floats and `[0.0, 1.0].has(0)` is false - gathered moss / letters / clues could be picked up (and sold) again after each load, interact objectives counted twice | confirmed | the load turns the taken lists back into ints like the other quest records (`src/autoload/game_state.gd:234`) |
| 6 | Journal -> Abandon on a side quest kept the items it handed out (letter, parcel, incense); restarting handed out another, so every abandon left an unsellable quest item for good. Items gathered from the quest's props stayed while the props came back (gather, abandon, gather again, sell) | confirmed | `_take_back_handouts` on abandon: on-start `give_item`s and prop-gathered items, capped by what is held (`src/quests/quest_system.gd:333, 346`) |
| 7 | Saves: the temp file was renamed over the slot without checking it was written; no previous version kept; a slot whose JSON is damaged (or a crash between write and rename) lost the journey | confirmed | write read back and compared before the rename, the old slot kept as `.bak`, `read_slot` falls back `.json` -> `.tmp` -> `.bak` with a warning, `has_save` / `delete_save` know all three (`src/autoload/save_system.gd:47-93, 126-175`) |
| 8 | Damaged fields made a journey unloadable: a NaN (JSON stores `null`) or a string where a number belongs raised script errors in `GameState.from_dict` / `get_save_info` / migration (the slot list and Continue broke) | confirmed (real NaN round trip) | `_num` / `_arr` sanitising with the defaults, positions only when finite (`src/autoload/game_state.gd:210-276`, `src/autoload/save_system.gd:142`) |
| 9 | NPC that faded out (vanish) freed itself before the director pruned it; releasing its settlement cell read it into a typed variable: "Trying to assign invalid previously freed instance" on fast travel, the loop aborted and the rest of the cell's crowd records stayed registered | confirmed (audit) | untyped read + validity check, freed entries erased (`src/npc/npc_director.gd:98`) |
| 10 | The same vanished NPC looked up by a chatting partner (`NpcBrain._partner`): `live_npc` ran `is NpcCharacter` on the freed instance - "Left operand of 'is' is a previously freed instance" (twice in the Ba Sing Se walk) | confirmed (walk audit) | validity before `is` (`src/npc/npc_director.gd:140`); same order where a mount / companion can be freed: `src/ui/touch/touch_overlay.gd:555`, `src/ui/hud/hud.gd:290` |
| 11 | Released content cells left their instance buffer, mesh and material in the pooled MultiMeshInstance3D until reuse (up to 26 732 instances of long-gone cells held after one flight) | confirmed (flight) | emptied before pooling (`src/world/content/world_content.gd:619-627`) |
| 12 | Farmer Dao (giver and turn-in of Lost in the Millet) could not be found: every Agrarian Zone hamlet put its elder's anchor 3 m off the hamlet centre, where the first farmhouse stands - he spawned inside its collision and was pushed out 2 m under the ground (crowd workers / children likewise inside other farmhouses) | confirmed (quest audit) | the elder stands in front of the first farmhouse, crowd anchors inside a farmhouse are dropped (`src/world/settlements/earth_kingdom/bss_farmland.gd:43-70, 207, 250`) |
| 13 | The Whistling Caves' tablet ("at the cave mouth") lay 3 m under the Hundred Winds falls pool among the boulders - the cave mouth POI is on the pool floor: a swimmer got no closer than 3.7 m (out of the 2.6 m reach), only one boulder was close enough | confirmed (quest audit + rendered regression) | the prop rests on the boulders over the mouth (`data/quests/quests_air.gd:106-109`: offset y 6, the prop drops onto the first surface below) |
| 14 | Merge conflict found by the full suite: flow_qa ended a projectile whose caster was freed, bughunt_gameplay let it fly on and land sourceless - `test_projectile_outlives_its_caster` failed after the merge | confirmed (integration) | the shot flies on and lands sourceless; only a missing context ends it (`src/bending/bending_projectile.gd:158`); flow_qa's test asserts only that it ends quietly (`tests/unit/test_flow_qa.gd`) |

Refuted suspicions and checks that came out clean are listed under **Checked, clean**; what is
left open is under **Remains**.

---

## Tools

### World audit — `tests/playtest/scenarios/bughunt_world_audit.gd`

The real `WorldScene`, the real `PlayerCharacter`, InputMap actions only (move / sprint / jump /
interact; the camera yaw set like a mouse would). Ambient encounters off (`spawn_radius = -1`)
so fights don't interfere; saves into `user://saves_bughunt_world_audit`.

* `PART=travel` — every fast-travel point of the map (`MapModel.travel`, the map's Travel
  button): the arrival must be on dry floor (not in water, not inside a building or rock: capsule
  0.45-1.65 m against WORLD | CONSTRUCT), and the player must walk in 4 directions from it.
* `PART=walk` — every ring city: every ramp bearing from its lowest tier to its highest (main
  streets, stairs, ramps); every gate from outside into the city (Ba Sing Se: the record's
  outside point; the Dragon's Throat: the plan's road -> gatehouse -> stair -> Lower City; gates
  at a tier's arc end: along the ring; others: radial through the gate position). The walker
  sprints at the target; when it makes < 1.2 m in 1.5 s it logs a **block** (what is at knee /
  chest height with distance and surface normal, the step ahead, the tier), jumps and sidesteps
  like a player and gives up after 4 tries; it logs **drops** (> 4 m) and **rescues** (> 25 m in
  one step: fall net / respawn). Points go to `walk_points.json`. `CITY=a,b`, `WHAT=ramps|gates`,
  `RAMP=<bearing>` narrow it.
* `PART=tour` (rendered) — `POINTS=<walk_points.json>`: the player at each block / drop, looking
  along the walk (how every block was judged).
* `PART=npc` — every city: 20 s of every NPC in range: buried in geometry, walkers that want to
  move but have not moved for 3 s.
* `PART=quests` — every quest stage: every prop (spawned? on dry floor? reachable? does interact
  take it? does the objective complete?), every `go_to` (safe ground inside the radius completes
  it), every named NPC of a talk / escort objective (spawned, not buried, a floor to talk from).

### Long flight — `tests/playtest/scenarios/bughunt_world_flight.gd`

Fire element, the dragon called with G, mounted with F, jump to take off, flown like a player
(move_forward + sprint = boost, jump / descend to hold ~70 m over the ground, camera yaw to
steer) Fire Nation Capital -> Northern Water Tribe -> Ba Sing Se -> Southern Air Temple -> Fire
Nation Capital (~18 km a loop, `LOOPS=2` for the numbers below), circling low over every city
for 14 s. Every game second: static memory, objects, nodes, orphan nodes, resources, video
memory, active / released content cells, the MultiMeshInstance / mesh pools and the instances
the pooled MultiMeshes still hold, NPCs / enemies / wildlife, the worst frame. Checks: no orphan
nodes besides the content pools (< 60), pooled MultiMeshes hold nothing, every leg flown.

### Regressions — `tests/playtest/scenarios/bughunt_world_regressions.gd`

Rendered (`tools/playtest.sh bughunt_world_regressions <out> 960x540`, `PART=` a comma list):
`canal` (swim to the Water Tribe ring canal's wall, jump: out onto the walkway; it notes what
both climb-out lifts see - the 1.8 m one is blocked by the wall, the 2.3 m-over-the-water one is
free), `gorge` (down the gorge below the Thundering Steps pool: no swimming, standing, walking),
`tablet` (the Whistling Caves tablet read from above the pool), `dao` (Farmer Dao on the ground
in front of his house, talking).

---

## Findings in detail

### 1. Lake water outside the drawn lake

`WorldData.get_water_height` answered "lake level" for any point within `radius` of a lake centre
whose ground was below the level. The renderer (`WaterSystem.build_inland_water`) draws the lake
polygon grown by 8 % + 3 m. Lakes are irregular: inside the bounding circle but outside the
polygon there is dry ground, and next to falls pools it can be far below the level. At the
Thundering Steps (pool level 111.5) the outlet gorge (3187.6, 96.1, -879.2) is 15 m below it:
the motor saw deep water, switched to swimming and pulled the player to the surface - into the
air. Companions, `get_safe_ground` and travel used the same query. Now the polygon itself is
the test (cached per lake in the water index, bucket radius = the grown reach) and the renderer
uses the same helper, so gameplay water and drawn water are one shape.
Tests: `test_lake_water_only_where_it_is_drawn` (every unfrozen lake: no water at dry points
> 2 m below the level outside the drawn outline, still water at the centre),
`test_player_below_a_falls_pool_walks_instead_of_swimming`; playtest `regressions PART=gorge`.

### 2. Water Tribe land gates

The gatehouses (`NwtDistricts`) stand on the radial cuts at the ends of the Middle Tier's arc
(bearing +-112) and leave a +-16 m gap in their own 9 m end walls. `NwtPlanner._edge_radial`
lines the same cut with the tier's edge wall - a 1.3 m parapet where the ground beyond is level -
without a gap: it ran straight through both passages (floor + 0.4 m and + 1.6 m both blocked in
the walk audit, the rendered tour showed the walker against it). It now skips `GATE_GAP` around
every land gate on the cut. Outside the east gate the terrain has a 1.7 m ditch across the
passage's outer half (16.0 -> 14.2 within 2 m, back to 15.9 at 10 m out) whose inner bank is
~42 degrees (surface normal y 0.74): too steep to walk or jump up. Any dip deeper than 0.8 m
within 16 m outside a gate now gets a low `canal_bridge` (10 m wide, from the gate floor over the
dip), its deck level with the ground at its outer end (a first version 0.11 m above it stopped
the walker for 1.5 s at the deck's thin edge - the motor's step-up needs a steep face; the tier
floor rising 0.1 m onto the inner end is a walkable slope). Re-walk: both gates REACHED, 0 blocks,
the walker 1.9 m over the ditch on the deck. Test: `test_water_tribe_land_gates_are_open` (no wall in
either passage, ground or a bridge under it from 12 m in to 14 m out).

### 3. Air Temple stairs

`SatPlanner._find_ramps` stored the WorldData bearing (220) while `spans()` cuts gaps in
-180..180: the 220 ramp got no gap at the courtyard edge (rb 112) nor the sanctum edge (rb 46),
so both walls ran across its stairs - the walker stopped at r = 115 on the stair, 0.36 m from a
wall facing it. Separately, `_sample_faces` moves a wall face out to the foot of a blended slope;
beside a stair the ramp's own side slopes did that at the gap end only, so the chord next to the
gap ran diagonally (its yaw 15-28 degrees off radial) and its body (up to 16 m deep) swung into
the walkway: the sanctum stairs at -30 / 25 / 140 kept 1.75 / 2.25 / 0.5 m of their 9 m (the
140 walk stopped at the sanctum edge). Bearings are wrapped now and the default face is kept over
a stair gap plus the +-2 degree conservative window. Re-walk: all four ramps reach the sanctum.
Test: `test_air_temple_stairs_are_not_walled_off` (the widest free lane across every stair, at
61 points of the climb, 0.4 and 1.6 m over the steps, must be >= 2 m; all are now the full 9 m).

### 4. Canal swim trap

Found by the walk audit: the walker on the -100 ramp line fell into the ring canal near
(-723, -2583) and never got out - the canal water is at 14.2, the walkway at 16.1 behind a 1.8 m
wall with a curb, and the swim exit only tried a 1.8 m lift from the swimmer's feet (who float
~1.3 m under the surface), i.e. ledges up to ~0.5 m over the water. `try_swim_exit` now tries
1.8 m and then a lift to `CLIMB_OUT_MAX` (2.3 m) over the water surface, each requiring head room
(no `test_move` hit going up) and a free step forward onto the ledge at that height; the vault
velocity still comes from the measured ledge top. Higher walls (harbour quays) are left alone:
they have stairs / jump-out spots.
Tests: `test_swimmer_climbs_out_of_a_canal` (ledges 0.3 m, a 1.8 m wall with a 0.32 m curb,
2.2 m); playtest `regressions PART=canal`.

### 5. Quest props back after a reload

`QuestProps.mark_taken` records prop indices in `GameState.quests[q]["taken"][objective]`;
`is_taken` asks `list.has(i)` with an int. JSON brings every number back as a float and
`Array.has` does not match 1 with 1.0 - flow_qa's `_ints` conversion covered `stage`, `log` and
`objectives` but not `taken`. After any load every picked-up prop was back. One key added.
Test: `test_taken_quest_props_stay_taken_after_a_reload` (real save / load through the files).

### 6. Abandon kept the handouts

`Quests.abandon` reset the quest but kept what it gave. `_take_back_handouts` removes the
`give_item` items of the quest's start actions and, for every collect objective with props, the
items its taken props gave (taken x give), never more than the player holds (bought moss stays).
The props come back with the restart and progress counts what is really held.
Test: `test_abandoning_a_quest_takes_back_its_handouts` (Pale Moon Shrine incense x 3 abandons,
Healer's Moss gathered + bought).

### 7, 8. Saves

* `save_game`: JSON -> `.tmp`, flush, `get_error()` and a read-back compare; any mismatch keeps
  the old slot untouched (warning, `false`). The old slot is copied to `.bak`, then the temp is
  renamed over it (remove + rename where the platform refuses to rename over a file).
* `read_slot` tries the slot, then `.tmp` (a crash between write and rename), then `.bak`, each
  only if it parses to a dictionary with a valid element; a recovery is logged.
* `GameState.from_dict` takes every number through `_num` (finite int / float, else the
  default), arrays through `_arr`, strings / bools type-checked; companion bond / health ratio and
  the player position (only when finite) likewise. `get_save_info`, `latest_slot` and the version
  migration use `SaveSystem._num`.

Tests: `test_damaged_save_falls_back_to_the_previous_one`,
`test_save_interrupted_before_the_rename_is_recovered`,
`test_damaged_fields_do_not_make_a_journey_unloadable` (a real NaN through `JSON.stringify` ->
`null`, strings for numbers, wrong-typed arrays).

### 9, 10. Vanished NPCs still in the director's live table

`NpcCharacter.vanish()` fades and frees the NPC; `NpcDirector._update` prunes `_live` on its
next tick. In that window `remove_records` (a settlement cell released on fast travel) read the
entry into a typed variable (script error, loop aborted, records left behind) and `live_npc`
(asked by a chatting partner's brain every talk tick) evaluated `n is NpcCharacter` before
`is_instance_valid(n)` ("Left operand of 'is' is a previously freed instance"). Both read
untyped and check validity first. The touch overlay (`_mount_node`) and the HUD (companion
panel) had the same `x is T and is_instance_valid(x)` order on values that can be freed: swapped.
Test: `test_releasing_a_cell_with_a_vanished_npc` (vanish, look it up, release the cell).

### 11. Pooled MultiMeshInstances held their old cell

`WorldContent._release_now` put a released cell's MultiMeshInstance3D nodes in the pool as they
were: instance buffer, mesh and material of a cell long gone, until the node was reused. After
one flight the pool held 244-282 nodes with up to 26 732 instances. They are emptied now
(`instance_count = 0`, mesh and `material_override` cleared); `spawn_multimesh` sets everything
again on reuse. The memory effect is small (~1.7 MB of buffers at the peak; static memory over
each city was the same within 2 MB in the before / after flights) - it is about not pinning
released cells' meshes / materials.
Test: `test_released_cells_leave_nothing_in_the_pool`; the flight checks it on every visit.

### 12. Farmer Dao inside his farmhouse

The quest audit stands at every named NPC of a talk / escort objective: Farmer Dao (giver and
turn-in of Lost in the Millet) was "there" at (1524, 55.8, 142) - 2 m under the ground - with no
floor to talk from. `BssFarmland._hamlet` builds the first farmhouse on the hamlet centre and put
the elder's anchor 3 m off that centre, inside the house; the NPC spawned in its collision and
was depenetrated downward, under the heightfield (an NPC fully below a heightfield overlaps
nothing, so the director's 3 m fall net never fired). The elder now stands 2.5 m in front of the
first farmhouse, facing out, on the ground; a post pass drops crowd anchors that ended up inside
a farmhouse (a worker's spot 5 m in front of one house falling inside the next, the children's
spot near the centre) - quest-giver anchors keep their indices.
Test: `test_no_one_stands_inside_a_farmhouse`; playtest `regressions PART=dao`.

### 13. The Whistling Caves tablet under water

The cave POI (`at_whistling_caves`, "underground") opens on the floor of the Hundred Winds falls
pool (level 494.6, floor 491.5): the quest's tablet "at the cave mouth" (POI + (2.5, 0, 2.5))
was dropped onto the pool floor, 3 m under the surface between the landmark's boulders. The
quest audit found no floor to stand on near it; the rendered regression swam to it and got no
closer than 3.7 m (the prop's reach is 2.2 + 0.4 m, horizontal) - only from one boulder was it
readable. The prop target is raised 6 m: `QuestProps` drops a prop onto the first surface under
its point, so the tablet now rests on the boulders over the mouth, 1.2 m above the water (re-audit:
on a floor, not in water, not inside anything, taken by interact).
Playtest: `regressions PART=tablet`.

### 14. Merge conflict between flow_qa and bughunt_gameplay

Not a world bug, but it broke the integrated build: flow_qa made `BendingProjectile.step` end a
shot whose caster was freed; bughunt_gameplay made the shot fly on and land without a source.
Kept bughunt_gameplay's behaviour (a shot already in the air should land) and relaxed flow_qa's
test to what it was really about (no script error, the projectile ends).

---

## Walk audit (headless, real player, `PART=walk`, final runs)

| City | Ramps / main streets | Gates |
| --- | --- | --- |
| Northern Water Tribe | @55, @-100 reached (the -100 walk fell into the ring canal before fix 4); @0 stopped at the palace tier's terrain step (r 591, 281 / 384 m); @-55 stopped at a house on the upper tier (208 / 246 m); @100 stopped 7 m in at a house between its start and the stair foot. Every block on the way: braziers / fountains on the plazas at the stair heads, houses, a playing child | east, west: **closed** (fix 2), then reached |
| Ba Sing Se | @90, @270 reached; @0, @180, @228 stopped at r 310 against the Lower Ring plaza fountain on the avenue (7.2 m basin, 0.7 m high: walk around it) | 5 / 5 reached |
| Omashu | 3 / 3 reached (a 0.5 m terrain lip at r 69 on @90, passed) | causeway reached; bridge reached (the first runs started inside the deck slab - harness) |
| Fire Nation Capital | 4 / 4 reached (dragon statues / great braziers on the avenue plazas at r 305 / 372 sidestepped) | Dragon's Throat reached along road -> gatehouse -> stair |
| Crimson Harbor | 4 / 4 reached, 0 blocks | 3 / 3 reached (two momentary stalls on steps, passed) |
| Southern Air Temple | -30, 25 reached; 140 stopped at the sanctum edge (r 46) and 220 stopped half way up the courtyard stair (r 115) - **fix 3**, then 4 / 4 reached | landing gate: opens onto the steep snow slope of the mountain (no trail; the temple is reached by air or the pass road elsewhere) - by design |

No hole, drop through geometry or fall-net rescue anywhere in 25 ramp lines and 14 gates.

## NPC audit (`PART=npc`)

101 NPCs watched for 20 s in the six cities (29 full rigs): 0 buried in geometry, 0 walkers stuck.

## Quest audit (`PART=quests`)

Every quest stage with props / go_to targets / named talk and escort NPCs: 55 checks.

* All `go_to` objectives complete from safe ground inside their radius; all props spawn and are
  taken by interact, every collect / interact objective completes from its props.
* **Farmer Dao**: 2 m under the ground inside his farmhouse - **fix 12**.
* **Whistling Caves tablet** (`at_whistling_caves`): 3 m under the falls pool, no floor to read
  it from, out of a swimmer's reach - **fix 13** (re-audit: on the boulders, taken).
* **Novice's Glider** prop overlaps a terrace wall's collision a little; it spawns, shows and is
  taken normally.

## Long flight (headless, `LOOPS=2`, ~36 km, 965 samples)

* **No leak.** Memory follows what is loaded: 1081 MB at take-off over the capital, down to
  563-818 MB over the wilderness, 1000-1470 MB over the cities. The wilderness floor rises during
  the first loop (563 -> 766 MB) as each city's caches fill once, then stays (loop 2: 771-818 MB).
  The same city on loop 1 vs loop 2: Fire Nation Capital +3.8 MB / -75 objects / -81 nodes,
  Air Temple +7.1 MB / +129 objects, Ba Sing Se +77 MB, Water Tribe +170 MB - on loop 1 those two
  were visited before the later cities' caches existed (static memory is global), and the loop-2
  wilderness floor is flat, so these are the one-time cache fills, not growth. Resources 537 ->
  566, flat from the end of loop 1.
* **Nodes**: 1 750-6 720, back to the same level per place; orphan nodes = the content pools
  (MMI pool <= 299, mesh pool <= 235) + 42 from the start, nothing else.
* **Pools**: pooled MultiMeshes hold 0 instances (fix 11; 26 732 before).
* **Frames** (headless, CPU only): 65 160 frames, p50 4.8 ms, p95 21.3 ms, p99 31.4 ms, max
  212 ms; 46 frames > 50 ms, 33 > 100 ms - all while a city streams in under the dragon
  (settlement cells instantiating), none over the wilderness after the first approach.
* Streaming: cells released behind the flight (4 371 releases in 1 053 game seconds), 93-259
  active at any time.

---

## Checked, clean (refuted suspicions)

* **Fast travel into water / void**: all 38 map travel points land on dry floor, outside
  buildings, walkable in 4 directions (`PART=travel`, 0 findings). Only Sunflare Isle Pier
  arrives facing something (0.0 m straight ahead in 1 s, 2-5 m in the other directions).
* **Settings persistence**: every row of every settings tab (35+ options, a rebound key) changed,
  saved, defaults restored, loaded and applied again: all survive, master volume applied
  (`test_every_settings_row_survives_a_restart`).
* **Dialogue dead ends**: every quest's giver / turn-in conversation, in every stage, reaches the
  action that starts / advances / completes it (`test_no_dialogue_dead_ends_in_any_quest`; a quest
  whose NPC is busy with another active quest is retried after progressing that one).
* **Shop / currency**: no buy-sell arbitrage (every item sells for 45 % of its value and buys at
  >= its value); quest items are `sellable: false`; sparring XP is repeatable by design.
* **Quest state through save / load**: stages, logs, objective counts and tracking survive (the
  quests module's round trip test) - only the taken props did not (fix 5).
* **Journey Book input traps**: Back / the same key / Esc close every page; pages opened from the
  pause menu return to it; no page without a way out.
* **Touch overlay**: held stick / buttons are released when the game pauses, a dialogue or shop
  opens, the player mounts / dismounts or the overlay hides (`release_all`); every touch is
  tracked by its finger index; safe-area margins are applied.
* **NPCs in walls / stuck**: none (NPC audit). **Streaming**: no cell left behind, pools plateau.

---

## Remains (not fixed)

* **Selling quest-gathered items before abandoning**: the take-back is capped by what the player
  still holds, so moss gathered for Healer's Moss and sold before abandoning keeps its coins and
  the props come back on the restart - a small, slow farm. Closing it needs per-quest bookkeeping
  of sold items.
* **Touch controls "Off" on a touch-only device** (phone browser / iOS without keyboard): the
  pause menu is reached through the overlay's top bar; with the overlay off only backgrounding
  the app (focus loss pauses) brings the menu back. A guard (keep the pause button) would be a
  mobile-module change.
* **Frame spikes while a city streams in** (100-212 ms headless frames on arrival over a city):
  a perf_polish topic (main-thread cell instantiation), not a correctness bug.
* **Per-city caches stay for the session** (~200-250 MB of static memory once all four nations
  were visited; they plateau). Worth an eviction policy on low-memory phones.
* **Decorative centre pieces on avenues** (plaza fountains, statues, great braziers, planters)
  stop a player running straight up an avenue; they are meant to be walked around (7-26 m
  plazas) and never trap anyone.
* **Air Temple landing gate record**: `bearing` 0 while the gate stands at -29 (on the -30 ramp).
  Nothing in gameplay reads it (the map uses the position).
* **Sunflare Isle Pier** arrival faces an obstacle (walks fine sideways) - cosmetic.
* **The Whistling Wind Caves' mouth is under water** (the POI sits on the falls pool floor, the
  first metres of the tunnel count as pool water): entering the cave means diving through the
  pool. Probably intended ("below the eastern cliffs"); a world-data decision.

---

## Verification

* `tools/check.sh`: OK. `tools/test.sh`: 493 / 493 on the final code (`test_bughunt_world.gd`
  15 / 15; `test_settlements_wa` 16 / 16, `test_settlements_ef` 19 / 19, quests 25 / 25 after
  the settlement / quest changes).
* Every regression test was run against the old code once (temporary revert) and failed there:
  freed-NPC lookup (SCRIPT ERROR), pool, taken props, land gates, Air Temple stairs, farmhouse
  anchors; the earlier ones as recorded in their commits.
* Headless audits on the final code: `PART=walk` all cities (ramps + gates; final gate re-walks
  for Omashu, the capital, the Air Temple and the Water Tribe), `PART=npc` (0 findings),
  `PART=quests` (4 findings, all handled above; re-audit of the Whistling Caves: clean),
  `PART=travel` (0 findings). Flight `LOOPS=2`: PASSED (no orphans besides the pools, pooled
  MultiMeshes empty, every leg flown).
* Rendered (960x540, llvmpipe): `bughunt_world_regressions` (canal, gorge, tablet, dao) and the
  audit tours before / after the fixes - screenshots looked at one by one (the walk blocks above
  were all judged from them).
* Screenshots: `shots/bughunt_world/` in the session scratchpad (before / after of the Air
  Temple stair and the Water Tribe gates, the canal climb, the gorge, Farmer Dao, a plaza
  fountain block).
