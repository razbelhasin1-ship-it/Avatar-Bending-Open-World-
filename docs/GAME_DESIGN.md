# Game design — bending, combat, companions, world loop

This is the design contract for gameplay modules. Numbers are starting points;
tune them by playtesting, but keep the *relationships* (air fastest and lightest,
earth heaviest and most stable, fire most aggressive, water smoothest and most
defensive).

## 1. Controls (defaults, rebindable)

| Input | Action |
| --- | --- |
| WASD / left stick | Move (camera-relative) |
| Mouse / right stick | Camera |
| Space / A | Jump (Air: second press = Air Jump; hold while falling = glide) |
| Shift / L3 | Sprint (air-assisted run for Air, ice-skate on snow/ice for Water) |
| C / B | Element dodge |
| LMB / X | Light strike — element combo chain (3–4 hits) |
| RMB / RT | Heavy strike — tap for the element's heavy, hold to charge |
| Q / LT (hold) | Element defense (shield/guard); perfect timing = parry/redirect |
| 1–4 / D-pad | Equipped techniques |
| R / RB | Signature technique (spends Focus) |
| Tab / MMB / R3 | Lock on / switch target (flick mouse while locked) |
| E / Y | Interact / talk |
| G / LB | Call companion |
| F | Mount / dismount |
| M, K, J, Esc | Map, skills, journal, pause |

Input buffering: the last bending press is buffered 0.2 s, so a press during
recovery fires on the first cancellable frame. Combos advance only if the next
light press arrives inside the chain window.

## 2. Resources

* **Health** — HealthComponent. Out of combat regenerates slowly after 6 s.
* **Chi** (0–100) — spent by techniques/heavies/defense upkeep, regenerates fast
  when not bending (25/s after 0.6 s idle; Water regenerates 20% faster near water).
  Light strikes are free. Insufficient chi → HUD flash + `Events.ability_failed`.
* **Focus** (0–100) — built by landing hits (+6 light, +10 heavy, +15 parry), lost
  slowly out of combat; the signature technique needs 100.
* **Poise** — HealthComponent poise; heavy actions add temporary armor (Earth most).

## 3. Locomotion profiles (feel must differ in the first five minutes)

| | Air | Earth | Fire | Water |
| --- | --- | --- | --- | --- |
| Walk / run / sprint (m/s) | 3.4 / 7.6 / 11.5 | 2.8 / 5.6 / 7.6 | 3.1 / 6.9 / 9.6 | 3.0 / 6.5 / 9.2 (12 skating on snow/ice) |
| Accel / decel (m/s²) | 42 / 30 | 16 / 28 | 32 / 24 | 20 / 12 (glides) |
| Turn rate (°/s) | 900 | 380 | 650 | 520 (smoothed) |
| Jump velocity (m/s) | 7.4 (+ air jump 6.5) | 5.0 | 6.3 | 6.0 |
| Gravity scale / air control | 0.8 / 0.85 | 1.3 / 0.2 | 1.0 / 0.5 | 1.0 / 0.55 |
| Dodge | Air Dash 7 m, 0.32 s i-frames, can be used in air | Earth Slide 3 m, no i-frames but full poise armor, small shockwave | Fire Step 4.5 m burst, 0.2 s i-frames, cancels into strikes | Flow Slide 4 m roll, 0.26 s i-frames, perfect dodge slows time briefly |
| Knockback taken | ×1.3 | ×0.4 | ×1.0 | ×0.9 |
| Landing | soft, air cushion | heavy, small quake on falls > 4 m | normal | normal, snow spray |
| Stance | light on toes, circular | low horse stance | forward-weighted | flowing weight shifts |

Deep snow (WorldData.get_snow_depth) slows walking up to 30% (Water ignores it while
sprinting). Slopes > 40° are not walkable.

## 4. Abilities

Every ability defines: id, element, display name, description, icon, slot kind
(light / heavy / defense / dodge / technique / signature / passive), chi cost,
cooldown, startup / active / recovery seconds, cancel window, animation clip with
timed events, charge behaviour, hit data (damage, reaction, force, lift, poise),
VFX/SFX, unlock requirements (level, prerequisite, trainer/quest, practice).
Gameplay effects spawn on the animation's `release`/`impact` event, never on a
timer that can drift from the body motion.

### Air — fast, evasive, acrobatic
| Slot | Ability | Notes |
| --- | --- | --- |
| Light | **Air Combo** | palm gust → spinning kick gust → double-palm burst; each pushes, 3rd staggers |
| Heavy | **Air Blast** | tap: fast gust (stagger + push 8 m/s); hold: wider charged blast |
| Defense | **Air Shield** | spinning current; blocks 70%, deflects projectiles; perfect = redirect back |
| Dodge | **Air Dash** | long wind-assisted dash, usable in air |
| Innate | **Air Jump** | second jump + glide (hold jump); landing puff |
| Technique (start) | **Air Sweep** | 360° circular sweep kick, knocks back ring of enemies |
| Technique (start) | **Air Push** | charged radial gust that clears space (knockdown close) |
| Technique (unlock) | **Air Scooter** (mobility) | ride a ball of air: fast travel speed, wall-run short |
| Signature | **Air Tornado** | vortex pulls enemies in, lifts, releases them launched |

