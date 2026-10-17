# QA wave 4 — adversarial gameplay bug hunt (`bughunt_gameplay`)

Focus: the player, bending (all four kits), enemies and companions. Method: read the code of
those modules critically for stuck states, missing timeouts, freed-instance access, double /
missed hits, Focus / chi / cooldown exploits, abilities in the wrong states, mount edge cases,
saves in odd states, time-scale leaks, pooling leaks and per-frame costs; then **long randomized
fuzz sessions** per element in the enemy arena and in the real world with an invariant
watchdog and an engine-error collector (every error / warning counted as a bug). Every
suspicion was reproduced (test or fuzz), fixed at its root with the smallest change, and kept
as a regression test (`tests/unit/test_bughunt_gameplay.gd`, each test fails on the old code).

| # | Bug | Verdict | Fix (file) |
| --- | --- | --- | --- |
| 1 | Cinematic / respawn / death while riding: collision stays off, rider falls through the floor (the training grounds end on the Ride lesson) | confirmed | dismount first (`player_character.gd`) |
| 2 | Saddle positions (and mid-air release points) recorded as the last safe ground: saves made in flight continue in mid-air | confirmed | `PlayerMotor.carried`, `teleport(mark_safe)` |
| 3 | Signatures refill the Focus they cost (Tidal Torrent: 100 Focus from 29 hits): endless signatures | confirmed | signature hits build no Focus (`bending_feedback.gd`) |
| 4 | Water Jet: hitstop on every 0.15 s pulse (19 per jet) and +6 Focus per pulse (one jet = full bar) | confirmed | `no_hitstop`, Focus every 4th pulse; `BendingHits` opts `meta` |
| 5 | Companion assist target freed while held: script error every tick (893 in 3 min) | confirmed (fuzz) | untyped `_valid_enemy` (`companion_assist.gd`) |
| 6 | Projectile whose caster was freed: script error every frame, the shot never lands | confirmed (fuzz) | `BendingContext.make_hit` / `forward` |
| 7 | Air Tornado captive freed mid-spin: "Trying to cast a freed object" every frame | confirmed (fuzz) | validity check before the cast (`air_tornado.gd`) |
| 8 | Hopping off a mount swimming at sea: arc to dry land 118 m away (up to 256 m / a port km off) | confirmed | slip into the water beside the mount (`companion_rider.gd`, `player_character.gd`) |
| 9 | Enemy hearing a fight it cannot see: ALERT until the 12 s safety timeout (engine warning), then RETURN -> ALERT forever | confirmed (fuzz) | new noises don't restart the give-up clock (`enemy_brain.gd`) |
| 10 | World respawn sequence overtaken by the auto-respawn backstop: two respawns for one death | confirmed (fuzz) | teleport only when already revived (`respawn_system.gd`) |

Refuted suspicions and checks that came out clean are listed at the end.

---

## Tools

### Fuzz harness — `tests/playtest/scenarios/bughunt_gameplay_fuzz.gd` (+ `bughunt_gameplay_util.gd`)

* **Monkey** (`util.Monkey`): random play through **InputMap actions only** (`Input.action_press` +
  an `InputEventAction`, exactly the touch overlay / keyboard path): stick directions + sprint,
  mouse look, light taps, heavy taps and holds up to 2 s, block holds, dodges, the four technique
  slots (tap or hold), the signature, jump / glide, lock-on (and it seeks a lock so fights happen),
  interact, mount / dismount / call, riding inputs (climb, dive / burrow, boost, hop off, strikes
  that must be ignored), the pause menu and the Journey Book (map / skills / journal, closed again
  with Back, the same key or Esc).
* **Adversarial events** every 6-20 s: near death (1 HP, so the next blow kills mid-ability /
  mid-guard), teleport into the pool (swimming with buffered presses), Focus refill, chi
  starvation, infinite chi toggles, saves in whatever state (`SaveSystem.save_game` + read back),
  the companion over the pool / against the arena walls then mount + hop off there, cheap shots
  from behind (every reaction incl. LAUNCH / FREEZE / PULL), element hops mid-action (dev arena),
  technique loadouts rotated through the element's whole tree via `GameState.equip_ability`
  (the live reload path), and enemy groups replaced while they act (freed mid-attack).
