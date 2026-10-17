# Earth bending module (`bending_earth`)

Earth is grounded, deliberate and forceful (Earth Kingdom, Hung Gar). This module completes
the Earth kit on top of the bending framework (`docs/modules/bending.md`): six new
techniques, the technique tree, an earth <-> world layer (what the ground is made of, what
stays broken after a fight, raised rock as cover and platforms) and a feel / visual pass
over the core kit. Every technique works for the player and for non-player casters
(enemies) through `BendingContext`.

| Piece | Files |
| --- | --- |
| Kit data + tree | `src/bending/kits/earth/earth_kit.gd` (`EarthKit`: `defs()`, `tree()`, `TRAINERS`, `enemy_attacks()`) |
| Core kit (retuned) | `earth_punch.gd`, `earth_boulder.gd`, `earth_shield.gd`, `earth_slide.gd`, `earth_wall.gd` |
| Techniques | `earth_pillar.gd`, `earth_stomp.gd`, `earth_spikes.gd`, `earth_grab.gd`, `earth_armor.gd` (+ `earth_armor_state.gd`), `earthquake.gd` |
| Shared | `earth_env.gd` (`EarthEnv`: ground kinds, refusals, marks, shake, pillars), `earth_common.gd` (`EarthCommon`: rock rising / launching), `earth_shockwave.gd` (`EarthShockwave`), `earth_spike_line.gd` (`EarthSpikeLine`), `earth_armor_state.gd` (`EarthArmorState`) |
| Body motion | `earth_clips.gd` (`EarthClips`: 7 Hung Gar clips registered into AnimLibrary) |
| Icons | `src/bending/kits/earth/icons/ability_{pillar,stomp,earth_spikes,grab,armor,earthquake}.svg` |
| VFX | `src/fx/earth/`: `EarthPalette` (rock / dust colours per ground), `EarthMeshes` (rocks, slabs, plates, hewn pillars, spikes, jaws; toon + vertex colour), `EarthMarks` (persistent crater / fissure / furrow decals, `textures/` + generator), `EarthRubble` (MultiMesh rubble), `EarthWaveFx` (shards along a shockwave front), `EarthShackleFx` (stone jaws), `EarthBurrowFx` (travelling hump under the ground); `src/fx/earth_fx.gd` uses the palette and leaves craters (additive) |
| Tests | `tests/unit/test_bending_earth.gd` (15 tests) |
| Playtests | `bending_earth_arena`, `bending_earth_enemies`, `bending_earth_world`, `bending_earth_mobile`, `bending_earth_poses` (`tests/playtest/scenarios/`) |

## Kit

