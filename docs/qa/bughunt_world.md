# QA wave 4 — adversarial world bug hunt (`bughunt_world`)

Focus: the world, streaming, settlements, NPCs / quests, UI, save / settings and mobile. Method:
read the code of those modules critically (freed-instance access, typed reads of untrusted data,
save atomicity, quest state that outlives a quest, dialogue routing, held input when a menu
takes over, water / collision queries that disagree with what is drawn), then let the **real
player** loose on the real world with InputMap actions only: fast travel to every map point,
walk every main street / ramp / stair and every gate of every city, stand at every quest prop /
target / named NPC, and fly the dragon across all four nations while recording memory, node
counts and frame times. Every suspicion was reproduced (unit test or playtest), fixed at its
root with the smallest change and kept as a regression test (`tests/unit/test_bughunt_world.gd`,
10 tests; each fails on the old code - either an expectation or the runner's SCRIPT ERROR log
check).

| # | Bug | Verdict | Fix (file:line) |
| --- | --- | --- | --- |
| 1 | Gameplay lake water used the lake's bounding radius while the renderer draws a (grown) polygon: dry ground inside the radius but under the lake level counted as deep water. Below the Thundering Steps falls the outlet gorge lies 15-18 m under the pool level: a player walking down it "swam" and was pulled up to the surface, 15 m into the air (y 62.9 -> 67.0 in the repro); companions, safe-ground and travel treated dry land as lake | confirmed | water only inside the drawn outline and above the ground: `WorldRecords.lake_surface_polygon` (`src/world/data/world_records.gd:138`, cached at :153-158), `WorldData.get_water_height` (`src/autoload/world_data.gd:361-366`), the renderer uses the same polygon (`src/world/water/water_system.gd:221`) |
| 2 | NPC that faded out (vanish) freed itself before the director pruned it; releasing its settlement cell read it into a typed variable: "Trying to assign invalid previously freed instance" on fast travel, the loop aborted and the rest of the cell's crowd records stayed registered | confirmed (audit) | untyped read + validity check, freed entries erased (`src/npc/npc_director.gd:98`) |
| 3 | The same vanished NPC looked up by a chatting partner (`NpcBrain._partner`): `live_npc` ran `is NpcCharacter` on the freed instance - a SCRIPT ERROR (twice in the Ba Sing Se walk) | confirmed (walk audit) | validity before `is` (`src/npc/npc_director.gd:140`); same order in the touch overlay's mount lookup (`src/ui/touch/touch_overlay.gd:555`) and the HUD's companion read (`src/ui/hud/hud.gd:290`) |
| 4 | Saves: the temp file was renamed over the slot without checking it was written; no previous version kept; a slot whose JSON is damaged (or a crash between write and rename) lost the journey | confirmed | write is read back and compared before the rename, the previous slot kept as `.bak`, `read_slot` falls back `.json` -> `.tmp` -> `.bak` with a warning, `has_save` / `delete_save` know all three (`src/autoload/save_system.gd:47-93, 126-175`) |
| 5 | Damaged fields made a journey unloadable: a NaN (JSON stores `null`) or a string where a number belongs raised script errors in `GameState.from_dict` / `get_save_info` / migration (the slot list and Continue broke) | confirmed (real NaN round trip) | `_num` / `_arr` sanitising with the defaults; positions only when finite (`src/autoload/game_state.gd:210-275`, `src/autoload/save_system.gd:142`) |
| 6 | Journal -> Abandon on a side quest kept the items it handed out (letter, parcel, incense); restarting handed out another, so every abandon left an unsellable quest item for good. Items gathered from the quest's props stayed while the props came back (gather, abandon, gather again, sell) | confirmed | `_take_back_handouts` on abandon: on-start `give_item`s and prop-gathered items, capped by what is held (`src/quests/quest_system.gd:333, 346`) |
| 7 | A swimmer could not climb out of the Northern Water Tribe ring canal: the climb-out only tested a 1.8 m lift from the swimmer's feet (ledges ~0.5 m over the water) while the canal walkways stand 1.9 m over it behind a curb - the walker fell in at the end of the -100 ramp walk and swam forever | confirmed (walk audit) | `try_swim_exit` also tries a lift to `CLIMB_OUT_MAX` (2.3 m) over the surface, both lifts checked for head room and the ledge (`src/player/player_motor.gd:23, 343-360`) |
| 9 | Quest props picked up came back after every reload: the taken lists (`GameState.quests[q]["taken"]`) return from JSON as floats and `[0.0, 1.0].has(0)` is false - gathered moss / letters / clues could be picked up (and sold) again after each load, interact objectives counted twice | confirmed | the load turns the taken lists back into ints like the other quest records (`src/autoload/game_state.gd:233`) |
| 10 | Released content cells left their instance buffer, mesh and material in the pooled MultiMeshInstance3D until reuse (up to ~27 000 instances of long-gone cells after one flight) | confirmed (flight) | emptied before pooling (`src/world/content/world_content.gd:619-626`) |
| 8 | Merge conflict found by the full suite: flow_qa ended a projectile whose caster was freed, bughunt_gameplay let it fly on and land sourceless - `test_projectile_outlives_its_caster` failed after the merge | confirmed (integration) | the shot flies on and lands sourceless; only a missing context ends it (`src/bending/bending_projectile.gd:158`); flow_qa's test now only asserts it ends quietly (`tests/unit/test_flow_qa.gd`) |

