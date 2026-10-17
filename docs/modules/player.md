# Player module

The playable bender: input, movement, state machine, health / chi / focus, damage
handling, camera, soft aim + lock-on, interaction, HUD / save / mount hooks. Bending itself
(abilities, projectiles, constructs, VFX) is the bending module: `docs/modules/bending.md`.

| Piece | Files |
| --- | --- |
| Character | `src/player/player_character.gd` (`PlayerCharacter`), `scenes/player/player.tscn` |
| Movement | `player_motor.gd` (`PlayerMotor`), `locomotion_profile.gd` (`LocomotionProfile`), `ground_sampler.gd` (`GroundSampler`) |
| Input | `player_input.gd` (`PlayerInput`) |
| States | `player_states.gd` (`PlayerStates`), `player_damage.gd` (`PlayerDamage`) |
| Resources | `player_resources.gd` (`PlayerResources`: chi, focus, health regen) |
| Visual | `player_visual.gd` (`PlayerVisual`, drives a `HumanoidRig`) |
| Camera | `player_camera.gd` (`PlayerCamera`), `time_dilation.gd` (`TimeDilation`) |
| Targeting | `player_targeting.gd` (`PlayerTargeting`) |
| Interaction | `interactable.gd` (`Interactable`), `player_interaction.gd` (`PlayerInteraction`) |
| Tests / tools | `src/player/dev/player_sim.gd` (`PlayerSim`), `tests/unit/test_player.gd`, `tests/playtest/scenarios/player_*.gd`, `scenes/dev/combat_arena.tscn` |

## Quick start

```gdscript
var p: PlayerCharacter = preload("res://scenes/player/player.tscn").instantiate()
p.element = GameState.element            # default when left NONE
world.add_child(p)
if not p.apply_saved_state():            # GameState.player_position / yaw / health
    p.respawn_at(spawn_xform, 1.0)       # teleport + revive (+ camera snaps behind)
hud.bind_player(p)                       # docs/modules/ui.md
Events.player_died.connect(func() -> void:
    await get_tree().create_timer(2.0, false).timeout
    p.respawn_at(shrine_xform))          # the world decides where (50 % health by default)
```

The player is a `CharacterBody3D` with its feet at the origin (capsule r 0.32, h 1.74) in
groups `&"player"`, `&"damageable"`, `&"persist"`, `team = Combat.Team.PLAYER`, physics layer
`Layers.PLAYER`, mask `SOLID | ENEMY | NPC`. Everything else is built in code (no sub-scenes):
`PlayerInput`, `PlayerResources`, `PlayerTargeting`, `PlayerInteraction`, `BendingController`,
`PlayerVisual` (HumanoidRig with the element preset), `HealthComponent` and a top-level
`PlayerCamera` (unless `use_camera = false`).

## PlayerCharacter API

| Member | Notes |
| --- | --- |
| `@export element` | `ElementDefs.Element`; `set_element(e)` switches at runtime (profile, rig preset/style, core kit, techniques, max health/poise) |
| `@export appearance: Dictionary` | rig overrides (`body`, `skin`, `hair_style`, `seed` ..., see characters.md) |
| `@export use_camera`, `auto_respawn`, `auto_respawn_time` (8 s) | auto respawn at the last safe ground if nobody calls `respawn_at()` |
| `signal resource_changed(resource, value, max)` | `&"health"`, `&"chi"`, `&"focus"` (HUD) |
| `signal state_changed(new, old)`, `died`, `respawned` | |
| `health: HealthComponent`, `resources`, `controller`, `targeting`, `camera_rig`, `motor`, `input`, `visual`, `ctx: BendingContext`, `profile` | components |
| `get_state()`, `get_state_name()` | `PlayerCharacter.State` |
| `receive_hit(hit) -> Combat.Result` | via `Combat.deal()` only (below) |
| `die(hit)`, `respawn_at(xform, health_ratio := 0.5)`, `teleport(xform)` | |
| `write_save_state()` / `apply_saved_state()` | `GameState.player_position`, `player_yaw`, `player_health_ratio` |
| `try_interact()`, `end_interaction()` | `Interactable` contract (below) |
| `enter_cinematic(max_s := 120)`, `exit_cinematic()` | input off; the state still times out |
| `mount_on(mount, seat)`, `dismount(at := INF)` | companions module; emits `Events.mounted / dismounted`; the player follows `seat` and ignores hits; a freed seat auto-dismounts; the `mount` action dismounts |
| `aim() -> {direction, target, point}` | lock target > soft target > camera ray |
| `get_bending_context()` | the player's `BendingContext` (projectile redirects use it) |
| HUD: `get_health_component()`, `get_resource(name) -> Vector2(cur, max)`, `get_ability_slot_info(i)`, `get_lock_target()`, `get_companion()`, `get_display_name()`, `get_aim_point()`, `is_alive()` | exactly the contract in ui.md |