| Slot | Ability | Cost / cd | What it does |
| --- | --- | --- | --- |
| Light | **Earth Punch** | free | 3 strikes 9 / 9 / 16 (3rd two-handed, KNOCKBACK heavy). Each strike stomps a chunk of rock out of the ground (cracks at the foot, rock in the ground's colours) and drives it forward at 30 m/s. No earth underfoot: stone-hard fists (0.65 x damage, 1.9 m reach). Poise armor 12. |
| Heavy | **Earth Boulder** | 14 chi (+10 charge) | stomp a boulder up, hold to aim / grow it, release to hurl: 26 dmg KNOCKDOWN heavy, 2.2 m splash, a crater + rim rubble where it lands. Refused without earth. |
| Defense | **Earth Shield** | 3 chi/s | a dressed stone slab in front: 90 % / 70° block, 80 guard HP; perfect block slams it into the attacker and splits the ground toward them. No earth: forearm guard only (50 %). |
| Dodge | **Earth Slide** | - | short slide with full poise armor (no i-frames): ploughs a furrow that stays, ends in a 2.4 m shockwave (STAGGER). On ice / wood: plain slide, no effects. |
| Tech, starter | **Earth Pillar** | 22 / 5 s | chamber, stomp (cracks race to the spot), double uppercut: a stone column (2.8 m, 120 HP, 9 s) erupts **under the target** - 14 dmg LAUNCH, unblockable from beneath. The column stays as cover (blocks movement, projectiles, sight) and a climbable platform, then crumbles. No target: rises at the aim point (2.6-9 m). **Hold the button through the release: the column rises under the bender and carries them up 3 m** (traversal / high ground; stacks up to 6 m above the terrain). |
| Tech, starter | **Earth Stomp** | 20 / 6 s | knee high, slam: a shockwave ring rolls 5 m in 0.28 s; everyone on the ground is hit **as the front reaches them** (12 dmg STAGGER, unblockable); jumping clears it (> 1.2 m above the ground), walls stop it. Shards pop up along the front, a cracked crater stays. |
| Tech, starter | **Earth Wall** | 30 / 8 s | 6 x 3 m dressed stone wall at the aim point (180 HP, 12 s), launches whoever stands where it rises, a fissure from the bender to it, base rubble. |
| Tech | **Earth Spikes** | 24 / 7 s | coil, lunge, drive both claws down: a line of stone spikes runs 12 m at 24 m/s toward the aim, following the ground; each target hit once: 16 dmg LAUNCH (unblockable - sidestep the line). Stops at ice, deep water, walls and steep steps (with a puff of what stopped it), leaves a fissure. |
| Tech | **Earth Grab** | 22 / 9 s | reach out: a ripple runs under the ground to the target (tracks it for the player; enemy casters commit), clench: stone jaws clamp the legs - rooted 2.5 s (FREEZE), 6 dmg, unblockable. Airborne targets escape. Missed: the jaws snap on empty ground. |
| Tech | **Earth Armor** | 20 chi, toggle / 4 s | double stomp, plates fly up and lock onto chest, back, belly, pauldrons, bracers, thighs, greaves: **40 % damage reduction, +40 poise, 22 % slower, 5 chi/s drain** (no chi regen meanwhile). Press again (free) to burst out: plates fly outward, 8 dmg KNOCKBACK in 3 m; cooldown starts then. Chi out: the armor breaks. Hits chip plates off. AI casters wear it 25 s max. |
| Signature | **Earthquake** | 100 Focus | palms to the ground (tremor, reach ring), rise with six boulders tearing loose and hovering, drop onto one knee and drive a fist into the earth: an 11 m fissure shockwave (0.6 s) knocks down everything on the ground (34 dmg KNOCKDOWN, unblockable; jump / i-frames avoid it, walls stop it), the boulders fly outward as debris (10 dmg STAGGER on targets the wave missed), 7 fissures split outward with broken slabs, a big crater stays, an aftershock rumbles. Poise armor + 50 % damage reduction while it runs. |

### Ground matters (`EarthEnv`)

| Ground under the feet / at the target | Power | Feedback |
| --- | --- | --- |
| stone (rock, gravel, roads, cobbles, earth constructs: pillars / walls) | x1.1 | grey rock |
| dirt, grass, farmland | x1.0 | brown rock, turf caps on grass |
| ash (Fire Nation volcanic ground) | x1.05 | dark basalt with rust bands |
| sand | x0.75 | sand-coloured, crumbly; toast "Loose sand: weaker earthbending" |
| snow | x0.85 | the earth under the snow, white caps; toast |
| mud / shallow water (0.06-0.7 m) | x0.7 | toast |
| **ice, wood (decks, boats, structures over water), deep water (> 0.7 m)** | - | **refused**: HUD `ability_failed` (`&"no_earth"`), a toast ("No earth to bend - only ice here" ...), a puff of snow / spray / splinters. No chi spent, no cooldown. |

Power scales damage (`scaled_hit`), size (pillar height / radius, stomp radius, spikes
height) and construct HP. The kind is read from the floor collider (`surface` meta,
`BendingConstruct.kind`), the water depth (`WorldData` / `GroundSampler.water_height`), then
`GroundSampler.surface` (world surfaces + zones). A floor more than 0.8 m above the terrain
is a structure: stone, or wood when it stands over water.

### Measured timing (60 Hz, `test_hit_vfx_parity_and_latency_report`, `test_light_strike_latency_and_fist_stomp`)

| | press -> active |
| --- | --- |
| Earth Punch strikes | **5 / 5 / 5 frames** (rock released; spec <= 6) |
| Earth Stomp | 19 frames (shockwave starts) |
| Earth Spikes | 21 frames (line starts) |
| Earth Pillar | 23 frames (column erupts; the stomp sends the cracks to the spot at frame 17) |
| Earth Wall | 29 frames |
| Earth Boulder (tap) | 29 frames (thrown) |
| Earth Grab | 32 frames (jaws close; the ripple leaves at frame 17) |
| Earthquake | 57 frames (slam; a deliberate signature wind-up with tremor + hovering boulders) |

Every gameplay effect is spawned on the clip's timed events (`stomp`, `release`, `impact`,
`grab`, `armor`, `gather`, `lift`, `pulse`), never on a free timer; rig-less casters get
the same events from the clip data. VFX parity: 9 hits applied = 9 hit VFX shown.

