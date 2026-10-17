# Fire bending module (`bending_fire`)

Fire is aggressive, precise and explosive: breath and Northern Shaolin strikes, fire from
the fists, feet and palms, pressure that keeps hurting (burn), and a world that answers
(braziers light, grass catches, ice melts, snow steams, the ground is scorched). This module
completes the Fire kit on top of the bending framework (`docs/modules/bending.md`): seven new
techniques, the technique tree, the BURNING status, fire <-> world interactions with shared
hooks, and a feel / visual pass over the core kit. Every technique works for the player and
for non-player casters (enemies, scripted actors) through `BendingContext`.

| Piece | Files |
| --- | --- |
| Kit data + tree | `src/bending/kits/fire/fire_kit.gd` (`FireKit`: `defs()`, `tree()`, `TRAINERS`, `enemy_attacks()`) |
| Core kit | `fire_combo.gd` (Fire Fist / Fire Kick), `fire_blast.gd` (tap Fire Blast / held Blaze Charge), `flame_guard.gd`, `fire_step.gd`, `flame_sweep.gd` (starter) |
| Techniques | `fire_burst.gd`, `jet_step.gd`, `fire_ring.gd`, `fire_whip.gd`, `inferno.gd`, `lightning.gd` (`FireLightning`) |
| Shared | `fire_common.gd` (`FireCommon`), `fire_status.gd` (`FireStatus`), `fire_env.gd` (`FireEnv`), `grass_fire.gd` (`GrassFire`), `fire_brazier.gd` (`FireBrazier`), `fire_hit_proxy.gd` (`FireHitProxy`), `fire_ring_wave.gd` (`FireRingWave`) |
| Body motion | `fire_clips.gd` (`FireClips`: 10 clips registered into AnimLibrary) |
| Icons | `src/bending/kits/fire/icons/ability_{fire_burst,jet_step,fire_ring,fire_whip,inferno,lightning}.svg` |
| VFX | `src/fx/fire/`: `FireMarks` (scorch decals + baked textures), `HeatShimmer`, `LightningFx` (bolts, charge arcs), `FireWhipFx`, `FireJetFx`, `FireVortexFx`, `FireGatherFx`, `LimbFlame`, `BodyFlames`; shaders `fx_flame_wall`, `fx_flame_spiral`, `fx_lightning`, `fx_heat_shimmer` |
| Audio | `fire_lightning` (x2), `fire_lightning_crackle` (x3), `fire_lightning_loop` (synthesised in `tools/audiogen/sfx_fire.py`); the rest uses the fire bending sound map |
| Tests | `tests/unit/test_bending_fire.gd` (15 tests) |
| Playtests | `bending_fire_arena`, `bending_fire_enemies`, `bending_fire_world`, `bending_fire_mobile` (`tests/playtest/scenarios/`) |

## Kit

