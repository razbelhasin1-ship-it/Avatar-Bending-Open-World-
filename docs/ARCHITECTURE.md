# Avatar: The Four Nations — Architecture

An open-world elemental bending action RPG built with **Godot 4.7.2** (GDScript,
Forward+ renderer with automatic fallback to Compatibility/OpenGL 3, Jolt physics).
Nearly all content is procedural/code-built, so the project has no binary art
dependencies apart from fonts, generated audio and generated world data.

## Principles

1. **Bending feel first.** Responsiveness, physicality and readability beat visual spectacle.
2. **Modules talk through contracts**, not through each other's internals: autoload APIs,
   the `Events` signal bus, `Combat`/`HitInfo`, and the documented module APIs below.
3. **Everything verifiable.** Every module ships unit/integration tests (`tests/`) and at least
   one scripted playtest with screenshots (`tests/playtest/scenarios/`).
4. **Scale with budgets.** Distance-based activation, pooling, MultiMesh, LOD and
   `Settings` quality levels; never unbounded spawning.
5. **No fake features.** A button, ability or system either works end-to-end or is not shown.

## Target platforms — desktop AND mobile

The game must be playable on **phones/tablets** (Android/iOS, Mobile renderer; and mobile
browsers via the Web export, Compatibility renderer) as well as desktop (Forward+).

* Every feature must work on all three renderers (`forward_plus`, `mobile`,
  `gl_compatibility`). Forward+-only effects (SSAO, SSIL, SDFGI, volumetric fog, TAA, FSR2)
  are optional extras that degrade gracefully — never required for readability or gameplay.
  Test with `RENDERER=mobile` and `RENDERER=gl_compatibility tools/playtest.sh ...`.
* `Settings.is_mobile_device()` (or `-- --mobile` for testing) selects the `mobile` quality preset
  on first launch (render scale 0.75, MSAA 2x, low shadows, short view distance, low
  vegetation/effects/detail). Every system must scale down via the Settings helpers so the
  `mobile` preset targets 30–60 fps on a mid-range phone: keep draw calls, shader cost,
  overdraw (big transparent particles!), skinned characters and physics bodies on a budget.
* Touch: `Settings.touch_controls_enabled()` turns on the on-screen controls overlay (virtual
  stick, camera drag, bending buttons). The overlay drives the SAME input actions via
  `Input.action_press/release`, and camera look via `Events.look_input(delta_px)`.
  Gameplay code must therefore read input only through actions (+ mouse motion / look_input
  for the camera); camera code must ignore `InputEventMouseMotion` with
  `device == InputEvent.DEVICE_ID_EMULATION` while touch controls are active. Mouse-button
  bindings are stripped from actions in touch mode so taps never trigger attacks.
* UI: everything usable by tap — minimum touch target ~88 px at 1080p, scroll containers
  draggable, no hover-only information, no right-click-only actions, safe-area margins
  (`DisplayServer.get_display_safe_area()`), landscape orientation.

## Running

| Task | Command |
| --- | --- |
| Play (from editor or CLI) | `godot --path .` |
| Jump straight into a scene | `godot --path . -- --scene=world --element=fire` (aliases: world, tutorial, menu, select; add `--mobile` to simulate a phone) |
| Parse-check every script | `tools/check.sh` |
| Unit/integration tests (headless) | `tools/test.sh [filter]` |
| Scripted playtest + screenshots | `tools/playtest.sh <scenario> [out_dir] [WxH]` (Xvfb + software Vulkan) |
| Test Compatibility renderer | `RENDERER=gl_compatibility tools/playtest.sh <scenario>` (or RENDERER=mobile) |

Pass `-- --test` (done by the tools) to stop Settings from resizing the window.
The engine API reference for 4.7 is dumped at `/opt/godot/api/doc/classes/*.xml` in the
dev container — grep it to confirm signatures instead of guessing.

## Directory layout and ownership