### Counterplay (readable, fair)

* Every ground attack has a visible tell: the pillar's stomp sends cracks to the spot and
  the ground rumbles there (enemy casters lock the spot when the cast starts: step off it);
  the stomp's knee raise; the spikes' coil; the grab's ripple travelling under the ground;
  the earthquake's tremor ring marking the reach.
* Waves and lines hit as they arrive (no instant AoE), walls stop them, a jump clears the
  stomp / earthquake front (`clearance`), airborne targets escape the grab, the spike line
  is dodged sideways. Unblockable from beneath, but dodgeable.
* Armor is strong but slow and expensive; burst it off or let chi break it.

## Technique tree (`EarthKit.tree()`, `AbilityDef.unlock`)

```
tier 1 (new game)   Earth Pillar        Earth Stomp           Earth Wall
                    (stone)             (seismic)             (guard)
tier 2 (level 3)    Earth Grab          Earth Spikes
                    <- Pillar x6        <- Stomp x6
tier 3 (level 5)                                              Earth Armor <- Earth Wall, Master Bao Shan
tier 4 (level 7)                        Earthquake <- Earth Spikes, Master Bao Shan, 2 points
```

* Unlock rules are standard `AbilityDef.unlock` keys read by `AbilityRegistry.can_unlock`
  (`level`, `prerequisite`, `practice`, `trainer`, `cost`), plus layout keys for the skill-tree
  UI: `tier`, `branch` (`&"stone"`, `&"seismic"`, `&"guard"`), `column`.
* `EarthKit.tree()` returns `[{id, tier, branch, column, requires, level, practice, trainer, cost,
  starter, signature}]` sorted by tier / column.
* **Practice**: a technique performed by the player (on its release / impact / grab / armor)
  calls `GameState.add_practice(id)` (`EarthEnv.practiced`); enemy casts never count.
* **Trainer** (`EarthKit.TRAINERS`): `&"ek_bao_shan"` (Master Bao Shan, Ba Sing Se Middle Ring
  training hall: Earth Armor, Earthquake). A lesson sets
  `GameState.set_flag("trained_ek_bao_shan_<ability>", true)` (the `can_unlock` contract), e.g.
  `trained_ek_bao_shan_earthquake`. The NPC module's trainer lessons set exactly this flag for
  the trainer's npc id.
* New game: the three starters are unlocked and equipped (slots 1-3, alphabetical:
  Earth Pillar, Earth Stomp, Earth Wall); slot 4 is free; the signature appears on R / the
  touch signature button once unlocked (`BendingController.load_equipped`). All techniques
  work from the 4 technique slots + signature on keyboard, controller and touch (holding a
  touch button holds the ability: the pillar self-lift works by touch too).

## Environment (`EarthEnv`, `EarthMarks`, `EarthRubble`)

