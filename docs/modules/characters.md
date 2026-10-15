# Characters module (`src/characters/`)

Code-built, procedurally animated humanoids for the player, NPCs, enemies and
trainers: `HumanoidRig` (Node3D, faces **-Z**, feet at the origin, ~1.76 m adult)
with a skinned toon mesh generated from a data-driven outfit config and a
layered procedural pose engine (locomotion with zero foot sliding, per-style
stances, keyframed action clips with timed events, hit reactions, foot IK,
look-at, secondary motion).

```
src/characters/
  humanoid_rig.gd            HumanoidRig: public API, sockets, LOD, feedback, events
  rig/rig_skeleton_def.gd    bone layout + proportions (body / age / bulk)
  mesh/                      skinned geometry: lofts, head/face, hair, garments, headwear
  outfits/                   CharacterOutfits (config -> spec), OutfitPresets (data)
  anim/rig_pose.gd           RigPose: animation channels (units / conventions below)
  anim/anim_clip.gd          AnimClip: compiled clip + evaluation
  anim/anim_library.gd       AnimLibrary: global clip registry (register / get_clip)
  anim/rig_animator.gd       layer stack (idle/stance, locomotion, states, actions, additive)
  anim/rig_locomotion.gd     gait: world-locked feet, predictive swings, footsteps
  anim/rig_solver.gd         FK + two-bone IK, heel/toe pivots, ground alignment
  anim/rig_secondary.gd      spring chains (hair, capes) + quadrant skirt panels
  anim/rig_styles.gd         gait parameters per style
  anim/rig_reactions.gd      hit reaction -> clip mapping
  anim/clips/*.gd            built-in clip data (170 clips)
  props/rig_props.gd         RigProps: simple toon hand/back props (staff, spear, tools...)
  dev/character_showcase.gd  dev stage (scenes/dev/character_showcase.tscn)
```

## Quick start

```gdscript
# On a CharacterBody3D (player / enemy / NPC):
var rig := HumanoidRig.create({"preset": &"fire_nation", "seed": 7})
add_child(rig)                      # rig.actor defaults to this body
rig.set_combat_stance(true)

func _physics_process(delta):
    move_and_slide()
    rig.set_locomotion(velocity, is_on_floor())   # every frame

func attack():
    var dur := rig.play_action(&"fire_jab_r")       # seconds
    await rig.action_event                          # or connect action_event
```

`HumanoidRig.create(config)` builds immediately; you can also set
`rig.config = {...}` before adding it to the tree (built in `_ready`), or call
`rig.build(config)` again to change looks. If `set_locomotion()` is never called
the rig derives its velocity from its own movement (good for tweened NPCs).

## Config (character look)

A plain Dictionary; every key except `preset` is optional and anything not
given is chosen deterministically from `seed`.

| key | values |
| --- | --- |
| `preset` | see presets below |
| `body` | `"male"`, `"female"` |
| `age` | `"adult"`, `"teen"`, `"child"`, `"elder"` (proportions: big heads for kids, hunched elders) |
| `height` | meters (default: canonical for body/age, seeded +-3.5%) |
| `bulk` | -1 slim .. 1 heavy (snapped to 0.5 steps so meshes are shared) |
| `skin` | int index into `CharacterOutfits.SKIN_TONES` (0 light .. 5 dark) or a Color |
| `hair_style` | `"bald"`, `"short"`, `"spiky"`, `"slick"`, `"undercut"`, `"bangs"`, `"parted"`, `"cropped"`, `"receding"`, `"long"` |
| `hair_extras` | Array of `"topknot"`, `"bun"`, `"wolf_tail"`, `"ponytail"`, `"loopies"`, `"long"`, `"braid"` |
| `hair_color` | Color or int index into `HAIR_COLORS` |
| `eye_color` | Color |
| `palette` | Dictionary overriding named preset colors (e.g. `{"tunic": Color(...)}`) |
| `accessories` | Array of props `"name"` or `"name@socket"` (`RigProps.NAMES`), e.g. `["staff@back"]`, `["spear@hand_r"]`, `["lantern@hand_l"]`. Default socket: `back` for the staff, else `hand_r`. Presets: `air_nomad` carries a staff on the back, `guard` a spear. Props are not part of the mesh cache key. |
| `tattoo` | bool (air nomad arrows) |
| `beard` | `"long"`, `"goatee"` |
| `style` | animation style override (StringName, see Styles) |
| `seed` | int: seeded variation of skin / hair / palette / height / bulk |
| `detail` | 0..3 mesh detail (default `Settings.detail_level()`) |

