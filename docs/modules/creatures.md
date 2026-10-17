# Creatures module (`src/creatures/`)

Procedurally built and procedurally animated creatures: the four element companions
(sky bison, dragon, polar bear dog, badgermole), wildlife (otter penguin, turtle duck,
ostrich horse, komodo rhino) and cheap bird flocks. Bodies are generated in code (no art
packs), skinned to a procedural skeleton and animated every frame from locomotion input,
actions and secondary motion. **Behaviour/AI and mount/flight controllers are NOT here**:
`src/companions/` (and wildlife spawners) drive this API.

```
src/creatures/
  creature_rig.gd          CreatureRig (Node3D) - the public API
  core/                    RigSkeleton, MeshKit, CreatureMaterials, CreatureLeg (IK),
                           GaitEngine, CreatureMotor, SpringChain, CreaturePose,
                           CreatureAction, ActionPlayer, CreatureParts
  species/                 creature_species.gd (base + shared actions) and one script per
                           species (+ dragon_wings.gd, dragon_mesh.gd)
  birds/bird_flock.gd      BirdFlock (MultiMesh birds)
  fx/creature_fx.gd        CreatureFx (dig debris / dust)
  dev/                     showcase stage + CreatureDriver (test helper, not gameplay)
assets/shaders/creatures/  creature_common.gdshaderinc (toon light + markings),
                           creature_skin, fur_shell, creature_eye, membrane,
                           creature_outline, bird
scenes/dev/creature_showcase.tscn
```

## Quick start

```gdscript
var bison := CreatureRig.create(&"sky_bison", {"seed": 7})
add_child(bison)                         # usually as a child of the companion's body
bison.footstep_actor = companion_body    # footprints/sounds attributed to the gameplay actor

# every physics frame (controller owns movement and collision):
bison.set_locomotion(body.velocity, body.is_on_floor(), delta)

# flyers:
bison.set_flying(true)                   # plays "takeoff"; climb after action_event "leap"
bison.set_flight(true, body.velocity, bank, pitch)   # each frame while airborne
bison.set_flying(false)                  # keep descending; "land" plays near the ground

var d := bison.play_action(&"call")      # returns duration (s), 0 if unsupported
bison.action_event.connect(func(a, e): if e == &"vocal_start": ...)
var seat := bison.get_socket(&"saddle")  # Node3D following the head bone
```

## Conventions

* Faces **-Z**, 1 unit = 1 m. The origin is the **ground point under the body center**
  (the controller keeps it on the ground). **Dragon:** the origin is under the
  **shoulders**; the head reaches ahead and the 26-segment body/tail follows the path the
  shoulders travelled (so a turning dragon snakes; it needs no extra collision beyond a
  capsule at the shoulders).
* The rig never moves itself. It reads its own `global_transform` (set by the controller)
  and the velocity passed to `set_locomotion` (if never called it derives velocity from its
  own movement, handy for scripted wildlife).
* Animation runs in `_process` on the creature's own clock (`time`), so it is smooth at any
  frame rate; action timing uses real elapsed time.

## API — `CreatureRig` (class_name, extends Node3D)

### Creation
| Call | Description |
| --- | --- |
| `static create(species: StringName, config := {}) -> CreatureRig` | Builds a creature (null + error for unknown ids). |
| `static species_list() -> Array[StringName]` | All ids. `COMPANIONS` / `WILDLIFE` constants list the groups. |
| `static clear_mesh_cache()` | Drops cached meshes (tests / hot reload). |

`config` keys: `seed` (int, idle randomness), `scale` (float, all lengths; speeds scale
with sqrt), `colors` (Dictionary overrides, keys per species: `fur`, `arrow`, `horn`,
`scales`, `belly`, `mane`, `membrane`, `back`, `body`, `head`, `shell`, `hide`),
`detail` (0..3, default `Settings.detail_level()`; fixes the detail and stops listening
to settings changes), `sounds` (bool, default true), `idle` (random idle behaviours,
default true), `fx` (built-in debris effects, default true), `lod` (-1 auto default, or a
fixed level), `draw_distance` (m).

