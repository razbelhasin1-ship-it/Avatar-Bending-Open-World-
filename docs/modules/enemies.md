# Enemies module (`enemies`)

Hostile fighters and beasts that make mastering bending worthwhile, and the encounters
that place them in the world: camps, outposts, road patrols and beast dens. Enemies use
the same combat contracts as the player (`HitInfo` / `Combat`), and elemental enemies cast
the **same bending abilities** as the player through a non-player `BendingContext`
(team `ENEMY`).

| Piece | Files |
| --- | --- |
| Enemy | `src/enemies/enemy_base.gd` (`EnemyBase`, CharacterBody3D) |
| Data | `enemy_archetypes.gd` (`EnemyArchetypes`: 14 archetypes, 7 roles) |
| AI | `enemy_perception.gd` (`EnemyPerception`), `enemy_brain.gd` (`EnemyBrain`), `attack_tokens.gd` (`AttackTokens`) |
| Attacks | `enemy_actions.gd` (`EnemyActions`: telegraph -> strike -> recover), `enemy_telegraph.gd` (`EnemyTelegraph`: glints, rings, alert mark) |
| Bending | `enemy_abilities.gd` (`EnemyAbilities`: tuned copies of the kit abilities), `abilities/rock_glove.gd` (Dai Li Rock Glove) |
| Damage | `enemy_damage.gd` (`EnemyDamage`: guards, reactions, death, surrender) |
| Look | `enemy_visual.gd` (`EnemyVisual`: HumanoidRig / CreatureRig), `enemy_props.gd` (`EnemyProps`: club, knife, bow, shield, quiver, arrows), `enemy_clips.gd` (`EnemyClips`), `enemy_health_bar.gd` (`EnemyHealthBar`) |
| Rewards | `enemy_rewards.gd` (`EnemyRewards`: XP + loot) |
| Encounters | `encounter/encounter_director.gd` (`EncounterDirector`), `encounter_site.gd` (`EncounterSite`), `encounter_sites.gd` (`EncounterSites`: the world table), `encounter_provider.gd` (`EncounterProvider`: WorldContent provider), `outpost_builder.gd` (`OutpostBuilder`) |
| World hook | `src/enemies/world_hook.gd` (installed by `WorldHooks` in the world scene; nothing in the tutorial) |
| Dev / tests | `src/enemies/dev/enemy_arena.gd` + `scenes/dev/enemy_arena.tscn`, `dev/enemy_sim.gd` (`EnemySim`), `tests/unit/test_enemies.gd`, `tests/integration/test_enemies_world.gd`, playtests `enemies_arena`, `enemies_camp`, `enemies_lowhealth`, `enemies_observe`, `enemies_posesheet` |

## Quick start

```gdscript
# Anywhere (quests, scripted fights): one enemy at a post.
var e := EnemyBase.create(&"fire_soldier", {"home": xform, "level": 2, "seed": 7})
add_child(e)
e.defeated.connect(func(en: EnemyBase, how: StringName) -> void: print(how))   # killed / surrendered / fled

# Through the director (budgets, dormancy, combat music, despawn of corpses):
var d := EncounterDirector.instance()          # the world's director (null outside the world)
var e2 := d.spawn_enemy(&"bandit_archer", xform, {"leash": 30.0})
d.adopt(my_enemy)                              # track an enemy created elsewhere
```

`EnemyBase.create(archetype, opts)` options: `home` (Transform3D post + facing), `seed`,
`level` (+8 % health, +6 % damage, +15 % XP per level), `leash` (m), `patrol`
(PackedVector3Array, walked back and forth), `site_id`, `faction` (allies answer calls
inside a faction), `rewards` (false: no XP / loot), `low_health_mode` (`&""`, `&"flee"`,
`&"surrender"`; otherwise rolled from the archetype).

## EnemyBase API