Presets (`CharacterOutfits.PRESETS`):
`air_nomad` (orange/yellow monk clothes, cape, bald + blue arrow; female: hair bun, dress),
`monk_elder` (long robe, bell sleeves, prayer beads, long beard, arrow),
`water_tribe` (blue parka, white fur trims, hood, boots; male wolf tail, female loopies + braid + necklace),
`water_warrior` (wolf helmet, face paint, armor, pauldrons),
`earth_kingdom` (green tunic, crossed V collar over tan undershirt, sash knot, topknot / bun),
`earth_soldier` (armor plates, pauldrons, conical soldier hat), `dai_li` (dark green robes, wide hat with jade ornament, stone gloves, braid),
`fire_nation` (red tunic with split panels, layered pauldrons, gold trims, topknot + gold crown),
`fire_soldier` (armor, three-layer pauldrons, skull face mask helmet), `bandit` (vest, face scarf, headband),
`pirate` (striped shirt, vest, sash, bandana), `merchant` (rich robe, bell sleeves, cap, goatee), `guard` (round helmet, armor),
`villager_air`, `villager_water`, `villager_earth`, `villager_fire` (muted palettes, straw hats, per-nation clothes).
Every preset works with `body: female` and all ages.

`CharacterOutfits.resolve(config) -> spec` returns the resolved spec (colors, body
bands, garment pieces, `style`, `scale`, `cache_key`). Meshes are cached per
`cache_key` (`CharacterMeshBuilder`), so crowds of the same variant share one
ArrayMesh and one material.

## HumanoidRig API

### Signals
* `action_event(clip: StringName, event: StringName)` – a clip's timed event (exact frame).
* `action_finished(clip: StringName)` – clip reached its end (not when stopped/replaced).
* `built` – after `build()`.

### Properties
* `config: Dictionary` (export), `spec: Dictionary` (resolved), `def: RigSkeletonDef`
* `actor: Node3D` – reported in `Events.footstep` / `Events.landed`; defaults to the parent body.
* `emit_footsteps := true`, `emit_landed := false`, `auto_lod := true`, `manual_update := false`
* `skeleton: Skeleton3D`, `mesh_instance: MeshInstance3D`, `animator: RigAnimator`, `lod: int`