* **Watchdog** (`util.Watch`, every physics frame): player state caps (HitStun 2 s, Knockdown 4 s,
  GetUp 1.2 s, Interacting 10 s, ability states = max_time + 1 s, Dead = the respawn backstop),
  ability `time <= max_time`, no ability running in a free / dead / mounted / cinematic state,
  i-frames / damage reduction / poise armor / gravity / chi upkeep reset when idle (toggles
  excepted), chi / Focus / health ranges, finite position and velocity, collision layers restored
  and no stale mount refs off the mount, no leftover camera override / mode, death bookkeeping,
  `Engine.time_scale` back to 1 within the dilation cap, projectile age / counts, construct
  counts, FX alive, bending loops that follow the player for > 40 s, double hits per attack id,
  abilities started in a forbidden state or while paused, **cooldown bypasses** (started while the
  controller still had it on cooldown), player capsule embedded in solid geometry, enemies over
  their state caps / below the ground / stuck chasing, more attackers than tokens, companion mode
  caps, mounted-but-not-ridden desyncs, double respawns, node / orphan / object counts every 20 s.
* **ErrorLog** (`util.ErrorLog`, a `Logger` added with `OS.add_logger`): collects every engine
  error and warning with the GDScript backtrace.
* Runs headless and fast: `godot --headless --fixed-fps 60 --path . res://tests/playtest/playtest.tscn
  -- --test --scenario=bughunt_gameplay_fuzz` with `ELEMENT`, `MODE=arena|world`, `MINUTES`, `SEED`
  (5 game minutes in the arena take ~1 min of wall time); rendered with `tools/playtest.sh` for
  screenshots.

### Regression playtest — `tests/playtest/scenarios/bughunt_gameplay_regressions.gd`

Plays the fixed cases with the real player (rendered, InputMap actions): Water Jet on a dummy,
Tidal Torrent among four dummies, riding into a cinematic, hopping off the polar bear dog at sea,
letting go of the sky bison and saving while falling. Observer + player-view screenshots.

---

## Findings

### 1. Riding into a cinematic / respawn / death leaves the rider half-mounted

**Found** (code read, then reproduced). `PlayerCharacter.enter_cinematic()` (and `respawn_at`,
`die`, `set_element`) changed the state away from MOUNTED without `dismount()`: collision layer and
mask stayed 0, `mount_node` / `mount_seat` stayed set, the companion stayed RIDDEN. The training
grounds end on the **Ride** lesson and `TutorialScene._on_finished` calls `enter_cinematic(600)`
one second later, so the rider dropped through the floor behind the complete screen; after any
cinematic the player kept falling (the fall net teleports them onto ground they then fall through
again).
**Evidence.** `test_cinematic_while_mounted_dismounts_cleanly` on the old code: layer 0, refs set,
no `Events.dismounted`, AIRBORNE at y -20.5 after the cinematic; `test_respawn_while_mounted_dismounts`:
the rider sank through the floor after a respawn.
**Fix.** `src/player/player_character.gd:151` (`set_element`), `:408` (`die`), `:430` (`respawn_at`),
`:502` (`enter_cinematic`): `if states.state == State.MOUNTED: dismount()` first (the companion
cleans up on `Events.dismounted`). Regression playtest `bughunt_gameplay_regressions` PART=ride.

### 2. The saddle becomes "safe ground": saves made in flight continue in mid-air

**Found** (code read while checking WorldSaveGuard). `PlayerMotor.sense()` reads
`body.is_on_floor()`, which keeps the value of the last `move_and_slide()`: while mounted no
`move_and_slide` runs, so the body "stood on the floor" at every saddle position and
`_last_safe` followed the saddle (40 m up on a sky bison). `teleport()` also marked any destination
safe - including the mid-air point where a rider lets go of a flyer. `WorldSaveGuard` stores
`last_safe_position()` for a mounted / airborne player, so an autosave (region change, 180 s timer)
or a pause-menu save during a flight, or after a let-go, put the continue point in mid-air
(over the sea: a long swim back).
**Evidence.** `test_midair_dismount_is_not_safe_ground`: last safe ground = the release point 40 m
up on the old code (and the seat while riding).
**Fix.** `src/player/player_motor.gd:58` `carried` (set in `mount_on` `player_character.gd:530`,
cleared in `dismount` `:565`): a carried body senses no floor (`player_motor.gd:82`).
`teleport(xform, mark_safe := true)` (`player_motor.gd:444` / `:456`, `player_character.gd:451`);
`dismount()` passes false. PART=flight of the
regression playtest saves while falling and checks the stored position against the terrain.