## Movement (LocomotionProfile, PlayerMotor)

Per-element numbers from `docs/GAME_DESIGN.md §3` live in `LocomotionProfile.TABLE`
(`LocomotionProfile.for_element(e)`). Unit tests measure them in the simulation:

| | Air | Earth | Fire | Water |
| --- | --- | --- | --- | --- |
| walk / run / sprint m/s | 3.4 / 7.6 / 11.5 | 2.8 / 5.6 / 7.6 | 3.1 / 6.9 / 9.6 | 3.0 / 6.5 / 9.2 (skate 12) |
| accel / decel m/s² | 42 / 30 | 16 / 28 | 32 / 24 | 20 / 12 |
| turn °/s | 900 | 380 | 650 | 520 (smoothed) |
| jump v (m/s) | 7.4 (+ air jump 6.5) | 5.0 | 6.3 | 6.0 |
| gravity mult / air control | 0.8 / 0.85 | 1.3 / 0.2 | 1.0 / 0.5 | 1.0 / 0.55 |
| dodge | Air Dash 7 m 0.32 s i-frames, also in the air | Earth Slide 3 m, NO i-frames, poise armor | Fire Step 4.5 m 0.2 s | Flow Slide 4 m 0.26 s |
| knockback taken | x1.3 | x0.4 | x1.0 | x0.9 |

* Analog: stick 0..0.5 walks, 0.5..1 blends to run; sprint (hold, or toggle with
  `controls.toggle_sprint`) above 0.5. Movement is camera-relative.
* Turning carves (momentum rotates at the turn rate) instead of snapping; Water smooths the
  target heading (fluid curves).
* Coyote time 0.12 s and jump buffer 0.15 s; releasing jump early cuts a ground jump.
* Slopes up to `max_slope_deg` (40°) are walkable; steps up to 0.38 m are climbed (step-up).
* Deep snow (`GroundSampler.snow_depth`) slows everyone but Water/Air sprinting; Water sprints
  into a **skate** on snow / ice (12 m/s, low friction, `water_skate` loop clip).
* Air: one air jump per airtime, hold jump while falling to **glide** (capped fall speed,
  forward drift, `air_glide` clip); cushioned landings.
* Water: wading slows progressively; deeper than 1.3 m the player **swims** (buoyancy holds
  the chest at the surface; never sinks, never drowns). Jump next to a ledge climbs out
  (exact vault velocity onto the ledge). Earth/Fire/Air swim too.
* Hard landings: stagger/roll by profile; never damage.
* `GroundSampler` = `WorldData` surface/water + optional rectangular zones (test arenas):
  `GroundSampler.add_zone(id, Rect2 xz, &"snow", depth)`.

## Input (PlayerInput)

Only InputMap actions are read (the touch overlay presses the same actions):
`move_*`, `look_*`, `jump`, `sprint`, `dodge`, `attack_light`, `attack_heavy`, `block`,
`ability_1..4`, `ability_special`, `lock_on`, `interact`, `mount`, `companion_call`.

* Presses of combat actions are **buffered 0.2 s** of game time: a press during recovery fires
  on the first cancellable frame; older presses are dropped.