### Methods
| method | notes |
| --- | --- |
| `static create(config) -> HumanoidRig` | builds immediately |
| `build(config)` | (re)build looks; keeps the node |
| `set_locomotion(world_velocity: Vector3, grounded := true, delta := 0.0)` | call every frame; stride/cadence follow the actual speed |
| `set_style(style: StringName)` / `get_style()` | crossfades body language |
| `set_combat_stance(on: bool)` / `is_combat_stance()` | style stance while idle; guard up while moving |
| `play_action(clip, opts := {}) -> float` | duration in seconds (0 if unknown). opts: `speed` (1.0), `blend_in`, `blend_out`, `mask` (`&"full"`, `&"upper"`, `&"arms"`, `&"arm_l"`, `&"arm_r"`, `&"legs"`, `&"head"`), `mirror` (bool), `root_motion` (bool), `start` (normalized) |
| `stop_action(blend := -1.0)` | crossfades out |
| `is_playing_action() -> bool`, `current_action() -> StringName`, `action_progress() -> float` | progress is normalized 0..1 (-1 if none) |
| `consume_root_motion() -> Vector3` | world-space displacement of `root_motion` clips since the last call |
| `play_reaction(kind, world_dir := Vector3.ZERO, strength := 1.0) -> float` | `kind`: `HitInfo.Reaction` value or `&"flinch"`, `&"stagger"`, `&"knockback"`, `&"knockdown"`, `&"launch"`, `&"pull"`, `&"freeze"`, `&"death"`, `&"getup"`. `world_dir` = direction the hit pushes this character. Flinch is additive and never interrupts; returns the clip duration (0 for flinch). |
| `set_pose_state(state, blend := 0.2)` / `get_pose_state()` | see Pose states |
| `land(impact_speed) -> float` | ends airborne/falling, plays `land_light` / `land_heavy` (impact > 9 m/s) or `knockdown_land` after a launch; emits `Events.landed` if `emit_landed` |
| `look_at_point(pos: Vector3, weight := 1.0)` / `clear_look_at()` | head 45% / neck 30% / chest 25%, clamped |
| `set_talking(on: bool)` | mouth flaps |
| `get_socket(name) -> Node3D` | `hand_l`, `hand_r` (palm center; -Z along fingers, -Y out of the palm), `foot_l`, `foot_r` (sole center), `head`, `chest`, `pelvis`, `back`, `mouth`. Children follow the animated bone (BoneAttachment3D). |
| `get_palm_direction(side) -> Vector3` | world direction the palm faces (0 left, 1 right) |
| `attach_prop(prop, socket := &"hand_r") -> Node3D` | `prop`: a `RigProps` name (`staff`, `spear`, `hammer`, `broom`, `fishing_rod`, `basket`, `sword`, `lantern`) or your own Node3D whose handle runs along +Y from the grip at its origin. Hand props are gripped across the fist (the hand closes around them); poles and lanterns also layer a carry pose (`hold_pole_*`, `hold_lantern_*`) over idle/locomotion, under actions. Replaces the socket's previous prop. |
| `detach_prop(socket)` / `get_prop(socket) -> Node3D` | frees the prop and releases the grip / carry pose |
| `flash_hit(color := WHITE, duration := 0.18)` | white hit flash (gives this rig its own material copies) |
| `set_status_tint(color, amount)` | soaked / frozen / burned overlay; 0 clears |
| `set_foot_ik(enabled)` | ground adaptation (raycasts on `Layers.SOLID`, `WorldData.get_height` fallback) |
| `set_lod(level)` | 0 full, 1 no secondary motion / fewer ground rays, 2 pose at 20 Hz without IK, 3 dormant (logic only). Disables `auto_lod`. |
| `advance(delta)` | manual update when `manual_update` (cutscenes, tests) |
| `get_height()`, `get_bone_index(name)`, `get_bone_world(name) -> Transform3D` | queries |

Typical enemy flow: `play_reaction(hit.reaction, hit.direction)` + `flash_hit()` on
damage; `play_reaction(&"death", dir)` on death (ends in the `dead` state).
Knockdowns end in `knocked_down`; call `RigReactions.get_up(rig)` (or
`play_reaction(&"getup")`) when the stun ends. Launches tumble (`tumbling`) until
`land(impact)`.

### Pose states
`normal`, `airborne` (`jump_air`, air style: `jump_air_air`), `falling`, `riding`
(rig origin at the saddle seat), `knocked_down`, `blocking` (upper body; legs keep
moving), `charging` (upper body; `charge_hold_<style>`), `swimming`, `dead`,
`sitting`, `meditating`, `sleeping`, `tumbling`. A state clip named
`<clip>_<style>` overrides the default for that style.

### Events (global bus)
* `Events.footstep(actor, foot_center_world, foot_yaw, foot_length (~0.26 * scale), weight, surface)`
  at the true plant moment of every step (gait plants, idle re-steps, turning in
  place) and for clip `plants`. `weight`: 0.6 walk .. 1.0 run, x1.3 for heavy styles
  (earth), lighter for air; position is the sole center snapped to the ground.
* `Events.landed(actor, position, impact, surface)` from `land()` when `emit_landed`.

## Styles (`RigStyles`)
| style | body language |
| --- | --- |
| `air` | Ba Gua: light, on the balls of the feet, bouncy, airy palms; trailing-arm run |
| `earth` | Hung Gar: low, wide toe-out steps, heavy plant drop, fists, horse stance |
| `fire` | Northern Shaolin: forward-weighted, tight pumping fists, bow stance |
| `water` | Tai Chi: gliding low-bob steps, weight shifting, floating circling palms |
| `civilian`, `soldier` (upright, stiff), `elder` (hunched, hands behind back, short steps), `child` (quick, bouncy) |

