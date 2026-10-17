# QA wave 4 — cross-module integration fixes (`integration_fixes`)

Eight integration gaps reported by the module agents were verified one by one in the merged
build, fixed at their source with the smallest change that makes the whole feature work, and
covered by tests (`tests/unit/test_integration_fixes.gd`, 13 tests) and two playtests
(`integration_fixes_fires`, `integration_fixes_enemies`). Each section says what was checked,
what was found, what changed (file:line at the time of writing), the evidence, and what remains.

| # | Gap | Verdict | Fix |
| --- | --- | --- | --- |
| 1 | World fires are static meshes | confirmed | `WorldFires`: interactive, budgeted, shader-masked baked fires |
| 2 | Enemy benders don't use the new techniques | confirmed | techniques in `EnemyAbilities.LOADOUTS` + archetype data; two air archetypes |
| 3 | Practice may be counted twice | **not reproduced** | test proves exactly one count per use for all 28 techniques |
| 4 | Level-up shows two messages | confirmed | GameState toast removed; banner, or one HUD toast where no banner |
| 5 | Water Tribe interior anchors face +Z | confirmed (also Ba Sing Se, Fire Nation) | facings fixed in the planners; NPC indoor workaround removed |
| 6 | DialogueBox close/open fade race | confirmed | `open()` kills the close tween; runner wait removed |
| 7 | Burn ticks shake the camera | confirmed | ticks (`dot` / `no_hitstop`) never shake; softer flash / vignette / haptics |
| 8 | New-game onboarding loadout | two bugs found | signatures no longer fill technique slots; locked-signature HUD hint; live reload |

---

## 1. World fires react to bending

**Checked.** Settlement, outpost and POI braziers / torches / lanterns / campfires are merged
into streamed cell meshes (`BuildingKit` glow surface + `LightBudget` lights + settlement night
glow sprites). Nothing joined the `ignitable` / `extinguishable` hooks: Water Surge over a Water
Tribe brazier did nothing.

**Design.** A real node per baked fire would cost thousands of nodes per city and could not hide
the baked flame anyway. Instead:

* **Records**: `BuildingKit.add_fire(pos, kind, radius)` (`src/world/buildings/building_kit.gd`);
  `brazier()` and flame-lit `lantern()` styles record themselves at LOD0 (ice lanterns don't burn);
  fire-pit recipes call it (`nwt_props.gd` fire pit, `nwt_places.gd` family-home hearth,
  `outpost_builder.gd` camp fire, `poi_structures.gd` camp fire). `KitResult.fires` is merged by
  `KitResult.merge` / `KitMerger.add` and registered with `WorldFires` wherever lights are made
  (`KitResult.instantiate` / `add_to_payload`, option `fires` = `lights` by default);
  `SettlementProvider.build_cell` registers its LOD0 cell's fires itself.
* **Registry**: `WorldFires` (`src/world/fires/world_fires.gd`, static, 32 m grid) keeps the spots
  of every streamed cell and forgets them when the cell root leaves the tree.
* **State**: everything is lit as baked, except 35 % of braziers (picked by position) that stand
  cold by day (lit at dusk with a flare) so a firebender has fires to light. Runtime changes are
  timed overrides near the camera (90 m): put out -> relights after 30-60 s (campfires 45-60,
  lanterns 25-35, braziers 30-45); a cold brazier lit by day -> burns 60-90 s. Beyond 115 m an
  override is dropped (the fire shows its baked state) - consistent at every distance.
* **Look**: no new meshes. Fires that are out go into a `fire_mask` uniform (vec4[32]) of the two
  shared materials: `kit_glow.gdshader` collapses the flame geometry above the flame base into a
  charred coal bed (lantern paper just goes dark), `night_glow.gdshader` collapses the night-glow
  sprite, `LightBudget.suppress` keeps the light off, the campfire's smoke / embers (`PropFx`
  group `fire_fx`) stop. So the night glows always match the lit state.