* Edge detection on the action state each physics tick: presses made between ticks (touch
  overlay, scripted input, slow frames) count exactly once.
* `virtual_mode` + `press(action)` / `release(action)` drive the same code from tests, AI or
  scripted sequences (`PlayerSim`).

## State machine (PlayerStates)

| State | Exit | Timeout |
| --- | --- | --- |
| Locomotion / Airborne | - | airborne without moving for 6 s -> Locomotion |
| Dodge / Action | ability finished or cancelled | ability `max_time` + 1 s |
| Defend | block released, chi out, guard broken | 120 s |
| HitStun | stun time | 2 s |
| KnockedDown -> GetUp | down time, then get-up (0.6 s i-frames) | 4 s / 1.2 s |
| Dead | `respawn_at()` | auto respawn 8 s |
| Mounted | `dismount()`, seat freed | - |
| Interacting | `lock_time`, `end_interaction()` | 10 s |
| Cinematic | `exit_cinematic()` | given (120 s) |

Bending presses are tried in priority order dodge > block > light > heavy > techniques >
signature; abilities steer the body through `BendingContext` movement requests
(`BRAKE / FREE / DRIVE / ROOT / HOLD`, gravity scale, facing, poise armor, i-frames). A 3000-frame
random-input fuzz per element always returns to Locomotion.

## Taking hits (PlayerDamage, GAME_DESIGN §5)

`Combat.deal(player, hit)` -> `receive_hit`:

1. Dead / cinematic / mounted -> `IGNORED`.
2. I-frames (dodges, get-up) -> `DODGED`, damage 0 (perfect-dodge hook: Water slow motion).
3. A held defense covering the hit (`DefenseAbility.guard`): inside the first **0.15 s** ->
   **parry** = `DEFLECTED`, no damage, element counter, **+15 Focus**, attacker staggered
   (projectiles redirected or destroyed); otherwise `BLOCKED` with the element's reduction
   (Air 70 % / 100° arc, Earth 90 % / 70°, Fire 75 % / 85°, Water 80 % / 110°), chi per block,
   guard break at 0 chi (Earth: slab HP).
4. Damage = `hit.damage x Settings.difficulty_damage_scale() x Combat.element_multiplier`
   (x (1 - action damage reduction)); `hit.damage` is overwritten with the applied value
   (HUD damage numbers read it).
5. Reaction: poise armor of the current action turns reactions into flinches unless poise
   breaks; knockback scaled by the element; `FLINCH / STAGGER / KNOCKBACK / KNOCKDOWN / LAUNCH /
   PULL / FREEZE`; hit flash, status tint (burn, soaked, chill, frozen), `Events.player_damaged`.
6. Health 0 -> `die()`: `Events.player_died`; the world scene calls `respawn_at()`.

## Chi, focus, health (PlayerResources)

Chi 100: techniques, heavies and defense upkeep spend it; +25/s after 0.6 s without bending
(x1.2 near water for Water). Light strikes are free. Focus 100: +6 light hit, +10 heavy hit,
+15 parry (enemy hits never give Focus), slow drain out of combat; the signature needs 100.
Health regenerates 2.5 %/s after 6 s without damage. Max health / poise by element: Air 95 / 22,
Earth 130 / 55, Fire 105 / 32, Water 110 / 30.

## Camera (PlayerCamera)

Orbit camera (distance 4.3 m x `controls.camera_distance`, pivot 1.55 m, shoulder 0.42 m).
Mouse (captured), `Events.look_input` (touch drags), `look_*` actions (pad); Settings: FOV,
sensitivities, invert Y, distance, shake scale. Mouse motion emulated from touch is ignored
while touch controls are active.

```gdscript
cam.set_mode(&"mount", {"height": 3.2, "distance": 7.5, "shoulder": 0.0, "fov": 4.0})
cam.set_mode(&"flight", {"height": 2.5, "distance": 11.0, "fov": 10.0, "auto_align": true})
cam.set_mode(&"cinematic", {"transform": xform, "fov": 50.0, "blend": 0.8})
cam.set_mode(&"default")
cam.set_target_override(node) / cam.clear_target_override()
cam.add_trauma(0.5)             # shake (also Events.camera_shake)
cam.impulse(dir, 0.3)           # spring kick (also Events.camera_impulse)
cam.snap_behind(player)
```