Each style has `idle_<style>` and `stance_<style>` loops and gait arrays
`[walk, run, sprint]` interpolated by speed (normalized by leg length, so
children take more steps). Presets pick a default style; `config.style` or
`set_style()` override it.

## Clips (`AnimLibrary`)

```gdscript
AnimLibrary.register(&"my_move", {
    "length": 0.6,                    # seconds at speed 1
    "mask": &"upper",                 # default mask (opts.mask overrides)
    "events": [[0.45, &"release"], [0.5, &"impact"]],   # normalized time
    "plants": [[0.4, "r", 1.3]],      # footstep at t for side l/r with weight
    "root": [[0.0, Vector3.ZERO], [1.0, Vector3(0, 0, 2.0)]],  # right/up/forward meters
    "keys": [
        [0.25, {"hand_r": Vector3(0.0, -0.4, 0.0), "fist_r": 1.0}, &"inout"],
        [0.45, {"hand_r": Vector3(-0.1, 0.0, 0.95), "chest": Vector3(4, 20, 0)}, &"snap"],
    ],
})
AnimLibrary.get_clip(&"my_move")   # AnimClip (or null)
AnimLibrary.alias(&"water_whip_r", &"whip_lash_r")   # copy under a new name
ClipKit.reg_pair("my_punch", clip_r)                  # registers _r and mirrored _l
ClipKit.chain([hit1, hit2, hit3])                     # one combo clip from parts
```

Other fields: `loop` (keys in [0, 1)), `blend_in` / `blend_out` (s), `hold` (keep the
last key instead of returning to the base pose), `next` (clip to chain),
`then_state` + optional `state_clip` (pose state after the end), `recover_ease`,
`meta`. Eases per key: `&"linear"` (default, Catmull-Rom), `&"in"`, `&"out"`,
`&"inout"`, `&"snap"`, `&"slow"`, `&"hold"`.

A clip only overrides the channels it keys. For non-looping clips the layer below
(stance / locomotion) is an implicit key at t = 0 and t = 1, so moves blend in from
and recover back to whatever the character was doing. Channels keyed in a clip
also define its effective mask (an upper-body punch while running keeps the legs
running). Euler channels blend along the shortest arc, so keys may spin
360/720 degrees (tornado spin, flips) without unwinding on recovery.

### RigPose channels (units)
| channel | meaning |
| --- | --- |
| `hips` | Vector3 offset (right, up, forward) in leg lengths (1.0 = hip height) |
| `hips_rot`, `spine`, `chest`, `neck`, `head` | Euler degrees (pitch forward +, yaw left +, roll left +); `chest` is split over chest + upper_chest |
| `clav_l/_r` | degrees (x raise/shrug, y forward) |
| `hand_l/_r` | wrist target relative to the shoulder in the upper-chest frame, arm lengths (out +, up +, forward +). `(0.1, -0.96, 0.04)` hangs, `(0, 0, 1)` is a straight punch |
| `elbow_l/_r` | elbow pole direction (out, up, forward) |
| `wrist_l/_r` | degrees (x flex toward palm, y pronation (forearm twist), z deviation). Palm forward, fingers up = `(-80, 90, 0)` |
| `fist_l/_r` | 0 open .. 1 fist |
| `foot_l/_r` | ankle offset from its rest spot under the hip, leg lengths (out, up, forward) |
| `knee_l/_r` | knee pole (out, up, forward) |
| `foot_rot_l/_r` | degrees (x toes up, y toe-out, z outer edge up) |
| `toe_l/_r` | toe bend degrees |
| `feet_hips` | 0..1: feet/knees relative to the rotating pelvis (rolls, flips, lying) |
| `mouth` | 0..1 open |

Lateral values are positive outward for both sides, so mirroring is a channel swap.

