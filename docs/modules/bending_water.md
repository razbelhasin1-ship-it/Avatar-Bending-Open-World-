# Water bending module (`bending_water`)

Water is the vertical-slice element (Northern Water Tribe): fluid, adaptive, defensive,
versatile. This module completes the Water kit on top of the bending framework
(`docs/modules/bending.md`): seven new techniques, the technique tree, the SOAKED status,
water <-> world interactions (sources, ice floes, the shared extinguish hook) and a feel /
visual pass over the core kit. Every technique works for the player and for non-player
casters (enemies) through `BendingContext`.

| Piece | Files |
| --- | --- |
| Kit data + tree | `src/bending/kits/water/water_kit.gd` (`WaterKit`: `defs()`, `tree()`, `TRAINERS`) |
| Core kit | `water_whip.gd`, `water_blast.gd` (tap bolt / held Torrent), `water_shield.gd`, `flow_slide.gd` |
| Techniques | `ice_shards.gd`, `water_surge.gd`, `ice_wall.gd`, `ice_trap.gd` (+ `ice_trap_zone.gd`), `water_wave.gd`, `water_jet.gd`, `healing_waters.gd`, `tidal_torrent.gd` |
| Shared | `water_common.gd` (`WaterCommon`), `water_status.gd` (`WaterStatus`), `water_env.gd` (`WaterEnv`), `ice_floe.gd` (`IceFloe`), `water_wave_runner.gd` (`WaterWaveRunner`), `extinguishable_fire.gd` (`ExtinguishableFire`) |
| Body motion | `water_clips.gd` (`WaterClips`: 9 clips registered into AnimLibrary) |
| Icons | `src/bending/kits/water/icons/ability_{ice_trap,water_wave,water_jet,healing,tidal}.svg` |
| VFX | `src/fx/water/`: `WaterWaveFx` (crest), `WaterVortexFx`, `IcePrisonFx`, `WaterFx` (`pull`, `orb`), `WaterMeshes` (crest / ice prison meshes), `fx_water_wave.gdshader`; `WaterStream.glow` + `fx_water.gdshader` glow/foam bands (bending module, additive) |
| Tests | `tests/unit/test_bending_water.gd` (15 tests) |
| Playtests | `bending_water_arena`, `bending_water_enemies`, `bending_water_world`, `bending_water_mobile`, `bending_water_poses` (`tests/playtest/scenarios/`) |

## Kit