### 3. Signatures refill the Focus they cost

**Found** (reading the feedback rules, then measured). Every landed hit of the player gives +6 /
+10 Focus (`BendingFeedback.on_result`), including the signature's own pulses. The Air Tornado
tagged some pulses `no_focus`, the other signatures did not.
**Evidence.** `test_signature_does_not_refill_focus` (4 dummies around the caster, old code):
Tidal Torrent **+100 Focus from 29 hits** (the bar was full again when it ended), Inferno +100 from
43, Earthquake +46 from 5, Air Tornado +10 from 33. A surrounded bender could chain signatures.
**Fix.** `src/bending/bending_feedback.gd:33` / `:45` `is_signature(id)`: a SIGNATURE's hits build no
Focus (enemy copies have their own ids and never give Focus anyway). PART=torrent.

### 4. Water Jet: hitstop every pulse and a Focus farm

**Found** (looking for sustained multi-hit moves without `no_hitstop`). The jet pulses every
0.15 s with a fresh attack id; every landed pulse requested a 0.04 s hitstop (time scale 0.05),
a camera shake and +6 Focus.
**Evidence.** `test_water_jet_pulses_no_hitstop_spam_or_focus_farm` (old code): **19 hitstops** and
**+100 Focus** from one 3 s jet on a single dummy.
**Fix.** `src/bending/bending_hits.gd:199` - opts `meta` set on every HitInfo;
`src/bending/kits/water/water_jet.gd:112` - every pulse `no_hitstop`, Focus only on every 4th pulse
(`no_focus` otherwise): at most ~+30 per jet. Tidal Torrent's pull pulses also carry `no_hitstop`
(`src/bending/kits/water/tidal_torrent.gd:135`). PART=jet of the regression playtest.

### 5. Companion assist: freed target -> script error every tick

**Found by the arena fuzz** (893 `SCRIPT ERROR: Invalid type in function '_valid_enemy'` in 3 game
minutes): the assist target is held across ticks; when it is freed (a fled enemy vanishing, a
despawn, a cleared group) it was passed to the typed `_valid_enemy(e: Node3D)` from `_approach` /
`_act_fire` every tick until the 9 s assist cap.
**Fix.** `src/companions/companion_assist.gd:405` untyped `_valid_enemy(v: Variant)`.
`test_companion_assist_survives_a_freed_target` (approach and mid-breath).

### 6. Projectiles that outlive their caster