| Member | Notes |
| --- | --- |
| groups / physics | `&"damageable"`, `&"enemy"`; `team = Combat.Team.ENEMY`; layer `Layers.ENEMY`, mask `SOLID | ENEMY | PLAYER` |
| `receive_hit(hit) -> Combat.Result`, `is_alive()` | damageable contract (via `Combat.deal` only) |
| `get_display_name()`, `get_aim_point()`, `get_health_component()`, `get_bending_context()` | lock-on / HUD / projectile redirect contract (same as the player's) |
| `state`, `get_state_name()`, `in_combat()`, `is_elite()` | `EnemyBase.State` below |
| `archetype`, `role`, `faction`, `element`, `level`, `home`, `leash`, `patrol`, `site_id` | data |
| `health`, `visual`, `perception`, `brain`, `actions`, `controller` (benders), `ctx`, `bar` | components |
| `dormant` | far from the player: no AI / physics / animation, ignores hits (director) |
| `bark(text)`, `show_alert_mark()` | floating line / "!" glyph |
| `reset_to_home()`, `vanish()`, `advance_dormant_patrol(dt)` | director helpers |
| signals | `state_changed(new, old)`, `alerted(enemy, target)`, `damaged(enemy, hit, result)`, `died(enemy, killer)`, `defeated(enemy, how)`, `attack_telegraphed(enemy, attack, seconds)`, `attack_struck(enemy, attack)`, `attack_finished(enemy, attack, landed)`, `despawn_ready(enemy)` |

Global events: `Events.enemy_alerted(enemy)` (first time it engages), `Events.enemy_killed(enemy,
killer)`, `Events.hit_landed` (through `Combat.deal`), `Events.combat_state_changed(bool)`
(director), `Events.notify` (reward toast), `Events.item_collected`, `Events.xp_gained`.

## Archetypes (`EnemyArchetypes`)

Every enemy is a dictionary (`EnemyArchetypes.get_archetype(id)`, read-only; `register(id,
dict)` adds or replaces one at runtime; `ids()`, `by_faction(f)`). Fields (defaults filled by
`_normalized`): `display_name, role, faction, element, tier (2 = elite), look (HumanoidRig
config or {"creature": id, "scale"}), props [[prop, socket]], health, poise, poise_resist,
mass, armor, speed {walk, run, strafe}, sight, fov, hearing, engage Vector2(min, max),
aggression, attacks [...], block {...}, dodge {...}, flee {...}, phases [...], xp, loot [...],
radius, height`.

| Id | Role | Faction | Look / weapon | Signature behaviour |
| --- | --- | --- | --- | --- |
| `bandit_brawler` | brawler | bandits | bandit + studded club | club swing -> backswing combo, armored overhead smash (ring, knockdown) |
| `bandit_skirmisher` | skirmisher | bandits | twin knives | fast 2-hit flurry then backs off, lunge stab, thrown knives; dodges slow attacks (75 %) |
| `bandit_archer` | ranged | bandits | bow + quiver | keeps 9-16 m, arrows (lead by difficulty), charged power shot; push kick up close |
| `fire_shieldbearer` | defender | Fire Nation | spear + shield | raised shield blocks frontal hits and projectiles of every element; heavy hits (earth x2.6) break the guard (stagger, 4 s open) |
| `fire_archer` | ranged | Fire Nation | Yuyan bow | pinning shot (FREEZE) |
| `fire_soldier` | bender | Fire Nation | fire soldier | Fire Fist jabs, Fire Blast, Flame Sweep (the player's kit scripts), Flame Guard vs projectiles, Fire Step |
| `fire_captain` | captain (elite) | Fire Nation | officer | 4-step fire combo, Blaze Charge, Flame Sweep; at 50 %: war cry burst + Blazing Leap, faster telegraphs |
| `earth_rogue` | bender | raiders | earth soldier | rock punches, boulder, Earth Wall for cover when the player charges a heavy |
| `earth_chief` | captain (elite) | raiders | big earth soldier | rock combo, boulder, Quake Stomp (ring); at 50 %: spike line (LAUNCH) |
| `dai_li_agent` | bender | Dai Li | Dai Li robes | Rock Glove (chained stone glove, roots the target 1.1 s), rock punches, agile sidesteps |
| `pirate_cutlass` | skirmisher | pirates | cutlass | slash / backslash, lunge |
| `pirate_archer` | ranged | pirates | crossbow-style bow | arrows, push kick |
| `water_pirate` | bender | pirates | rogue waterbender | Water Whip, Water Blast, Ice Shards, Water Surge, Ice Trap, Ice Wall (cover), Water Shield (no redirect), Flow Slide |
| `air_renegade` | bender | bandits | renegade airbender (bandit clothes) | Air jabs, Air Blast, Air Push (space), Air Sweep (ring), Wind Blade, Air Shield, Air Dash; leads the north road bandits |
| `air_sparring_monk` | bender | air_acolytes | Air Nomad | `AirKit.enemy_archetype()`: jabs, blast, Air Push, Wind Blade (the air trainer's spar partner) |
| `komodo_rhino` | beast | wild | CreatureRig `komodo_rhino` | bite, tail swipe (ring), roaring charge that stops on walls |

### Attack dictionary (`EnemyActions`)

```
id, kind (&"melee" &"projectile" &"slam" &"bending" &"beast" &"charge"), clip, mirror,
windup (normalized hold point of the clip), approach (s to reach it), telegraph (s held),
speed (clip speed), range Vector2(min, max), cooldown, weight, needs_los, glint (socket),
ring (ground telegraph radius), hit {damage, reaction, force, lift, stun, poise, heavy, status},
shape {type: sweep | sphere | line, reach, radius}, lunge (m), leap, line (m), recover (s),
armor (poise hyper armor), shake, next + next_chance (combo follow-up), retreat,
tag (&"space" close-range only, &"cover" reactive), bending {slot, steps, hold, tap},
projectile {visual, speed, gravity, radius, range, socket, trail}, charge {speed, distance},
action / event (creature action + its hit event), element (override)
```

## AI

```
IDLE / PATROL --awareness--> ALERT (suspicious: stare, walk over, give up after 7 s)
   --spotted / hit / ally call--> ALERT (spotted beat 0.35-0.7 s: "!", point, bark, call allies 22 m)
   --> CHASE --> STRAFE (circle at the role's range, always moving, feints)
   --attack token--> ATTACK (EnemyActions: telegraph -> strike -> recover) [-> combo follow-up]
reactive: BLOCK (shield / bending guard vs projectiles, combo breaker after 3 quick hits)
          DODGE (agile roles evade slow / heavy attacks and released charges, then may counter)
hit:      STAGGER / KNOCKDOWN -> GETUP (i-frames) -> STRAFE
leash broken / target lost 6 s -> RETURN (heals 12 %/s) -> IDLE / PATROL
low health (rolled per enemy): FLEE (vanishes out of sight, half XP) or SURRENDER (kneels, hands over loot)
captains: phase change at the health threshold (war cry burst, new attacks, faster)
```

* **Perception** (8 Hz, staggered): sight cone (`sight` m, `fov`) with line of sight to the
  chest; awareness builds 5/s point blank to 0.75/s at the edge of sight (decays 0.22/s);
  3.2 m proximity sense all around; hearing of combat (`Events.hit_landed` within `hearing`);
  memory of the last seen position. Players in cinematics, mounted or dead are ignored.
* **Attack tokens** (`AttackTokens`): at most 2 enemies attack the player at once (story 1,
  hard 3) with 0.75 s between two attack starts (story 1.1, hard 0.45); others circle and
  pressure (feint steps in). Tokens are held by instance id, validated every query and expire
  after 6 s: a freed or dead enemy never keeps one.
* **Fair play**: an enemy outside the player's camera view circles toward it instead of
  attacking; after 2.5 s off-screen it may attack with a 1.45x telegraph (`flanking`). No new
  attack (or combo follow-up) starts while the player is knocked down or getting up. Melee /
  slam hits use the attacker as `HitInfo.origin`, so a held guard judges where the enemy stands
  (the hit shape's centre can lie behind a close target). Every attack has a hard cap (6 s),
  every state a timeout (`EnemyBase.STATE_TIMEOUT`).
* **Never stand still**: circlers always move (tested: > 80 % of strafing frames moving);
  stuck detection flips the circle direction; returning enemies snap home after 4 s stuck when
  the player is far.

## Telegraphs, strikes and recovery (`EnemyActions`, `EnemyTelegraph`)

1. **Wind-up**: the attack clip plays to its anticipation key and HOLDS there (the animator
   creeps on) for `telegraph` s (x difficulty: story 1.3, hard 0.85; captains' phase x0.85;
   off-screen x1.45). A star **glint** (element tinted) pops on the weapon tip / hand and rides
   it, with a wind-up sound (fire ignite, water draw, stone debris, whoosh). Area attacks show
   a red **ground ring** (element-tinted fill) until the strike; leaps track the player until
   the last 0.14 s (commit), so a late sidestep still works.
2. **Strike** on the clip's `impact` / `release` event (deadline fallback). Weapons sweep a
   capsule, smashes / bites a sphere, slams a ground disc, spike lines erupt every 0.05 s,
   projectiles (arrows, knives) are `BendingProjectile`s (continuous collision, deflectable).
   Bending attacks request the slot on the enemy's `BendingController` (heavy: hold = the
   charge is the telegraph; tap = short telegraph then release).
3. **Recover** (`recover` s): no blocking, dodging or turning: the punish window.

Measured (`enemies_arena` fairness report, normal difficulty, first attack of each duel):

| Enemy | First attack | Telegraph | Glint -> strike | Recovery |
| --- | --- | --- | --- | --- |
| bandit brawler | club swing (-> backswing) | 0.44 s | 0.55 s | 0.45 s |
| bandit skirmisher | knife flurry | 0.34 s | 0.40 s | 0.20 s (then backs off) |
| bandit archer | arrow | 0.60 s | 0.65 s | 0.40 s |
| Fire Nation spearman | spear thrust | 0.52 s | 0.62 s | 0.55 s |
| firebender soldier | Fire Blast | 0.52 s | 0.72 s | 0.55 s |
| rogue earthbender | rock punches | 0.41 s | 0.62 s | 0.50 s |
| Raider Chief Dun | Quake Stomp (4.2 m ring) | 0.68 s | 0.90 s | 0.90 s |
| komodo rhino | bite | 0.50 s | 0.87 s | 0.60 s |

The fastest tell (the skirmisher's knives) is 0.40 s from glint to blade; heavies and areas
give 0.7-0.9 s with a ground ring.

## Damage and reactions (`EnemyDamage`)

* I-frames (dodges, get-up) -> `DODGED`; bending defense through the controller
  (`DefenseAbility.guard`, enemies never get a reflex parry); physical shields (defenders):
  frontal melee is reduced 85 %, frontal projectiles of every element stop on the shield,
  heavy hits wear the guard (earth heavies x2.6) and break it (stagger, 4 s open).
* Damage x `Combat.element_multiplier` x (1 - armor) x bending damage reduction.
* Reaction by weight class: `poise_resist` turns staggers into flinches (and knockdowns into
  staggers) for hits with little poise damage; `mass` scales knockback (archers fly, chiefs
  barely move); heavy knockback blasts with force x mass >= 11.5 **topple** light and medium
  fighters (knockdown); attack hyper armor swallows reactions below its poise; hits on a
  downed enemy never turn the knockdown into a stagger. Water douses firebenders (longer
  stun, steam, fire cooldowns). Poise break always staggers.
* Knockdown 0.9-2.2 s on the floor (after landing when launched), then get-up with i-frames.
  Beasts are bowled over: the creature rolls onto its side and back up on the get-up.
* Surrender: the bandit kneels with open hands (looping kneel), drops its hand weapons, hands
  over its loot, is skipped by lock-on and ignores further hits; it leaves after 30 s or when
  the player is 40 m away. Flee: runs from the player and vanishes out of sight (half XP); a
  cornered runner turns and fights to the end.
* Death: death reaction, collision off, `Events.enemy_killed`, rewards, fade and sink after
  5 s, `despawn_ready` at 6.6 s.

## Encounters (`EncounterDirector`, `EncounterSite`, `EncounterSites`, `EncounterProvider`)

* **Sites**: `camp` (hostile WorldData camp POIs: Dustwind Raider Camp; the structure is the
  worldcontent POI camp), `outpost` (authored, near each home region: Fire Navy Landing,
  Fire Nation Scout Camp, Smugglers' Cove, Fire Nation Scouting Party), `patrol` (groups walking
  a stretch of a road: Omashu road, Dai Li on the Full Moon Bay road, pirates on the Saltspark
  road, bandits on the north road) and `den` (komodo rhinos). Outposts / dens snap to flat, dry,
  open ground near their anchor (`find_flat`), and are built by `EncounterProvider` through
  WorldContent (`OutpostBuilder`: Fire Nation war camp with tents, barricades, braziers and
  banners; pirate cove with a beached boat; boulder ring den) with exclusions that keep trees and
  rocks out.
* **Spawning**: a site spawns its living members when the player is within `spawn_radius`
  (85-130 m by `Settings.detail_level()`), nearest first, within the active-enemy budget
  (7 / 11 / 15 / 20 by detail level); calm sites despawn beyond `spawn_radius + 40 m`.
  Time-sliced (8 sites per 0.5 s).
* **Cheap far simulation**: calm enemies beyond `sim_radius` (45-85 m) go dormant (no physics,
  AI or animation; hits ignored); far patrols keep walking their route kinematically.
* **Respawn**: dead members stay dead; a thinned or cleared site refills `respawn_time`
  (360-600 s of play time) after its first loss, only while the player is far away. Cleared
  camps are saved in `GameState.world_flags["encounters"]` (site id -> play time).
* **Rewards**: each enemy pays XP (`GameState.add_xp`) and rolls its loot table (coins ->
  `GameState.currency`, items -> `GameState.add_item`) with one toast; surrendering enemies hand
  over their loot, fled ones give half XP. A cleared camp / outpost adds 40 + 10 per member XP,
  a "cleared" toast, the quest stinger and `stats.camps_cleared`. Nothing is granted in the
  tutorial.
* **Combat state**: `Events.combat_state_changed(true)` when the first enemy within 60 m engages
  the player, `false` 2.5 s after the last one stops (combat music in Audio).
* **Difficulty** (`Settings` gameplay/difficulty): health x0.75 / x1.25, telegraphs x1.3 /
  x0.85, cooldowns x1.35 / x0.8, attackers 1 / 2 / 3, projectile lead 0.2 / 0.5 / 0.75; damage
  to the player is scaled by the player (`Settings.difficulty_damage_scale`).

## Performance (mobile)

Enemies are budgeted by detail level (7 on the mobile preset), dormant beyond 45 m on mobile,
perception runs at 8 Hz staggered, thinking at ~6 Hz, avoidance raycasts are cached 0.2 s,
glints / rings / projectiles are pooled (`FxLib`), health bars are 3-4 unshaded quads shown
only in combat, telegraph lights respect `FxLib.tier()`, outpost geometry is merged by the
building kit with LOD1 beyond 120 m.

Measured worst case (`test_cost_of_a_full_budget_fight`, headless, this dev container): 15
engaged enemies + the player = **7.3 ms per physics frame**, of which ~5.9 ms is HumanoidRig
animation at LOD 0 (no camera in the test, so no rig auto-LOD), brain 0.7 ms, physics 0.35 ms,
attacks 0.24 ms, perception 0.1 ms. In the game the rig's own auto-LOD (distance + on-screen)
cuts the animation share; the mobile budget is 7 enemies.

## Tests and tools

* `tests/unit/test_enemies.gd`: archetype data completeness (roles, clips, readable telegraphs),
  enemy abilities = the kit scripts (unregistered), spawning every archetype, perception (cone,
  LOS, proximity, hearing, ally call), engage -> telegraph -> strike timing, attack tokens
  (max 2, circlers keep moving), token release on death / free, reactions by weight class and
  hyper armor, knockdown -> get-up i-frames, shields, agile dodge of slow projectiles, a bender
  casting the real ability + parry stagger, leash / return / heal, death rewards + events,
  surrender / flee, captain phase change, world sites on the real world data (on land, dry, no
  road / field / town paving inside outposts), director spawn / despawn / respawn / combat
  state, dormancy, guard origin of area attacks, off-screen enemies circling into view before
  attacking, toppling heavies vs brutes (and no knockdown -> stagger downgrade), the cost of a
  full-budget fight, and a 3000-frame no-stuck fuzz over 10 archetypes (25 tests).
* `tests/integration/test_enemies_world.gd` (headless world scene, streamed terrain collision):
  the world hook installs the director, the Omashu road patrol activates and walks its road on
  the real terrain (moves, stays within 6 m of the road, on the ground), and the Fire Nation
  Scout Camp garrison engages a player who walks in (combat state on, attackers capped at 2).
* `EnemySim` steps players, enemies, projectiles and constructs at 1/60 s with a sim clock.
* `scenes/dev/enemy_arena.tscn` (`--scene=res://scenes/dev/enemy_arena.tscn --element=earth`):
  the combat arena with enemy groups (F5 respawn, F6 next group, F9 passive toggle).
* Playtests:
  * `enemies_arena`: one duel per archetype with the real player through InputMap actions
    (telegraph -> parry / dodge / guard -> counter -> charged heavy knockdown -> get-up ->
    defeat), observer-camera screenshots + the player's own view, a fairness report;
    `ARCH=a,b ELEMENT=fire`. Each archetype gets the player element that suits the matchup.
  * `enemies_camp`: the Fire Nation Scout Camp outpost in the real world (710 m from the Earth
    Kingdom home spawn): approach, spotted (alert marks, ally call, combat music state), group
    fight (token cap, circling), cleared (XP, loot, bonus toast, saved flag, combat off).
    `SITE=<id> ELEMENT=<element>`.
  * `enemies_lowhealth`: a bandit surrenders (kneel, dropped club, spared) and an archer flees.
  * `enemies_observe` (log a group vs an idle / blocking player), `enemies_posesheet` (weapon
    clip poses at the telegraph hold and the strike).
  * Mobile: `RENDERER=mobile MOBILE=1 ARCH=fire_soldier tools/playtest.sh enemies_arena`.

## Design decisions

* Enemies reuse the player's ability scripts so every bending attack the player faces looks,
  sounds and resolves exactly like the player's own; tuning lives in `EnemyAbilities.VARIANTS`
  (slower projectiles, shorter chains, no redirect parries) on unregistered copies.
* The telegraph is a held pose + glint + sound (+ ring for areas), never a UI marker; a fair
  punish window follows every attack.
* Weight classes (`mass`, `poise_resist`, `armor`) make the elements matter: earth heavies break
  shields and floor brutes, air blasts send archers flying, water douses fire.
* Sites are deterministic data (`EncounterSites`), so saves only store cleared timestamps.
* Fair play beats difficulty: enemies wait for the player to see them, never pile on a downed
  player and never get a reflex parry; difficulty changes telegraph length, cooldowns, attacker
  count and projectile lead, not reaction-time cheats.

## Element techniques (wave 4, docs/qa/integration_fixes.md)

Bender archetypes cast the element techniques of the kits, not only the core kit:
`EnemyAbilities.LOADOUTS` fills `technique_1..4` per element (Fire: Flame Sweep, Fire Burst,
Fire Ring, Fire Whip; Earth: Earth Wall, Earth Pillar, Earth Stomp, Earth Spikes; Water: Ice
Shards, Water Surge, Ice Trap, Ice Wall; Air: Air Push, Air Sweep, Wind Blade - plus an Air core
kit) with enemy-tuned copies (`VARIANTS`: ~20-30 % less damage, longer cooldowns, Ice Trap
freezes 1.1 s, Burst / Whip / Ring burn 2.5 s). The archetype attack entries come from the kits'
`enemy_attacks()` (`EnemyArchetypes._kit(...)` with per-archetype weight / cooldown):

| Archetype | Techniques added | Range window | Glint -> strike (measured) |
| --- | --- | --- | --- |
| `fire_soldier` | Fire Burst (point-blank, ring 3.8 m) | 0-3.4 m | 0.42 s + ring |
| `fire_captain` | Fire Whip; phase 2: Fire Ring (ring 6.5 m) | 2.5-7 m / 0-6 m | 0.40 s (overhead wind-up) |
| `earth_rogue` | Earth Pillar, Earth Stomp (ring 5 m) | 3-14 m / 0-4.5 m | 0.35 s / 0.47 s |
| `earth_chief` | Earth Pillar | 3-14 m | 0.35 s |
| `dai_li_agent` | Earth Spikes | 3-11 m | 0.40 s |
| `water_pirate` | Water Surge, Ice Trap, Ice Wall (cover) | 3-10 m / 3.5-12 m | 0.46 s / 0.40 s |
| `air_renegade` | Air Push (space, ring 4.4 m), Air Sweep (ring 4.6 m), Wind Blade | 0-3.6 / 0-4 / 3-16 m | 0.42 / 0.45 / 0.45 s |

Every technique still goes through the normal attack flow (attack tokens, telegraph hold +
glint + wind-up sound, recovery punish window); a technique is used at most every 6 s.
Measured in `test_integration_fixes.gd::test_enemy_techniques_cast_and_land` (each cast lands
on the player at its range, tell 0.35-0.47 s before the strike) and the
`integration_fixes_enemies` playtest (variety per duel + group, token cap).

## Changes outside the module

* `src/player/player_targeting.gd`: `_valid()` takes an untyped argument so a lock / soft target
  freed while referenced (a despawned or fled enemy) reads as invalid instead of raising a
  script error.
* `tests/unit/test_worldscene.gd`: the hook test tolerates other modules' hooks (wave-2 branch).

## Known limitations

* The player's own lock-on camera can put a close melee attacker behind the player model; the
  glint usually shows above the shoulder, the arena screenshots use an observer camera. The
  camera framing belongs to the player module.
* Enemies have no off-screen indicator: off-screen fairness relies on the circle-into-view rule,
  the longer flank telegraph and the wind-up sounds.
* Only one WorldData camp POI (Dustwind Raider Camp) is hostile; the other camps are friendly
  (hunters, wardens). The other encounters are authored outposts, patrols and dens.
* Navigation is steering + whiskers (no navmesh): enemies can get stuck behind large concave
  obstacles; they flip direction and, when going home with the player far away, snap home.

## Wave 4 bug hunt (docs/qa/bughunt_gameplay.md)

* `EnemyBrain.investigate()`: a new noise while already suspicious (ALERT) only moves the point of
  interest; it no longer restarts the 7 s give-up clock. Continuous combat noise beyond a wall kept
  an enemy that could not see the player in ALERT until the 12 s state safety timeout (an engine
  warning), then RETURN -> ALERT again, forever.
