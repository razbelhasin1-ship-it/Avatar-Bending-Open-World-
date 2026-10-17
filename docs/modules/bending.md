# Bending module

The ability framework, the four element kits (core kit + one starter technique each), the
VFX library they draw with, and the dev targets (training dummy, sparring bot). Used by the
player (`docs/modules/player.md`) and by any non-player caster (enemies, companions,
scripted sequences): abilities only talk to a `BendingContext`.

| Piece | Files |
| --- | --- |
| Data | `src/bending/ability_def.gd` (`AbilityDef`), `ability_registry.gd` (`AbilityRegistry`) |
| Runtime | `bending_ability.gd` (`BendingAbility`), `bending_controller.gd` (`BendingController`), `bending_context.gd` (`BendingContext`) |
| Gameplay helpers | `bending_hits.gd` (`BendingHits`), `bending_projectile.gd` (`BendingProjectile`), `bending_construct.gd` (`BendingConstruct`), `water_source.gd` (`WaterSource`), `bending_feedback.gd` (`BendingFeedback`) |
| Base abilities | `src/bending/core/`: `ComboAbility`, `ChargeAbility`, `DefenseAbility`, `DodgeAbility` |
| Kits | `src/bending/kits/<element>/<element>_kit.gd` (defs) + one script per ability; shared `AirCommon`, `EarthCommon` |
| Clips | `src/bending/anim/bending_clips.gd` (`BendingClips`: air_dash, air_glide, air_jump_flip, water_skate, water_gather_hold, earth_slide_fwd, earth_hold, flame_sweep_kick, fire_guard_hold) |
| VFX | `src/fx/` (`FxLib`, `FxBurst`, `FxRing`, `FxFlash`, `FxDecal`, `FxDebris`, `FxMeshes`, `WaterStream`, `FireFx`, `AirFx`, `EarthFx`, `IceFx`, `ImpactFx`, shaders in `src/fx/shaders/`) |
| Dev | `src/bending/dev/training_dummy.gd` (`TrainingDummy`), `sparring_bot.gd` (`SparringBot`), `scenes/dev/combat_arena.tscn` |
| Tests | `tests/unit/test_bending.gd`, `tests/unit/test_player.gd` (combat part), `tests/playtest/scenarios/player_elements.gd`, `player_fx_gallery.gd` |

## Concepts

* **AbilityDef** (Resource, pure data): id, element, slot (`LIGHT HEAVY DEFENSE DODGE TECHNIQUE
  SIGNATURE PASSIVE INNATE`), name, description, icon, chi / focus cost, cooldown, design
  timings (`startup active recovery`), `cancel_window`, clip (+ speed / start), charge
  (`charge_time`, `max_hold`), default `hit` dictionary, free-form `params`, `fx`, `unlock`
  rules, `starter`, `poise_armor`, and `script_path` (the `BendingAbility` subclass).
* **BendingAbility** (RefCounted, one instance per use): lifecycle below. Gameplay is spawned
  on the clip's timed events (`release`, `impact`, `gather` ...), never on a free timer.
* **BendingController** (Node on the caster): slots (`light heavy defense dodge technique_1..4
  signature`), `request(slot)` / `release(slot)` / `tick(dt)`, cooldowns, light-chain
  bookkeeping (`CHAIN_GRACE` 0.35 s), `ability_started / ability_ended / ability_failed`
  signals (player: also `Events.ability_used / ability_failed`), HUD slot info.
* **BendingContext** (RefCounted): the caster abstraction. Body, rig, element, team,
  resources (or null = unlimited), aim provider, `on_hit` callback, helpers (sockets, ground,
  aim with lead, chi / focus) and the **movement request** the owner applies every tick:
  `move_mode` `BRAKE / FREE (x move_speed_scale) / DRIVE (move_velocity) / ROOT / HOLD`,
  `gravity_scale`, `face_dir` + `face_rate`, `poise_armor`, `invulnerable`,
  `damage_reduction`, `no_focus`.
