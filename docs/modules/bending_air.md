# Airbending module (`bending_air`)

Air is the most mobile, most acrobatic element: wide gusts that push and redirect rather
than crush, a long air dash usable twice per jump, hang time on every aerial strike, a
ball of air to ride at 16.5 m/s and up walls, and a signature tornado that lifts a whole
group. Everything runs on the shared bending framework (`docs/modules/bending.md`):
`AbilityDef` data, `BendingAbility` scripts driven by clip events, `BendingHits`,
`BendingProjectile`. AI casters use the same scripts through a non-player
`BendingContext`.

| Piece | Files |
| --- | --- |
| Kit data | `src/bending/kits/air/air_kit.gd` (`AirKit`: defs, tree, trainers, branches, enemy data) |
| Clips | `air_clips.gd` (`AirClips`: 10 Ba Gua clips with timed events) |
| Shared | `air_common.gd` (`AirCommon`: gusts, aim, airborne / height, hang time, input) |
| Core kit | `air_combo.gd`, `air_blast.gd` (+ Gale Drop), `air_shield.gd`, `air_dash.gd` |
| Techniques | `air_push.gd`, `air_sweep.gd`, `wind_blade.gd`, `air_scooter.gd`, `vortex_ward.gd`, `air_tornado.gd` (signature) |
| World | `air_env.gd` (`AirEnv`), `air_prop.gd` (`AirProp`), `air_traversal.gd` (`AirTraversal`) |
| FX | `src/fx/air/`: `air_wind_field.gd` (`AirWindField`), `air_wind.gdshaderinc`, `fx_air_sheet.gdshader` + `air_sheets.gd` (`AirSheets`), `air_wave_fx.gd`, `air_vortex_fx.gd`, `air_ball_fx.gd`, `wind_blade_fx.gd` + `fx_wind_blade.gdshader`, `air_ward_fx.gd` |
| Icons | `src/bending/kits/air/icons/*.svg` (+ `gen_air_icons.py`) |
| Dev | `src/bending/kits/air/dev/air_garden.gd` (`AirPlaytestGarden`: a patch of real vegetation, grass, a banner, props, torches) |
| Tests | `tests/unit/test_bending_air.gd` (18 tests), playtests `bending_air_arena`, `bending_air_enemies`, `bending_air_world`, `bending_air_mobile`, `bending_air_poses` |

## Abilities

All numbers are the `AbilityDef` data in `air_kit.gd` (tune there; scripts read
`param()` / `hit`).

### Core kit (always equipped)

| Slot | Ability | What it does |
| --- | --- | --- |
| light | **Air Combo** | 3 strikes: left palm gust (7 dmg, flinch), spinning hook-kick gust low along the ground (8), double-palm burst (11, stagger). Each gust is a travelling volume (36 / 32 / 38 m/s, 6.5-9 m) that pushes the target back. 5 frames press -> active (target <= 6). In the air every strike holds the bender aloft (hang time). |
| heavy | **Air Blast** | Tap: a fast gust (14, stagger). Hold (1.0 s full): wind spirals into a ball between the palms, release a wide blast that hurls targets back; in the air the charge hovers. **Gale Drop**: pressed 2.4 m+ above the ground, the bender dives at 24 m/s and slams a ring of wind (3.8 m, 18 dmg, knockdown) on the landing clip's `impact`; with a lock-on (or aim target) within 8 m the dive homes onto it. |
| defense | **Air Shield** | Spinning current: 70 % frontal block, deflects projectiles aside; a parry (first 0.15 s) sends projectiles back and blows melee attackers off their feet. |
| dodge | **Air Dash** | Long wind dash with i-frames; **twice per jump** in the air (`params.air_dashes`, refilled on landing). Perfect dodge leaves a gust that knocks the attacker back. |
| innate | **Air Jump** | Double jump + glide (hold jump while falling; LocomotionProfile), cushioned landings. |

### Techniques (4 slots) and signature