* Collision: a sphere cast against `Layers.CAMERA_BLOCKERS` pulls the camera in instantly and
  eases back out; never below the terrain.
* Lock-on: yaw follows player -> target, distance grows with separation, pitch adapts to height
  difference, a wider shoulder offset (0.95 m) keeps the target visible beside the player.
  Close quarters (perf_polish): below `LOCK_CLOSE_FAR` (4.8 m) the view swings up to
  `LOCK_SWING_DEG` (30°) off the player → target axis (full at 2.2 m), pulls back 0.9 m, lifts
  6° and aims a little more at the target (`lock_close` 0..1, smoothed). The side (`lock_side`)
  is picked once, on the side the camera already leans to, and kept until the target backs off
  past 5.5 m, so it never flip-flops. `close_framing = false` restores the old framing (A/B).
  Measured (playtest `perf_polish_camera`, bandit brawler at < 3.5 m): attacker visible in 100 %
  of close frames (24 % before), no added yaw reversals.
* Occluders (perf_polish): `occluders` (`OccluderFader`, child of the camera) casts from the lens
  to the player's knees, chest and head (plus a lens sphere) against NPC, companion and wildlife
  bodies and dithers them out to 72 % over 0.15 s (back over 0.3 s): toon materials through
  per-surface dither twins (`OccluderFader.twin_of`, same uniforms, `src/perf/shaders/
  toon_dither` / `outline_dither`), creatures through the `occlusion_fade` instance uniform of
  the creature shaders. Shared materials are never modified; the owner's overrides (hit flash)
  are respected and restored. `fade_of(body)`, `faded_bodies()` for tests.
* Feel: trauma shake, exact critically damped impulse spring, hitstop through `TimeDilation`
  (`Events.hitstop`): requests are timed in real time, the lowest scale wins and
  `Engine.time_scale` always returns to 1 (also when the node leaves the tree). Everything
  camera-side runs on real time, so hitstop never freezes the camera.

## Targeting (PlayerTargeting)

* Soft aim: best enemy within **25°** of the view direction (measured from the player),
  22 m, line of sight, refreshed at 15 Hz. Abilities aim at it (`ctx.aim()`).
* Lock-on (`lock_on`): best target within 50° (or the nearest in front), 30 m; press again to
  release. Switch with a mouse flick / right-stick flick / `cycle(dir)`. Auto release when the
  target dies, goes beyond 36 m or stays out of sight for 2 s.
  `Events.target_locked(t)` / `target_unlocked()`.
* Targets: group `&"damageable"`, another team, alive, not tagged `no_lock` (constructs).

## Interaction

```gdscript
var it := Interactable.new()        # Area3D, group &"interactable", Layers.INTERACTABLE
it.prompt = "Talk to Master Pakku"
it.radius = 2.0
it.interact_priority = 1            # higher wins when several are in range
it.animation = &"interact_r"        # clip the player plays (&"" = none)
it.lock_time = 0.6                  # Interacting state (end_interaction() ends it early)
it.interacted.connect(func(player: Node3D) -> void: dialogue.start())
npc.add_child(it)
```

The player picks the best one (in range, in front, priority) at 10 Hz and shows
`Events.interaction_prompt("[E] Talk to Master Pakku", true)`; `interact` calls
`it.interact(player)`. Override `get_interaction_text`, `can_interact`, `interact` for dynamic
behaviour.

## Testing

* `PlayerSim` (src/player/dev): flat ground, boxes, a player with virtual input, fixed
  1/60 s stepping of the player, projectiles and constructs inside a physics frame.