* **Persistent marks**: `EarthEnv.crater(ctx, at, radius, kind, normal)` (cracked crater decal
  + rim rubble), `EarthEnv.fissure(ctx, a, b, width, kind, slabs)` (a jagged fissure decal;
  long ones > 7 m kink; optional broken slabs jutting along it),
  `EarthMarks.furrow(from, pos, dir, length, surface)`. Decals (albedo + normal maps, generated
  by `src/fx/earth/textures/gen_earth_marks.py`) tinted with the ground's rock colour; they
  stay 12-36 s by quality tier and fade over the last 30 %, pooled and capped per kind
  (crater 4/6/10/14, fissure 8/12/20/28, furrow 2/3/5/6; Mobile renderer max 6 fissures /
  3 others since it allows 8 decals per mesh); the oldest is recycled first. On Compatibility
  (no decals) they are flat ground quads.
* **Raised rock**: `EarthEnv.raise_pillar(ctx, ground, facing, {radius, height, hp, lifetime,
  rise_time, kind})` -> `BendingConstruct` (Layers.CONSTRUCT: blocks movement, projectiles
  and line of sight; walkable top; crumbles into rubble when broken or expired). Pillars and
  walls are tagged `surface = stone`, so you can bend from on top of them and stack pillars
  (up to 6 m above the terrain).
* **Shake**: `EarthEnv.shake(ctx, center, strength, duration)` - full strength for the player's
  own moves, falling off with distance for enemy quakes; capped at `MAX_SHAKE` (0.62 trauma)
  and scaled by the camera-shake setting (screen-safe).
* **Rocks in the ground's colours**: `EarthEnv.rock(from, radius, kind)`,
  `EarthMeshes.rock / slab / pillar / spike / plate / chunk(..., surface)` and
  `EarthPalette.color(surface, "rock" | "dust" | "debris" | "cap" | "band")`.
* **Dust / debris** everywhere a rock leaves or hits the ground (`EarthFx.tear_out / impact /
  quake / dust_trail`, palette-coloured; snow kicks up snow).

## Building blocks for other abilities

```gdscript
# A shockwave over the ground: hits each target when the front reaches it,
# skips targets higher than `clearance` above the ground, walls stop it.
var w := EarthShockwave.start(ctx, center, radius, duration, hit, attack_id, ability_id, {"clearance": 1.2})
# A spike line toward `dir` (stops at no-earth / walls, one attack id).
var l := EarthSpikeLine.start(ctx, from, dir, {"length": 12.0, "speed": 24.0, "hit": hit, "attack_id": id,
		"ability_id": &"earth_spikes", "kind": info["kind"], "power": EarthEnv.power(info)})
# Armor state (any caster)
EarthArmorState.is_worn(caster); EarthArmorState.of(caster).shed(true)
# Ground checks
var info := EarthEnv.material_at(ctx, point)   # {"ok", "kind", "power", "weak", "label", "ground", "normal"}
if not info["ok"]: return EarthEnv.refuse(ctx, def.id, info)
```

## Body motion (`EarthClips`)

Hung Gar motion authored with the characters clip kit (`docs/modules/characters.md`), deep
horse stances and planted feet: `earth_pillar_raise` (knee chamber, stomp, double uppercut),
`earth_stomp_quake` (knee to the chest, fists high, slam down into horse, both fists hammer
down), `earth_spikes_drive` (coil back, lunge, both claws driven into the ground),
`earth_grab_clench` (open claw reach, clench and yank back), `earth_armor_don` (double stomp,
arms sweep the plates up, cross-slam on the chest), `earth_armor_shed` (chest expands, arms
fling outward), `earthquake_slam` (palms to the ground, rise on the toes with fists overhead,
drop onto one knee and drive the right fist into the ground, the left arm flung back).
Review them with `tools/playtest.sh bending_earth_poses` (pose sheets at the key frames;
`VIEW=front|side|34|back`, `SHEET=clip@t,...`).

## AI usage