| Ability | Tier / branch | Chi / cd | Behaviour |
| --- | --- | --- | --- |
| **Air Push** (starter) | 1 Gale | 16 / 4 s | Gather between the palms (hold widens the ring 4.4 -> 6.8 m), then throw both palms out: a ring of wind races outward. Each target is hit once **when the visible front reaches it** (`AirWaveFx.front(p, R)` is also the gameplay front): within 2.4 m (3.2 charged) knockdown (12), beyond knockback (8). Enemy projectiles in the ring are scattered outward and become the bender's. Usable in the air. |
| **Air Sweep** (starter) | 1 Circle | 22 / 5.5 s | 360 degree sweep kick, knockback around the bender (14). |
| **Wind Blade** | 2 Gale | 18 / 3.5 s | Spinning kick throws a crescent of compressed air (40 m/s, 24 m): pierces every target in line once (16, stagger, heavy). In the air: an axe-kick that hops up and cuts down at the target. Deflectable. |
| **Air Scooter** | 2 Flight | 12 + 4/s / 1.5 s | Mobility ride, no attacks: hop onto a spinning ball, 16.5 m/s with carving turns, coasts to a hover without input, skims water, runs up steep static walls for 0.9 s (pops over the top or peels off). Jump launches off with the momentum (then air jump / glide); pressing the technique again hops down; a dodge dashes off. Ends at 0 chi, after 22 s or when hit hard. |
| **Vortex Ward** | 3 Circle (trainer) | 24 / 10 s | 3.5 s sphere of wind around the bender (walks freely, 35 % damage reduction): catches enemy projectiles and orbits them, repels close attackers every 0.35 s; on expiry or a second press it bursts, flinging the held projectiles at the nearest foes. |
| **Air Tornado** (signature) | 4 Gale (trainer) | 100 Focus | Stirring Ba Gua circle (2.6 s clip, 60 poise armor, 50 % DR): a funnel forms at the target (or aim point, 2.5-14 m), drifts toward the locked target, pulls everyone within 7.5 m in, lifts those within 2.4 m up the column (orbiting, pulse hits 4 dmg without hitstop spam), swallows enemy projectiles, then the clip's `impact` flings the whole column outward (30 dmg, launch, unblockable). |

Counterplay (enemies get the same rules): every technique has a readable anticipation on
its clip (gather / wind-up keys before `release`), wide moves are slow to start and
leave recovery, Wind Blade is deflectable, Air Push can be dodged through (skirmishers do),
the tornado has a long telegraph ring and the caster is rooted while stirring it.

### Clips (`AirClips.ensure()`, registered into `AnimLibrary`)

| Clip | Events | Used by |
| --- | --- | --- |
| `air_push_gather` (loop) | - | Air Push hold |
| `air_push_release` | gather 0.16, release 0.3, recover 0.72 | Air Push |
| `air_combo_kick` | impact 0.42, recover 0.8 | combo step 2 |
| `wind_blade_kick` / `wind_blade_air` | release 0.44 / 0.46, recover 0.84 / 0.86 | Wind Blade ground / air |
| `air_scooter_ride` (loop) | - | Air Scooter |
| `vortex_ward_hold` (loop, upper body) | - | Vortex Ward |
| `air_tornado_cast` | gather 0.06, release 0.2, impact 0.86, recover 0.93 | Air Tornado |
| `air_dive` (loop) / `air_slam_land` | - / impact 0.1, recover 0.74 | Gale Drop |

Gameplay happens on the events (`release` / `impact`), never on timers; rig-less casters
(AI without a rig, tests) get the same events from `play_clip` virtual timing.

## Progression

`AirKit.tree()` returns the technique tree for the skill-tree UI (same format as the other
elements), sorted by tier then column:

```gdscript
[{id, tier, branch, column, requires, level, practice, trainer, cost, starter, signature}, ...]
# tier 1  air_push (gale, starter)         air_sweep (circle, starter)
# tier 2  wind_blade (gale)  lvl 3, needs air_push, practice 6 casts, 1 point
#         air_scooter (flight) lvl 3, needs air_sweep, practice 6, 1 point
# tier 3  vortex_ward (circle) lvl 5, needs air_scooter, practice 6, trainer at_tashi, 1 point
# tier 4  air_tornado (gale, signature) lvl 7, needs wind_blade, trainer at_tashi, 2 points
```

* Gates are `AbilityDef.unlock` (`AbilityRegistry.can_unlock` returns the first missing one:
  `level`, `prerequisite`, `trainer`, `practice`, `skill_points`).