* **AbilityRegistry**: all defs by id (`get_def`, `for_element`, `core_kit(e)`,
  `starter_techniques(e)`, `grant_starters(e)` for a new game, `can_unlock(id)` -> `&""` or
  `&"level" / &"prerequisite" / &"trainer" / &"quest" / &"practice" / &"skill_points" /
  &"unlocked" / &"unknown"`). Other modules may `register(def)` more at runtime.

### Lifecycle (driven by BendingController)

```
request(slot) -> cooldown / chi / focus checks -> ability.can_use() -> spend -> begin()
   tick: _tick (virtual events) -> on_event(event) ... update(dt) ... finish()
   release(slot) -> on_input_released()          (charges, holds)
   interrupted -> on_cancel(reason)              (hit, dodge-cancel, death, respawn)
   normal end -> on_finish()
   hard safety: ability.max_time (default 4 s)  -> ends no matter what
```

`request()` returns `&""` (started / chained), `&"busy"` (cannot start yet: keep the press
buffered) or a failure reason (`&"cooldown"`, `&"chi"`, `&"focus"`, `&"empty"`, custom).
Dodge and defense may cancel another ability once `time >= cancel_at` (the clip's `recover`
event, or `def.cancel_window`).

**Virtual events**: `play_clip()` schedules the clip's events on the ability clock. A rig-less
caster gets them exactly on time; with a rig they are a safety net 0.12 s late if the rig
never delivers them (clip replaced). So the same ability works for the player, enemies and
tests without a body.

### Non-player casters

```gdscript
var ctx := BendingContext.new(enemy_body, enemy_rig, ElementDefs.Element.FIRE, Combat.Team.ENEMY)
ctx.aim_provider = func() -> Dictionary:
    return {"direction": (player_chest - hands).normalized(), "target": player, "point": player_chest}
var bc := BendingController.new()
enemy_body.add_child(bc)
bc.setup(ctx)                       # loads the element's core kit
bc.set_slot(&"technique_1", AbilityRegistry.get_def(&"flame_sweep"))
bc.auto_tick = true                 # or call bc.tick(delta) from the AI
bc.request(&"heavy"); ...; bc.release(&"heavy")
# Each tick apply ctx.move_mode / move_velocity / face_dir ... to the body.
```

Enemy hits use `Layers.ENEMY_ATTACK_TARGETS`, never grant Focus, and go through the same
`BendingHits` / projectiles. `SparringBot` is a minimal example (telegraph ring + fireball or
melee sweep, `attack_in(seconds, kind)` for timed tests).

## Hits, projectiles, constructs

Hit dictionary (`AbilityDef.hit`, overrides per step): `{"damage", "reaction"
(HitInfo.Reaction), "force", "lift", "stun", "poise", "heavy", "projectile", "deflectable",
"unblockable", "status": {"burn": s, "soaked": s, "chill": s, "frozen": s}}` -> `ctx.make_hit()`.

* `BendingHits.deliver(ctx, target, hit)` - **once per attack_id per target**, team check,
  `Combat.deal`, feedback (`BendingFeedback.on_result`), `ctx.on_hit`. `sphere()`, `cone()`,
  `sweep()` (capsule) find targets and require **line of sight** (walls and constructs block).
  A new attack id per use (`ability.attack_id`, `new_attack()` for multi-hit moves).
* `BendingProjectile.launch(ctx, from, dir, speed, hit, opts)` - pooled; continuous collision
  (sphere `cast_motion` each tick: no tunnelling at 200 m/s); `pierce`, `gravity`,
  `radius_growth`, `homing` (deg/s for `homing_time`), aim lead (`ctx.aim_dir_from(from, speed,
  lead)`), `on_impact(proj, pos, normal, target)`, `on_step`, `on_finish(visual)`, `visual`
  node placed every tick. Defenders call `redirect(dir, team, source)` (new attack id,
  x1.15 speed, x1.25 damage) or `destroy()`. `BendingProjectile.incoming(pos, r, team)` lists
  threats. Stops on `WORLD | CONSTRUCT`.