### Locomotion
| Call | Description |
| --- | --- |
| `set_locomotion(world_velocity: Vector3, grounded: bool, delta := 0.0)` | Feed every physics frame. Drives gait choice (speed thresholds per species), stride frequency, lean/turn bend, airborne leg reach (`grounded == false` for > 0.15 s while not flying). |
| `set_flight(active: bool, velocity := Vector3.ZERO, bank := 0.0, pitch := 0.0)` | Flyers, every frame while airborne. `bank` rad, **+ = right side down (turning right)**; `pitch` rad, + = nose up. Calls `set_flying(active)`. |
| `set_flying(active: bool) -> float` | Request takeoff/landing. Returns the transition duration (0 if unchanged or the species cannot fly). Takeoff plays `takeoff` immediately (`action_event("takeoff", "leap")` = start climbing). Landing keeps the flight pose while `altitude() > land_altitude()` (controller descends), then plays `land` (`"touchdown"` event); `flight_w` blends to 0 (faster once `grounded`). |
| `is_flying()`, `is_landing()`, `can_fly()`, `altitude()`, `land_altitude()` | Flight state queries. `flight_w` (0..1) is the current air/ground pose blend. |
| `set_swimming(active: bool, water_height := 0.0)` | Floats the body at the water line (`tune.swim_float`) and paddles all legs. Keep the origin roughly at the surface. |
| `reset_feet()` | Re-plant all feet under the body (after teleporting; also automatic for jumps > 12 m). |

### Actions
| Call / signal | Description |
| --- | --- |
| `play_action(name: StringName, opts := {}) -> float` | Plays an action, returns its duration in seconds (0 = unsupported). Cross-fades from the previous action. **Hold actions** return the time to reach the held pose and stay until `stop_action()` (`sit`, `lie_down` also end when the creature starts moving; `dig_in` ends with `emerge`; `breathe_fire_start` with `breathe_fire_end`). `takeoff`/`land` on flyers go through `set_flying`. |
| `stop_action()` | Blend back to locomotion. |
| `is_action_playing(name := &"")`, `current_action()`, `supported_actions()` | Queries. |
| `signal action_event(action_name, event)` | Timed events (table below). |
| `signal action_finished(action_name)` | When an action has fully blended out. |

Shared actions (every species): `sniff`, `look_around`, `ear_twitch`, `yawn`, `shake`
(event `shake` - spawn droplets), `roar` / `call` / `howl` / `bark` / `growl` (`vocal_start`,
`vocal_end`), `sit` (hold), `lie_down` (hold), `rear_up` (`peak`, `land`), `eat` (`chew`),
`bite` (`hit` at the strike), `swipe` (`hit`; opts `side` ±1), `scratch`.

| Species | Extra actions / notes |
| --- | --- |
| sky_bison | `groan`, `takeoff` (`leap`, `stroke`), `land` (`stroke`, `touchdown`); `call` = bison call |
| dragon | `takeoff` (`leap`), `land` (`touchdown`), `breathe_fire_start` (hold; `inhale`, `fire_start` at 0.6 s), `breathe_fire_end` (`fire_end`), `snort` (`smoke`), `stretch_wings`, `prowl` (hold, low stalking) |
| polar_bear_dog | `howl` sits back and howls; idle may `scratch`, `shake`, `sit` |
| badgermole | `dig_in` (hold; `scoop` ×8, `burrowed`), `emerge` (`burst`, `shake`), `dig` (idle scratch at the ground) |
| otter_penguin | `belly_slide` (hold; `slide_start`), `flap` (`call`), `preen` |
| turtle_duck | `quack`/`call` (`vocal_start`), `preen`, `dive` (`splash`) |

The rig plays creature sounds for some events when `sounds` is on (`bison_call`,
`bison_groan`, `dragon_roar`, `wing_flap_large`, `dog_bark`, `dog_growl`,
`badgermole_snort`, `badgermole_dig`, `land_heavy`, `fire_whoosh`) and
`creature_step_heavy` on heavy footfalls (weight ≥ 0.7). Gameplay (fire damage, bite
damage, burrow travel) belongs to the companion module: listen to the events, use the
sockets.

### Sockets
`get_socket(name) -> Node3D` (child of the rig, updated every animation step; -Z of the
socket = creature forward). Every species has: `saddle` (rider seat: on the bison it is the
pilot seat on the head, on the dragon the neck base), `back` (second seat / bison passenger
saddle), `rider_left`, `rider_right` (side seats / stirrups), `head`, `mouth` (fire breath,
bite VFX), `chest`, `tail`. Extra: dragon `wing_left`, `wing_right`; badgermole
`claw_left`, `claw_right`; ostrich horse `reins`. `get_socket_names()` lists them.