* Practice: every **player** cast of a technique calls `AirEnv.practiced()` ->
  `GameState.add_practice(id)`; AI casts never count. A tier-2+ technique needs `practice`
  casts of its prerequisite.
* Trainers: `AirKit.TRAINERS` - `at_tashi` "Master Tashi", Southern Air Temple (teaches
  Vortex Ward and Air Tornado). A lesson sets the flag `trained_at_tashi_<ability>`
  (`GameState.set_flag`); quests / dialogue own that.
* `AirKit.BRANCHES` gives the UI labels (Gale, Circle, Flight).
* Slots: any technique goes into `technique_1..4`, the tornado into `signature`; the HUD,
  the controller bar and the touch buttons read `PlayerCharacter.get_ability_slot_info(i)`
  (0-3 techniques, 4 signature). Keyboard 1-4 / R, controller and touch buttons all go
  through the `ability_1..4` / `ability_special` InputMap actions.

## Aerial play

* **Hang time**: `AirCommon.hang(ctx, delta, lift)` - while airborne and the per-airtime
  budget (`HANG_BUDGET` 1.6 s, meta `air_hang`) lasts, gravity drops to 6 % and the fall is
  braked. Aerial combo strikes, the Air Blast charge, Air Push and Wind Blade use it, so an
  airbender can chain jump -> strikes -> air dash -> strikes -> Gale Drop.
* **Air dashes**: 2 per airtime (meta `air_dashes_used`); `AirTraversal` refills both
  budgets on landing.
* `AirCommon.airborne(ctx)`: not on the floor AND more than 0.3 m above the ground below
  (bodies that never moved read as grounded).

## Environment

### Wind impulses for vegetation, grass and cloth

`AirWindField` (a node under the FX root) keeps **4 slots** of short-lived wind impulses and
writes them every frame into global shader uniforms registered by `WorldShaderGlobals`:

| Global | Type | Meaning |
| --- | --- | --- |
| `air_impulse_a` | mat4 | column i = (centre.xyz, radius m) |
| `air_impulse_b` | mat4 | column i = (dir.x, dir.z, mode, strength m/s); mode 0 directional, 1 radial, 2 vortex |
| `air_impulse_on` | float | 0 while no slot is live (shaders skip the work) |

```gdscript
var id := AirWindField.add(self, pos, 4.0, 22.0, AirWindField.RADIAL)          # one-shot burst
var g := AirWindField.add(self, head, 2.5, 18.0, AirWindField.DIRECTIONAL, dir, INF)  # held
AirWindField.move(g, proj.global_position, dir)   # moving gust head
AirWindField.release(g)                            # spring back + fade
```

Strength rises in 0.07 s, holds, then decays as a damped spring (1.5 Hz, the plants swing
back past rest). Held impulses are released when their owner node is freed or after 8 s.
When all 4 slots are busy the weakest is replaced.

Shaders include `res://src/fx/air/air_wind.gdshaderinc` and call
`vec3 air_impulse_at(vec3 world_pos)` (horizontal wind m/s). Already wired:
`veg_common.gdshaderinc` (trees, shrubs, bushes, flowers, their outlines), `grass.gdshader`
(blades flatten, clamped so they never stretch), `cloth.gdshader` (banners / awnings snap
out and flap harder). Any other wind-swayed shader can include it the same way.

### `AirEnv.blow()` - the one call every Air technique makes

```gdscript
AirEnv.blow(ctx, center, radius, power, {"mode": &"radial"})         # push ring
AirEnv.blow(ctx, head, 2.0, 0.6, {"dir": d, "ground": false})        # passing gust
```

`power` 0.3 light gust .. 1 strong blast .. 2 tornado. opts: `mode` (`&"radial"`,
`&"directional"` + `dir`, `&"vortex"`), `ground`, `props`, `fires`, `plants` (all true by
default), `hold`, `by`. It:

* adds a wind impulse (above);
* **ground by surface** (`ctx.surface_at` / `WorldData.get_surface`): dust in the ground
  colour on dirt / stone / sand / ash, leaves on grass, snow on snow / ice (strong blasts
  scour a hollow into the snow trails via the renderer's `snow.add_crater`), spray on water;
  `AirEnv.puff()` is the ring-less variant used along gust paths, rides and glide wakes;
* **physics props**: every `RigidBody3D` within reach is shoved (sphere query on
  `PROJECTILE | WORLD`); nodes in group `&"wind_reactive"` get
  `wind(impulse: Vector3, at: Vector3, by: Node)` instead;
* **fires**: the shared EXTINGUISH hook - nodes in group `&"extinguishable"` with
  `func extinguish(by: Node, at: Vector3) -> bool` (optional `var extinguish_radius`) are
  blown out. `AirEnv.extinguish(from, pos, radius, by)` can be called by any module.

### `AirProp` - loose props

Clay pots (shatter on hard knocks), crates, baskets, barrels as `RigidBody3D` with toon
meshes built in code. Layer `Layers.PROJECTILE` (characters walk through and kick them),
mask `WORLD | CONSTRUCT | PROJECTILE`, group `wind_reactive`. Budget per scene by
`Settings.detail_level()`: 10 / 18 / 28 / 40. `AirProp.spawn(parent, &"pot", pos, yaw)`,
`AirProp.scatter(parent, center, radius, count)`. Settlement / quest modules can scatter
them where loose clutter makes sense.

### `AirTraversal` - the world answering movement

Attached to the player on `Events.player_spawned` (dormant for other elements): cushioned
landings (impact >= 5) blow a ring through the grass and kick up the ground, air jumps press
the grass down under the feet, gliding below 6 m drags a held wind impulse + puffs along
(a wake through grass, bushes, snow). The Air Scooter drives its own wake / dust / spray
trail and a vortex impulse under the ball.

## AI / enemy usage

Every Air ability runs for any `BendingContext` (no player assumptions: input is read via
`AirCommon.input(ctx)` which is null for AI). Non-player specifics: Air Push releases after
`params.ai_hold` (0 = tap), the scooter rides `ai_time` (5 s) following the caster's move
intent, practice never counts.

`EnemyAbilities.LOADOUTS` has no Air entry (no air enemy archetype exists on this
branch), so the kit provides the pieces:

```gdscript
EnemyArchetypes.register(&"air_sparring_monk", AirKit.enemy_archetype())   # a sparring airbender
var e := EnemyBase.create(&"air_sparring_monk")
add_child(e)
AirKit.equip_enemy(e.controller)            # enemy-tuned, unregistered copies (EnemyAbilities.variant)
# or for any bender: archetype["attacks"].append(AirKit.enemy_attacks()[&"wind_blade"])
```

`AirKit.ENEMY_LOADOUT` = light air_combo (2 steps), heavy air_blast, defense air_shield,
dodge air_dash, technique_1 air_push, technique_3 wind_blade. `enemy_attacks()` has ready
`EnemyActions` entries (telegraph, range, cooldown, ring, glint) for push, sweep, blade and
tornado. The enemies playtest shows the sparring airbender using jabs + blast against the
player through the normal brain.

## Performance

* Gusts are pooled `BendingProjectile`s; all FX are pooled through `FxLib`
  (`air_wave`, `air_vortex`, `air_ball`, `wind_blade`, `air_ward`, swirls, gusts).
* Wind impulses: 4 fixed slots, one uniform write per frame, a single branch in the shaders
  when idle. Ground puffs are capped per gust (max 4) and spaced (1.6 m); snow scouring at
  most one crater per 2 frames.
* Props are budgeted by detail level and sleep until touched; kicks are checked every 3
  ticks.
* `Settings.effects_scale()` scales particle counts in `FxBurst` (0.35 on mobile).

## Measurements

Unit test `test_hit_vfx_parity_and_latency_report` (frames at 60 Hz, press -> active):
combo 5 / 5 / 5, Air Push 13 (tap; gather -> release), Wind Blade 16 (kick wind-up),
Air Scooter 2. 31 / 31 hits showed hit VFX.

Frame times in this container (software rendering, llvmpipe; only the deltas are
meaningful):

| Where | Baseline | With Air effects |
| --- | --- | --- |
| Arena, mobile renderer, 1600x720 (`bending_air_mobile`) | 88 ms idle | 112 ms during the tornado |
| Garden patch, mobile renderer | 214 ms calm | 238 ms under Air Push (impulse + props + torches) |
| Real world meadow, Forward+, 960x540 (`bending_air_world`) | 407 ms | 412 ms during the push wind; tornado 631 ms (2 bandits lifted, debris, funnel) |

The vegetation / grass impulse itself costs nothing measurable (the push delta is within
noise); the tornado's cost is its transparent funnel layers and two ragdolling enemies.

## Playtests

```
tools/playtest.sh bending_air_arena <dir> 960x540        # TECH=core,aerial,push,blade,scooter,ward,tornado,env
tools/playtest.sh bending_air_enemies <dir> 960x540      # PART=group,sparring
tools/playtest.sh bending_air_world <dir> 960x540        # SPOT=x,z
RENDERER=mobile MOBILE=1 tools/playtest.sh bending_air_mobile <dir> 1600x720
tools/playtest.sh bending_air_poses <dir>                # pose sheets of the Air clips
```

* `bending_air_arena`: every technique at anticipation / active / impact from observer
  cameras and the player camera; core kit (combo, tap + charged blast, shield parry vs the
  bot's fireball, dash), aerial chain (hang-time strikes, 2 air dashes, glide, Gale Drop),
  Air Push ring on sparring dummies, Wind Blade through two, the scooter (ride, 7 m wall
  run, hop down, pool skim, jump off), Vortex Ward catching fireballs and bursting, the
  tornado lifting 3 dummies, the garden (grass / bushes / banner under gusts, pots knocked
  over, torches blown out, snow scoured, glide wake).
* `bending_air_enemies`: a real group fight (bandit brawler + skirmisher + firebender):
  push when surrounded, blade at the ranged one, combo, ward vs fire bolts, tornado on the
  group, scooter out + Gale Drop back; then the sparring airbender fighting the player.
* `bending_air_world`: the world near the Southern Air Temple (meadow 320 m from the Air
  spawn): gust, push, blade, scooter + glide, tornado on two bandits, then a fast-travel
  hop to the nearest snowfield (by the Northern Water Tribe; the temple's peaks have no
  snow surface) where push + sweep scour the snow.
* `bending_air_mobile`: every technique cast from its touch button, the scooter steered by
  the stick and launched with the jump button, slot info, frame times.

## Changes outside the module

All additive and minimal:

| File | Change |
| --- | --- |
| `src/bending/ability_registry.gd` | `starter_techniques()` sorts by `String` (StringName order is not alphabetical; identical to the other element branches) |
| `src/bending/bending_controller.gd` | optional `on_repress() -> bool` hook: a second press of the slot of the running ability goes to it (Air Scooter hop down, Vortex Ward burst) |
| `src/bending/bending_feedback.gd` | hits with meta `&"no_hitstop"` skip hitstop / shake (tornado pulse ticks) |
| `src/player/player_character.gd` | `can_bend_airborne()` also allows slots whose def has `params.in_air` (identical to bending_fire's change) |
| `src/world/weather/world_shader_globals.gd` | `MAT4` type + `air_impulse_a`, `air_impulse_b`, `air_impulse_on` defaults + doc rows |
| `assets/shaders/content/veg_common.gdshaderinc`, `grass.gdshader`, `cloth.gdshader` | include `air_wind.gdshaderinc` and add the impulse term |
| `tests/unit/test_bending.gd` | starter checks use `.has()` (Air now has two starters; identical to the peers) |

## Known limitations

* No Air enemy archetype ships in `EnemyArchetypes` (and `EnemyAbilities.LOADOUTS` has no
  Air entry); `AirKit.enemy_archetype()` / `equip_enemy()` provide one for quests / arenas.
  The enemy brain rarely picks push / blade (range windows) - it used jabs + blast in the
  playtest.
* World lanterns and settlement props are static meshes: only vegetation, grass, cloth,
  `AirProp`s, `wind_reactive` nodes and `extinguishable` nodes react. The fire module's
  braziers / burning grass join through the `extinguishable` group contract (not on this
  branch, so only the playtest torches were verified).
* The scooter raises the rig visually (`ride_height`); the capsule stays on the ground, so
  low ceilings are checked at capsule height.
* Wall runs only trigger on static geometry (characters / props / rigid bodies are not
  runnable).
* No new audio files: Air reuses the audio module's air bending sounds (`push`, `dash`,
  `special_loop`, `cast_light`, `cast_heavy`, `jump`).
* Frame times above come from software rendering in CI-like containers, not a phone.