Refuted suspicions and checks that came out clean are listed under **Checked, clean**.

Verification: see the end.

---

## Tools

### World audit — `tests/playtest/scenarios/bughunt_world_audit.gd`

The real `WorldScene`, the real `PlayerCharacter`, InputMap actions only (move / sprint / jump /
interact; camera yaw set like a mouse would). Ambient encounters off (`spawn_radius = -1`) so
fights don't interfere; saves into `user://saves_bughunt_world_audit`.

* `PART=travel` — every fast-travel point of the map (`MapModel.travel` like the map's Travel
  button): the arrival must be on dry floor (not in water, not inside a building or rock: capsule
  0.45-1.65 m against WORLD | CONSTRUCT), and the player must walk 4 directions from it.
* `PART=walk` — every city: every ramp bearing from its lowest tier to its highest (main
  streets, stairs, ramps), every gate from outside into the city (BSS: the record's outside
  point; the Dragon's Throat: the plan's road -> gatehouse -> stair -> Lower City; others: the
  radial / tangential axis through the gate position). The walker sprints at the target; when
  it makes < 1.2 m in 1.5 s it logs a **block** (what is at knee / chest height, the step in
  front, the tier), jumps and sidesteps like a player, and gives up after 4 tries; it logs
  **drops** (> 4 m) and **rescues** (teleports > 25 m: fall net / respawn). Points go to
  `walk_points.json`. `CITY=a,b` / `WHAT=ramps|gates` narrow it.
* `PART=tour` (rendered) — `POINTS=<walk_points.json>`: the player is put at each block / drop
  and photographed looking along the walk.
* `PART=npc` — every city: 20 s of every NPC in range: buried in geometry, walkers that want to
  move but have not moved for 3 s.
* `PART=quests` — every quest stage: every prop (spawned? on dry floor? reachable? interact
  takes it? the objective completes?), every `go_to` (safe ground inside the radius completes
  it), every named NPC of a talk / escort objective (spawned, not buried, a floor to talk from).

### Long flight — `tests/playtest/scenarios/bughunt_world_flight.gd`

Fire element, the dragon called with G, mounted with F, jump to take off, then flown like a
player (move_forward + sprint = boost, jump / descend to hold ~70 m over the ground, camera yaw
to steer) Fire Nation Capital -> Northern Water Tribe -> Ba Sing Se -> Southern Air Temple -> Fire
Nation Capital (~18 km), circling low over every city for 14 s. Every game second:
static memory, objects, nodes, orphan nodes, resources, video memory, active / released content
cells, the MultiMeshInstance / mesh pools and the instances the pooled MultiMeshes still hold,
NPCs / enemies / wildlife, the worst frame. CSV + summary: `<out>/flight.csv`, `flight.txt`.

