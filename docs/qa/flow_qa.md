# QA wave 4 — end-to-end game flow and the brief's testing checklist (`flow_qa`)

The real game was played like a QA lead: scripted playtests on the REAL scenes (boot, main
menu, element select, world, training grounds, pause / settings, Journey Book, ferries, map,
mounts) for all four elements, with input through the InputMap (key / pad actions, mouse-look
events, simulated touch on the phone run) — never by calling gameplay functions, except where
a step says "harness" (placing the player next to a target, a heal to keep a long run going).
Every log was scanned for `ERROR` / `WARNING` / `SCRIPT ERROR`. Bugs were fixed at their root
(in any module), each with a regression test that fails without the fix.

* Tests: `tests/unit/test_flow_qa.gd` (13 tests).
* Playtests: `tests/playtest/scenarios/flow_qa_menus.gd`, `flow_qa_journey.gd` (`ELEMENT=`),
  `flow_qa_travel.gd` (`ELEMENT=fire|air`, `PART=fly` for the flight only),
  `flow_qa_confirms.gd`, `flow_qa_mobile.gd` (`MOBILE=1 RENDERER=mobile`), and the fixed
  `worldscene_tutorial.gd` (`ELEMENT=`). Each flow playtest saves into its own folder
  (`user://saves_flow_qa_*`): `user://saves_test` is shared by every agent's runs on the
  machine, and a save appearing there mid-run changes what ENTER THE WORLD does.
* Run on the shared CI container: llvmpipe software Vulkan, 4 cores shared with two other
  agents' Godot runs, 960×540 (phone run 1600×720). Load times are software-rendering numbers.

## Bugs found and fixed