* `BendingConstruct.raise(ctx, ground_pos, facing, {"kind": &"earth"|&"ice", "size", "hp",
  "lifetime", "rise_time", "launch": {"lift", "damage"}, "follow", "follow_offset"})` -
  AnimatableBody3D on `Layers.CONSTRUCT` (blocks movement, projectiles, line of sight and the
  camera), damageable by the other team (heavy x1.6, fire vs ice x1.8), crumbles / shatters
  when broken or expired, launches whoever stands where it erupts (once), never collides with
  its caster. `hit_filter` lets the owner resolve hits (Earth Shield parries on the slab).
* `WaterSource.find(ctx)` -> `{found, position, kind, distance}` (WorldData water within
  12 m, or snow / ice underfoot). Without a source: **chi x1.3, size x0.7**
  (`WaterSource.chi_cost`, `size_mult`); `WaterSource.draw(ctx, src, duration)` streams water
  from the source to the hand (canteen curl without one).

### Feedback rules (BendingFeedback)

Only for hits gameplay applied (a hit VFX is shown iff damage was applied - tested):
`HIT/KILLED` -> `ImpactFx.hit` + hitstop 0.04 s (light) / 0.08 s (heavy or kill) + shake +
Focus +6 / +10 for the player; `BLOCKED` -> block sparks + light shake; `DEFLECTED` -> hitstop
0.12 s (parries). Hitstop and shake are requested at most once per physics frame (strongest
wins). Target hit sounds come from Audio (`Events.hit_landed`); abilities play casts, loops
(`Audio.start_bending_loop`) and world impacts (`BendingFeedback.world_impact`).

## Element kits

| Element | Light (chain) | Heavy (tap / charge) | Defense | Dodge | Starter technique |
| --- | --- | --- | --- | --- | --- |
| Air | Air Combo, 3 gust strikes 7 / 8 / 11 | Air Blast 10 chi, charge 1.0 s: gust -> wide burst | Air Shield 70 % / 100°, deflects, parry redirects | Air Dash 7 m, i-frames, in air | **Air Sweep** 25 chi, cd 6 s: 360° 4.6 m knockback |
| Earth | Earth Punch 3 rock punches 9 / 9 / 16 (+splash) | Earth Boulder 14 chi, 1.2 s: rock / overhead boulder 26+ | Earth Shield slab, 90 % / 70°, slab HP 80, parry slams | Earth Slide 3 m, poise armor, shockwave | **Earth Wall** 30 chi, cd 8 s: 6x3 m wall 4.5 m ahead, 180 HP, 12 s, launches |
| Fire | Fire Fist / Fire Kick, 4 strikes: bolts 6 / 6, rising arc 9, spin-kick wave 13 | Fire Blast 10 chi, 1.1 s: bolt -> exploding fireball | Flame Guard 75 % / 85°, burns projectiles, parry Fire Burst | Fire Step 4.5 m, i-frames, flame burst | **Flame Sweep** 22 chi, cd 6 s: expanding fire wave 7.5 m / 62° |
| Water | Water Whip 3 lashes 7 / 7 / 10 (pull) | Water Blast 10 chi, 1.2 s: jet -> torrent | Water Shield 80 % / 110°, deflects, parry redirects + freezes melee | Flow Slide 4 m, perfect dodge slow-mo | **Ice Shards** 22 chi, cd 5 s: 3 homing daggers (water from a source) |

Innate: Air Jump (double jump + glide), Water skating (movement module).

## How to add an ability

1. **Define it** in the element kit (`src/bending/kits/<element>/<element>_kit.gd`, the array
   returned by `defs()`), or register at runtime from another module:

   ```gdscript
   AbilityRegistry.register(AbilityDef.make({
       "id": &"earth_spikes", "element": ElementDefs.Element.EARTH,
       "slot": AbilityDef.Slot.TECHNIQUE, "display_name": "Earth Spikes",
       "description": "A line of stone spikes erupts toward the target.",
       "icon": "res://assets/ui/ability_spikes.svg",
       "chi_cost": 20.0, "cooldown": 5.0, "clip": &"stomp_r", "clip_speed": 1.1,
       "startup": 0.3, "active": 0.4, "recovery": 0.4,
       "hit": {"damage": 16.0, "reaction": HitInfo.Reaction.LAUNCH, "lift": 6.0, "force": 3.0, "poise": 30.0, "heavy": true},
       "params": {"count": 6, "spacing": 1.1},
       "unlock": {"level": 4, "prerequisite": &"earth_wall", "cost": 1},
       "script_path": "res://src/bending/kits/earth/earth_spikes.gd"}))
   ```