### Regressions — `tests/playtest/scenarios/bughunt_world_regressions.gd`

Rendered: `PART=canal` (into the NWT ring canal, jump out onto the walkway) and `PART=gorge`
(walk down the gorge below the Thundering Steps pool: no swimming, standing, walking).

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
Test: `test_lake_water_only_where_it_is_drawn` (every unfrozen lake: no water at dry points
> 2 m below the level outside the drawn outline; still water at the centre),
`test_player_below_a_falls_pool_walks_instead_of_swimming` (PlayerSim at the gorge point),
playtest `bughunt_world_regressions PART=gorge`.

### 2, 3. Vanished NPCs (freed) still in the director's live table

`NpcCharacter.vanish()` fades and frees the NPC; `NpcDirector._update` prunes `_live` on its
next tick. In that window: `remove_records` (a settlement cell released on fast travel) read the
entry into a typed variable -> script error, loop aborted, records left behind; `live_npc` (asked
by a chatting partner's brain every talk tick) evaluated `n is NpcCharacter` before
`is_instance_valid(n)` -> "Left operand of 'is' is a previously freed instance". Both read
untyped and check validity first. The touch overlay (`_mount_node`) and the HUD (companion
panel) had the same `x is T and is_instance_valid(x)` order on values that can be freed (a
despawned mount / companion): swapped too.
Test: `test_releasing_a_cell_with_a_vanished_npc` (vanish, look it up, release the cell).

### 4, 5. Saves

* `save_game` now: JSON -> `.tmp`, flush, check `get_error()` and read it back; any mismatch
  keeps the old slot untouched (warning, `false`). The old slot is copied to `.bak`, then the
  temp is renamed over it (remove + rename when the platform refuses to rename over a file).
* `read_slot` tries the slot, then `.tmp` (crash between write and rename), then `.bak`, each
  only if it parses to a dictionary with a valid element; recovery is logged.
* `GameState.from_dict` takes every number through `_num` (finite int / float, else the default),
  arrays through `_arr`, strings / bools type-checked; companion bond / health ratio and the
  player position (only when finite) likewise. `get_save_info`, `latest_slot` and the version
  migration use `SaveSystem._num`.

Tests: `test_damaged_save_falls_back_to_the_previous_one`,
`test_save_interrupted_before_the_rename_is_recovered`,
`test_damaged_fields_do_not_make_a_journey_unloadable` (a real NaN round trip through
`JSON.stringify` -> `null`, strings for numbers, wrong-typed arrays).

### 6. Abandon kept the handouts

`Quests.abandon` reset the quest but kept what it gave. Now `_take_back_handouts` removes the
`give_item` items of the quest's start actions and, for every collect objective with props, the
items its taken props gave (taken count x give), never more than the player holds (bought moss
stays). The props come back with the restart and progress counts what is really held.
Test: `test_abandoning_a_quest_takes_back_its_handouts` (Pale Moon Shrine incense x3 abandons,
Healer's Moss gathered + bought).

### 7. Canal swim trap

Found by the walk audit: the walker on the NWT -100 ramp line fell into the ring canal near
(-723, -2583) and never got out - the canal water is at 14.2, the walkway at 16.1 behind a
1.8 m wall with a curb, and the swim exit only tried a 1.8 m lift from the swimmer's feet (who
float ~1.3 m under the surface), i.e. ledges up to ~0.5 m over the water. `try_swim_exit` now
tries 1.8 m and then a lift to `CLIMB_OUT_MAX` (2.3 m) over the water surface, each requiring
head room (no `test_move` hit going up) and a free step forward onto the ledge at that height;
the vault velocity comes from the measured ledge top as before. Higher walls (harbour quays)
are left alone: they have stairs / jump-out spots.
Tests: `test_swimmer_climbs_out_of_a_canal` (ledges 0.3 m, a 1.8 m wall with a 0.32 m curb,
2.2 m), playtest `bughunt_world_regressions PART=canal`.

### 8. Merge conflict between flow_qa and bughunt_gameplay

Not a world bug, but it broke the integrated build: flow_qa made `BendingProjectile.step` end a
shot whose caster was freed; bughunt_gameplay made the shot fly on and land without a source.
Kept bughunt_gameplay's behaviour (a shot already in the air should land) and relaxed flow_qa's
test to what it was really about (no script error, the projectile ends).

---

## Checked, clean (refuted suspicions)

* **Fast travel into water / void**: all 38 map travel points land on dry floor, outside
  buildings, walkable in 4 directions (audit `PART=travel`, 0 findings). Only Sunflare Isle Pier
  arrives facing something (0.0 m straight ahead in 1 s, 2-5 m in the other directions) - cosmetic.
* **City walks** (`PART=walk`, all 6 ring cities, 25 ramp lines, 14 gates): no hole, no drop, no
  rescue anywhere; every block was looked at (rendered tour) - plaza fountains / statues /
  braziers / benches in the middle of a street, houses between a walk line and a stair foot,
  NPCs in the way, a patrol on the Omashu bridge. Gates: all reached (Omashu's bridge once the
  harness started on the deck; the Dragon's Throat along its road and stair). See the table below.
* **Settings persistence**: every row of every settings tab (35+ options, a rebound key) changed,
  saved, defaults restored, loaded and applied again: all survive, master volume applied
  (`test_every_settings_row_survives_a_restart`).
* **Dialogue dead ends**: every quest's giver / turn-in conversation, in every stage, reaches the
  action that starts / advances / completes it (`test_no_dialogue_dead_ends_in_any_quest`; a quest
  whose NPC is busy with another active quest is retried after progressing that one).
* **Shop / currency**: no buy-sell arbitrage (every item sells for 45 % of its value, buys at >=
  its value); quest items are `sellable: false`; sparring XP is repeatable by design (+40 per bout).
* **Journey Book input traps**: Back / the same key / Esc close every page; pages opened from the
  pause menu return to it; no page reachable with no way out.
* **Touch overlay**: held stick / buttons are released when the game pauses, a dialogue or shop
  opens, the player mounts / dismounts or the overlay hides (`release_all`); every touch is
  tracked by its finger index; safe-area margins are applied.
* **Streaming**: content cells are released behind the flight, pools plateau (see the flight
  numbers), no orphan nodes pile up.

---

## Walk audit results (headless, `PART=walk`)

FLIGHT_AND_WALK_TABLE

---

## Long flight (headless)

FLIGHT_SECTION

---

## Remains (not fixed)

* **Selling quest-gathered items before abandoning**: the take-back is capped by what the player
  still holds, so moss gathered for Healer's Moss and sold before abandoning keeps its coins and
  the props come back on the restart: a small, slow farm (a few moss per restart at the sell price).
  Closing it needs per-quest bookkeeping of sold items; left as is.
* **Touch controls "Off" on a touch-only device** (phone browser / iOS without keyboard): the
  pause menu is reached through the overlay's top bar; with the overlay switched off only
  backgrounding the app (focus loss pauses) brings the menu back. The setting is labelled for
  controller / keyboard players; a guard (keep the pause button) would be a mobile-module change.
* **Frame spikes when a city streams in** (headless numbers, see the flight): 100-180 ms frames
  while arriving over a city (settlement cells instantiating) - a perf_polish topic, not a bug.
* **Decorative centre pieces on avenues** (plaza fountains, dragon statues, great braziers,
  planters) stop a player running straight up an avenue; they are meant to be walked around and
  are 7-26 m wide plazas, so nothing traps a player. A designer may want clear centre lines.
* **Air Temple landing gate record**: `bearing` 0 while the gate stands at -29 (on the -30 ramp).
  Nothing in gameplay reads it (the map uses the position); the audit uses the position.
* **Sunflare Isle Pier** arrival faces an obstacle (walks fine sideways) - cosmetic.
* **Sparring XP** is repeatable (+40 per bout) - by design (training), not an exploit worth
  closing.

---

## Verification

VERIFICATION_SECTION
