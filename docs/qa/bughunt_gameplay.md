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

<!-- FINDINGS -->

---

## Fuzz sessions

<!-- SESSIONS -->

---

## Refuted / clean

<!-- REFUTED -->

---

## Remaining

<!-- REMAINING -->