### Built-in clips (166)
Events: `release` (spawn the projectile), `impact` (melee contact), `recover`
(cancel window), `stomp`, `takeoff`, `dodge`, `ground_hit`, `gather`, `lift`, `grab`, ...
* **Idle / stance loops**: `idle_<style>`, `stance_<style>` (air, earth, fire, water, civilian, soldier; elder/child idles).
* **Air / landing**: `jump_start`, `jump_air`, `jump_air_air`, `fall`, `land_light`, `land_heavy`.
* **Dodges** (root tracks; use `root_motion` or move the body yourself): `dodge_roll`, `dodge_side_l/_r`, `dodge_back`, `dodge_flip`, `dodge_earth_slide_l/_r`, `dodge_water_slide_l/_r`, `dodge_fire_burst`.
* **Defense**: `block_hold` (+ `_air`, `_earth`, `_water`), `block_impact`, `parry_l/_r`.
* **Reactions**: `flinch_front/back/left/right`, `stagger_front/back/left/right`, `knockback_back`, `knockdown_back`, `knockdown_front` -> `down_loop` -> `getup`, `launch` -> `air_tumble` -> `knockdown_land`, `death_front`, `death_back` -> `dead_loop` / `dead_loop_prone`.
* **Generic strikes**: `jab_l/_r`, `cross_l/_r`, `front_kick_l/_r`, `side_kick_l/_r`, `roundhouse_l/_r`, `spin_kick`, `flip_kick`, `palm_strike_l/_r`, `two_hand_push`, `shield_raise`, `uppercut_lift`, `wall_raise`, `stomp_l/_r`, `ground_slam`, `draw_up`, `whip_lash_l/_r`, `arm_circle`, `charge_hold` (+ `_air`, `_fire`), `charge_release`, `spin_attack`, `tornado_spin`, `leap_attack`.
* **Element moves**: `air_jab_l/_r`, `air_blast`, `air_sweep`, `air_spin`, `air_tornado`, `air_charge_hold/_release`; `earth_jab_l/_r` (stomp + fist), `earth_raise`, `earth_wall`, `earth_throw`, `earth_stomp_l/_r`, `earth_slam`, `earth_shield`; `fire_jab_l/_r`, `fire_kick_l/_r`, `fire_spin_kick_l/_r`, `fire_flip_kick`, `fire_charge_hold`, `fire_charge_release`, `fire_breath` (use the `mouth` socket); `water_jab_l/_r`, `water_whip_l/_r`, `water_draw`, `water_surge`, `water_shield`, `water_heal_loop`.
* **Combos**: `combo_<style>_1..N` (single hits to chain on input; air 3, earth 3, fire 4, water 3) and `combo_<style>` (whole chain, one `impact` per hit).
* **Life**: `talk_1`, `talk_2` (loops), `talk_3` (shrug), `wave_l/_r`, `cheer`, `point_l/_r`, `bow`, `sit` -> `sit_loop`, `meditate` -> `meditate_loop`, `kneel`, `sleep_loop`, `work_hammer`, `sweep`, `carry`, `fish` (loops; pair them with the `hammer`, `broom`, `basket`, `fishing_rod` props), `interact_l/_r` (`grab` event), `mount` -> `ride`, `dismount`, `swim`.
* **Carry layers** (single-arm masks, applied automatically by `attach_prop`): `hold_pole_l/_r`, `hold_lantern_l/_r`.

## Mesh & look
* Bodies are **painted lofts**: torso, arms, legs, neck and feet are swept
  superellipse tubes whose clothing is expressed as color bands with inflation
  (crisp hems via duplicated rings), so cloth never pokes through skin. Loose
  garments (robe/tunic skirts, split armor panels, bell sleeves, fur rings, trims,
  V-neck patches, layered pauldrons, capes, sash knots, beads, necklaces, scarf
  masks, conical hats, helmets incl. the fire soldier skull mask and the wolf
  helmet) are layered on top, skinned with the same weight functions as the
  surface below.
* Heads are an analytic surface (cranium, jaw taper, chin); eyes (white, iris,
  pupil, two highlights, lash line), brows, mouth, nose, tattoos, face paint and
  hair are placed on that surface. Eyes / mouth have bones (blink squash, talk).
* Two surfaces: outlined body (`ToonMaterials.make(WHITE, {vertex_color, ...})`
  with the ink outline next pass) and flat face/trim decals (no outline).
  Vertex colors are authored in sRGB and converted to linear.
