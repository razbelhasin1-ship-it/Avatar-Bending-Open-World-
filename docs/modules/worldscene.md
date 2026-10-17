# World scene (`worldscene`)

The playable game: the open-world scene the menus route to (`Router.WORLD`), the arrival
cinematic, the region director, death / respawn, ferries and fast travel, save consistency,
and the training grounds (`Router.TUTORIAL`). Everything is composed in code on top of the
wave-1/2 modules; the `.tscn` files are thin wrappers.

| Piece | Files |
| --- | --- |
| Scenes | `scenes/world/world.tscn` (`WorldScene`), `scenes/world/tutorial.tscn` (`TutorialScene`) |
| Shared base | `src/world/game/playable_scene.gd` (`PlayableScene`), `screen_fader.gd` (`ScreenFader`), `cinematic_overlay.gd` (`CinematicOverlay`), `world_hooks.gd` (`WorldHooks`) |
| World | `world_scene.gd` (`WorldScene`), `arrival_cinematic.gd` (`ArrivalCinematic`), `region_director.gd` (`RegionDirector`), `respawn_system.gd` (`RespawnSystem`), `travel_system.gd` (`TravelSystem`), `ferry_boat.gd` (`FerryBoat`), `ferry_dock.gd` (`FerryDock`), `world_save_guard.gd` (`WorldSaveGuard`) |
| Tutorial | `src/tutorial/`: `tutorial_scene.gd` (`TutorialScene`), `tutorial_director.gd` (`TutorialDirector`), `tutorial_steps.gd` (`TutorialSteps`), `tutorial_prompt.gd` (`TutorialPrompt`), `training_ground.gd` (`TrainingGround`), `tutorial_complete_screen.gd` (`TutorialCompleteScreen`) |
| Tests | `tests/unit/test_worldscene.gd`; playtests `worldscene_flow`, `worldscene_arrival`, `worldscene_tutorial`, `worldscene_travel` |

## Scene flow

```
main menu -> ENTER THE WORLD -> element select -> GameState.new_game(e)
   -> Router.goto(WORLD, {new_game: true, element: e})
        loading (Router fade held + LoadingOverlay "Journeying to Ba Sing Se")
        -> ArrivalCinematic (letterboxed flight, title card, music swell, skippable)
        -> control, RegionDirector, autosave
main menu -> CONTINUE (SaveSystem.load_game) -> Router.goto(WORLD, {new_game: false})
        loading ("Returning to the Fire Nation") -> saved place / hour / health -> control
main menu -> TUTORIAL -> element select -> Router.goto(TUTORIAL, {element: e})
        training grounds -> lessons -> TRAINING COMPLETE -> ENTER THE WORLD | MAIN MENU
in game: Esc / Start -> PauseMenu (save, settings, main menu, quit)
```

## PlayableScene (base of both scenes)

Composition (all children of the scene root, built in `_ready`):

| Node | What |
| --- | --- |
| `SpawnFocus` | marker that drives streaming while no player exists (loading, fast travel) |
| `WorldRenderer` | terrain, water, sky, weather, snow, collision (`renderer`) |
| `WorldContent` | vegetation / nature / POIs (`content`; `null` with option `no_content`) |
| `Props` | ferry docks, ferries, training ground, dummies (`props_root`) |
| `Companions` | companion slot (`companion_root`, see hooks) |
| `Hooks` | module hook nodes (`hooks`) |
| `Hud` (layer 10) | bound to the player; hidden during loading and cinematics |
| `DialogueLayer` (30) | `DialogueBox` (`dialogue`) |
| `CinematicOverlay` (35) | letterbox bars, caption, skip hint (`overlay`) |
| `TitleLayer` (40) | standalone `TitleCard` (`title_card`) above the letterbox |
| `PauseMenu` (90) | enabled once playing |
| `Fader` (110) | `ScreenFader` (`fader`): respawns, travel, skips; independent of the Router |
| `Player` | `PlayerCharacter` from `scenes/player/player.tscn` |