```
project.godot            engine config, autoloads, physics layer names   (foundation)
src/autoload/            Events, Settings, GameState, SaveSystem, Audio, WorldData, Router
src/core/                ElementDefs, HitInfo, Combat, HealthComponent, Layers,
                         InputDefaults, ToonMaterials                      (foundation)
src/boot.gd              entry scene script                                (foundation)
assets/shaders/          toon.gdshader, outline.gdshader (+ module shaders in module dirs)
assets/fonts/            Cinzel, Marcellus (Latin UI), Ma Shan Zheng / Zhi Mang Xing (brush CJK)
assets/ui/               SVG emblems/icons                                 (ui)
assets/audio/            generated sfx/ and music/                         (audio)
assets/world/            generated world data (heightmap, maps, json)      (worldgen)
src/world/               terrain, water, sky, weather, snow, vegetation, settlements
src/characters/          humanoid rig, procedural animation, outfits       (characters)
src/creatures/           companion + wildlife models and animation         (creatures)
src/player/              player controller, camera, lock-on, locomotion profiles
src/bending/             ability framework + per-element abilities + VFX
src/enemies/             enemy AI + archetypes
src/companions/          companion behaviour, mount + flight controllers
src/npc/                 NPC routines, dialogue, merchants, trainers
src/quests/              quest system and quest data
src/ui/                  menus, HUD, map, skills, journal, theme
src/fx/                  shared VFX helpers and pools
scenes/                  thin .tscn wrappers (root node + script); content is built in code
tests/unit, tests/integration   TestCase-based tests (tests/test_case.gd)
tests/playtest/          scripted playtests (tests/playtest/playtest.gd)
tools/                   check/test/playtest scripts, worldgen and audio generators
docs/modules/            one page per module: API, data formats, decisions
```

**Foundation files** (`project.godot`, `src/autoload/*`, `src/core/*`, `tests/*.gd` runners,
`tools/*.sh`) are shared. Modules should not edit them; if a change is unavoidable keep it
additive (new function/signal at the end of a section) and call it out in the hand-off notes.
Register shader globals, input or buses at runtime from your module instead of editing
`project.godot`.

## Scene flow

```
boot.tscn → Router → scenes/ui/main_menu.tscn
  01 ENTER THE WORLD → (Continue if save exists) → scenes/ui/element_select.tscn
       → GameState.new_game(element) → Router.goto(scenes/world/world.tscn, {"new_game": true})
       → arrival cinematic in the element's home region → gameplay
  02 TUTORIAL → element picker → scenes/world/tutorial.tscn (training ground, nothing saved)
  03 SETTINGS → scenes/ui/settings_menu.tscn (also used by the pause menu)
  04 EXIT GAME → get_tree().quit()
In game: Esc → pause menu (Resume, Save, Settings, Main Menu, Quit) — saves before leaving.
```

`Router.goto(path, params)` does fade → threaded load → swap → fade-in. Scenes read
`Router.params`. Long setups call `Router.hold_fade()` in `_ready()` and `Router.release_fade()`
when ready. A `goto` made while a transition runs is dropped if it comes before the swap (the
outgoing scene), and queued (latest wins) if the new scene makes it during its fade-in — the
fade blocks the mouse but not keys / pad, so a menu that already marked itself busy would
otherwise wait forever.

## Autoload APIs (summary — read the scripts for details)

* **Events** — global signal bus (game flow, player, combat, camera feel, world, quests, UI,
  companion, settings). Key signals: `footstep(actor, position, yaw, size, weight, surface)`,
  `landed(actor, position, impact, surface)`, `hit_landed(hit, target, result)`,
  `camera_shake(strength, duration)`, `hitstop(duration)`, `notify(text, kind)`.
* **Settings** — `get_value/set_value/apply/save/snapshot/restore_snapshot/restore_defaults/
  apply_preset`, rebinding (`get_bindings/set_binding/reset_bindings`), and helpers every
  renderer-owning system must use: `configure_environment(env)`, `configure_sun(light)`,
  `configure_viewport(vp)`, `view_distance_m()`, `vegetation_density()`,
  `vegetation_distance_m()`, `effects_scale()`, `detail_level()`, `fov()`, `mouse_sensitivity()`,
  `camera_shake_scale()`, `is_feature_supported(name)`. Re-apply on `Events.graphics_settings_changed`.
* **GameState** — element, level/xp/skill points, unlocked/equipped abilities, inventory,
  quests, flags, discovered POIs, companion, player transform; `to_dict()/from_dict()`.
  JSON has one number type: `from_dict` turns whole numbers in the integer records
  (inventory, stats, practice, quest stage / log / objective progress / taken props, companion bond) back
  into ints; free-form `world_flags` keep what JSON gives (read them with `int()` / `float()`).