Every Earth def works on an enemy controller. `EarthKit.enemy_attacks()` gives ready-made
`EnemyActions` attack entries (`kind: &"bending"`) for Earth Pillar (3-14 m, slot
`technique_2`), Earth Stomp (0-4.5 m, `technique_3`, ring telegraph 5 m) and Earth Spikes
(3-11 m, `technique_4`):

```gdscript
var atk := EarthKit.enemy_attacks()
bc.set_slot(&"technique_2", AbilityRegistry.get_def(&"earth_pillar"))
archetype["attacks"].append(atk[&"earth_pillar"])
```

Enemy casters commit to the pillar / grab spot when the cast starts (rumble at the spot),
so the player can step out; their quakes shake the player's screen with distance falloff;
practice never counts for them; armor on an AI caster times out after 25 s.

## Decisions

* **Rock always comes out of the ground you stand on** - in its colours (turf on grass, white
  caps on snow, basalt on ash), torn out with dust and cracks. No earth (ice, wood, deep water)
  means no technique, with clear feedback, never a silent no-op. Weak ground (sand, snow,
  mud) still works, smaller and weaker, with a one-time hint.
* **Waves and lines are gameplay objects**: `EarthShockwave` / `EarthSpikeLine` hit when the
  front / spike arrives and stop at walls; the shards and spikes you see are exactly where
  the hits are (tested: hit VFX == applied hits).
* **Fights leave scars**: craters, fissures and furrows stay for half a minute (capped,
  pooled), raised rock stays as cover and platforms until it crumbles.
* **Armor is a state, not an ability**: `EarthArmorState` lives on the caster and sets
  `BendingContext.base_damage_reduction / base_poise_armor`, which `reset_request()` now
  restores instead of zero, so the armor survives every other ability starting and ending.
* **Self-lift by holding the pillar** instead of a separate slot: one technique serves combat
  (launch) and traversal (high ground, ledges), on keyboard, controller and touch.
* **Light attack stays fast** (5 frames) - Earth's weight is in the stance, the hitstop and
  the rock, not in a slow jab; heavy moves are deliberate and readable instead.

## Performance / mobile

* Pooled + capped: marks (per kind and tier), rubble MultiMeshes (16, 3-12 live), wave shards
  (one MultiMesh of 48 per wave), shackles (4), burrows, bursts, rings, debris (FxLib caps).
  Spike lines max 56 spikes. Meshes are built once per (variant, surface) and cached.
* Physics: the shockwave re-queries one sphere every 0.1 s; the spike line does one ground
  ray, one wall ray and one sphere per spike (every 0.6 m); no other per-frame queries
  beyond ground probes where something spawns.
* All shaders are the shared toon shader with vertex colours; decals on Forward+ / Mobile,
  quads on Compatibility. Verified: Forward+ (all playtests), the Mobile renderer with the
  mobile preset and touch (`RENDERER=mobile MOBILE=1 tools/playtest.sh bending_earth_mobile`:
  effects scale 0.35, tier 0, every slot from its touch button, the held pillar button rides
  3.0 m up, the earthquake from the signature button, marks within the mobile caps) and
  Compatibility (`RENDERER=gl_compatibility TECH=stomp,spikes,quake tools/playtest.sh
  bending_earth_arena`).

## Playtests

| Scenario | What it shows |
| --- | --- |
| `bending_earth_arena` (`TECH=core,defense,pillar,self,stomp,wall,spikes,grab,armor,quake,env`) | every technique at its anticipation / active / impact frames from the player camera and an observer camera; punch chain, boulder charge + crater, shield + parry, slide furrow; self-lift onto a pillar; sand / ash / snow pillars and stomps, ice refusal; the marks left behind |
| `bending_earth_enemies` (`PART=combo,squad,adept`) | a combo string frame by frame on a bandit (punch x3 -> Stomp -> Pillar launch -> Spikes), a Fire Nation squad vs Spikes, Grab, Armor (under fire) and the Earthquake, then an enemy earthbender using `EarthKit.enemy_attacks()` on the player; hit report by ability |
| `bending_earth_world` (`PART=beach` for the shore only) | the real world near the Earth Kingdom spawn: stomp crater on the plains, a pillar, riding a column up to look out, marks staying on the terrain; spikes and a grey pillar on rocky ground; a weaker stomp on a beach; a pillar aimed into the sea refused (deep water) |
| `bending_earth_mobile` | Mobile renderer + touch overlay (above) |
| `bending_earth_poses` | pose sheets of the earth clips at their key frames |