Loading sequence (`_boot`): `Router.hold_fade()` (when a Router transition is running) +
`LoadingOverlay` -> spawn transform -> `_before_spawn` -> **wait for terrain collision** under
the spawn and 6 m around it (`wait_for_ground`: `ensure_collision_now` + `is_collision_ready_at`,
25 s timeout) -> **wait for WorldContent to settle** (progress shown, 25 s timeout) -> raycast
the spawn onto the real ground (`ground_transform`; if nothing solid is found a temporary
8x8 m `SafetyFloor` holds the player until collision exists: never spawns into the void) ->
player added (its transform is set *before* entering the tree, so `Events.player_spawned`
carries the spawn) -> `_after_spawn` -> first-frame camera -> 3 warm-up frames -> reveal
(overlay closed, fade released) -> `ready_for_play` -> `_play`.
`load_report` = `{collision_ready, collision_s, content_settled, content_s, total_s, safety_floor, warmup}`.

Shader warm-up (perf_polish, `docs/qa/perf_polish.md`): once the ground is ready (progress
0.35) `ShaderWarmup.start(self, element)` casts every technique of the player's element plus the
light and heavy strikes of the other three elements on rig-less casters on a private stage
beyond the world edge, and spawns the shared impact FX, while the content streams behind the
loading screen; the boot waits for it (cap `ShaderWarmup.MAX_SECONDS`) before spawning the
player. Skipped headless, with option `no_warmup` or the `--no-warmup` user argument. While it
runs its camera is the active one (the terrain clipmap / ocean follow it behind the overlay).

Options (`Router.params`, or `scene.options` before `add_child` in tests): `element`,
`new_game`, `skip_intro`, `no_content`, `spawn` (Transform3D), `time_of_day`,
`collision_timeout`, `content_timeout`.

Services for directors, hooks and tests:

```gdscript
scene.capture_mouse() / release_mouse()      # desktop only; never in touch mode / --test runs
scene.set_hud_visible(on, fade_s)
scene.spawn_companion(node, at)              # parents under Companions, player.companion, Events.companion_spawned
scene.set_quest_provider(obj)                # -> Hud.bind_quest_provider
await scene.wait_for_ground(pos, timeout)    # collision ready around pos
scene.ground_transform(xform)                # onto physical ground (+ safety floor fallback)
await scene.fade_through(callable)           # black, run (may await), back
var i: int = await scene.ask_choice(speaker, text, choices)   # DialogueBox choice, player held, 90 s timeout -> last option
await scene.wait_seconds(t)                  # pause-aware scene time
```

Exit (`_exit_tree`): hooks `world_exit()`, fade hold released, loading overlay freed, mouse
visible, **every held action released** (`Input.action_release`), `Engine.time_scale = 1`,
registered water sources cleared. Verified by `test_exit_leaves_no_duplicates_or_held_input`
and the flow playtest (root children identical after menu round trips).

## WorldScene