* **SaveSystem** — atomic JSON slots in `user://saves`; calls `write_save_state()` on group
  `&"persist"` before saving; `save_game/load_game/has_save/latest_slot/get_save_info`. A write is
  read back before it replaces the slot; the previous save is kept as `slot_N.json.bak` and a
  damaged / missing slot is read from its complete `.tmp` or `.bak` instead. `GameState.from_dict`
  falls back to defaults for damaged or wrongly typed fields (a NaN is saved as JSON null).
  `Settings.save_path` (default `user://settings.cfg`) lets tests use a scratch settings file.
* **Audio** — `play_sfx(name, pos)`, `play_2d`, `play_ui`, `play_music(track)`,
  `set_ambience(name)`. Missing files are skipped silently. Names are listed below.
* **WorldData** — terrain height/normal, biome, surface, region, water, snow depth, water
  sources, POIs, spawn points, safe ground. Works without any terrain loaded.
* **Router** — scene transitions (see above).

## Core contracts

### Elements
`ElementDefs.Element { NONE=-1, AIR=0, EARTH=1, FIRE=2, WATER=3 }` (saved; never renumber).
`ElementDefs.DATA[e]` holds names, tagline, home region, companion id, colors, CJK glyph/virtue
(水善 土强 火烈 气和), and `emblem_path(e)` → `res://assets/ui/emblem_<id>.svg`.

### Damage
* Damageable = node in group `&"damageable"` with `var team: int` (`Combat.Team`) and
  `func receive_hit(hit: HitInfo) -> int` returning `Combat.Result`
  (IGNORED, HIT, BLOCKED, DEFLECTED, DODGED, KILLED). Optional `is_alive()`.
* Attacks build a `HitInfo` (`HitInfo.make(...)`), then `Combat.deal(target_or_collider, hit)`.
  `Combat.query_sphere/query_box/query_cone` return unique damageables in an area.
  Multi-part attacks reuse one `attack_id` so a target is hit once per attack.
* Reactions: NONE, FLINCH, STAGGER, KNOCKBACK, KNOCKDOWN, LAUNCH, PULL, FREEZE (+ `force`,
  `lift`, `stun_time`, `poise_damage`). `HealthComponent` tracks health + poise.
* Every successful hit must have visible + audible feedback (impact VFX, sound, hit flash,
  hitstop for heavy hits). Never let VFX imply a hit that gameplay did not apply.

### Physics layers (`Layers`)
WORLD 1, PLAYER 2, ENEMY 3, NPC 4, COMPANION 5, PROJECTILE 6, CONSTRUCT 7 (earth/ice walls),
WATER 8, INTERACTABLE 9, TRIGGER 10, WILDLIFE 11, HURTBOX 12. Helper masks: `SOLID`,
`PLAYER_ATTACK_TARGETS`, `ENEMY_ATTACK_TARGETS`, `CAMERA_BLOCKERS`.

### Input actions (`InputDefaults.ACTIONS`, rebindable via Settings)
move_forward/back/left/right, jump, sprint, dodge, descend, look_* (pad), lock_on,
attack_light (LMB), attack_heavy (RMB, hold to charge), block (Q), ability_1..4 (1–4),
ability_special (R), interact (E), companion_call (G), mount (F), pause (Esc), open_map (M),
open_skills (K), open_journal (J). Mouse look is read from `InputEventMouseMotion`.

### Look and feel
* Art direction: the animated series — clean silhouettes, saturated but harmonious palettes per
  nation, soft two-tone shading with ink outlines on characters/creatures, painterly skies,
  strong atmospheric perspective. Use `ToonMaterials.make(color, opts)` for characters,
  creatures and props (adds the outline pass). Terrain/water/sky use their own shaders tuned to
  sit beside the toon look.
* Forward is **-Z** for every character, creature and prop. 1 unit = 1 meter. Humans ≈ 1.75 m.
* UI fonts: Cinzel (titles), Marcellus (body), Ma Shan Zheng (brush CJK glyphs).
  Palette: ink #1b1512, parchment #efe3c8, gold #e7b552; element colors in `ElementDefs`.