| Slot | Ability | Cost / cd | What it does |
| --- | --- | --- | --- |
| Light | **Water Whip** | free | 3 lashes 7 / 7 / 10, 5.2-5.8 m reach; the 3rd is two-handed and yanks (PULL). One body of water drawn from the source on the first lash and carried through the chain; it splashes down when the chain ends. Soaks (3 s). |
| Heavy | **Water Blast / Torrent** | 10 chi (+14 over the charge) | tap: bolt 14 (knockback, soak 5 s). Hold 1.2 s: one coil, then a second counter-rotating coil, a far source keeps feeding in, full charge flashes (ready cue); release: piercing torrent 20-36 dmg that keeps flowing from the hands, carries what it hit, leaves a wet trail and douses fires. |
| Defense | **Water Shield** | 4 chi/s | two counter-rotating bands, 80 % / 110° block, deflects projectiles; parry redirects projectiles and freezes melee attackers (ice prison, x1.5 when soaked). |
| Dodge | **Flow Slide** | - | 4 m slide, 0.26 s i-frames, water spray or snow spray on snow, perfect dodge slow-mo. |
| Tech, starter | **Ice Shards** | 22 / 5 s | three daggers frozen from drawn water, slight homing; on a SOAKED target the dagger **flash-freezes** it (0.9 s FREEZE, x1.5 if soaked... the soak is consumed). |
| Tech, starter | **Water Surge** | 26 / 7 s | scoop, circle the mass overhead on the back foot, step in and drive it down: a 4.6 m wide, 2.2 m tall crest rolls 10 m at 14 m/s over ground or water, 18 dmg KNOCKBACK heavy + soak 6 s, carries the targets it hits, douses fires and fire projectiles, crashes against walls. |
| Tech, starter | **Ice Wall** | 28 / 9 s | 4.6 x 2.8 x 0.9 m ice construct (150 HP, 10 s, fire x1.8), launches whoever stands where it rises. **Broken by enemies it shatters into 7 ice shards** flying at them; expiring walls melt harmlessly. Aimed at open water it stands on a fresh ice floe. |
| Tech | **Ice Trap** | 24 / 8 s | low palm sweep: water skims the ground to the target's feet (tracks a moving target until it arrives) and freezes on the fist clench (`freeze` clip event): FREEZE 2 s (x1.5 soaked) in 1.4 m, ice prison around the legs. Missed: the frozen patch stays **armed** 4 s and catches the first enemy stepping in. On open water: a walkable ice floe. |
| Tech | **Water Wave** | 22 + 9/s / 8 s | hold: ride a mound of water at 12 m/s, steered by the stick (110°/s), over ground or open water; enemies in the way are bowled aside (10 dmg knockback, once each). Release / 2.6 s / chi out / blocked by a wall: the wave crashes forward (16 dmg KNOCKDOWN heavy). Over water the bender lands on a floe frozen where they stop. Never climbs walls (step probe). |
| Tech | **Water Jet** | 10 + 16/s / 6 s | hold: palms stacked forward, a pressurised stream that follows the aim (sweepable), pulses every 0.15 s (3.5 dmg, push 3.5 m/s, soak), stops on the first target or wall, douses fires along its length, a feed stream from a far source. Max 3 s. |
| Tech | **Healing Waters** | 25 + 6/s / 18 s | hold: rooted, glowing water in both hands pressed to the chest: 10 HP/s, max 35 per use (allies within 3.5 m get half); refuses at full health; a staggering hit interrupts it. |
| Signature | **Tidal Torrent** | 100 Focus | gather from all around, rise on a water column inside a spiralling vortex (3.6 m, 6 m tall) that PULLs enemies within 9 m every 0.25 s and LAUNCHes those within 3.4 m, swallows incoming projectiles, douses fires; then rear back and drive it outward: a ring wave (10 m, 34 dmg KNOCKDOWN) plus a 7 m wide wave crest rolling 15 m ahead (20 dmg LAUNCH). Poise armor + 50 % damage reduction while it runs. |

Without a water source every technique costs **+30 % chi** and its water is **x0.7**
(smaller waves, shorter jet, weaker floes), exactly as `WaterSource` specifies.

### Measured timing (60 Hz, `test_water_latency_report`)

| | press -> active |
| --- | --- |
| Water Whip lashes | 6 / 6 / 6 frames (spec <= 6) |
| Water Wave | 2 frames (riding) |
| Water Jet | 17 frames (stream on) |
| Ice Trap | 20 frames (water leaves the hand; freeze ~0.35 s later) |
| Ice Wall | 25 frames (wall rising) |
| Water Surge | 41 frames (wave thrown: a deliberate, readable wind-up) |

Every gameplay effect is spawned on the clip's timed events (`gather`, `release`, `freeze`,
`rise`), never on a free timer; rig-less casters get the same events from the clip data.

## Technique tree (`WaterKit.tree()`, `AbilityDef.unlock`)

```
tier 1 (new game)   Ice Shards          Water Surge           Ice Wall
tier 2 (level 3)    Ice Trap            Water Wave
                    <- Ice Shards x8    <- Water Surge x6
tier 3              Healing Waters      Water Jet (level 5)
                    (level 4, Yugoda)   <- Water Wave x6
tier 4 (level 7)    Tidal Torrent  <- Water Jet, Master Pakku, 2 points
```

* Unlock rules are standard `AbilityDef.unlock` keys read by `AbilityRegistry.can_unlock`
  (`level`, `prerequisite`, `practice`, `trainer`, `cost`), plus layout keys for the skill-tree
  UI: `tier`, `branch` (`&"ice"`, `&"flow"`, `&"healing"`), `column`.
* `WaterKit.tree()` returns `[{id, tier, branch, column, requires, level, practice, trainer, cost,
  starter, signature}]` sorted by tier / column.
* **Practice**: a technique performed by the player (on its release / freeze / first pulse /
  successful heal) calls `GameState.add_practice(id)` (`WaterCommon.practiced`); enemy casts
  never count.