* **New game**: element from `GameState` (the journey's element wins over params), hour set
  to a flattering arrival light per element (`ARRIVAL_HOUR`: air 9.0, earth 16.4, fire 15.6,
  water 8.6), spawn `WorldData.get_spawn(element)`, then `ArrivalCinematic` unless
  `GameState.intro_done` or `skip_intro`. After the arrival `GameState.intro_done = true` and
  an immediate autosave, so CONTINUE exists right away.
* **Continue** (`new_game == false`): `GameState.player_position / player_yaw /
  player_health_ratio`, `time_of_day` (WorldRenderer starts at it), element + equipped
  abilities (the player loads them), visited regions and discoveries (`world_flags`,
  `discovered_pois`). A "Journey resumed" toast; no cinematic.
* Signals: `ready_for_play` (revealed), `gameplay_started` (control handed to the player);
  `Events.game_started(element, new_game)` and `Events.world_ready` when revealed. Group
  `&"world_scene"` (`get_tree().get_first_node_in_group(&"world_scene")`).
* `can_autosave()` - only while playing normally (not during the arrival, death, travel).

### Arrival cinematic (`ArrivalCinematic`)

`prepare(scene)` before the first visible frame: own `Camera3D` at the path start, player in
`CINEMATIC`, HUD hidden, letterbox on, regional theme started quietly (-7 dB) + ambience.
`play()` after the reveal. The flight is a cubic Bezier from
`WorldData.get_arrival_camera(element).start` to `.end` (keeps altitude first, then swoops down
behind the player; look target eases from the start's focus to the end's; slight bank;
smootherstep timing; FOV `fov_start -> fov_end`), `duration` clamped to 5-9 s (data: 8 s).
At 20 % the title card shows the home (`ElementDefs.home_name`; caption "Your journey begins",
or the nation when the city name does not contain it: "BA SING SE · The Earth Kingdom"), a gong
(wind chime for Air) plays and the music swells (+1.5 dB). The last 1.6 s blend the camera
onto the player's live camera (transform + FOV) while the bars retract and the HUD fades in,
then the player camera becomes current: no cut. **Skip**: any key / mouse button / pad button /
trigger / touch / `InputEventAction` / touch-overlay action press (after a 0.5 s grace) ->
0.25 s fade, same end state. Without baked camera data a fallback orbit-down path is used.
Total <= ~10.6 s.

### Region director (`RegionDirector`)

* Samples `WorldData.get_region` at the player every 0.25 s; a different region must be
  reported continuously for `HOLD_TIME` (2 s) to become current (border flicker never switches).
* On change: `GameState.region`, `Events.region_entered` (Audio switches regional music and
  the ambience bed; the HUD compass shows the name), `region_changed` signal, autosave
  (vetoed by `can_autosave`).
* First visit (`GameState.world_flags["visited_regions"]`): "Region Discovered" title card.
  The HUD's own per-entry card is off in the world (`Hud.region_titles = false`).
* Local audio at 1 Hz from the biome under the player: `CITY` -> reverb `city` + `amb_city`
  layer, `TEMPLE` -> `temple` + `amb_temple`, `FOREST` -> `forest`, else `open`.
* POI discovery at 2 Hz: inside a POI's `radius + 12 m` (and within 45 m vertically) ->
  `GameState.discover_poi` (Audio plays the discovery stinger), XP by type (vista / spirit
  place 60, landmark / ruin / cave 50, shrine / waterfall / village / training ground 40,
  camp / resource / bridge 30, harbor 25), a title card ("Landmark Discovered") and a toast
  "+50 XP". The HUD compass marks discovered / undiscovered POIs within 900 m itself.
* Paused while travelling. Tests inject `region_provider`.

### Death and safety (`RespawnSystem`)

* `Events.player_died` -> 2.2 s -> fade -> `player.respawn_at(point, 0.5)` at the nearest of:
  the home spawn, the spawn of any visited capital, discovered shrines / villages / harbors /
  training grounds (snapped to `WorldData.get_safe_ground`). Nothing else changes (no progress
  lost). The player's own 15 s auto-respawn stays as a backstop. If the backstop revives the
  player while the fade waits for the respawn point's ground, `_place` only teleports (one
  `player_respawned` per death; wave 4 bug hunt, `docs/qa/bughunt_gameplay.md` #10).
* Net (5 Hz): non-finite position, beyond +-4060 m (open sea edge), below -300 m, or 30 m
  under the terrain with nothing solid below (caves are fine) -> fade back to the last safe
  ground (`PlayerMotor.last_safe_position`). WorldRenderer's 1.5 m collision net still runs.
* Tutorial mode: `use_fixed` + `fixed_point` (arena start, full health) and a leash radius.

### Travel (`TravelSystem`)

```gdscript
var w := get_tree().get_first_node_in_group(&"world_scene") as WorldScene
var ok: bool = await w.travel.travel_to(Transform3D(Basis(), pos), {"text": "Flying to Omashu"})
await w.travel.take_ferry(&"port_full_moon_bay", &"port_crimson_harbor")
TravelSystem.routes_from(&"port_full_moon_bay")   # [{ferry, to, points (from this berth)}]
```

* `travel_to(xform, opts)` (map fast travel): fade (`fade` s, optional `text` on black), the
  player is frozen while the destination streams (`SpawnFocus` drives collision + content),
  then placed on real ground, fade in, autosave (`autosave: false` to skip). Refused while busy
  or dead. Signals `travel_started(kind, destination)` / `travel_finished(kind, at)`.
* **Ferries**: every port with a ferry line gets a `FerryDock` at its quay (timber landing,
  ferry-master's signpost with a lantern, bell frame, cargo, nation flag; `Interactable`
  "Take the ferry") and a moored `FerryBoat` (nation colours) bobbing at the berth. Interact ->
  `ask_choice("Ferry Master", ...)` with the destinations of both directions of every line +
  "Stay ashore" (B / Esc also cancels). The trip: fade -> the ferry (deck collision,
  `AnimatableBody3D`) casts off from the berth along the real route with the player standing on
  the fore deck (pinned each physics tick after the player's own tick), letterboxed chase
  camera orbiting off the starboard bow, caption "Bound for ...", ocean ambience (3 s) -> black
  with "Sailing to ..." while the destination streams in -> the ferry glides the last 18 m to
  the destination berth with the camera behind and above the bow (2 s) -> fade -> the player
  stands on the destination quay facing inland, HUD back, autosave. `interlude_scale` speeds it
  up (tests). `phase` is `depart / transit / arrive` during a trip.

### Saves (`WorldSaveGuard`, SaveSystem integration)

The world's last child, in group `&"persist"`: `SaveSystem` calls `write_save_state()` in tree
order, so it runs after the player and the renderer. A save made while the player is dead
stores the respawn point (50 % health), while travelling the trip's destination, while
swimming / airborne / mounted the last safe ground; it also writes the tracked region.
Autosaves: SaveSystem's 180 s cadence + arrival + region change + ferry / fast-travel arrival.
The pause menu saves manually and before returning to the menu / quitting.

## Module hooks (`WorldHooks`)

Later modules attach without editing the scenes: if one of these scripts exists it is
instantiated (must extend Node) under `Hooks` and its optional methods are called:

```
res://src/companions/world_hook.gd      res://src/quests/world_hook.gd
res://src/npc/world_hook.gd             res://src/enemies/world_hook.gd
res://src/world/settlements/world_hook.gd
```

```gdscript
extends Node                                      # e.g. src/companions/world_hook.gd
var scene: PlayableScene
func world_setup(p_scene: PlayableScene) -> void: # before the player spawns
	scene = p_scene                               # scene.content may be null (tests)
func player_spawned(player: PlayerCharacter) -> void:
	var c := Companion.new()
	scene.spawn_companion(c, player.global_transform.translated(Vector3(2, 0, 2)))
func world_ready() -> void: pass                  # play begins (after the arrival)
func world_exit() -> void: pass
```

`scene.is_tutorial` tells a hook it runs in the training grounds (the tutorial's companion
lessons appear only when a companion exists after `player_spawned`). The HUD companion panel is
hidden until a companion exists (`Events.companion_spawned`). Tests can add hooks with
`scene.extra_hooks`.

## Training grounds (`TutorialScene`)

* **Where**: the element's real `training_ground` POI, flattened by the world generator, near
  the home city: The Ice Flats (frozen lake west of the Water Tribe), Stonefist Training Yard
  (farmland before Ba Sing Se's western wall), Flame Kata Grounds (caldera floor of the Fire
  Nation Capital), Airball Courts (top terrace of the Southern Air Temple). Arena frame: origin
  at the POI, -Z towards the home city.
* **Dressing** (`TrainingGround`, BuildingKit in the nation palette): sparring circle (r 13 m)
  with an inlaid element-coloured emblem (Earth gets a paved stone yard over the farmland), ten
  banner posts in the nation's style (ice obelisks, stone posts, red lacquer columns, wooden
  posts with orbs), a master's pavilion with stairs (ice dome, hip roof, two-tier pagoda,
  temple cone), lights (ice lanterns, stone lanterns, braziers, post lanterns). WorldContent
  keeps vegetation out of the circle and the pavilion (exclusions).