* Skeleton: 32 core bones (root, hips, spine, chest, upper_chest, neck, head,
  eye_l/r, mouth, clavicles, upper/fore arms, hands, fingers + fingertips, thumbs,
  thighs, shins, feet, toes) with identity rest rotations (model axes), plus
  outfit bones: `hair_1/2`, `hair_back_1/2`, `cape_1/2`, `skirt_fl/fr/bl/br`.

## Design decisions
* **Pose channels instead of bone rotations**: clips are authored as hand/foot
  targets and torso angles normalized by limb length, then solved with analytic
  IK, so one clip works on children, women, elders and giants, blends linearly
  and mirrors by swapping channels.
* **World-locked feet**: planted feet store world position + yaw; the swing lands
  where the foot must be at mid-stance for the current velocity and turn rate.
  Stride = speed x cycle time by construction; turning, braking and pushes never
  slide feet. Heel strike / toe-off rotate exactly about the heel / ball contact
  points (the ball stays locked through toe-off, verified by tests). Unreachable
  targets pivot the foot (leading: toe-up around the heel; trailing: heel-up around
  the ball) instead of overstretching.
* **Snapshot crossfades** handle every transition (action -> action, state
  changes, style changes) without per-pair blend logic.
* **Quadrant skirt panels** follow their own thigh's swing and spread, so robes
  open for kicks and horse stances instead of being pierced by the legs. When
  both thighs are forward (sitting, meditating) long robes are tucked: the back
  panels fold under the thighs and the panels shorten (bone scale) to end near
  the knees. Spring chains rest on the rig's ground plane.
* Secondary motion is GDScript verlet (hair tails, long hair, braids, capes) in
  world space so it trails behind motion, with a back-collision plane; it is
  disabled beyond LOD 0.

## Performance
* Meshes/materials cached per appearance (`cache_key`); seeded crowds reuse a
  handful of variants. A character builds in ~40-90 ms (once per variant).
* Measured (headless, this dev container): ~0.17 ms per rig per frame at LOD 0
  (full IK, ground rays, springs), ~0.05 ms at LOD 2. Auto LOD uses distance
  (scaled by `Settings.detail_level()`) and `VisibleOnScreenNotifier3D`; action
  time and events always advance at full rate (gameplay sync) even when the pose
  is updated less often. Characters fade out past 160 m (visibility range).

## Testing
* `tools/test.sh test_characters` – build all presets/ages, skeleton layout,
  normalized weights, clip registry/format, event timing, stride vs speed, ball of
  foot locked through stance, footstep counts, states/reactions, sockets, props
  (preset accessories, upright carry pose, detach), root motion, LOD, look-at,
  style differences, update cost.
* Playtests: `characters_lineup` (all presets, female/ages/crowd, faces),
  `characters_motion` (each style idle/walk/run sequences, turning, step and stair
  foot IK), `characters_strikes` (signature strikes at anticipation/active frames
  per style, reactions, dodges, combo event check). `characters_posesheet`
  renders arbitrary clips frozen at a normalized time, optionally per preset and
  with a prop: `SHEET="jab_r,front_kick_r@0.4;villager_earth:work_hammer@0.35+hammer/hand_r" PRESET=fire_nation VIEW=side tools/playtest.sh characters_posesheet`
  (`;` separates images, `<preset>_f` = female, `VIEW=front|side|34|back|back34`,
  `CLOSE=1` frames the upper body).
  Without `SHEET` it renders the life/props review set.
* Interactive: `godot --path . -- --scene=res://scenes/dev/character_showcase.tscn`.

## Known limitations
* Props are simple primitives without their own animation (the glider staff
  does not open; the fishing line is not simulated). Two-handed poles in combat
  clips are not authored; the carry pose is one-handed.
* Capes are two-bone spring chains: in lying poses they rest flat on the
  ground plane rather than draping around the body.
* Bell sleeves are rigid around the forearm (no gravity drape).
* Long dresses use four rigid skirt panels; extreme leg poses (splits) can
  still clip, and a seated tunic shows its open hem from above.
* Hair has a soft environment-reflection sheen from the shared toon shader.