* **Trainers** (`WaterKit.TRAINERS`): `&"pakku"` (Master Pakku, Water Tribe: Tidal Torrent) and
  `&"yugoda"` (Yugoda, Water Tribe healer: Healing Waters). A trainer marks a lesson with
  `GameState.set_flag("trained_<trainer>_<ability>", true)` (the `can_unlock` contract), e.g.
  `trained_pakku_tidal_torrent`.
* New game: the three starters are unlocked and equipped (slots 1-3; `grant_starters`), slot 4
  is free; the signature appears on R / the touch signature button once unlocked
  (`BendingController.load_equipped`).

## SOAKED (`WaterStatus`)

Any hit with `status.soaked` (whip, blast, torrent, surge, wave, jet, vortex) drenches its
target (player, enemies, dummies, wildlife) for that many seconds: a capped drip emitter
(8 at once, off below effects 0.3) and a blue tint. Synergies:

* freeze durations x1.5 on soaked targets (`WaterStatus.freeze_time(target, base)`): Ice Trap,
  armed traps, Water Shield parry freeze, flash-freeze;
* Ice Shards flash-freeze soaked targets (the water on them freezes; the soak is consumed);
* a drenched target with an `extinguish()` method is put out;
* (enemies module) water already douses firebenders hit by a staggering water hit.

```gdscript
WaterStatus.soak(target, 4.0)
WaterStatus.is_soaked(target); WaterStatus.time_left(target); WaterStatus.clear(target)
```

The listener (`Events.hit_landed`) starts with the first Water ability (`WaterStatus.ensure()`),
so enemy waterbenders soak the player too.

## Environment (`WaterEnv`, `IceFloe`, `WaterCommon`)

* **Sources**: `WaterSource.find` (sea, lakes, canals, registered fountains, snow / ice
  underfoot). `WaterCommon.pull(ctx, src, target_fn, duration, radius, strands)` pulls thick
  strands out of the source along an arc to a moving point: water sources splash and ring on
  the surface, snow / ice sources come up as slush with a snow burst, no source = a thin
  canteen stream at the hip. Every technique draws its water visibly before it acts.
* **Ice floes**: `WaterEnv.freeze_floe(ctx, point, radius, lifetime)` freezes open water into a
  walkable disc (`IceFloe`, `AnimatableBody3D` on `Layers.CONSTRUCT`, top 0.14 m above the
  water, bobbing, melts after its lifetime; max 6 live, the oldest melts first). Used by Ice
  Trap / Ice Wall / Water Wave over water. `IceFloe.supports(p)`.
* **Waves**: `WaterWaveRunner.launch(ctx, start, dir, opts)` / `.ring(ctx, center, opts)`: a
  crest that follows the ground or the water surface, hits targets as the water reaches them
  (one attack id), carries them, douses fires, leaves wet / snow marks, crashes against walls
  and steep steps. Outlives the ability.
* **Extinguish hook (shared contract)**: any `Node3D` in group `&"extinguishable"` with
  `func extinguish(by: Node, at: Vector3) -> bool` (true = a fire went out) and an optional
  `var extinguish_radius: float` is put out by water reaching it; enemy fire projectiles in
  the water are doused in flight.
  ```gdscript
  WaterEnv.extinguish(ctx, center, radius) -> int      # fires put out
  var f := ExtinguishableFire.new(); f.size = 0.5; f.relight_time = 20.0
  brazier.add_child(f)                                   # ready-made fire implementing the hook
  f.extinguished.connect(func(by: Node) -> void: ...)    # quests, AI reactions
  ```
  Called by Water Surge, Water Wave, the Torrent, Water Jet, Ice Wall and Tidal Torrent.
* **Marks**: `WaterEnv.splash_ground(from, p, size)` (wet decal; snow spray on snow; splash
  ring on water), `WaterEnv.snow_spray(...)`; `WaterEnv.surface_y(ctx, p)` (ground or water).

## Body motion (`WaterClips`)