* **Interaction**: the nearest fires within 60 m (8 / 12 / 16 / 24 by detail level) get a pooled
  `WorldFireSpot` (`src/world/fires/world_fire_spot.gd`) at the flame: groups `ignitable` /
  `extinguishable` with the hook methods (FireEnv.heat / ignite_at, WaterEnv.extinguish,
  AirEnv / FireEnv.extinguish) plus a `FireHitProxy` (water hits douse, heavy / force >= 4 air
  hits and heavy earth hits douse, fire hits ignite). State changes from hit callbacks apply at
  the end of the frame (no area added / removed during a physics query). Signals
  `fire_ignited` / `fire_extinguished` and `WorldFires.ignite_at / extinguish_at` for scripts.
* **Cost**: 5 Hz update over the spots within 90 m (grid lookup), at most 24 stand-ins (8 on
  the mobile preset, each one Area3D sphere), one uniform array update per state change, a
  loop of `fire_mask_count` (usually 0-3) iterations in two shaders. No new draw calls.

**Evidence.** `test_world_fires_kit_records_and_registry`, `test_world_fires_douse_ignite_relight`
(hook douse, hit-proxy douse, fire relight, relight timer, gust vs breeze, smoke stop / restart,
lantern darken-only, cold brazier day / night / burn-out, stand-in budget, far drop, material
uniforms and light suppression), `test_player_bending_reaches_world_fires` (a real player at
3.7 m from a brazier on a plinth: Air heavy attack douses it, Water light attack douses it, Fire
light attack lights it - this caught the stand-in's hit sphere hidden inside the brazier's own
collision box, see "fixed during the playtest" below), `test_settlement_cells_record_fires` (a
real Water Tribe cell's braziers recorded at LOD0, none at LOD1). Playtest `integration_fixes_fires` at night in the
Northern Water Tribe (real new game, 960x540, Forward+): 368 fires registered around the
spawn; a plaza brazier on a plinth burns at night (`fire_1_lit_night`); the player's Water Surge
puts it out with steam (`fire_2_doused_steam`), its flames collapse into dark coals, its night
glow and light go out while the next brazier's stay on (`fire_3_out_night`); Fire Burst next to
it relights it with a flare (`fire_4_relit_by_fire`); an airbender's Air Push blows it out
(`fire_6_blown_out`) and it relights by itself when its timer (33 s) runs out
(`fire_7_relit_timer`); at noon a cold brazier stands unlit (`fire_8_cold_by_day`) and Fire
Burst lights it (`fire_9_lit_by_day`). PLAYTEST PASSED, all 20 checks.

**Fixed during the playtest.** The first run failed "an air blast blew it out": the stand-in's
hit sphere centre sat inside the brazier bowl's own collision box, so line-of-sight checked
attacks (water whip, air blast) hit the bowl first. `WorldFireSpot.bind` now lifts the sphere
into the flame (`minf(radius, 0.5)` above the base) and sizes it `radius + 0.45` (0.6..1.0 m);
`test_player_bending_reaches_world_fires` pins it.

---

## 2. Enemy benders use the element techniques

**Checked.** `EnemyAbilities.LOADOUTS` filled only `technique_1`; `FireKit` / `EarthKit` /
`AirKit.enemy_attacks()` existed but no archetype used them, Water had none, no Air archetype
existed and the air trainer's spar partner was a knife bandit in monk clothes.

**Fixed.**
* `src/enemies/enemy_abilities.gd`: `VARIANTS` gains enemy-tuned copies of Fire Burst / Ring /
  Whip, Earth Pillar / Stomp / Spikes, Water Surge / Ice Trap / Ice Wall and the Air kit (~20-30 %
  less damage, cooldowns 7-14 s, Ice Trap freezes 1.1 s, burns 2.5 s, no redirect for the Air
  Shield); `LOADOUTS` fills `technique_1..4` per element and gains an AIR entry.
* `src/bending/kits/water/water_kit.gd`: `WaterKit.enemy_attacks()` (Water Surge, Ice Trap, Ice
  Wall as reactive cover), mirroring the other kits.
* `src/enemies/enemy_archetypes.gd`: `_kit()` helper; `fire_soldier` + Fire Burst (space),
  `fire_captain` + Fire Whip and Fire Ring in phase two, `earth_rogue` + Pillar / Stomp,
  `earth_chief` + Pillar, `dai_li_agent` + Spikes, `water_pirate` + Surge / Ice Trap / Ice Wall;
  new `air_sparring_monk` (= `AirKit.enemy_archetype()`) and `air_renegade` (a temple exile with
  the north road bandits: jabs, blast, Air Push, Air Sweep, Wind Blade); faction colour / name
  for `air_acolytes`.
* `src/enemies/encounter/encounter_sites.gd`: the north road bandits patrol is led by the
  renegade. `src/npc/trainer/trainer_lessons.gd`: the air spar partner is the sparring monk.

**Evidence.** `test_enemy_bender_loadouts_carry_the_techniques` (every bending attack's slot is
filled with the technique's own enemy copy, unregistered, ranges, readable tells, cooldowns no
faster than the player's), `test_enemy_techniques_cast_and_land` (10 technique attacks cast
through `EnemyActions` and land on the player at their range; glint -> strike 0.35-0.47 s).
Playtest `integration_fixes_enemies` (enemy arena, real AI vs a passive player):
PLAYTEST PASSED, 17 checks. 36 s duels, alternating 7.5 m and 2.3 m; casts per bender:

| Archetype | Casts (technique copies in bold) | Tells (glint -> strike, s) |
| --- | --- | --- |
| fire_soldier | fire_blast 4, fire_combo 5, **fire_burst 1**, **flame_sweep 1** | blast 0.52, jabs 0.42, burst 0.42, sweep 0.30 |
| earth_rogue | earth_punch 3, earth_boulder 2, **earth_pillar 3**, **earth_stomp 2** | punches 0.41, boulder 0.55, pillar 0.35, stomp 0.47 |
| water_pirate | water_blast 4, water_whip 5, **water_surge 1**, **ice_trap 1** | blast 0.47, whip 0.41, surge 0.46, trap 0.40 |
| air_renegade | air_blast 3, **air_sweep 2**, **wind_blade 3**, **air_push 3** | blast 0.46, sweep 0.45, blade 0.45, push 0.42 |
| fire_captain | fire_blast 4, fire_combo 4, **fire_whip 2**, **flame_sweep 2** | blaze charge 0.75, combo 0.38, whip 0.40 |
| group of 4 | 10 different attacks, 4 different element techniques | at most 2 attacking at once (tokens) |

The captain's Fire Ring belongs to its second phase (below 50 % health), not reached against a
passive player; `test_enemy_techniques_cast_and_land` casts it. Screenshots
`integration_fixes_enemy_*` (observer camera, just after release): fire burst ring, earth
pillar + stomp (player in hit-stun), water surge crashing over the player, ice trap stream,
air push knocking the player down, fire whip setting the player alight, the group.

---

## 3. Practice counted exactly once

**Checked.** Each kit counts practice inside its abilities (`FireCommon` / `EarthEnv` /
`AirEnv` / `WaterCommon.practiced`, player casts only); the controller, quests, HUD and tutorial
count nothing; rig events and the virtual-event safety net share a fired flag
(`BendingAbility._rig_event`).

**Result.** No double count exists. `test_practice_counted_exactly_once_per_use` casts every
technique and signature of all four elements (28) through the real player's input actions
(holds held, toggles toggled off) and asserts +1 on itself and +0 on every other technique:
`air_push=1 ... tidal_torrent=1`, all 28 pass. No code change was needed.

---

## 4. One level-up presentation

**Found.** `GameState.add_xp` emitted `Events.player_level_up` and an "unlock" toast, and the
progression `LevelUpBanner` showed the same level-up on top.

**Fixed.** `src/autoload/game_state.gd:105` (foundation) no longer toasts.
`src/ui/progression/level_up_banner.gd` joins group `level_up_banner`; `src/ui/hud/hud.gd`
`_on_level_up` updates the vitals seal and shows one combined toast ("Level n reached · +1 skill
point") only when no banner is in the scene (dev arenas) and not in the tutorial.

**Evidence.** `test_level_up_has_one_presentation` (no toast from GameState; one HUD toast for
two levels at once without a banner; banner only with one). Playtest
`integration_fixes_fires` (real world scene, Water new game): XP for level 2 -> the banner
"LEVEL 2 · +1 skill point" shows and no level-up toast appears among the HUD toasts
(`integration_fixes_levelup_banner`); the onboarding checks (starters on slots 1-3, slot 4 free,
locked Tidal Torrent drawn with a padlock and "LV 7", R -> "Tidal Torrent is locked · learn it in
Bending Skills (level 7)", a reward lands on slot 4 and the HUD shows it at once) pass in the
same run (`integration_fixes_hud_locked_signature`, `integration_fixes_reward_slot4`).

---

## 5. Interior anchors face into their rooms

**Found.** The Water Tribe interiors' anchor facings were written for a +Z-forward model: the
healer, the master and the idlers faced the wall behind them, the students faced away from the
master. The same copy exists in the Ba Sing Se tea shop / training hall, the Fire Nation dojo /
noble house and the Flame Kata Grounds (master facing the back of his dais). The NPC module
turned indoor NPCs around at runtime (`NpcCharacter.ensure_open_facing`).

**Fixed at the source.** `src/world/settlements/water_tribe/nwt_districts.gd` (`_interior`
anchor table), `src/world/settlements/earth_kingdom/bss_districts.gd` (`_interiors`),
`src/world/settlements/fire_nation/fnc_planner.gd` (kata grounds, dojo, noble house).
`src/npc/npc_character.gd` `ensure_open_facing` keeps only its named-NPC safety net (see
"remains").

**Evidence.** `test_interior_anchors_face_into_their_rooms` (every interior anchor of the three
cities faces into its room; kata master and students face each other). A probe before the fix:
healer / trainer / students / interior idlers 0 of 13 facing into the room.

**Remains.** Door-front anchors (homes, door quest givers, palace guards, the princess at the
oasis, shop doors) in every settlement face their building, while the contract describes homes
as "facing out" and the NPC crowd steps residents "off the doorstep" along the facing (into the
doorway). Measured with the same probe: home anchors facing toward their nearest building -
Water Tribe 652 / 737, Ba Sing Se 659 / 893, Fire Nation capital 716 / 984, Air Temple 51 / 51.
This is a 71-call-site data convention across four planners plus the NPC crowd's assumption;
it was left for a dedicated pass (named NPCs keep the runtime turn).

---

## 6. DialogueBox fade race

**Found.** `DialogueBox.close()` started a 0.15 s fade that hid the box at its end even if
`open()` ran meanwhile (a trainer menu right after a conversation opened invisible); the NPC
runner polled up to 40 frames (`_settle_box`) to wait it out.

**Fixed.** `src/ui/common/dialogue_box.gd` keeps the fade tween and kills it in `open()` /
`close()`; `src/npc/dialogue/dialogue_runner.gd` drops `_settle_box` and its three awaits.

**Evidence.** `test_dialogue_box_reopened_during_close_fade_stays_visible`.

---

## 7. Burn ticks never shake the camera

**Found.** FireStatus ticks the player through `receive_hit` -> `PlayerDamage.receive`, which
shook the camera (0.16) on every tick - once a second while burning.

**Fixed.** `src/player/player_damage.gd`: `is_tick(hit)` (meta `dot` from FireStatus or
`no_hitstop` from sustained pulses) skips the shake and halves the hit flash;
`src/ui/hud/hud.gd` tints the damage vignette to 0.3 instead of a full flash for `dot` hits;
`src/ui/touch/touch_haptics.gd` gives a 14 ms buzz instead of a damage pulse.

**Evidence.** `test_burn_ticks_hurt_without_camera_shake` (3.5 s burning: damage taken, zero
`camera_shake` events; a normal hit still shakes).

---

## 8. New-game onboarding: loadout, locked signature, lessons and rewards

**Checked** for every element through a real new game: level 1; starters on slots 1..n in order
(Air 2, Earth 3, Fire 2, Water 3 - per GAME_DESIGN §4; each opening chain's technique reward
fills the next slot), the other slots free, no signature.

**Found.**
* A trainer lesson or quest reward that granted a **signature** auto-equipped it into a free
  technique slot (`GameState.unlock_ability(id, true)`): the controller skips it there, so the
  slot stayed dead and the next technique could not use it.
* An unlearned signature was just an empty circle on the HUD (absent on touch); R failed with
  `&"empty"` and an empty id (the HUD flashed a random empty slot).
* Slots reloaded only where a caller remembered to call `load_equipped()`.

**Fixed.**
* `src/npc/trainer/trainer_lessons.gd`, `src/quests/quest_rewards.gd`: auto-equip only
  techniques; the toast names where it went (`QuestRewards.slot_hint`: "slot 3", "signature
  (R)", "equip it in Bending Skills").
* `src/bending/bending_controller.gd`: `load_equipped()` frees a technique slot holding a
  signature (older saves) and keeps the unlearned signature as `locked_signature`;
  `request(&"signature")` then fails with `&"locked"` + its id; `locked_signature_info()`.
* `src/player/player_character.gd`: reloads the loadout (deferred, coalesced) on
  `abilities_equipped_changed` / `ability_unlocked` when the save's element is the player's;
  `get_locked_signature_info()` (HUD contract addition).
* `src/ui/hud/hud_ability_slot.gd`, `src/ui/hud/hud.gd`: the signature slot draws the technique
  faint under a padlock with "LV n"; R shows a hint toast at most every 4 s.
  `src/ui/touch/touch_overlay.gd`: the signature button is shown locked (tap = the same hint).

**Evidence.** `test_new_game_loadout_per_element` (all four elements: slots, lock info, R ->
`locked` + toast, learning it enables the button at once), `test_lessons_and_rewards_fill_free_slots_and_hud_follows`
(reward -> next free slot, HUD updated next frame; Inferno lesson -> signature button, not a
technique slot; a following lesson takes the next free slot; a dead signature slot is healed).

---

## Files changed outside this QA module

Everything is additive or a local fix; no public signature was changed or removed.

* **Foundation**: `src/autoload/game_state.gd` (`add_xp` no longer toasts the level-up).
* **player**: `src/player/player_damage.gd` (`is_tick`), `src/player/player_character.gd`
  (live loadout reload, `get_locked_signature_info`).
* **bending**: `src/bending/bending_controller.gd` (`locked_signature`, `locked_signature_info`,
  signature-in-technique-slot heal), `src/bending/kits/water/water_kit.gd` (`enemy_attacks`).
* **enemies**: `src/enemies/enemy_abilities.gd`, `src/enemies/enemy_archetypes.gd`,
  `src/enemies/encounter/encounter_sites.gd`, `src/enemies/encounter/outpost_builder.gd`
  (camp fire record).
* **ui / progression_ui / mobile**: `src/ui/hud/hud.gd`, `src/ui/hud/hud_ability_slot.gd`,
  `src/ui/common/dialogue_box.gd`, `src/ui/progression/level_up_banner.gd`,
  `src/ui/touch/touch_overlay.gd`, `src/ui/touch/touch_haptics.gd`.
* **quests_npcs**: `src/npc/dialogue/dialogue_runner.gd`, `src/npc/npc_character.gd`,
  `src/npc/trainer/trainer_lessons.gd`, `src/quests/quest_rewards.gd`.
* **worldcontent**: `src/world/buildings/building_kit.gd`, `src/world/buildings/kit_result.gd`,
  `src/world/buildings/light_budget.gd`, `src/world/props/poi_structures.gd`,
  `src/world/props/prop_fx.gd`, `assets/shaders/content/kit_glow.gdshader`.
* **settlements_wa / settlements_ef**: `src/world/settlements/common/kit_merger.gd`,
  `settlement_provider.gd`, `settlement_fx.gd`, `night_glow.gdshader`,
  `src/world/settlements/water_tribe/nwt_districts.gd`, `nwt_places.gd`, `nwt_props.gd`,
  `src/world/settlements/earth_kingdom/bss_districts.gd`,
  `src/world/settlements/fire_nation/fnc_planner.gd`.
* **Module docs** (a "wave 4" note each): `docs/modules/bending.md`, `bending_air.md`,
  `bending_fire.md`, `bending_water.md`, `enemies.md`, `mobile.md`, `player.md`,
  `progression_ui.md`, `quests_npcs.md`, `settlements_ef.md`, `settlements_wa.md`, `ui.md`,
  `worldcontent.md`.
* **New**: `src/world/fires/world_fires.gd`, `src/world/fires/world_fire_spot.gd`,
  `tests/unit/test_integration_fixes.gd`,
  `tests/playtest/scenarios/integration_fixes_fires.gd`,
  `tests/playtest/scenarios/integration_fixes_enemies.gd`, this file.

## Verification

* `tools/check.sh`: OK.
* `tools/test.sh test_integration_fixes`: 13 run, 0 failed.
* `tools/test.sh` (full suite): 434 run, 0 failed on the main-fix run; on the final run 434 run,
  1 failed - `test_worldcontent::test_main_thread_budget_slices_instantiation` (4 of 39 frames
  over a wall-clock bound, a synthetic provider with no module code; the known flaky timing
  test fixed on the `perf_polish` branch). It passes on its own (`test_worldcontent` 19 / 19).
  Exit warnings (81 ObjectDB leaked, 5 resources in use) are the same as the baseline.
* Playtests (960x540, Forward+, xvfb): `integration_fixes_fires` PASSED (20 checks),
  `integration_fixes_enemies` PASSED (17 checks). Screenshots were reviewed one by one.

## What remains

* **Door-front anchors** face their buildings in every settlement (see section 5); named NPCs
  keep the runtime turn, crowd residents use the facing as authored.
* **World fires**:
  * The shader mask covers the 32 nearest fires that are out within 90 m. Further away a fire
    shows its baked (lit) look: by day a cold brazier's flame switches to coals when the camera
    comes within 90 m. Small and far, but it is a pop.
  * A fire's override is dropped beyond 115 m: a doused fire you walk away from shows lit again
    (its relight timer would usually have run out anyway).
  * Baked flames by day use the kit glow's day energy (0.6): a brazier lit by day reads as a pale
    flame shape in bright snow light (`fire_9_lit_by_day`). Pre-existing look, left unchanged.
  * The playtest drove braziers; torches, lanterns and camp fires are covered by unit tests
    (records, darken-only lanterns, camp fire smoke / embers stop and restart), not by a
    screenshot run.
  * The mobile stand-in budget (8) and the shader loop were checked in headless tests and the
    desktop renderer only; no device run.
* **Enemies**: the technique mix was tuned in the arena against a passive player (cooldowns no
  faster than the player's, enemy damage 70-80 %); the captain's Fire Ring (phase two) was seen
  only in the unit test. Balance against a real player over a long fight is untested.
* **Practice** (gap 3) needed no change; the test guards it.