2. **Implement it** (extend `BendingAbility`, or `ComboAbility` / `ChargeAbility` /
   `DefenseAbility` / `DodgeAbility` for those shapes):

   ```gdscript
   extends BendingAbility

   func can_use() -> StringName:
       return &"" if ctx.body == null or ctx.body.is_on_floor() else &"no_ground"

   func begin() -> void:
       ctx.move_mode = BendingContext.Move.BRAKE      # movement request
       ctx.face_dir = ctx.aim_flat()
       ctx.poise_armor = 20.0
       play_clip(def.clip, {"speed": def.clip_speed})  # schedules the clip's events

   func on_event(event: StringName) -> void:
       if event != &"impact":
           return
       var dir := ctx.aim_flat()
       for i in int(param("count", 6)):
           var p := ctx.ground_point(ctx.origin() + dir * (1.2 + i * float(param("spacing", 1.1))))
           EarthFx.tear_out(ctx.caster, p, 0.5, ctx.surface_at(p))
           BendingHits.sphere(ctx, p + Vector3.UP * 0.5, 0.9, hit_data(), attack_id, def.id, {"push": &"forward"})
       sound(&"cast_heavy", ctx.origin())
       if ctx.is_player():
           BendingFeedback.shake(0.25, 0.2)
   # default update(): finish() when the clip ends; max_time is the hard cap.
   ```

   Rules: spawn gameplay on clip events; one `attack_id` per hit window (BendingHits makes it
   one hit per target); clean up loops / held VFX in `on_cancel` and `on_finish`; keep VFX
   pooled (`FxLib`) and scaled by `FxLib.amount()`; projectiles that outlive the ability use
   lambdas or helper objects kept with `set_meta` (bound methods of a finished ability do not
   keep it alive).

3. **Clip**: use an existing AnimLibrary clip (docs/modules/characters.md) with events
   `release` / `impact` (and `recover` for the cancel window), or add one in
   `BendingClips` (`K.reg(name, clip_dict)` with the characters clip kit; `BendingClips.ensure()`
   registers them, `BendingController.setup()` calls it).
4. **Unlock / equip**: `unlock` rules are read by `AbilityRegistry.can_unlock`;
   `GameState.unlock_ability(id)` + `equip_ability(slot, id)`; the player's controller
   reloads equipped techniques on `set_element` / `load_equipped()`.
5. **Test**: add it to `test_bending.gd` (instantiate, run on a rig-less caster, hit a
   `TrainingDummy`) and try it in the combat arena.

## VFX library (src/fx)

Stylized, flat / banded toon look, everything pooled and capped (`FxLib.take(from, kind,
factory)` / `release(n)`, per-kind caps scaled by `Settings.effects_scale()` 0.35..1.4, max 4
transient lights). Parented under one `FxRoot` in the current scene.

| API | Use |
| --- | --- |
| `FxBurst.spawn(from, kind, pos, {count, size, color, dir, radius, speed})` | GPU particle one-shots: `dust dust_ring snow embers flame smoke steam droplets spray sparkle sparks leaves` |
| `FxRing.spawn(from, pos, radius, color, duration, {opacity, width, fill})` | ground shockwave / telegraph |
| `FxFlash.spawn(from, pos, color, energy, duration, range)` | short point light (capped) |
| `FxDecal.spawn(from, pos, &"crack" / &"scorch" / &"wet" / &"frost", radius)` | fading ground marks (quad fallback in Compatibility) |
| `FxDebris.spawn(from, pos, {count, size, up, out, ground_y, kind})` | tumbling chunks |
| `WaterStream.spawn(from)` + `set_points(pts, r0, r1)`, `finish(fade)` | water tube along a curve (whips, draws, torrents) |
| `FireFx.ball / arc / burst / explosion / muzzle` | flame sprites + ribbons (banded shader) |
| `AirFx.gust / swirl / ground_puff` | helix currents, wind rings, surface puffs |
| `EarthFx.rock / release_rock / tear_out / impact / quake / dust_trail` | flat-shaded rocks, cracks, dust |
| `IceFx.shard / shatter / splash` | crystal shards, shatter, splashes |
| `ImpactFx.hit / block / parry / world` | element impacts (`ImpactFx.hits_shown` counts hit VFX) |