| Slot | Ability | Cost / cd | What it does | Counterplay |
| --- | --- | --- | --- | --- |
| Light | **Fire Fist / Fire Kick** | free | jab, jab (fire darts 6 dmg, 38 m/s, 16 m), front kick (9, 2.4 m lunge), spinning roundhouse (13 KNOCKBACK, a flame arc). The striking fist / foot catches fire on the strike. Burn 1.5-3 s. | block / parry; the 4th hit has a visible spin-up |
| Heavy | **Fire Blast / Blaze Charge** | 10 chi (+16 over the charge) | tap: fast fireball 15 STAGGER, 32 m. Hold 1.1 s: the fire is breathed into a ball cupped at the hip that grows, pulses, draws embers in, shimmers and FLARES at full charge (cue); release: step in and drive it out with both palms - 20-38 dmg KNOCKBACK, exploding on impact (2.4-4.2 m: flame ball, ring of fire along the ground, scorch, grass catches). | the charge is loud and visible; sidestep the slower ball; walls stop it |
| Defense | **Flame Guard** | 5 chi/s | 75 % block in an 85° arc, burns projectiles away; perfect parry: a 3.2 m Fire Burst counter (KNOCKDOWN). | attack from behind |
| Dodge | **Fire Step** | - | 4.5 m jet-propelled step, 0.2 s i-frames, flame trail + scorch streak; cancels into strikes after 0.12 s. | |
| Tech, starter | **Fire Burst** | 20 / 5 s | breathe in (fists flare), stomp, throw both palms out: a point-blank explosion - KNOCKDOWN within 2 m (16), KNOCKBACK to 3.8 m (14), burns incoming projectiles, ring of flame marks the reach, scorched ground. Poise armor 30 during the breath. | get out of 3.8 m during the 0.26 s breath; it never reaches far |
| Tech, starter | **Flame Sweep** | 22 / 6 s | low sweeping kick, a wide wave of fire rolls 7.5 m along the ground (124°), heats the ground along its path. | jump; outside the cone |
| Tech | **Jet Step** | 14 (+18/s hover) / 1.6 s | crouch, fire jets from the feet and palms: a 5-6 m leap up and forward; keep holding to hover on the flames (up to 1.1 s, drift with the stick). Taking off scorches whoever stands within 2.2 m (8 KNOCKBACK). Usable in the air once per jump (resets on landing). Enemies never hover. | it is mobility: punish the landing |
| Tech | **Fire Ring** | 26 / 7 s | coil, spin with the leg out: a standing wall of flame races out in a full circle, 6.5 m in 0.38 s; each target is hit once when the flames reach it (16 KNOCKBACK + burn); a scorched ring stays. | jump it (> 1.4 m clear), stand behind a wall, be outside 6.5 m |
| Tech | **Fire Whip** | 24 / 6 s | the fist ignites and circles back over the head (tell), then a 7.5 m lash of fire sweeps a 110° arc from high right to low left: everything it passes through is hit once (14 STAGGER), the last 1.6 m (tip) hits harder (21 KNOCKBACK). The lash is the hit volume (curve capsules + the space swept since the last tick); walls stop it; the crack scorches a streak. | read the overhead wind-up; dodge through; walls |
| Signature | **Inferno** | 100 Focus | sink and breathe in (a faint 11 m ring marks the final reach), rise spinning inside a whirling column of fire (3 m: 4 pulses of 5 dmg + burn, swallows projectiles), stomp and drive both palms out: a towering ring of flame races to 11 m and LAUNCHES everything it reaches (34 + burn). Hyper armor + 50 % damage reduction while it runs. | jump the ring (> 1.8 m), hide behind a wall, get out of 11 m during the 1 s spin |
| Tech (late) | **Lightning Generation** | 40 / 14 s | hold: rooted, the arms trace slow opposed circles while arcs crackle at the fingertips (1.6 s; a flash and crackle at full). Release: two fingers thrust forward and an instant bolt jumps along the aim (38 m, aim assist): 55 dmg KNOCKDOWN, unblockable, arcs to one more target within 4 m (40 %); striking water electrifies everyone in it within 5 m (the bender too, if standing in it). Released before 55 %: it fizzles (chi and cooldown spent); 55-100 %: a weaker bolt (x0.55-1). **Risk:** held past 2.8 s it turns on the bender (18 KNOCKDOWN); struck while charging past half way it discharges into them (12 STAGGER); struck earlier, the charge just breaks. Non-player casters release on the full charge. | hit the bender while they charge (no poise armor); i-frames dodge the bolt |

Light strikes and the bolt / ball impacts leave the element's look: fire darts and arcs,
flames licking burning targets, orange light flashes, scorch marks; every hit VFX corresponds
to an applied hit (tested: hit VFX shown == hits landed, burn ticks included).

### Measured timing (60 Hz, `test_hit_vfx_parity_and_latency_report`)

| | press -> active |
| --- | --- |
| Fire Fist / Kick (4 hits) | 5 / 5 / 6 / 6 frames (spec <= 6) |
| Jet Step | 11 frames (airborne) |
| Fire Burst | 16 frames (explosion) |
| Fire Whip | 20 frames (lash leaves the hand; the crack ~10 frames later) |
| Fire Ring | 26 frames (wall released; it reaches 6.5 m 23 frames later) |
| Lightning | 111 frames (a full charge held, then released) |