* `tests/unit/test_player.gd` (27 tests): measured speeds / turn rates / jump heights, analog
  walk, variable jump, double jump + glide, coyote + buffer, snow + skating, step-up + slopes,
  swimming + climb-out, input buffer, combo windows, light latency, cooldowns + chi, parry
  window + block, i-frames + earth armor, reactions + knockback by element, death / respawn,
  save state, HUD contract, targeting, interaction, hitstop, camera modes + collision, mount
  hook, and a 3000-frame fuzz per element.
* Playtests: `player_elements` (all elements or `ELEMENT=fire`: sprint, jump, glide / skate /
  snow, dodge, every light strike on its active frame, heavy charge + release, lock-on
  framing, block + parry against the sparring bot, starter technique), `player_smoke`,
  `player_fx_gallery`. Mobile: `RENDERER=mobile MOBILE=1 tools/playtest.sh player_elements`.
* `scenes/dev/combat_arena.tscn` (`Router.params {"element": e}` or `--element=fire`): flat
  courtyard, pool (swim + water source), snow and ice patches, steps, ramps, pillars, three
  post dummies, a humanoid dummy and the sparring bot. F1-F4 element, F5 reset dummies,
  F6 bot, F7 infinite chi, F8 help.

### Measured light-attack latency

Press -> active (hit volume) frames at 60 Hz, every step of every chain (limit 6):
Air 6 / 6 / 6, Earth 5 / 5 / 5, Fire 5 / 5 / 6 / 6, Water 6 / 6 / 6.

## Design decisions

* The HumanoidRig runs in `manual_update` and is advanced in the player's physics tick, so
  animation events (`release`, `impact`) fire on the gameplay clock; gameplay is spawned on
  those events, never on free-running timers.
* Movement is velocity based (profiles), root motion only for specific moves (dodges drive a
  velocity curve so distances are exact: v0 = 1.5 d / T, quadratic ease-out).
* All randomness of feel (camera shake, hitstop) is decoupled from simulation; hitstop dips
  `Engine.time_scale` but is always restored by `TimeDilation`.

## Wave 4 integration fixes (docs/qa/integration_fixes.md)

* `PlayerDamage.is_tick(hit)`: damage-over-time ticks (FireStatus burn, meta `dot`) and sustained
  pulses (meta `no_hitstop`) hurt and flash softly but add **no camera shake**.
* The player re-reads its technique slots (`BendingController.load_equipped`, deferred and
  coalesced) on `Events.abilities_equipped_changed` / `ability_unlocked` when the save's element
  is the player's, so a technique learned anywhere (quest reward, trainer, skill tree, script) is
  usable at once and the HUD / touch buttons follow on the next frame.
* HUD contract addition: `get_locked_signature_info() -> Dictionary` (the element's signature
  while it is not learned: id, name, icon, element, level; `{}` once learned).

## Wave 4 bug hunt (docs/qa/bughunt_gameplay.md)

* `enter_cinematic()`, `respawn_at()`, `die()` and `set_element()` dismount first when the player
  is MOUNTED. A cinematic used to start while riding (the training grounds end on the Ride lesson)
  without a dismount: the collision layers stayed 0 and the mount refs stayed set, so the player
  fell through the floor after the cinematic and the companion stayed "ridden".
* `PlayerMotor.carried` (set by `mount_on`, cleared by `dismount`): a carried body senses no floor
  and never records the saddle as the last safe ground (`is_on_floor()` keeps its last value while
  mounted, so every saddle position high up on a flyer used to become safe ground and saves made in
  flight continued in mid-air). `teleport(xform, mark_safe := true)`: `dismount()` passes false, so
  a mid-air release point is not safe ground until the player stands there. A ground mount still
  carries the safe ground along: `update_mounted` hands a carrier `CharacterBody3D` that is on the
  floor with its collision on (not tunnelling) to `PlayerMotor.carrier_on_floor(pos, normal)`,
  which records it when it is walkable and dry (no water within 0.5 m of the mount's feet).
* `dismount()` without a position: out at sea (the seat over water deeper than 1 m and no safe
  ground within 10 m) the player slips into the water beside the seat (and swims) instead of being
  teleported to WorldData's nearest safe ground, which can be hundreds of metres (or a far port)
  away.