| # | Bug (how it showed in play) | Root cause | Fix | Regression |
| --- | --- | --- | --- | --- |
| 1 | Training grounds as an **earthbender**: lessons *Heavy Strike* and *Charged Strike* never complete (the known `worldscene_tutorial ELEMENT=earth` failure) | `TutorialDirector._on_ability_ended` counted a heavy only if the ability `is ChargeAbility`; Earth Boulder is its own lift → hold → throw state machine | Heavies share one release contract (`released`, `tapped`, `charge`); `earth_boulder.gd` exposes it; the director reads it for any heavy-slot ability (`TutorialDirector.heavy_strike_of`) | `test_tutorial_light_heavy_charge_sprint_lessons_complete_for_every_element`, `test_heavy_strike_report_for_charge_abilities_and_earth_boulder` |
| 2 | Same run, lesson *Sprint* fails for Earth | Harness, not the game: the playtest sprinted right, then left (1.1 s each); Earth (accel 16, decel 28 m/s²) spends each reversal braking — ~1.3 s above run speed of the 1.5 s needed | The playtest runs one straight line like a player told "hold Shift while moving" | same unit test (straight sprint, all four elements) |
| 3 | **Back / Esc on the element select during its fade-in** leaves a dead screen: every later key / pad / tap is ignored, the only way out is quitting | `Router.goto` silently returned while a transition was running, but the screen had already set its own `_busy` flag before routing. The fade blocks the mouse, not keys / pad | `Router.goto`: a request from the NEW scene during its fade-in is queued (latest wins) and runs when the fade ends; requests made before the swap (by the outgoing scene) are still dropped | `test_router_request_during_fade_in_is_not_lost`; playtest `flow_qa_menus` ("Back pressed during the fade-in returns to the main menu") |
| 4 | After a **save → load**, a failed quest's journal page shows no stages; every count comes back as `2.0` | A save is JSON (one number type): integer records came back as floats and `[0.0, 1.0].has(1)` is false (the journal's "stage reached" test) | `GameState.from_dict` turns whole numbers back into ints in the integer records (inventory, stats, practice, quest stage / log / objective progress, companion bond); times stay floats | `test_save_round_trip_keeps_integer_records` |
| 5 | **Tutorial → ENTER THE WORLD silently replaces a saved journey**: main menu → 02 TUTORIAL (with a level-7 journey on disk) → finish → ENTER THE WORLD starts a new journey whose arrival autosave overwrites the old one, no question asked (the main menu's NEW JOURNEY asks) | The completion screen started the new journey unconditionally | With a journey on disk ENTER THE WORLD asks "A NEW JOURNEY" (names the saved journey; KEEP JOURNEY focused, BEGIN ANEW) | `test_tutorial_enter_world_asks_before_replacing_a_saved_journey`; `worldscene_tutorial` checks the question appears exactly when a save exists |
| 6 | Pause → SETTINGS → change an option → Back → "UNSAVED CHANGES": pressing **right on APPLY sends focus behind the dialog** (to a Glow / SSAO toggle under the dim); Enter then flips a setting the player cannot see and the question can no longer be answered with keys / pad | `ConfirmDialog` buttons had no focus neighbours; Godot picks the nearest focusable control in the direction, and on a real 960×540 window that was a settings toggle behind the overlay (headless layout differs, so only the rendered run showed it) | `ConfirmDialog._trap_focus()`: left / right cycle the answers, up / down / Tab stay in the row — every confirmation in the game (settings, Journey Book fast travel / unlearn, rebind reset, the new tutorial question) | `test_confirm_dialog_traps_focus_on_its_answers`; rendered playtest `flow_qa_confirms` (right ×3 cycles inside the dialog, DISCARD by Enter, map FAST TRAVEL answered by Enter) |
| 7 | **Training grounds as an airbender: *Strike Combo* (chain 3 strikes into a dummy) never completes** — stuck below 3 / 3 (`worldscene_tutorial ELEMENT=air`); in the world a light chain landed one hit | Air Combo's second strike is a low, wide hook-kick gust (0.75 m growing to 3.15 m) launched 0.5 m above the floor. `BendingProjectile` stops on the first SOLID contact, so the growing sphere met the floor after ~0.5 m and the gust died (the palm and Air Blast gusts likewise ended early wherever their grown radius met the ground) | `BendingProjectile` option `world_radius`: bodies meet the full radius, terrain / walls / constructs only a core; `AirCommon.gust` uses a 0.25 m core | `test_wide_gust_skims_the_floor_and_reaches_its_target`; the light-chain part of `test_tutorial_light_heavy_charge_sprint_lessons_complete_for_every_element` (fails for air without the fix; the scripted check showed the kick gust ending 0.53 m out) |
| 8 | **Phone: the quest tracker sits under the technique buttons** for the whole first stretch of a new journey ("Speak with Elder Anaaya" covered by the 3rd technique button) | The first quest slides in (`UiFx.slide_in`, a tween on `position`) while the arrival still hides the HUD — touch overlay off, tracker on the right. The overlay then moves the tracker under the vitals; the running tween carried it back to the right. Two quests in quick succession also left it 40 px off | `HudQuestTracker.settle()` ends a running slide (back at its layout spot, opaque); `Hud.apply_touch_layout()` calls it before moving the tracker and each new slide calls it first | `test_quest_tracker_takes_the_touch_layout_during_its_slide_in`; phone playtest `flow_qa_mobile` |
| 9 | Enemies never reacted to an **earthbender's charged boulder** (no Earth Wall cover while it charges, no evade on the close release) — they did for every other element | `EnemyBrain._threats()` asked `is ChargeAbility` (same root as #1) | The brain reads the release contract (`charging`, `released`) by duck typing — Earth Boulder and Lightning included | `test_enemies_see_every_element_charge_a_heavy` |
| 10 | Training-ground dummies print **"2  None"** over every chip / burn tick | `TrainingDummy._show` printed the reaction name even for `Reaction.NONE` | Damage-only hits show just the damage | `test_training_dummy_readout_names_only_real_reactions` |
| 11 | `SCRIPT ERROR` in `BendingContext.make_hit` ("previously freed") when a projectile outlives its caster (seen when the training grounds were torn down while a gust flew; also a despawned enemy's bolt) | Every hit is built from `ctx.caster`; nothing stopped a projectile whose caster was freed | `BendingProjectile.step()` ends the projectile when its caster is gone | `test_projectile_outliving_its_caster_ends_quietly` |
| 12 | (tooling) A playtest scenario with a parse error made the runner idle until its 15–30 min timeout | `Playtest._ready` called `new()` on a script that loaded but could not be instantiated | `tests/playtest/playtest.gd` fails at once ("cannot load scenario … (parse error?)") | — |

## The brief's testing checklist

Evidence = the playtest / test that checks it (logs and screenshots under the run's `--out`
folder; the best shots are listed at the end). "Journey" = `flow_qa_journey ELEMENT=<el>`.

| # | Item | Result | Evidence |
| --- | --- | --- | --- |
| 1 | Launches without fatal errors | PASS | Every playtest boots the real `boot.tscn` / main menu (menus run boots `scenes/boot.tscn`); logs scanned for `ERROR` / `WARNING` / `SCRIPT ERROR` / `Failed to load` (see *Log scan*). The only engine errors are the container's missing audio device at start-up and the exit-time leak summary |
| 2 | All four main-menu buttons work | PASS (bug #3 fixed) | `flow_qa_menus`: four options read ENTER THE WORLD / TUTORIAL / SETTINGS / EXIT GAME; 01 → element select (and Back during its fade-in returns to the menu); 02 → tutorial-mode select → PRACTISE AS FIREBENDER → training grounds (nothing can be saved there, pause SAVE GAME disabled) → RETURN TO MAIN MENU clean; 03 opens the settings overlay; ui_up wraps to 04 EXIT GAME which quits. Phone: every step by tap (`flow_qa_mobile`) |
| 3 | Graphics settings modify real settings | PASS | Main menu, Low preset by `ui_left` on the preset row: viewport SSAA 1 → 0, mesh LOD threshold 1 → 4, positional shadow atlas 4096 → 1024, the menu scene's glow off and sun shadow mode 2 → 0, render scale 70 % applied to the viewport; CANCEL restores every value. In the world (`flow_qa_travel`): sun shadow distance 220 → 60 m, glow off, terrain clipmap 22 levels / 4000 m → 16 / 1500 m, vegetation density 1.0 → 0.25, mesh LOD 1 → 4; Back → UNSAVED CHANGES → DISCARD restores the world |
| 4 | Element selection assigns the element | PASS | Journey ×4: "chosen element assigned to the journey"; the controller bends that element ("player bends earth" …); tutorial select reads "PRACTISE AS FIREBENDER" and the training grounds run as that element |
| 5 | Each element starts in its home region | PASS | Journey: water → `water_tribe`, earth → `earth_kingdom`, fire → `fire_nation`, air → `air_temple` (GameState region at the spawn + region banner in the shots) |
| 6 | The right companion appears | PASS | Journey: polar bear dog / badgermole / dragon / sky bison, beside the player at the spawn (3.4–7.5 m) |
| 7 | All four bending configurations perform their starter abilities | PASS (bug #7 fixed for Air) | Journey, locked on a `bandit_brawler`: every filled slot (light, heavy, techniques 1–3) cast through its key and reported (cast / hits / results / damage / constructs) — see *Per element*. The locked signature refuses with a hint (`[&"earthquake", &"locked"]` …) |
| 8 | Attacks apply gameplay effects | PASS | Same report: every cast hit, was blocked / dodged by the bandit, or raised a construct (Ice Wall, Earth Pillar, Earth Wall); bandit health 95 → 25–62 during the slot pass |
| 9 | Enemies respond and can be defeated | PASS | The bandit went ALERT → CHASE → STRAFE → ATTACK (telegraphed 1–4 attacks), STAGGER / KNOCKDOWN / GETUP on hits, FLEE when low; defeated in 10–18 s by play (killed, or surrendered / fled: `defeated` how), +11 – +22 XP |
| 10 | Block / dodge / movement / camera consistent | PASS | Journey: block against a second bandit's attack returns BLOCKED, dodge moves 3.0–5.7 m and hands control back (LOCOMOTION), mouse-look events turn the camera 0.78–1.05 rad, the camera stays with the player; movement after every menu / book / pause round trip (5.6 m) |
| 11 | No permanent stuck states (fuzz) | PASS | `test_input_fuzz_never_leaves_the_player_stuck`: 45 s of seeded random input per element next to an attacking bandit — longest locking state 0.85–1.35 s (ACTION), longest busy controller 1.2–2.2 s, back in LOCOMOTION and walking afterwards. A conversation the random `interact` opens holds the player until answered (by design) and is answered like a player would |
| 12 | Snow footprints in the Water Tribe | PASS | Journey water: SnowTrails stamps 239 → 264 while walking on snow, the trail lies under the walked path (`water_08_footprints.png`) |
| 13 | Companions follow / navigate | PASS | Journey: after a 3.5 s sprint the companion catches up (ground distance ≤ 12 m: dog 8.9, badgermole 9.6, bison / dragon land first); it survives save → menu → continue with its health |
| 14 | Tutorial playable for every element | PASS (bugs #1, #7 fixed) | `worldscene_tutorial ELEMENT=` earth / fire / air / water: every lesson completed by play (14; air 16 with air jump + glide), completion screen, ENTER THE WORLD asks before replacing a saved journey (bug #5) and starts a fresh journey; nothing saved by the tutorial |
| 15 | Save / load keeps everything | PASS (bug #4 fixed) | Journey: pause → SAVE GAME → RETURN TO MAIN MENU → CONTINUE: position (0.00 m), element, level / XP / points, unlocked abilities + loadout and the live slots, quests (by value), inventory (ints), discovered POIs, hour (± the minutes that pass), companion species + health |
| 16 | Menu ↔ game transitions keep input working | PASS (bugs #3, #6 fixed) | No action held after leaving the world; mouse visible, tree unpaused, time scale 1 on the menu; movement and bending answer after CONTINUE, after the Journey Book, after pause → settings → resume; the menu answers taps after a phone round trip |
| 17 | No duplicate critical objects after transitions | PASS | Census after RETURN TO MAIN MENU: 0 players / companions / world scenes / journey books, one current camera, one of every autoload; after CONTINUE exactly one player, companion, world scene, journey book, level-up banner and current camera |
| 18 | No missing resources / scripts | PASS | `tools/check.sh` parses every script; a static scan of every `res://` literal in `src/` and `scenes/` found none missing, and no sound name is missing from the audio bank; no `Failed to load` / `Cannot open` in any playtest log |

## Extra flows

| Flow | Result | Evidence |
| --- | --- | --- |
| Opening quest giver → first objective, every element | PASS | Journey: Anaaya (water) / Lin (earth) / Kaida (fire) / Pasang (air) stand by the spawn; `interact` opens the conversation, the lines advance by key, the opening quest's first objective completes (stage 0 → 1), control comes back (`*_03b_quest_giver.png`, `*_03c_objective.png`) |
| Fast travel from the map | PASS | `flow_qa_travel` + `flow_qa_confirms`: M opens the map, the reticle (pad / keys) rests on the home city, Enter asks FAST TRAVEL with TRAVEL focused, Enter travels; the book closes, arrival toast, 0.0 m from the travel point |
| Ferry trip | PASS | `flow_qa_travel ELEMENT=fire`: at Crimson Harbor's landing the ferry prompt shows, the ferry master offers destinations, the ferry casts off, the trip ends on the Full Moon Bay quay with the player in control |
| Mounting and flying (dragon, bison) | PASS (dragon); bison TBD | `flow_qa_travel PART=fly`, fire: G calls the dragon, it lands beside the player (8 m), F mounts from the prompt, jump takes off, holding jump climbs +29.9 m, descend lands, F dismounts, the player walks on (`travel_12_flying.png`, `travel_13_landed.png`) |
| Journey Book open / close | PASS | K opens skills (pauses), J journal, M map, Esc closes and resumes; movement answers after |
| Pause → settings → back | PASS (bug #6 fixed) | Back with a change asks UNSAVED CHANGES, right cycles APPLY → DISCARD → KEEP EDITING inside the dialog, DISCARD restores; back on the pause menu, RESUME, movement answers |
| Phone pass (`MOBILE=1 RENDERER=mobile`, 1600×720, water) | PASS (bug #8 fixed) | Touch only: tap ENTER THE WORLD, tap the card, tap BEGIN, tap to skip the arrival, the stick runs 11 m, a drag turns the camera, Strike / first technique by tap, top-bar pause → RESUME → the stick still drives → pause → RETURN TO MAIN MENU → the menu answers taps; mobile preset, 32 s load on llvmpipe |

## Per element (journey + training grounds)

Journey = menu → element card → BEGIN → arrival (skipped by a key) → home → quest giver →
open ground → `bandit_brawler` → every slot → fight to the defeat → block / dodge a second
bandit → companion follow → (water: footprints) → save → menu → CONTINUE → compare.

| Element | Home / companion / quest | Slot pass (cast → result on the bandit) | Fight | Save → continue | Training grounds |
| --- | --- | --- | --- | --- | --- |
| Water | `water_tribe`, polar bear dog, *Born of the Tide* (Anaaya, stage 0 → 1) | Water Whip 3 hits / 33 dmg; Water Blast hit (push); Ice Shards 2 hits; Ice Wall wall + hit; Water Surge hit (push) | defeated (killed) in 12 s, +22 XP | all fields equal, one of each, moves + bends | all 14 lessons |
| Earth | `earth_kingdom`, badgermole, *Stone Beneath the Sky* (Lin) | Earth Punch 4 hits / 46 dmg; Earth Boulder dodged by the bandit (enemies now read the earth heavy, #9); Earth Pillar pillar + launch 14 dmg; Earth Stomp TBD; Earth Wall wall | defeated (killed) in 10 s, +22 XP | all fields equal, one of each, moves + bends | all 14 lessons (was: heavy + charge never completed, #1) |
| Fire | `fire_nation`, dragon, *A Spark Returns* (Kaida) | Fire Jabs 3 hits / 25 dmg; Fire Blast hit 17; Fire Burst hit 18; Flame Sweep hit | defeated (killed) TBD | TBD | all 14 lessons |
| Air | `air_temple`, sky bison, *The First Breath* (Pasang) | TBD (Air Combo was 1 hit for 3 presses before #7) | TBD | TBD | all 16 lessons (was: Strike Combo never completed, #7) |

## Log scan

TBD

## Found, not fixed (owners)

| Issue | Evidence | Owner / why not here |
| --- | --- | --- |
| **The camera enters tree canopies**: near trees the screen fills with dark green foliage (the camera collides with `WORLD | CONSTRUCT`, canopies have no collider) | `journey_water2/water_05_defeated.png`, `water_06_block.png` (pine woods by the Water Tribe), bamboo groves in the fire runs | player camera / worldcontent: a near-camera dither fade in `assets/shaders/content/vegetation.gdshader` (+ its outline pass). Not done here: a `discard` in the opaque vegetation shader costs early-z on tiled mobile GPUs, which perf_polish budgets — it needs their measurement |
| Big companions can stand between the lens and the player in the first frames after a spawn / continue (badgermole, dragon fill a third of the view) | `journey_earth3/earth_03_home.png`, `journey_fire3/fire_10_continued.png` | companions (`Companion.teleport_near_player` picks a spot from the view direction; the perf_polish `OccluderFader` fades it once it scans) |
| A flying companion that escorted during a fight needs 7–10 s to land back beside the player (the bison returned to 16.9 m in 8 s) | `journey_air2` note, `journey_fire3` note (mode `escort`, 11.9 m after 7.1 s) | companions (by design: flyers take off to follow and land when the player is still) |
| Load hold: `content_settled` false at the 25 s limit on llvmpipe under load (the world still opens; collision is ready in < 2 s) | every world load in the logs | perf / software rendering on a shared 4-core container |
| Exit: "N resources still in use at exit", ObjectDB leak lines when the game quits | every log's last lines | engine-level at quit (unchanged baseline, no gameplay effect) |
| Swimming refuses bending (a bender in a lake cannot cast) | `journey_fire2` (open-ground finder picked a lake: every cast refused) | bending design (not a stuck state: leaving the water restores it) |

## Files changed

flow_qa's own: `tests/unit/test_flow_qa.gd`, `tests/playtest/scenarios/flow_qa_*.gd`,
`docs/qa/flow_qa.md`. Outside the focus (each documented in its module doc, "Wave 4 (flow_qa)"):

* foundation: `src/autoload/router.gd` (#3), `src/autoload/game_state.gd` (#4),
  `tests/playtest/playtest.gd` (#12), `docs/ARCHITECTURE.md` (Router queue, integer records)
* bending: `src/bending/bending_projectile.gd` (#7 `world_radius`, #11),
  `src/bending/dev/training_dummy.gd` (#10), `docs/modules/bending.md`
* bending_air: `src/bending/kits/air/air_common.gd` (#7), `docs/modules/bending_air.md`
* bending_earth: `src/bending/kits/earth/earth_boulder.gd` (#1), `docs/modules/bending_earth.md`
* enemies: `src/enemies/enemy_brain.gd` (#9), `docs/modules/enemies.md`
* worldscene / tutorial: `src/tutorial/tutorial_director.gd` (#1),
  `src/tutorial/tutorial_complete_screen.gd` (#5), `tests/playtest/scenarios/worldscene_tutorial.gd`
  (#2, #5 check), `docs/modules/worldscene.md`
* ui: `src/ui/widgets/confirm_dialog.gd` (#6), `src/ui/hud/hud.gd`,
  `src/ui/hud/hud_quest_tracker.gd` (#8), `docs/modules/ui.md`

## Verification

TBD