**Shader warm-up (perf_polish).** `ShaderWarmup` (`src/perf/shader_warmup.gd`) casts the whole
kit on rig-less casters on a stage beyond the world edge and spawns every shared one-shot above
(all `FxBurst` kinds, the four decals, ring, flash, rock / ice debris, parries and world impacts
of every element) behind a loading screen, so the first use of a technique compiles nothing.
The world / tutorial boot runs it (docs/modules/worldscene.md); the combat arena
(`scenes/dev/combat_arena.gd::_warm_up`) runs it behind the held Router fade when it was entered
through a transition (or with param `warmup`, then behind its own black cover); param
`no_warmup` skips it. A new technique is covered automatically when it is in
`AbilityRegistry.for_element()` with a `script_path`; FX spawned only in special situations
should be added to `ShaderWarmup._common_fx()`.

## Verification

* `tests/unit/test_bending.gd` (12): registry + kits complete (scripts, clips, 3-4 light
  steps, starters), runtime registration + unlock rules, rig-less light chains / heavy /
  technique for every element, virtual events on the clip time, enemy-team caster damaging the
  player, chi / cooldown / busy / failures / water-source cost, projectiles at 150-200 m/s vs a
  5 cm wall and a dummy (no tunnelling) + pooling, redirect (team, id, speed, damage, credit),
  one hit per attack id + line of sight, constructs (launch once, block + wear, heavy break,
  crumble, lifetime), and "hit VFX shown == hits applied == dummy HIT results".
* Light latency per strike (press -> active, 60 Hz): Air 6/6/6, Earth 5/5/5, Fire 5/5/6/6,
  Water 6/6/6 (`test_player.gd::test_light_attack_latency`).
* Playtest `player_elements` (Forward+ and Mobile renderer).

## Wave 4 integration fixes (docs/qa/integration_fixes.md)

* Practice is counted exactly once per use for every technique and signature of every element
  (verified through the real player: `test_integration_fixes.gd::test_practice_counted_exactly_once_per_use`);
  the counting stays inside the abilities (`FireCommon` / `EarthEnv` / `AirEnv` / `WaterCommon.practiced`),
  the controller counts nothing.
* `BendingController.locked_signature` / `locked_signature_info()`: the element's signature while
  it is not learned; `request(&"signature")` then fails with `&"locked"` (was `&"empty"` with no id).
  `load_equipped()` frees a technique slot holding a signature (older saves: lessons / rewards
  used to auto-equip signatures into technique slots).

## Wave 4 (flow_qa, docs/qa/flow_qa.md)

* `TrainingDummy` readout (`_show`): a damage-only hit (`HitInfo.Reaction.NONE`, e.g. a fire
  jab's burn chip) shows just the damage. The training grounds' dummies printed "2  None".
  Regression: `tests/unit/test_flow_qa.gd::test_training_dummy_readout_names_only_real_reactions`.
* The release contract (`charging`, `released`, `charge`; heavies also `tapped`) is shared by
  `ChargeAbility`, Earth Boulder and Lightning; the tutorial lessons and the enemy brain read
  it by duck typing instead of `is ChargeAbility` (docs/modules/bending_earth.md, enemies.md).
* `BendingProjectile` option `world_radius` (default -1 = `radius`): the sphere used against
  terrain / constructs (SOLID) when smaller than the hit radius; bodies are cast with the full
  radius and the nearer contact wins (`_cast` -> `_cast_sphere`). Used by air gusts.
* A `BendingProjectile` whose caster is freed mid-flight ends at its next step (`step()`):
  hits are built from the caster (`BendingContext.make_hit`), and a freed one raised script
  errors (seen when a scene was torn down while a gust still flew; also a despawned enemy's
  bolt). Regression: `tests/unit/test_flow_qa.gd::test_projectile_outliving_its_caster_ends_quietly`.
