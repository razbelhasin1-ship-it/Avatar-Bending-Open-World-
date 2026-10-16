# Companions module (`companions`)

The element companion — sky bison (Air), badgermole (Earth), dragon (Fire), polar bear dog
(Water) — as a living partner and a mount: follow formation, idles and reactions, call,
never-lost safety, health that never kills, optional combat assist, mount / dismount with
animated transitions, ground riding, badgermole burrowing and flight (sky bison, dragon).
The creature itself (mesh, skeleton, gaits, flight pose, actions, sockets) is the creatures
module's `CreatureRig` (`docs/modules/creatures.md`); this module moves it and gives it a
mind.

| Piece | Files |
| --- | --- |
| Body / hub | `src/companions/companion.gd` (`Companion`, CharacterBody3D) |
| Data | `companion_profile.gd` (`CompanionProfile`: per-species tuning) |
| Ground motion | `companion_motor.gd` (`CompanionMotor`: steering, whiskers, slopes, snow, water, stuck detection, world-floor safety) |
| Flight | `companion_flight.gd` (`CompanionFlight`: takeoff / fly / landing, banking, terrain + sea avoidance, ceiling, world edge) |
| Behaviour | `companion_brain.gd` (`CompanionBrain`: follow / escort / call / retreat / wait, idles + reactions, never lost) |
| Riding | `companion_rider.gd` (`CompanionRider`: mount / dismount transitions, saddle seat, rider tilt), `companion_mount_point.gd` (`CompanionMountPoint`: "Ride the …" Interactable), `companion_ride.gd` (`CompanionRide`: mounted controls + camera) |
| Burrow | `companion_burrow.gd` (`CompanionBurrow`: dig in, tunnel, emerge) |
| Assist | `companion_assist.gd` (`CompanionAssist`: fire breath, tail gust, pounce, tremor) |
| Placement | `companion_nav.gd` (`CompanionNav`: ground height, walkability, safe spots, landing spots, burrow exits) |
| World hook | `src/companions/world_hook.gd` (installed by `WorldHooks` in the world and the training grounds) |
| Tests / tools | `src/companions/dev/companion_sim.gd` (`CompanionSim`), `tests/unit/test_companions.gd`, `tests/integration/test_companions_world.gd`, playtests `companions_follow`, `companions_ride`, `companions_flight` |

## Quick start

```gdscript
# The world hook does this for the playable scenes:
var c := Companion.create(&"sky_bison")             # CompanionProfile.SPECIES
c.player = player                                   # else the first node in group &"player"
c.renderer = scene.renderer                         # optional: collision requests, teleports
scene.spawn_companion(c, Companion.spawn_transform(player, &"sky_bison"))

c.call_companion()                  # same as the companion_call action
c.request_mount(player)             # same as the mount action / the "Ride" prompt
c.request_dismount()                # hop down (ground) / let go (air)
c.teleport_near_player(air := false)
c.get_status_text()                 # "Following", "Flying overhead", "Coming", "Ridden" ...
Events.companion_command.emit(&"stay")   # &"call", &"stay", &"follow"
```

## Companion API

| Member | Notes |
| --- | --- |
| groups / physics | `&"companion"`, `&"damageable"`, `&"persist"`; `team = Combat.Team.PLAYER`; layer `Layers.COMPANION`, mask `Layers.SOLID` (never collides with the player or enemies: it cannot block the player); vertical capsule (species radius / height); `process_physics_priority = -10` (ticks before the player) |
| `species`, `prof` (`CompanionProfile`), `rig` (`CreatureRig`), `health` (`HealthComponent`), `motor`, `flight` (flyers), `brain`, `rider`, `ride`, `burrow` (badgermole), `assist` | components |
| `mode` (`Companion.Mode`), `get_mode_name()`, `mode_changed(new, old)` | FOLLOW, ESCORT, CALLED, RETREAT, ASSIST, WAIT, MOUNTING, RIDDEN, DISMOUNTING, BURROW |
| `is_ridden()`, `is_flying()`, `is_airborne()` | state queries |
| `call_companion()`, signal `called` | come to the player |
| `can_mount(p)`, `request_mount(p)`, `request_dismount()`, signal `rider_changed(rider)` | riding |
| `teleport_near_player(air := false)` | safe spot near the player, off-screen when possible; flyers with `air` appear in the sky behind the camera and fly in |
| `receive_hit(hit)`, `is_alive()` (always true), `get_health_component()` | damageable contract; ridden / burrowed companions ignore hits |
| `get_status_text()`, `get_display_name()`, `get_aim_point()`, `flash_status(text, s)` | HUD contract (`health` property + status line) |
| `write_save_state()` | `GameState.companion` = `{type, name, bond, health_ratio, unlocked, assist}` |
| `autonomous` (false = no behaviour, riding still works), `assist_enabled` | switches |
| `Companion.create(id, {rig: {...}, autonomous})`, `Companion.spawn_transform(player, id)` | construction |