* **Targets**: three post dummies, a humanoid sparring dummy in the nation's outfit, and the
  `SparringBot` (fireballs, telegraphed) - placed once the ground under them is solid.
* **Lessons** (`TutorialSteps` -> `TutorialDirector`), measured on the real systems:
  look (150 deg of camera rotation), move (12 m), sprint (1.5 s above run speed), jump x2,
  Air: air jump + glide (1 s), dodge x2, light combo (all chain strikes landing on a dummy,
  distinct attack ids within 1.7 s gaps), heavy (tap released), charged heavy (>= 70 %),
  lock-on (the partner steps up), defend (block a fireball), parry (DEFLECTED), the starter
  technique, and - only when a companion exists - call companion (`Events.companion_command`)
  and mount (`Events.mounted`). The partner is idle until lock-on, throws fireballs during
  defend (0.65 s telegraph) and slower ones for the parry (1.0 s).
* **Prompts** (`TutorialPrompt`, right side): "TRAINING · 6 / 12", title, the binding glyphs
  of the active device (keycaps / mouse / controller glyphs via `PromptGlyph`; none on touch),
  the instruction with `{action}` placeholders filled from the live bindings (rebinding-proof;
  touch has its own wording: "Tap Strike in rhythm ..."), a progress bar with units, and
  "Hold [interact] to skip this lesson" (1.2 s hold; every lesson can be skipped, so there is
  no stuck state). Re-renders when the device changes (`UiInput.device_changed`).