Every gameplay effect is spawned on the clip's timed events (`gather`, `windup`, `release`,
`impact`, `takeoff`, `spin`, `pulse`), never on a free timer; rig-less casters get the same
events from the clip data (`FireClips.ensure()` runs for every Fire ability and the kit).

## Technique tree (`FireKit.tree()`, `AbilityDef.unlock`)

```
tier 1 (new game)   Fire Burst (breath)           Flame Sweep (flame)
tier 2 (level 3)    Jet Step  <- Fire Burst x6    Fire Ring <- Flame Sweep x6
tier 3 (level 5)                                  Fire Whip <- Fire Ring x6
tier 4 (level 7)                                  Inferno (signature) <- Fire Whip, Master Jinzo, 2 points
tier 5 (level 9)                                                        Lightning Generation (lightning)
                                                                        <- Jet Step x8, Master Jinzo, 2 points
```

* Unlock rules are standard `AbilityDef.unlock` keys read by `AbilityRegistry.can_unlock`
  (`level`, `prerequisite`, `practice`, `trainer`, `cost`) plus layout keys for the skill-tree
  UI: `tier`, `branch` (`&"breath"`, `&"flame"`, `&"lightning"`), `column` (0-2).
* `FireKit.tree()` returns `[{id, tier, branch, column, requires, level, practice, trainer,
  cost, starter, signature}]` sorted by tier / column (same format as the other elements).
* **Practice**: a technique performed by the player (on its release / takeoff / bolt) calls
  `GameState.add_practice(id)` (`FireCommon.practiced`); enemy casts never count.
* **Trainer** (`FireKit.TRAINERS`): `&"fn_jinzo"` (Master Jinzo, Flame Kata Grounds of the
  Fire Nation capital) teaches the Inferno and Lightning Generation; a lesson sets
  `GameState.set_flag("trained_fn_jinzo_inferno", true)` (the `can_unlock` contract).
* New game: Fire Burst and Flame Sweep are unlocked and equipped (slots 1-2, alphabetical,
  `grant_starters`); slots 3-4 are free; the signature appears on R / the touch signature
  button once unlocked. All techniques work from the 4 slots + signature on keyboard,
  controller and touch (`get_ability_slot_info` drives the touch buttons; holds - Blaze
  Charge, Jet Step hover, Lightning - follow the button / key being held).

## BURNING (`FireStatus`)

Fire hits whose hit data carries `status.burn >= 2` s set their target alight (player,
enemies, dummies, wildlife): flames lick the body (`BodyFlames`, capped 3/5/8/10 per effects
tier) and it takes 2 damage every 0.6 s (the player: every 1 s), unblockable, no reaction,
credited to whoever set the fire. Duration refreshes to `max(remaining, new)`, capped at 5 s;
firebenders burn half as long. Put out by any water hit or soak, standing in water, a dodge
roll (stop, drop and roll), death. Lighter fire hits (jabs) only scorch-tint.

```gdscript
FireStatus.ensure()                          # starts listening (first fire ability does it)
FireStatus.ignite(target, 3.0, source, team) # set alight directly (grass fire, hazards)
FireStatus.is_burning(t); FireStatus.time_left(t); FireStatus.douse(t)
```

Ticks are delivered with `receive_hit` (not `Combat.deal`: no hit sounds, no quest /
tutorial hit counters) with the same accounting as `BendingHits` (`applied_hits`,
`ImpactFx.hits_shown`), so the hit / VFX parity invariant holds.

## Environment (`FireEnv`, `GrassFire`, `FireBrazier`, `FireHitProxy`, `FireMarks`)

Every Fire technique calls `FireEnv.heat(ctx, point, radius, power, opts)` where its fire
reaches the world (explosions, the ring front every 1.6 m, the whip crack, jets, the bolt
end, fireball impacts) and the world answers by what is there:

* **IGNITE hook (new shared contract)**: any `Node3D` in group `&"ignitable"` with
  `func ignite(by: Node, at: Vector3) -> bool` (true = it caught fire) and an optional
  `var ignite_radius: float`. `FireEnv.ignite_at(from, p, radius)` lights them.
* **EXTINGUISH hook** (the contract `bending_water` defined): group `&"extinguishable"`,
  `func extinguish(by: Node, at: Vector3) -> bool`, optional `var extinguish_radius`. Every
  fire this module makes implements it (grass cells, braziers). `FireEnv.extinguish(from, p,
  radius)` puts them out for any module (air gusts, earth smothering, scripted rain), the
  same as `WaterEnv.extinguish`.
* **Hits put fires out with no change to the other kits** (`FireHitProxy`): every fire
  object carries an `Area3D` on the hurtbox layer, group `damageable`, team NEUTRAL, tagged
  `no_lock`; `receive_hit` hands the hit over and returns IGNORED (no damage, no feedback,
  projectiles fly on through). `FireHitProxy.reaction(hit)`: water (or a soak) douses, air
  douses when heavy or force >= 4, earth douses when heavy, fire ignites.
* **MELT hook**: group `&"meltable"` with `func melt(by, at, heat) -> bool`; enemy ice
  constructs (`BendingConstruct` kind ice, fire x1.8) take a "melt" hit and sag; ice floes
  (`&"ice_floe"`, `melt()`) melt away with steam.