**Found by the arena fuzz** (an archer's arrow in flight when the group was replaced).
`BendingContext.make_hit()` passed the freed caster to `HitInfo.make(..., p_source: Node, ...)`:
a script error every frame; the projectile never landed and stayed alive until its max age.
**Fix.** `src/bending/bending_context.gd:304` (`make_hit` uses `caster if is_instance_valid(caster)
else null`), `:127` (`forward()` without a caster). `test_projectile_outlives_its_caster`: the shot
lands, the hit has no source.

### 7. Air Tornado: captive freed mid-spin

**Found by the arena fuzz** ("Trying to cast a freed object" in `air_tornado.gd` `_steer`, every
frame of the tornado, and once in `_blow`). **Fix.** `src/bending/kits/air/air_tornado.gd:178`,
`:222`: validity check before the cast. `test_tornado_survives_a_freed_captive`.

### 8. Hopping off a mount that swims at sea

**Found** (code read of `_ground_beside` / `WorldData.get_safe_ground`). With nothing dry within reach
of the four sides, the hop-down target was `WorldData.get_safe_ground()`: a ring search up to 256 m,
then the **nearest port quay** (kilometres). The polar bear dog, badgermole and sky bison all swim,
so a rider pressing F out at sea arced across the water to a far shore. `PlayerCharacter.dismount()`
without a position (external dismounts) had the same fallback.
**Evidence.** `test_dismount_at_sea_stays_beside_the_mount` (real world map, open sea point):
hop-down point **118 m** away, external dismount 122 m away (old code).
**Fix.** `src/companions/companion_rider.gd:334-339`: dry ground within 8 m of the side is used, a
mount in the water drops the rider into the water beside it (riders swim, never drown);
`src/player/player_character.gd` `dismount()` does the same for the external fallback. PART=sea.

### 9. Enemy suspicion loop under continuous combat noise

**Found by the arena fuzz** (`WARNING: EnemyBase Pirate Crossbowman: state Alert timed out`).
`EnemyBrain.investigate()` restarted the 7 s give-up clock on every new noise; an enemy hearing a
fight it could not see (behind a pillar / wall) stayed suspicious until the 12 s ALERT safety
timeout, went home and was pulled straight back by the next noise - forever, with a warning each
time. **Fix.** `src/enemies/enemy_brain.gd:166`: a noise while already in ALERT only moves the point of
interest. `test_suspicion_gives_up_under_continuous_noise` (old code: ALERT reached 12.0 s).

### 10. Double respawn (world)

**Found by the world fuzz** (`double_respawn`: `player_respawned` twice for one death). The world's
respawn sequence (2.2 s beat, fade, wait for the respawn point's ground) can be overtaken by the
player's own auto-respawn backstop (15 s in the world); `RespawnSystem._place` then called
`respawn_at()` again (second event, health / chi reset twice). It needs a slow `wait_for_ground`
(far respawn point streaming in) - the fuzz's fast-forwarded clock made it likely, a loaded phone
could too.
**Fix.** `src/world/game/respawn_system.gd:117-123`: if the player is already alive and not DEAD when
the fade reaches the move, it only teleports (the move still happens under the black fade).
`test_world_respawn_never_doubles_with_the_backstop` (old code: 2 respawns).

---

## Fuzz sessions

<!-- SESSIONS -->

---

## Refuted / clean

| Suspicion | Result |
| --- | --- |
| Air dashes not refilled after landing without dashing (the refill sits in `AirDash.on_dodge_tick`) | refuted: `AirTraversal` refills `air_dashes_used` whenever the player is on the floor |
| `try_interact()` with an interactable freed since the last 10 Hz pick | refuted: a freed instance read from a typed member compares equal to null - kept as `test_interact_with_a_freed_interactable` |
| Journey Book + pause menu double pause (resume unpausing under an open book) | refuted: the book handles `pause` in `_input` first and closes itself |
| Earth Shield guard break then a hit cancel -> `on_guard_down` twice | harmless: idempotent (`_slab` nulled) |
| Abilities while mounted / dead / in a cinematic / interacting / paused | clean: never seen in the fuzz sessions (`ability_started_in_*`, `ability_started_while_paused`) |
| Ferry / dialogue while mounted | not reachable: interactions need a free state |
| Hitstop / slow-motion leaks | clean: `TimeDilation` is real-time and PROCESS_MODE_ALWAYS; no `time_scale_stuck` / `time_scale_leak` |
| Cooldown bypasses | clean (Earth Armor clears its own cooldown when donned - by design, it starts when shed) |
| Double hits per attack id | clean (`double_hit` never fired) |
| Pooling leaks | clean: node counts plateau at ~1 200-1 300 in 6-minute arena sessions (pools fill as new techniques are used), no orphan nodes |
| Companion assist landing hits while the player is dead | by design: its move is credited to the player and finishes |
| Enemy RETURN 40 s safety timeout (Dai Li agent, renegade airbender) | harness-made: the fuzz spawned enemies with a 60 m leash (long walks home); with the default leash it did not recur |
| Player inside their own Earth Wall / pillar (`player_embedded`) | by design: constructs never collide with their caster (an eruption at the feet must not trap them) |
| Enemies striking through walls | clean: melee / ranged strikes check line of sight (`EnemyBase` LOS ray) |
| Per-frame allocations in hot paths | reviewed: projectile casts reuse their shape / params, player aim is a ray per ability tick, group scans are 10-15 Hz or per pulse; physics frame time measured in the fuzz (sessions table) |

---

## Remaining

* The player can stand inside (and walk through) their own Earth Wall / pillar: deliberate in the
  bending framework (no self-trapping), visible as clipping.
* Navigation is still steering + whiskers (no navmesh): a cornered enemy can sit in RETURN until
  the 40 s safety timeout, which snaps it home (and prints a warning) - seen only with the fuzz's
  long leash.
* The fuzz is a monkey, not a player: rare multi-step sequences (e.g. a burrow ending exactly as a
  cinematic starts) are covered by reasoning and unit tests, not by fuzz statistics.
* Headless fast-forward (`--fixed-fps`) runs the game clock faster than the wall clock, which makes
  real-time waits (TimeDilation, `wait_for_ground`) relatively short or long; the rendered
  regression playtest and the unit tests run at normal speed.