* **Completion** (`TutorialCompleteScreen`): blurred arena, emblem, "TRAINING COMPLETE",
  mastered / skipped counts, ENTER THE WORLD (`GameState.new_game(element)` ->
  `Router.WORLD {new_game: true}`) or MAIN MENU.
* **Nothing is saved**: `GameState.is_tutorial` (SaveSystem refuses, the pause menu's SAVE is
  disabled, no region director / autosaves). Death or straying 47 m from the circle resets the
  player to the start (full health).

## Performance notes

* Loading waits for real collision + content instead of guessing; the measured boot is in
  `load_report` (headless no-content ~0.2 s; llvmpipe with content 5-17 s).
* Docks and moored ferries: 6 small kit meshes + 6 shared boat meshes (one per nation, built
  once), visibility ranges 420 / 900 m, two budgeted lights each (LightBudget).
* Directors poll at 2-5 Hz; no per-frame allocations in the hot paths.
* Arena dressing is one kit mesh (4 material slots) + budgeted lights.
* First casts: the shader warm-up above removes the pipeline compilations of the first use of
  every technique (fire, Forward+ llvmpipe: 27 pipelines compiled during the first casts without
  it, 0 with it; the warm-up itself compiles 65 behind the loading screen).

## Testing

* `tools/test.sh test_worldscene` (15 tests): spawns / arrival paths / training sites per
  element (home region, flat circle), ferry routes (two-way, berth to berth, quay faces inland)
  + polyline helpers, region hysteresis + first visits + autosave veto, POI discovery (XP once,
  toast), respawn point choice (home, discovered shrine, visited capitals), and headless
  integration: new game on real ground, continue (position, yaw, health, hour, abilities),
  arrival plays and any key skips onto the player camera, death -> 50 % at the safe point (and
  a save while dead points there), fall-out / world-edge rescue, `travel_to` + a full ferry trip
  (depart / transit / arrive, rode on deck, quay, camera, cleanup), two world round trips leave
  identical root nodes and no held actions, a hook installing a companion, tutorial steps per
  element (bindings resolved on every device), the tutorial lessons + skip + partner + completion
  -> ENTER THE WORLD, nothing saved.
* Playtests (`tools/playtest.sh <name> <out> 960x540`):
  * `worldscene_flow` - boot -> main menu -> ENTER THE WORLD -> element select (ui navigation)
    -> arrival -> gameplay in the home region -> move + attack -> pause -> SAVE GAME -> RETURN TO
    MAIN MENU (root nodes unique, no held input, mouse visible) -> CONTINUE -> same place /
    element / abilities / hour. `ELEMENT=water` or `ELEMENT=air,earth` (default all four). Backs up
    and restores real saves.
  * `worldscene_arrival` - the flight per element at 4 %, 30 %, 60 %, 90 % + first gameplay frame.
  * `worldscene_tutorial` - every lesson completed through simulated input (mouse-look events,
    InputMap actions; the harness re-places the player before target lessons), then completion
    and ENTER THE WORLD. `ELEMENT=fire`, `ALL=1`, `QUICK=1` (site overview only).
  * `worldscene_travel` - ferry landing prompt, destination choice by number key, the sailing
    interlude, arrival, death -> respawn, `travel_to`.

## Known limitations

* Settlements (buildings, piers, walls) are another module: spawns stand on the generator's
  flattened city tiers, the ferry quays get only the landing built here.
* The sparring partner always firebends (SparringBot); per-element enemies come with the
  enemies module.
* Companion lessons and `world_hook.gd` integrations activate once those modules exist.