* **Ground** (`FireEnv.ground`): water hisses into steam; snow steams, gets a wet decal and
  a melted hollow (`WorldRenderer.snow.add_crater`); ice steams; dry grass catches
  (`GrassFire`); anything else gets a charred burn mark (`FireMarks`) with embers that glow
  and cool in 5 s. Rain (the world's weather, or `FireEnv.force_wet`) stops grass catching.
* **Burnable grass** (`FireEnv.is_burnable(p)`): a grass surface in a grassland / farmland /
  forest / volcanic biome, on the terrain itself (not a bridge or plaza), not under water,
  ground wetness hint < 0.55, not raining. Arenas use `GroundSampler` zones (a zone's
  surface decides). The Fire Nation's home island is mostly city, rock and ash and its
  forests are humid; the nearest dry patches are 0.5-1 km from the spawn.
* **Grass fire budget** (`GrassFire`, one node per scene): 1.6 m cells; at most 8 / 14 /
  20 / 24 cells burning at once (effects tier), at most 12 per ignition (scaled by power),
  3 generations of spread, a spread attempt every 0.85 s per cell (45 %, biased downwind),
  each cell burns 4.5-7 s then leaves a charred mark; burnt cells cannot catch again for
  90 s; 4 flame sprites per cell in ONE MultiMesh, 2 lights max; standing in it burns
  other teams (2.5 s). Measured in the world: 12 cells lit from one Fire Burst, burnt out
  after 7-8 s.
* **Braziers / torches / lanterns** (`FireBrazier`): the ready-made IGNITE + EXTINGUISH
  implementation in three toon looks (bronze brazier, iron-cage torch, stone lantern), with
  a flame, light, signals and an optional relight / burn-out time.

```gdscript
var b := FireBrazier.new(); b.kind = &"torch"; b.lit = false
add_child(b); b.global_position = p
b.ignited.connect(func(by: Node) -> void: ...)      # quests, puzzles
b.extinguished.connect(func(by: Node) -> void: ...)
b.relight_time = 20.0       # an eternal flame relights itself
FireEnv.heat(ctx, p, 2.0, 1.0)                       # all of the above, once
FireEnv.heat(ctx, p, 1.0, 0.6, {"ground": false})    # air-only (no marks / grass)
FireEnv.ignite_at(self, p, 1.5); FireEnv.extinguish(self, p, 3.0)
FireMarks.burn(self, ground_p, 1.2); FireMarks.ring(self, center, 6.0)
```

## Body motion (`FireClips`)

Northern Shaolin motion authored with the characters clip kit (`docs/modules/characters.md`):
`fire_burst_blast` (sink and breathe, stomp into horse, both palms out), `fire_ring_kick`
(coil, spin on the left foot with the right leg sweeping at hip height), `jet_step_launch`
(crouch, spring) + `jet_hover` (loop), `fire_whip_lash` (the right hand circles back over
the head and lashes down across the body into a bow stance), `inferno_spin` (sink, rise
spinning twice with the arms wide, stomp into horse, palms out), `lightning_charge` (loop,
long front stance, arms tracing slow opposed circles) -> `lightning_release` (two-finger
thrust), `fire_blaze_hold` (upper-body loop, the ball cupped at the hip) ->
`fire_blaze_release` (step in, both palms). Events are normalised times in the clip data.

## Using it from other modules

```gdscript
# Enemies: any fire def works on an enemy controller; FireKit.enemy_attacks() has ready
# EnemyActions entries (telegraph, range, ring size) for Fire Burst / Fire Ring / Fire Whip.
bc.set_slot(&"technique_2", AbilityRegistry.get_def(&"fire_burst"))
archetype["attacks"].append(FireKit.enemy_attacks()[&"fire_burst"])
# Skill tree UI
for node in FireKit.tree(): ...
AbilityRegistry.can_unlock(&"fire_whip")     # -> &"" or &"level" / &"practice" / ...
# Trainers
GameState.set_flag("trained_fn_jinzo_inferno", true)
# World / props / quests: a fire to light (and put out)
var b := FireBrazier.new(); add_child(b)
# Any node can opt in to the hooks:
add_to_group(&"ignitable")       # func ignite(by: Node, at: Vector3) -> bool
add_to_group(&"extinguishable")  # func extinguish(by: Node, at: Vector3) -> bool
```

## Decisions

* **Fire has a source and a body.** Fists and feet ignite on the strike (`LimbFlame` rides
  the socket so it moves with the punch), the Blaze ball is breathed into at the hip, jets
  come from the feet and palms, the Inferno column rises around the bender.
* **Walls of flame are gameplay objects** (`FireRingWave`): the mesh radius is the hit
  radius, each target is hit when the front reaches it (one attack id), feet more than
  `clearance` above the ground are jumped over, walls block it. The VFX never implies a hit
  that did not happen.
* **Burn is fire's identity** (pressure that keeps hurting), countered by water and rolling
  - distinct from water's soak-and-freeze, earth's weight, air's mobility.
* **The world answers through hooks, not special cases.** Braziers / grass / ice / snow
  opt in via groups and `FireHitProxy`; no other kit needed a change for water whips or air
  gusts to put fires out.
* **Grass fire is strictly budgeted** (cells, generations, per-fire cap, one MultiMesh,
  two lights, cooldown on burnt ground) so it is a spectacle, never a runaway cost.
* **Lightning is a risk / reward discipline**: long charge, rooted, no armor, interrupted by
  any hit, self-damage when mistimed - the highest damage in the kit has the clearest
  counterplay.
* **Flame walls fade near the camera** (`fx_flame_wall`, `fx_flame_spiral`): a ring racing
  under the camera or the Inferno column around the bender thins out instead of filling
  the screen.

## Performance / mobile

* Pooled: flame / ember bursts, marks, rings, vortex, whip ribbon, jets, limb flames,
  shimmer (FxLib caps). Grass fire: one MultiMesh for every cell; at most 2 lights.
* Physics queries: ring waves one sphere per physics tick while expanding (0.38 / 0.55 s),
  the whip a few capsules per tick during its 0.16 s sweep, the bolt one ray (+ a sphere
  for the chain), the vortex one sphere per pulse, grass cells one overlap every 0.5 s.
* Burn marks: decals on Forward+ / Mobile (the Mobile renderer allows 8 decals per mesh, so
  it keeps 3 round marks + 1 ring), flat quads on Compatibility; live marks capped per tier
  (5 / 9 / 14 / 22) and they fade after 14-60 s.
* Heat shimmer (screen texture) only on Forward+ at effects high / ultra; nothing depends on
  it. All other shaders are plain spatial shaders: Forward+, Mobile and Compatibility render
  the same.
* Verified with `RENDERER=mobile MOBILE=1 tools/playtest.sh bending_fire_mobile` (touch
  overlay, every technique from its button, Lightning held on its button, the Inferno from
  the signature button).

## Playtests

| Scenario | What it shows |
| --- | --- |
| `bending_fire_arena` (`TECH=core,defense,burst,ring,jet,whip,inferno,lightning,env`) | every technique at its anticipation / active / impact frames from the player camera and an observer camera; combo string, Blaze Charge stages + explosion, Flame Guard parry counter, Fire Burst, Fire Ring, Jet Step leap + hover, Fire Whip, Inferno, Lightning; braziers lit, put out by a water whip, an enemy ice wall melted, a burst on snow |
| `bending_fire_enemies` (`PART=combo,squad,adept`) | jab, jab, kick, roundhouse -> Fire Burst -> Fire Whip -> Blaze Charge on a bandit frame by frame (burn ticks counted); a squad vs Fire Ring, Jet Step, Lightning and the Inferno; an enemy firebender (FireKit.enemy_attacks) turning the techniques on the player |
| `bending_fire_world` | the real world near the Fire Nation spawn: a dry patch found from world data, Fire Burst lights the grass, the fire spreads within its budget, burns out, the patch does not catch again, rain stops it |
| `bending_fire_mobile` | Mobile renderer + touch overlay (above) |

## Changes outside the module (all additive)

* `src/bending/ability_registry.gd`: `starter_techniques()` sorts ids alphabetically by
  string (identical to `bending_water` / `bending_earth`; slot order is stable across runs).
* `tests/unit/test_bending.gd`: the starter check accepts several starters per element
  (identical to the peers).
* `tests/unit/test_mobile.gd`: the tech_0 touch button check accepts any Fire starter (slot 1
  is now Fire Burst, alphabetical).
* `src/player/player_character.gd`: `can_bend_airborne(slot)` also allows abilities whose
  data says `params.in_air` (Jet Step can be used in the air).
* Audio: `tools/audiogen/sfx_fire.py` (three lightning sounds), `assets/audio/sfx/
  fire_lightning*.wav` (+ `.import`), `src/audio/sound_catalog.gd` (`ALL_SFX`),
  `docs/ARCHITECTURE.md` ("Audio names", Fire), `tools/audiogen/report.{json,md}`.

## Wave 4 integration (docs/qa/integration_fixes.md)

* **World fires react**: the braziers, torches, lanterns and campfires baked into settlement,
  outpost and POI cells are registered with `WorldFires` (`src/world/fires/`); the nearest get
  a `WorldFireSpot` stand-in carrying the IGNITE / EXTINGUISH hooks and a `FireHitProxy`, so
  `FireEnv.heat` / fire hits light them and water / strong wind put them out (they relight
  after 30-60 s). A share of braziers stands cold by day for a firebender to light.
* **Enemy firebenders use the techniques**: `fire_soldier` adds Fire Burst (space), the
  lieutenant Fire Whip and, in phase two, Fire Ring (`FireKit.enemy_attacks()` entries; the
  enemy-tuned copies live in `EnemyAbilities.VARIANTS` / `LOADOUTS`).
* **Burn ticks never shake the camera** (`PlayerDamage.is_tick`: hits tagged `dot` /
  `no_hitstop`); the HUD vignette and phone haptics are softer for ticks too.

## Known limitations

* Trainer-gated techniques (Inferno, Lightning) need the NPC module to set
  `trained_fn_jinzo_<id>`.
* `FireEnv.is_burnable` reads `GroundSampler._zone_at` (a private helper of the player
  module) so arena zones decide burnability.
* Grass blades inside a burnt patch are darkened by the decal but not removed (no
  per-instance grass edit API).