Tai Chi motion authored with the characters clip kit (`docs/modules/characters.md`):
`water_surge_heave` (scoop low on the front foot, roll onto the back foot circling the water
overhead, step in and drive it down), `water_ice_wall` (horse stance, palms rise, fists clench),
`water_ice_trap` (coil, low skimming palm, rising fist clench on `freeze`), `water_wave_ride`
(loop, side-on surf stance) -> `water_wave_crash`, `water_jet_open` (hold, palms stacked
forward), `water_heal_channel` (hold, rooted, hands cupped to the chest, head bowed),
`tidal_torrent` (sink, rise, 360° turn with the vortex, rear back, drive forward),
`water_torrent_hold` (upper-body circle). Review them with
`tools/playtest.sh bending_water_poses` (pose sheets at the key frames).

## Using it from other modules

```gdscript
# Enemies (non-player casters): any water def works on an enemy controller.
bc.set_slot(&"technique_1", EnemyAbilities.variant(&"ice_trap"))   # or AbilityRegistry.get_def
bc.request(&"technique_1")      # hold techniques: bc.release(&"technique_1") ends them
# Skill tree UI
for node in WaterKit.tree(): ...           # tiers / branches / requirements
AbilityRegistry.can_unlock(&"water_wave")  # -> &"" or &"level" / &"practice" / ...
# Trainers (NPC module)
GameState.set_flag("trained_pakku_tidal_torrent", true)
# World / props: make a fire water can put out
add_child(ExtinguishableFire.new())
```

## Decisions

* **Water comes from somewhere you can see.** Every technique pulls its water out of the
  real source before it acts (sea, canal, snow at the feet); without one the canteen stream is
  thin and the technique smaller and dearer - the world matters for a waterbender.
* **Ice is the payoff of water.** Soak first (whip, blast, jet, surge), then freeze longer or
  flash-freeze with ice: Water's combo identity, distinct from fire's pressure, earth's
  weight and air's mobility.
* **Waves are gameplay objects, not particles**: the crest mesh travels on the ground / water
  height, hits when it arrives and stops at walls, so the VFX never implies a hit that did
  not happen (tested: hit VFX == applied hits).
* **Riding / lifting** uses the same movement request as every ability (`DRIVE`, gravity 0,
  `WaterCommon.hold_height` setting the body's vertical velocity) - no special player code.
* **Healing is limited** (35 HP per use, 18 s cooldown, chi upfront + upkeep, rooted and
  interruptible) so it is a tactical choice, not sustain.
* **Trainer-gated tiers** (Healing Waters, Tidal Torrent) follow the lore (Yugoda, Pakku); the
  ids are published in `WaterKit.TRAINERS` for the NPC / trainer module.

## Performance / mobile

* Pooled: `WaterStream`, `WaterWaveFx`, `IcePrisonFx`, bursts, decals, rings (FxLib caps);
  vortex streams 4 (3 on low effects); pulls 2 strands max on low; drips capped at 8.
* No per-frame physics queries beyond the hit volumes: waves query one sphere per tick,
  the jet one ray + one capsule per 0.15 s pulse, the vortex one sphere per 0.25 s.
* Every shader is a plain spatial shader (no screen textures), so Forward+, Mobile and
  Compatibility render the same. Tested on the Mobile renderer with the mobile preset and
  touch controls (`bending_water_mobile`).

## Changes outside the module (all additive)

* `src/fx/water_stream.gd`: `glow` property (healing water).
* `src/fx/shaders/fx_water.gdshader`: banded foam caps, slightly deeper blue, `glow` uniform.
* `tests/unit/test_bending.gd`: the starter check accepts several starters per element
  (`starter_techniques(e).has(...)`).

## Known limitations

* Trainer-gated techniques (Healing Waters, Tidal Torrent) can only be learned once the NPC /
  trainer module sets the `trained_<trainer>_<id>` flags (ids in `WaterKit.TRAINERS`).
* World fires (braziers, campfires built into settlement geometry) are not yet extinguishable
  nodes; they need an `ExtinguishableFire` (or the hook) from the modules that place them.
* Enemy waterbenders (`water_pirate`) still use the core kit + Ice Shards; the new techniques
  are verified on enemy casters in tests but are not in an archetype's attack list yet
  (enemies module data).
* The water crest is a stylised mesh with a flowing shader; seen from directly behind at a
  low camera it reads as a rounded mound.