### Dimensions
`get_dimensions() -> Dictionary`: `length`, `height`, `width`, `saddle_height`,
`paw_size` (footprint length), `weight` (footstep weight 0..1+, bison/badgermole 1.0),
`can_fly`, `walk_speed`, `run_speed`, `sprint_speed`, `fly_speed`, `collision_radius`,
`collision_height`, `mass` (kg); dragon also `wingspan`. Use the speeds to pick
velocities so the gait engine selects the intended gait.

| Species | Length | Height | Gaits (speed thresholds scale with sqrt(scale)) |
| --- | --- | --- | --- |
| sky_bison | 8.0 m | 4.0 m | walk (6-leg wave, ≤2.6 m/s), run (tripod trot) |
| dragon | 21.5 m | 4.4 m | walk (lizard crawl, ≤3.2), run (diagonal trot) + flight |
| polar_bear_dog | 3.0 m | 2.35 m | walk (≤2.2), trot (≤5.5), gallop |
| badgermole | 4.6 m | 1.95 m | walk (≤2.4), run (half bound) |
| otter_penguin | 0.5 m | 1.08 m | waddle, hurry; belly slide |
| turtle_duck | 0.56 m | 0.42 m | waddle, hurry; swims |
| ostrich_horse | 2.6 m | 2.85 m | walk, run (flight phase) |
| komodo_rhino | 4.4 m | 1.7 m | walk, run (with spine undulation) |