### Earth — grounded, deliberate, forceful
| Slot | Ability | Notes |
| --- | --- | --- |
| Light | **Earth Punch** | rock chunks ripped from the ground, punched as projectiles (3-hit chain, last bigger) |
| Heavy | **Earth Boulder** | lift a boulder (stomp), hold to aim, release to hurl — heavy impact, knockdown |
| Defense | **Earth Shield** | slab rises in front while held; blocks 90% frontal; breaks under sustained damage |
| Dodge | **Earth Slide** | short slide with poise armor |
| Technique (start) | **Earth Wall** | wall (6×3×1 m) rises from terrain at aim point; blocks projectiles and movement for 12 s |
| Technique (start) | **Earth Pillar** | pillar erupts beneath target → launch |
| Technique (start) | **Earth Stomp** | shockwave ring, staggers nearby, cracks ground |
| Technique (unlock) | **Earth Spikes**, **Earth Grab** (root target 2.5 s), **Earth Armor** (toggle: +damage reduction, −speed, drains chi) |
| Signature | **Earthquake** | large fissure shockwave, knocks down everything nearby, debris |

### Fire — aggressive, precise, explosive
| Slot | Ability | Notes |
| --- | --- | --- |
| Light | **Fire Punch / Fire Kick** combo | jab-jab-kick-roundhouse; fire bursts on each strike, kick leaves an arc |
| Heavy | **Fire Blast** / **Blaze Charge** | tap: fast long-range fireball; hold: charged blast with visible buildup, explosion |
| Defense | **Flame Guard** | short flare that burns away projectiles; perfect = Fire Burst counter |
| Dodge | **Fire Dash** | burst-step leaving a short flame trail; cancels into strikes |
| Technique (start) | **Flame Sweep** | low sweeping kick arc, wide fire wave |
| Technique (start) | **Fire Burst** | point-blank explosion for space, knockdown |
| Technique (unlock) | **Fire Ring** (360° ring), **Jet Step** (fire-propelled leap/hover), **Fire Whip** (advanced) |
| Signature | **Inferno** | spinning ring of flame expanding outward + launch; lightning is a later separate technique |

### Water — fluid, adaptive, defensive, versatile
| Slot | Ability | Notes |
| --- | --- | --- |
| Light | **Water Whip** | flexible lash combo; 3rd hit yanks (PULL) |
| Heavy | **Water Blast** / **Torrent** | tap: concentrated projectile; hold: gather a stream around the body, release as a crushing torrent |
| Defense | **Water Shield** | rotating barrier; perfect timing redirects projectiles and freezes melee attackers |
| Dodge | **Flow Slide** | smooth slide roll; skating on snow/ice |
| Technique (start) | **Ice Shards** | three ice daggers from drawn water |
| Technique (start) | **Water Surge** | draw a large mass from the nearest source → crashing wave |
| Technique (start) | **Ice Wall** | temporary ice wall (shatters into shards when broken) |
| Technique (unlock) | **Ice Trap** (FREEZE), **Water Wave** (ride/push wave), **Water Jet**, **Healing Waters** |
| Signature | **Tidal Torrent** | huge spiralling water vortex |

**Water sources**: abilities query `WorldData.find_water_source(pos, radius)`. With a
source in range, water visibly streams from it to the hands; without one the
bender uses the canteen/air moisture: reduced size, +30% chi cost. Snow/ice
biomes always count as sources (snow is pulled up from the ground).

## 5. Combat rules

* Startup is short and readable (0.08–0.2 s light, 0.25–0.5 s heavy); every attack has
  a recovery the enemy can punish. Dodge and block cancel recovery after the cancel window.
* Lock-on: camera frames player + target; abilities aim at the target (with a slight
  lead for projectiles). Without lock: soft aim assist toward the best target in a
  25° cone of the camera, otherwise straight along the camera.
* Hit feedback: hitstop 0.04 (light) / 0.08 (heavy) s, camera shake scaled by
  Settings.camera_shake_scale(), target hit flash, impact VFX + SFX per element,
  damage numbers if enabled.
* Reactions: light hits flinch, heavies stagger/knock back, launchers launch;
  poise break always staggers; knockdowns have a 0.6 s get-up with i-frames.
* Parry (perfect defense, first 0.15 s of defense, or 0.15 s before impact): negate,
  element-specific counter, +15 Focus, attacker staggered.
* Death → fade, respawn at last safe point/shrine with 50% health; no progress lost.
* Enemies use the same HitInfo/ability systems; at most 2 enemies attack the player at
  once (attack tokens), others circle and pressure.

## 6. Companions

Follow behind-left/right of the player without blocking the camera; idle behaviours
when the player is still; G calls (teleports to a safe point near the player if
far/stuck); F mounts when close. Ground mounts (polar bear dog, badgermole) run fast
and handle snow/rough terrain; the badgermole can tunnel short distances through
earth (burrow + emerge at the target point). Flying mounts (sky bison, dragon): take off
from the ground, forward thrust, banking turns, altitude with jump/descend, glide,
boost, smooth landing on terrain. Companions are protected from death (they
retreat when hurt and recover).

## 7. World loop

Explore → discover POIs (XP, map reveal) → talk to NPCs → quests (go to, talk,
defeat, collect, use ability, discover, interact, escort) → train with trainers to
unlock techniques → fight camps/elites → travel between nations by foot, ferry or
flight. Progression unlocks *options* (new techniques, longer combos, defense
upgrades) more than raw damage. The opening 10 minutes give each element 1 light
combo + 1 heavy + defense + dodge + 2–3 techniques.