Every mode has an exit and a cap (`MODE_TIMEOUT`: called 30 s, retreat 45 s, assist 9 s,
mounting / dismounting 3 s, burrow 22 s); the riding state ends with the rider.

## Behaviour (`CompanionBrain`)

* **Follow formation.** A slot beside the player — level with them at rest, trailing a little
  when they move (`follow.side`, `follow.back` scaled by the player's speed) — on the side
  the companion is already on (hysteresis, it never cuts across in front). The slot must be
  walkable, dry and in line of sight of the player; otherwise the other side, otherwise
  behind the camera (corridors). It is pushed out of the camera -> player line and away
  from the lens (no creature filling the screen). Speed = the player's speed + a catch-up
  term, capped per species; a personal-space radius makes it step aside instead of
  crowding the player.
* **Terrain-aware steering.** Creatures move along their heading with a turn rate (big ones
  pivot), slow on steep uphill and in deep snow (not the polar bear dog), wade and swim, and
  steer with 9 whisker rays at chest height that follow the terrain: walls, trees, rocks,
  steep or flooded ground block a whisker; the clearest direction near the wish wins.
  Stuck detection (progress < 25 % of the intended distance) triggers a sideways escape,
  then a teleport when it persists.
* **Idles and reactions** (on top of the rig's own random idles): faces and looks at the
  player at rest; contextual actions every 7-13 s — shakes off snow / rain, lies down (or
  sits) at night and in blizzards, species play actions; the polar bear dog does a lap
  around an idle player and rears up with a bark; greets the player after time apart (and
  on arrival after a call); growls / roars at enemies that become alerted nearby; looks at
  the player's hits; a vocal answer to every call.
* **Escort (flyers).** When the player moves fast / gets far (the dragon as soon as the
  player walks: it prefers the air), the flyer takes off and flies along above them (lead
  when moving, a wide circle over a resting player). Once the player settles (bison 2.5 s,
  dragon 6 s) it finds a flat, dry, open landing spot beside them and lands. A falling
  player (let go in the air, a cliff jump) gets a dive underneath, saddle up, for a catch.
* **Call (`companion_call`).** Ground companions run to the player; far (> 60 m) or stuck
  ones first appear at a safe spot near the player out of view; the badgermole tunnels to
  the player (24-160 m); flyers fly in and land beside the player (appearing in the sky
  behind the camera when > 420 m away). Emits `Events.companion_command(&"call")`.
* **Never lost.** Every tick: invalid positions; 4 Hz: > 110 m from the player on the ground
  (flyers fly back, teleport beyond 650 m), under the world with nothing solid below, below
  -250 m -> back next to the player. While far away it keeps a terrain collision request
  around itself. During player cinematics / death it waits.
* **Health and safety.** Never dies: damage stops at 1 HP. Below 30 % it retreats away from
  the threat (flyers climb high), lies down and recovers (5 %/s) to 70 %; out of combat it
  regenerates 1.2 %/s after 8 s. Ridden or burrowed it ignores hits, like its rider.

## Combat assist (`CompanionAssist`)

Enemies (group `&"enemy"`) that are engaged in a fight within 18 m of the player and 30 m of
the companion; one move per cooldown, every phase capped:

| Species | Move | Hit |
| --- | --- | --- |
| dragon | faces the enemy, `breathe_fire_start` (flames from the `mouth` socket on `fire_start`), a damage cone ticks while it breathes, `breathe_fire_end` | 7 ticks x 5 + burn, 13 m / 24 deg cone, 11 s cooldown |
| sky bison | turns its back to the enemy, `tail_gust` (tail raised, slammed down: event `gust`), a wind blast from the tail (AirFx gust + ground puff) | 10 dmg, knockback 15 m/s + lift, 10 m / 40 deg, 10 s |
| polar bear dog | growl, crouch, leap at the enemy, bite on landing | 16 dmg knockdown in 2.4 m, 7 s |
| badgermole | `rear_up`, slams down (event `land`): ground shockwave | 12 dmg stagger, knockdown inside 3 m, 6.5 m radius, 9 s |

Hits are real `HitInfo`s through `BendingHits.deliver` (once per attack id, line of sight,
impact VFX only for applied hits). `hit.source` is the player: the companion fights as the
player's partner, so XP / loot and enemy aggro stay with the player (enemies target only the
player, never the companion). `ability_id` = `companion_<move>`.

## Riding (`CompanionRider`, `CompanionRide`)

* **Mount**: the `mount` action within reach of the body (the lateral distance to the
  creature's long axis < radius + 2.4 m), or `interact` on the "Ride the Sky Bison" prompt
  (`CompanionMountPoint`, priority -1; gamepads have no mount binding, touch gets the
  contextual button). The rider leaps along a Bezier arc onto the saddle (0.6-1.0 s by
  height, the player's `mount` clip, a wind puff for Air / dust for the others) via
  `PlayerCharacter.mount_on(companion, seat)`. Mid-air: a falling player within 7.5 m of a
  flyer's saddle is caught (0.35 s).
* **Seat**: a top-level node recomputed from the rig's `saddle` socket and the body's
  current transform each tick (the companion ticks before the player): the rider never lags
  a fast mount (measured below). The rider's HumanoidRig is tilted with the saddle (bank /
  pitch) in the `riding` pose, hidden while the saddle is underground; both are reset on every
  exit path (dismount, travel / respawn dismounts, companion freed).
* **Dismount**: `mount` (the player's MOUNTED state calls `request_dismount()` on its mount)
  or `interact`: on the ground the rider hops down beside the creature (`dismount` clip, arc
  to dry ground on the left / right / behind); in the air the rider lets go with the mount's
  momentum and falls or glides (no fall damage in this game), the flyer escorts and lands
  beside them. The camera keeps its yaw.
* **Controls** (InputMap actions only, so touch and rebinding work):

| Input | Ground mount | Flying mount |
| --- | --- | --- |
| move (camera-relative) | walk / run toward the stick | steer toward the stick (banking turns), thrust = stick amount; pull back = brake / hover |
| sprint | gallop (polar bear dog 15 m/s) | boost |
| jump | leap (polar bear dog) / take off (flyers) | climb (hold) |
| descend | burrow (badgermole) | dive (hold); near the ground: land |
| mount / interact | hop down | let go |

* **Camera**: PlayerCamera's `flight` mode for both (it auto-aligns behind the mount's
  velocity 1.2 s after the last look input) with per-species height / distance / FOV
  (`ride.camera`, `flight.camera`), and an FOV kick while galloping / boosting.

| Species | Ride walk / run / sprint (m/s) | Max slope | Snow | Extra |
| --- | --- | --- | --- | --- |
| polar bear dog | 2.6 / 8 / 15 | 42 deg | no slowdown | leap (7.5 m/s) |
| badgermole | 2.2 / 6.5 / 9 | 55 deg, no uphill slowdown | -25 % | burrow |
| sky bison (ground) | 2.4 / 5.6 / 7.6 | 36 deg | -15 % | take off |
| dragon (ground) | 2.6 / 7.5 / 10.5 | 36 deg | -20 % | take off |

## Flight (`CompanionFlight`)

Phases NONE -> TAKEOFF (rig `takeoff`: crouch, the climb starts on the `leap` event) -> FLY ->
LANDING (rig `land` near the ground, touchdown) -> NONE; takeoff 4.5 s / landing 9 s caps.
Per tick from an intent (`want_dir`, `throttle`, `boost`, `brake`, `climb` or `hold_altitude`,
`hold_speed`) written by the rider controls or the brain:

* airspeed approaches glide (no input) / cruise (thrust) / boost / hover-or-minimum (brake);
  diving gains speed, climbing costs some; the dragon never drops below 9 m/s (no stall);
* the heading turns toward `want_dir` with a speed-dependent rate (bison 80 -> 46 deg/s,
  dragon 100 -> 62 deg/s); the bank is the coordinated-turn roll `atan(v * yaw_rate / g)`
  (bison max 0.5 rad, dragon 0.75), pitch follows the climb angle; both feed
  `CreatureRig.set_flight(true, velocity, bank, pitch)`;
* vertical speed from climb / descend (bison 8 / 11 m/s, dragon 10 / 14), gliding sinks
  1.1-1.4 m/s;
* **terrain + sea avoidance**: WorldData terrain / water heights along the path up to 2.8 s
  ahead plus a forward physics ray (trees, buildings, arches) force a pull-up (and slow down
  for walls); clearance 7-8 m, 2 m while deliberately descending; the origin never goes below
  the terrain / water surface; ceiling 320 m above the terrain (max 1500 m); beyond 3880 m
  from the centre the winds turn the flyer back toward land;
* **landing**: holding descend within ~5.5 m of the ground starts a landing when the ground
  below is flat, dry and solid (else "Can't land here"); forward speed bleeds off with
  altitude, a soft vertical touchdown.

| | cruise / glide / boost (m/s) | min | escort height |
| --- | --- | --- | --- |
| sky bison | 18 / 11 / 30 | 0 (hovers) | 16 m |
| dragon | 24 / 16 / 40 | 9 | 26 m |

## Burrow (`CompanionBurrow`, badgermole)

`descend` while riding (or the brain, to reach the player): the exit is validated first
(walkable, dry, open ground on the line toward the camera's aim point, 8-42 m; no burrow
starts that cannot end). DIG: rig `dig_in` (scoops, sinks; collision off) -> TRAVEL at 11 m/s
along the surface (the rig hides the mesh and leaves dirt puffs; crack decals + dust every
2.6 m, dig rumble + light camera shake) -> EMERGE: rig `emerge` (rock burst, shake-off),
quake ring, collision back on, still ridden. The rider is hidden while the saddle is
underground; the seat stays at the surface (the terrain safety net never sees the rider
under the world).

## Data (`CompanionProfile`)

`for_species(id)` -> `display_name, element, max_health, armor, can_fly, prefers_air,
can_burrow, can_swim, follow {side, back, space, walk, run, sprint, max, turn, max_slope,
radius, height}, ride {walk, run, sprint, accel, decel, turn, max_slope, snow, jump, rugged,
camera}, flight {escort_height, cruise, glide, boost, min, hover, accel, decel, boost_accel,
turn_slow, turn_fast, max_bank, climb, descend, clearance, land_clearance, glide_sink,
camera}, assist {kind, range, min_range, cooldown, hit {...}, cone, ticks, tick_time},
vocals {greet, angry, hurt}, play_actions`. `species_for_element(e)` maps elements.

## Persistence

`GameState.companion` (`type`, `name`, `health_ratio`, `assist`; `unlocked` = false spawns
no companion) is written in `write_save_state()` (group `&"persist"`) and read when the
companion is built. Stats: `companion_rides`, `companion_ridden_m`, `companion_flown_m`.
A save while riding stores the player's last safe ground (WorldSaveGuard); the companion
spawns beside the player on load.

## Integration points

* **World scene**: `src/companions/world_hook.gd` spawns the element's companion in
  `player_spawned` (world and training grounds, where it enables the "call" and "ride"
  lessons) through `PlayableScene.spawn_companion` (HUD panel, `player.companion`).
* **Player**: `PlayerCharacter.mount_on / dismount`, the MOUNTED state; the mount press
  while mounted is delegated to `mount_node.request_dismount()` (the one change in the
  player module). Travel, ferries and respawns dismount the player directly; the companion
  cleans up on `Events.dismounted` and teleports to the player when it is left far behind.
* **HUD**: `get_companion()` on the player -> `health` + `get_status_text()`; compass marker
  when > 25 m away.
* **Enemies**: enemies ignore mounted players; area attacks / projectiles of enemies can hit
  the companion (layer COMPANION is in `Layers.ENEMY_ATTACK_TARGETS`).

## Performance (mobile)

One companion per scene. Whiskers: 9 rays at 10 Hz, flight: a forward ray at 10 Hz +
WorldData samples, slot and landing searches at 1-4 Hz, safety at 4 Hz; no per-frame
allocations in the hot paths. The rig's own LOD / detail levels apply (mobile preset: no
fur shells). No extra lights; assist VFX use the pooled FX library (`FxLib` caps).

## Testing

* `tools/test.sh test_companions` (unit, CompanionSim on flat ground): profiles, every
  species spawns and stands, follow formation (beside / behind, never into the player),
  steering around a wall, a boxed-in companion freed by a call (teleport) +
  `Events.companion_command`, call from 80 m (dog teleports + runs, bison flies in and
  lands), never lost (player teleport, NaN, under the world), mount -> gallop -> dismount
  with the rider on the saddle socket at full gallop, the interact prompt path, external
  dismount cleanup, flight for both flyers (takeoff, cruise, banking left turn with the rig
  rolling, climb, boost, glide without stall, dive + land still seated), flight bounds
  (a 120 m cliff, a dive at the ground, the ceiling, the world edge), mid-air let go + catch +
  safe landing, ridden burrow (dig -> travel -> emerge at the target, rider hidden, seat never
  under the surface, collision restored, descend digs in), invalid burrow exits refused,
  never dies + retreat + recovery + ridden hits ignored, assist of every species landing a
  real hit on an engaged bandit (credit to the player), persistence round trip, and a
  2400-frame random-input riding fuzz per species (always settles).
* `tests/integration/test_companions_world.gd` (headless world scene): the hook spawns the
  element's companion on real terrain next to the player, it follows a walk, saves carry
  its state; the sky bison takes off, flies and lands on the real heightfield with the
  player seated.
* Playtests (`tools/playtest.sh <name> <out> 960x540`, ~5 min wall per companion; set
  `PLAYTEST_TIMEOUT=2400` for all four): `companions_follow` (`ELEMENT=`: spawn, walk over
  real terrain, rest, sprint / escort, call from 150 m), `companions_ride` (`SPECIES=`
  polar_bear_dog / badgermole: mount, gallop, leap, burrow, dismount), `companions_flight`
  (`SPECIES=` sky_bison / dragon: mount, takeoff, circuit with banking, climb, boost, glide,
  low pass, landing, let go in the air).

## Changes outside the module

* `src/player/player_character.gd`: `update_mounted` delegates the mount press to
  `mount_node.request_dismount()` when the mount implements it (animated / mid-air
  dismounts); otherwise `dismount()` as before.
* `src/creatures/species/sky_bison.gd`: new `tail_gust` action (tail raised, slammed down,
  event `gust`, wing-flap sound) for the bison's assist.
* `src/creatures/core/creature_leg.gd`: `_put` orthonormalizes before the quaternion
  conversion (near-degenerate IK frames during a flyer's landing failed the engine's
  rotation check and spammed errors).
* `tests/unit/test_worldscene.gd`: the HUD companion panel check accepts the companion the
  hook now spawns.

## Known limitations

* No navmesh: steering is whiskers + escapes + teleports; a companion can still take a
  long way around large concave structures before the stuck teleport kicks in.
* The dragon's 20 m body follows the shoulders' path and only the shoulders collide; its
  tail can clip trees / terrain edges during tight ground turns.
* The rider is hidden (not animated) while tunnelling; the burrow goes in a straight line.
* Mid-air catches need the player to press mount near the saddle; there is no automatic
  catch. Non-Air riders who let go simply fall (the game has no fall damage).