### Look, LOD, misc
| Call | Description |
| --- | --- |
| `look_at_point(pos: Vector3, weight := 1.0)` / `clear_look()` | Neck + head + eyes turn toward a world point within species limits, smoothed. |
| `set_lod(level: int)` | `-1` auto (distance to the active camera scaled by creature size + `VisibleOnScreenNotifier3D`; re-evaluated on screen entry). `0` full: fur shells, ground raycasts, springs, every frame. `1` half shells. `2` no shells/springs, WorldData ground only, 20 Hz. `3` 6 Hz, no shadow casting, no footsteps. |
| `flash_hit(strength := 1.0)`, `set_status(color, amount)` | Per-instance hit flash / status tint (instance uniforms; materials stay shared). |
| `footstep_actor: Node3D` | Actor passed in `Events.footstep` (default: the rig). |
| `set_probe_exclude(rids)` | Colliders the ground probe ignores (e.g. the companion's own body if it is on a SOLID layer). |
| `signal foot_planted(leg_index, position)`, `signal flight_changed(flying)` | Local notifications. |
| `get_paw_position(i)` | World position of a planted/moving paw. |

## Footsteps

At the exact plant moment of each paw, the gait engine probes the ground (ray on
`Layers.SOLID`, `WorldData.get_height` fallback; WorldData only at LOD ≥ 2) and the rig
emits `Events.footstep(actor, paw_contact, yaw, paw_size, weight, WorldData.get_surface(p))`.
A walk cycle produces exactly one footstep per leg (tested). No footsteps while flying,
swimming, burrowed or at LOD 3.

## How it works

### Skeleton and skinning
`RigSkeleton` holds bones with **identity rest bases** (bone axes = creature axes, so
"pitch the neck about X" is literal), local rotations/offsets and non-inherited scale
(breathing). FK is computed in GDScript and pushed to a **flat** `Skeleton3D` (every bone
is a root whose pose is the skeleton-space transform), so the engine does no hierarchy
work and skinning uses exactly the solved transforms. IK and springs write globals
directly and keep local rotations consistent.

### Geometry (`MeshKit`)
Everything is a *loft*: superellipse cross-sections (separate top/bottom half heights)
swept along a Catmull-Rom path with rounded/pointed/flat caps and optional "fluff"
scallops (clumped fur silhouettes, stronger on bellies via `fluff_lo`). Normals come from
the grid (seamless). Ellipsoids, tubes (horns, claws, whiskers), eyes and closed thin
sheets (wing membranes via Coons patches) are built on the same machinery. Skin weights
come from `RigSkeleton.chain_weighter` (smooth blend along a bone chain),
`rigid_weighter`, or `segment_weighter` (inverse distance, for membranes). Meshes are
cached per species + scale/colors + detail, so every bison shares one `ArrayMesh`.

UV convention (used by the shaders): `UV = (u around: 0 top, 0.25 right, 0.5 belly;
mark_row + v along the part)`, `UV2 = (meters around, meters along)`, `COLOR.rgb` tint
(linear), `COLOR.a` fur amount (or mane flutter weight).

### Materials and shaders
* `creature_skin.gdshader`: the project toon light model (copied from `toon.gdshader` via
  `creature_common.gdshaderinc`), vertex tint, **analytic marking bands** (dorsal /
  ventral / lateral pair, widths per part row from a small RGBAF texture: the bison
  arrow, badger stripes, gold dragon belly), procedural patterns (fur strokes, scales,
  feathers, shell plates, belly plate seams), optional mane flutter. No sky reflections.
* `fur_shell.gdshader`: N alpha-scissor shells chained as `next_pass` (N = 0/4/7/10 for
  detail 0..3, halved at LOD 1, none at LOD ≥ 2). Dense at the root so silhouettes have no
  gaps, sparse strands at the tips.
* `creature_outline.gdshader`: the ink outline (same look as the foundation outline) with
  a push into the fur and matching mane flutter.
* `creature_eye.gdshader`: analytic iris/pupil (slits for dragon/komodo), view-space
  catchlights, glow (dragon). `membrane.gdshader`: double-sided wing skin with veins and
  translucency. `bird.gdshader`: vertex-shader wing flap for MultiMesh flocks.
* Per-creature hit flash / status use `instance uniform`s with fixed `instance_index`, so
  materials are shared across instances. `occlusion_fade` (index 3, perf_polish) dithers the
  creature out (4×4 Bayer discard at the start of every creature fragment shader: skin, fur
  shells, membrane, eye, outline) when it stands between the camera and the player
  (`OccluderFader`). All shaders run on Forward+, Mobile and
  Compatibility (verified with playtests on all three).

### Gait engine (`GaitEngine`, `CreatureLeg`)
A cycle phase advances at the gait frequency (grows with speed, so stride length stays
in range); each leg has a per-gait phase offset and duty factor. A leg lifts when its
phase enters the swing window and lands at a point predicted from its hip's velocity so
it is under the hip at mid-stance. **Planted feet are pinned in world space** (no
sliding, tested); swings follow an asymmetric arc and re-target every frame. Gaits blend
(phase offsets interpolate circularly) with hysteresis. When stopped, legs that are out
of place take corrective steps in gait order (turning on the spot works). A planted
foot left too far behind (sudden dash) steps immediately. Two-bone analytic IK with a
pole per leg, an optional digitigrade metacarpal/metatarsal segment that curls during
swing, paws aligned to the ground normal.

The body follows the averaged support heights (pitch from front/hind, roll from
left/right), plus per-gait bob/pitch/roll/sway/spine oscillations, lean into turns and
acceleration, and spine bend into turns. Heavy creatures roll with their lumbering gait.

### Body motor and secondary motion
`CreatureMotor` turns `CreaturePose` channels (additive, written by locomotion, flight,
idles, actions and look-at) into bone rotations: body around a pivot (rear up, sit, nose
dive), spine, neck arc, a head **stabilized** against body bob/pitch, jaw, eyes (look),
lids (blinks, squints), ears, tail, breathing scale. `SpringChain` gives tails, ears and
whiskers damped secondary motion in world space; particles are carried with the body's
translation so steady speed causes no lag (only acceleration and turning swing them).

### Species specifics
* **Sky bison**: six legs (wave gait walk, tripod run), flight "swims": vertical tail
  strokes with paddling legs (tucked at cruise), body undulation opposite to the tail,
  banking and pitch from `set_flight`.
* **Dragon**: trail-following spine (body heights blend from a ground profile to level
  flight), lateral undulation synced to the leg gait, vertical undulation and per-segment
  bank (stored in the trail) in flight. `DragonWings` blends each bone direction between
  the spread pose (rotated by flap angle, swept, flexed on the upstroke) and a designed
  folded pose; the membrane is skinned to arm/forearm/fingers/flank. Flight rhythm: a
  few strong beats, then a long glide when cruising; faster beats when climbing, slow,
  or taking off/landing; downstroke shortened near the ground.
* **Badgermole**: `dig_in` scoops (debris at the claws) and sinks below every part of the
  mesh, then the mesh is hidden; moving while burrowed leaves dirt puffs; `emerge` bursts
  out (rock chunks + dust) and shakes off.

### Performance
* Headless measurement: **~0.35 ms per companion per frame** for the full solve (gait,
  IK, motor, springs, push) - tested with a 4 ms budget assertion.
* One `MeshInstance3D` per creature (5-9 surfaces), shared meshes/materials, custom AABB
  for skinning, `visibility_range_end` per species (wildlife 90-300 m).
* LOD tiers reduce shells, raycasts, springs and update rate; offscreen creatures drop to
  LOD 2. Mobile preset (detail 0) builds lower-resolution meshes with no shells.
* `BirdFlock`: one MultiMesh draw per flock, vertex-shader flapping, steering at 8-60 Hz by
  camera distance, hidden beyond `max_distance`.

## Bird flocks (`BirdFlock`, class_name, Node3D)

```gdscript
var gulls := BirdFlock.create(&"gull", 14, harbor_center, 40.0, 25.0)   # kind, count, center, radius, altitude
add_child(gulls)
gulls.set_center(new_center)   # follow a region
gulls.startle(player_pos)      # flee upward for a few seconds
```
Kinds: `gull`, `hawk` (soars more), `crow`. Steering: circle the center inside an altitude
band, cohesion, separation, wander, bank from turn rate; flap when climbing/startled,
glide otherwise. `bird_positions()` returns a copy of the positions.

## Effects (`CreatureFx`)
* `CreatureFx.debris_burst(parent, pos, surface, power, radius)` - CPUParticles3D rock
  chunks + dust tinted by surface, scaled by `Settings.effects_scale()`, self-freeing. Used
  by the badgermole; available to other modules (e.g. heavy landings).
* `CreatureFx.fire_breath(mouth_socket, length := 14.0) -> CPUParticles3D` - a toon fire
  stream parented to the dragon's `mouth` socket (aims along its -Z). **Visual only**:
  toggle `emitting` on the `fire_start` / `fire_end` action events and pair it with the
  companion module's own damage cone so visuals never imply hits that did not happen.

```gdscript
var flames := CreatureFx.fire_breath(dragon.get_socket(&"mouth"))
dragon.action_event.connect(func(_a, e):
	if e == &"fire_start": flames.emitting = true      # + start damage ticks
	elif e == &"fire_end": flames.emitting = false)
dragon.play_action(&"breathe_fire_start")   # hold; later: play_action(&"breathe_fire_end")
```

## Extending
Add a script in `species/` extending `CreatureSpecies`, register its path in
`CreatureRig.SPECIES_PATHS`, and implement `build(rig)` (bones, legs, motor bone map,
springs, gaits, sockets, `rig.set_dimensions`), `build_mesh(rig, kit)`, `material_for()`.
Override `make_action()/action_pose()` for new actions, `animate()`, `flight_pose()`,
`post_pose()` / `final_pose()` for special rigs and `on_event()` for effects.
`CreatureParts` has limbs, paws with toes/claws, eyes with lids, ears, horns and teeth.

## Testing
* `tools/test.sh creatures` - `tests/unit/test_creatures.gd` (18 tests): every species
  builds within budgets, mesh cache, sockets follow bones, dimensions, **footsteps per
  walk cycle == legs** (dog 4, bison 6, badgermole 4), footstep payload, gait change with
  speed, planted feet never slide, IK reaches planted paws, settling after turning on the
  spot, flight takeoff/bank/landing for both flyers (events, tucked legs), actions/events
  and hold semantics, burrow cycle, look-at, LOD tiers and runtime detail changes,
  dragon path following, swimming, bird flocks, update-cost budget.
* Playtests (`tools/playtest.sh <name> <out> 1280x720`): `creatures_showcase` (lineup with
  1.75 m human markers, 3/4 + side views, faces, signature actions), `creatures_gaits`
  (walk/run strips), `creatures_flight` (takeoff, banked turn from behind/front, cruise,
  landing), `creatures_actions` (sit, lie down, shake, scratch, dig, fire breath, wing
  stretch, prowl...), `creatures_terrain` (rolling hills: checks planted paws stay on the
  surface and IK reaches slopes), `creatures_wildlife` (wildlife + pond swim + flocks),
  `creatures_iter` (`SPECIES=<id>` quick look). `SPECIES` also filters gaits/flight/actions.
  Verified on Forward+, Mobile and Compatibility renderers.
* The showcase stage (`src/creatures/dev/creature_showcase.gd`) offers `spawn()`,
  `add_reference_human()`, `frame()`, `follow()`, `set_hills()`, `add_pond()` and a
  `CreatureDriver` per creature (line / circle / fly paths) for scenarios.
  Scenarios pace shots on `rig.time` because the playtest `wait()` is wall-clock while
  software-rendered frames cap game time per frame.

## Known limitations
* The dragon's folded wing is a designed pose blended per bone; the membrane can look
  slab-like from some angles when fully folded.
* Fire breath, bite damage and burrow travel are gameplay (companion/bending modules):
  the rig provides events and the `mouth`/`claw_*` sockets, not damage or flames.
* Mesh resolution follows the detail level at creation; a runtime detail change updates
  fur shells only.