## Changes outside the module (all additive)

* `src/bending/bending_context.gd`: `base_damage_reduction`, `base_poise_armor`;
  `reset_request()` restores them instead of 0 (0 by default: no change for other elements).
* `src/bending/ability_registry.gd`: `starter_techniques()` sorts alphabetically by string
  (StringName `sort()` orders by pointer: with three starters the slot order changed between
  runs). Identical to the change on the water branch.
* `src/fx/earth_fx.gd`: palette colours per ground (`EarthPalette`), heavy impacts / big
  quakes leave a persistent crater (`EarthMarks`) instead of the short-lived crack decal.
* `tests/unit/test_bending.gd`: the starter check accepts several starters per element
  (identical to the water branch); `tests/unit/test_player.gd`: the cooldown test accepts any
  earth starter in slot 1.

## Wave 4 bug hunt (docs/qa/bughunt_gameplay.md)

* Earth Pillar self-lift checks the headroom first (`_headroom`: the bender's capsule cast up
  against `Layers.WORLD`). The lift sets the position directly, so under a roof, an arch, a
  bridge or a cave ceiling the bender used to be carried into / through it and popped out on
  top. The column (and the lift) now stops 5 cm below whatever is overhead; with less than
  `MIN_SELF_LIFT` (0.6 m) of room there is no self-lift and the column erupts ahead as a tap
  would.

## Known limitations

* Earth Armor and Earthquake are trainer-gated (`trained_ek_bao_shan_*`): learnable once the
  NPC module's Master Bao Shan lesson sets the flag (the quests_npcs branch does this for the
  trainer's npc id `ek_bao_shan`).
* Enemy archetypes in the enemies module data do not list the new techniques yet; the
  entries are ready in `EarthKit.enemy_attacks()` and are verified on a runtime archetype in
  the enemies playtest and the unit tests.
* Structures are detected by height above the terrain (> 0.8 m): a stone floor over water
  reads as wood unless its collider carries a `surface` meta.
* Marks are decals: on steep slopes they project vertically and stretch a little.
* Audio uses the existing earth bending sound map (`BendingSounds`: `stomp`, `launch`,
  `spikes`, `armor`, `debris`, `wall`, `wall_break`, `impact`, `special`, `cast_light` /
  `cast_heavy`); the grab's clench is layered from `wall` + `impact` (no dedicated sound).

## Wave 4 (flow_qa)

* **Earth Boulder follows the heavy release contract.** Every other element's heavy extends
  `ChargeAbility`; Earth Boulder is its own lift -> hold -> throw state machine, so code that
  asked "was this heavy tapped / charged / released?" with `is ChargeAbility` never counted
  Earth (the training grounds' *Heavy Strike* and *Charged Strike* lessons could not be
  completed by an earthbender). `earth_boulder.gd` now exposes the same public fields:
  `charging` (true until the throw starts), `released` (the boulder was hurled), `tapped`
  (thrown with less than `TAP_CHARGE` = 0.15 charge) next to its existing `charge`. Readers
  use them by duck typing (`TutorialDirector.heavy_strike_of(ability)`; the enemy brain's
  evade / cover reactions read `charging` / `released`, docs/modules/enemies.md).
  Regression: `tests/unit/test_flow_qa.gd::test_tutorial_light_heavy_charge_sprint_lessons_complete_for_every_element`,
  `test_heavy_strike_report_for_charge_abilities_and_earth_boulder`. See `docs/qa/flow_qa.md`.
