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
| Dev / tests | `src/enemies/dev/enemy_arena.gd` + `scenes/dev/enemy_arena.tscn`, `dev/enemy_sim.gd` (`EnemySim`), `tests/unit/test_enemies.gd`, playtests `enemies_arena`, `enemies_camp`, `enemies_observe`, `enemies_posesheet` |

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
| `water_pirate` | bender | pirates | rogue waterbender | Water Whip, Water Blast, Ice Shards, Water Shield (no redirect), Flow Slide |
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
  attacking; after 2.5 s off-screen it may attack with a 1.45x telegraph. Attack origins are the
  attacker (guards judge where the enemy stands). Every attack has a hard cap (6 s), every state
  a timeout (`EnemyBase.STATE_TIMEOUT`).
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

Measured (arena playtest, normal difficulty): glint -> strike 0.45-1.1 s for every attack.

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
* Death: ragdoll-like death reaction, collision off, `Events.enemy_killed`, rewards, fade and
  sink after 5 s, `despawn_ready` at 6.6 s.

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

## Tests and tools

* `tests/unit/test_enemies.gd`: archetype data completeness (roles, clips, readable telegraphs),
  enemy abilities = the kit scripts (unregistered), spawning every archetype, perception (cone,
  LOS, proximity, hearing, ally call), engage -> telegraph -> strike timing, attack tokens
  (max 2, circlers keep moving), token release on death / free, reactions by weight class and
  hyper armor, knockdown -> get-up i-frames, shields, agile dodge of slow projectiles, a bender
  casting the real ability + parry stagger, leash / return / heal, death rewards + events,
  surrender / flee, captain phase change, world sites on the real world data, director spawn /
  despawn / respawn / combat state, dormancy, off-screen fairness, guard origin of area
  attacks, and a 3000-frame no-stuck fuzz over 10 archetypes.
* `EnemySim` steps players, enemies, projectiles and constructs at 1/60 s with a sim clock.
* `scenes/dev/enemy_arena.tscn` (`--scene=res://scenes/dev/enemy_arena.tscn --element=earth`):
  the combat arena with enemy groups (F5 respawn, F6 next group, F9 passive toggle).
* Playtests: `enemies_arena` (one duel per archetype, observer camera, fairness report;
  `ARCH=a,b ELEMENT=fire`), `enemies_camp` (a real outpost near the Earth Kingdom home region),
  `enemies_observe` (log a group vs an idle / blocking player), `enemies_posesheet` (weapon clip
  poses at the telegraph hold and the strike).

## Design decisions

* Enemies reuse the player's ability scripts so every bending attack the player faces looks,
  sounds and resolves exactly like the player's own; tuning lives in `EnemyAbilities.VARIANTS`
  (slower projectiles, shorter chains, no redirect parries) on unregistered copies.
* The telegraph is a held pose + glint + sound (+ ring for areas), never a UI marker; a fair
  punish window follows every attack.
* Weight classes (`mass`, `poise_resist`, `armor`) make the elements matter: earth heavies break
  shields and floor brutes, air blasts send archers flying, water douses fire.
* Sites are deterministic data (`EncounterSites`), so saves only store cleared timestamps.