## Module contracts (implemented by the module, consumed by others)

### World data (`tools/worldgen/`, `assets/world/`, `src/autoload/world_data.gd`)
Offline Python generator bakes an 8192 × 8192 m world centered on the origin (north = -Z):
heightmap, biome/splat maps, region map, roads, cities, POIs, spawn points. `WorldData` loads
them and answers all queries. Data formats are documented in `docs/modules/worlddata.md`.
Layout: Northern Water Tribe in the arctic north; Earth Kingdom (Ba Sing Se) on the large
central/eastern continent; Fire Nation volcanic archipelago in the south-west with the capital
in a caldera; Southern Air Temple on high southern peaks. Walkable links (frozen strait,
mountain pass) plus ferries between ports and flight everywhere.

### World rendering (`src/world/`)
`WorldRenderer` node: clipmap terrain + collision streaming around a focus node, ocean/lake
water, sky + day/night, weather, snow trail deformation (driven by `Events.footstep`/`landed`).
Exposes `set_focus(node)`, time-of-day and weather control, and honours Settings.

### Humanoid characters (`src/characters/`)
`HumanoidRig` (Node3D, faces -Z, feet at origin) built from a config (nation outfit, build,
colors, seed) with a procedural animation system: per-style locomotion, stances, actions with
timed events, hit reactions, foot IK, sockets. Emits `Events.footstep`. API documented in
`docs/modules/characters.md`; `AnimLibrary.register(name, clip)` lets other modules add moves.

### Creatures (`src/creatures/`)
`CreatureRig` for sky_bison, dragon, polar_bear_dog, badgermole (+ wildlife) with procedural
locomotion (ground + flight), actions and sockets (`saddle`, `head`). API in
`docs/modules/creatures.md`.

### UI (`src/ui/`, `scenes/ui/`)
main_menu, element_select, settings_menu (reusable), pause_menu, hud, loading; `UiTheme`.

### Audio names (`assets/audio/sfx|music/<name>[ _1.._6].wav|ogg`)
UI: ui_hover, ui_click, ui_back, ui_confirm, ui_open, ui_close, ui_error, ui_select_element,
ui_notify, ui_quest, ui_levelup, ui_discovery.
Steps: step_snow, step_ice, step_stone, step_grass, step_dirt, step_sand, step_wood,
step_water, step_ash, step_heavy, land_soft, land_heavy, land_snow.
Body: whoosh_light, whoosh_heavy, punch_impact, kick_impact, body_fall, hit_flesh,
block_impact, dodge_whoosh, jump, parry.
Air: air_blast, air_sweep, air_dash, air_shield_loop, air_jump, air_tornado_loop, air_push,
air_impact. Earth: earth_raise, earth_launch, earth_impact, earth_wall_rise, earth_crumble,
earth_stomp, earth_quake, earth_spikes, earth_armor, rock_debris. Fire: fire_ignite,
fire_blast, fire_whoosh, fire_impact, fire_explosion, fire_loop, fire_charge_loop, fire_ring,
fire_extinguish, fire_lightning, fire_lightning_crackle, fire_lightning_loop. Water: water_whip,
water_splash, water_blast, water_shield_loop, water_surge, water_draw, ice_form, ice_shatter, ice_impact, water_wave, water_heal_loop.
Creatures: bison_call, bison_groan, dragon_roar, wing_flap_large, dog_bark, dog_growl,
badgermole_snort, badgermole_dig, creature_step_heavy.
Ambience loops: amb_arctic_wind, amb_blizzard, amb_city, amb_forest, amb_mountain_wind,
amb_volcanic, amb_ocean_waves, amb_night, amb_rain, amb_temple.
Stingers: pickup, quest_complete, discovery, level_up, gong, wind_chime.
Music (looping): music_menu, music_select, music_water_tribe, music_earth_kingdom,
music_fire_nation, music_air_temple, music_combat, music_tutorial.

## Testing rules

* `tools/check.sh` and `tools/test.sh` must pass before every commit.
* Each module adds `tests/unit/test_<module>.gd` and at least one playtest scenario that takes
  screenshots; look at the screenshots — a test that only proves "no crash" is not enough for
  visual or feel features.
* Never leave the player able to get stuck: every locking state needs a timeout/exit path.
