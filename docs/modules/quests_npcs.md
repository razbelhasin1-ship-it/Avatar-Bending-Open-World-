# NPCs, dialogue, quests, trainers, merchants, wildlife (`quests_npcs`)

The living layer of the four nations and the game loop on top of it: townsfolk with daily
routines spawned from the settlement anchors, named characters with data-driven dialogue, the
quest system (autoload **`Quests`**), bending masters who teach techniques through challenges,
merchants with a trade panel, and ambient wildlife. Everything attaches to the playable scenes
through `WorldHooks` (`src/quests/world_hook.gd`, `src/npc/world_hook.gd`); nothing runs in the
training grounds.

| Piece | Files |
| --- | --- |
| Quest system | `src/quests/quest_system.gd` (`QuestSystem`, autoload `Quests`), `quest_defs.gd` (`QuestDefs`), `quest_conditions.gd` (`QuestConditions`), `quest_actions.gd` (`QuestActions`), `quest_rewards.gd` (`QuestRewards`), `quest_targets.gd` (`QuestTargets`), `quest_props.gd` (`QuestProps`) + `quest_prop_meshes.gd` + `quest_glint.gdshader`, `bending_challenge.gd` (`BendingChallenge`), `challenge_hud.gd` (`ChallengeHud`), `world_hook.gd` |
| NPCs | `src/npc/npc_director.gd` (`NpcDirector`), `npc_provider.gd` (`NpcProvider`), `npc_crowd.gd` (`NpcCrowd`), `npc_character.gd` (`NpcCharacter`), `npc_brain.gd` (`NpcBrain`), `npc_steering.gd` (`NpcSteering`), `npc_routines.gd` (`NpcRoutines`), `npc_looks.gd` (`NpcLooks`), `npc_barks.gd` (`NpcBarks`), `npc_marker.gd` (`NpcMarker`), `npc_registry.gd` (`NpcRegistry`), `world_hook.gd` |
| Dialogue | `src/npc/dialogue/dialogue_tree.gd` (`DialogueTree`), `dialogue_runner.gd` (`DialogueRunner`) |
| Trainers | `src/npc/trainer/trainer_lessons.gd` (`TrainerLessons`) |
| Merchants | `src/npc/shop/trade_goods.gd` (`TradeGoods`: the item catalog), `merchant_stock.gd` (`MerchantStock`), `shop_panel.gd` (`ShopPanel`), `item_icon.gd` (`ItemIcon`) |
| Wildlife | `src/wildlife/wildlife_director.gd` (`WildlifeDirector`), `wildlife_provider.gd` (`WildlifeProvider`), `wildlife_animal.gd` (`WildlifeAnimal`) |
| Data | `data/quests/quests_{water,earth,fire,air,travel}.gd` (`const QUESTS`), `data/dialogue/npcs_{water,earth,fire,air,travel}.gd` (`const NPCS`, `const TREES`), `data/dialogue/ambient.gd` (`BARKS`, `SMALL_TALK`) |
| Tests | `tests/unit/test_quests_npcs.gd` (24), `tests/integration/test_quests_npcs_world.gd`; playtests `quests_npcs_city` (`ELEMENT=`, `HOUR=`, `TOUR=0`), `quests_npcs_water_chain` (`STOP=`), `quests_npcs_wildlife` (`SPECIES=`) |

Data files are GDScript constants (not JSON) so they export with the project, are parse-checked,
and can use `Vector3` / `StringName` literals. `QuestDefs.FILES` / `NpcRegistry.FILES` list them.

## Quick start (other modules)

```gdscript
Quests.start(&"wt_first_form")                 # start a quest (if never started)
Quests.state(&"wt_first_form")                 # &"none" | &"active" | &"completed" | &"failed"
Quests.is_objective_active(q, o) / is_objective_done(q, o) / progress(q, o) / current_stage(q)
Quests.complete_objective(q, o)                # scripted completion
Quests.report(&"interact", &"cave_tablet")     # kinds: talk (npc id), interact (key), escort (npc id), challenge (objective id)
Quests.track(q)                                # HUD tracker + compass target
Quests.get_quest_display(q)                    # HUD provider contract (docs/modules/ui.md)
Quests.journal(&"all" | &"active" | &"completed")   # journal UI data (below)
Quests.journal_entry(q)
Quests.map_markers()                           # [{quest, objective, position, kind: &"objective"|&"giver", text, tracked}]
Quests.npc_marker(npc_id)                      # &"available" | &"turn_in" | &""
Quests.register_quest(dict) / unregister_quest(id)   # runtime quests (other modules, tests)
Quests.quest_changed                           # signal: any change (journal refresh)

NpcRegistry.get_npc(&"wt_siku"); NpcRegistry.position_of(&"wt_siku"); NpcRegistry.live_npc(&"wt_siku")
TradeGoods.info(&"arctic_moss")                # {name, desc, category, value, nation, color, use, sellable, stack}
TradeGoods.use_item(&"arctic_moss", player)    # consumables (heal / chi)
ItemIcon.make(&"arctic_moss", 56)              # vector item icon for any UI
MerchantStock.buy(shop, item) / sell(item) / stock(shop)
ShopPanel.open_for(get_tree(), &"nwt_healer", npc)
TrainerLessons.lessons_for(&"wt_siku")         # techniques that master can teach now
```

Global events used: emits `Events.quest_started / quest_updated / objective_completed /
quest_completed / dialogue_started / dialogue_ended / notify / item_collected (via GameState)`;
listens to `ability_used`, `hit_landed`, `enemy_killed`, `item_collected`, `poi_discovered`,
`player_spawned`, `combat_state_changed`, plus `EncounterDirector.enemy_spawned / site_cleared`
and every enemy's `defeated` (surrenders and flights count).

## Quests

### Definition format (`data/quests/*.gd`)

```gdscript
{
	"id": &"wt_smoke_on_the_horizon", "title": "Smoke on the Horizon", "kind": &"main",   # main | side | travel | training
	"nation": &"water", "giver": &"wt_tulok", "location": "The eastern ice",
	"summary": "...", "description": "...",                 # journal text
	"requires": {condition},                                 # availability (offered by the giver)
	"auto_start": {condition},                               # started by itself when true (opening quests)
	"on_start": [actions], "on_complete": [actions],
	"stages": [
		{"id": &"fight", "text": "Journal line for this stage.", "objectives": [ {objective}, ... ],
		 "on_complete": [actions]},
	],
	"rewards": {"xp": 220, "currency": 40, "items": {&"healing_salve": 2}, "skill_points": 0,
		"techniques": [&"water_surge", &"ice_wall"]},       # candidates: first registered, own element, not learned
	"next": &"wt_moon_and_ocean",                            # chain: started when this completes
}
```

A stage completes when all its non-`optional` objectives are done; stage actions run, the next
stage becomes current (objectives that are already satisfied complete at once). The last stage
completes the quest: quest `on_complete`, rewards (`QuestRewards`), toast, `Events.quest_completed`
(Audio plays the stinger), then `next` starts. Tracking falls back to the best active quest.

### Objective types

| type | fields | completes when |
| --- | --- | --- |
| `go_to` | `target` (spec), `radius` (10) | the player is within the radius (4 Hz poll) |
| `talk_to` | `npc` | a conversation with that NPC ends (`Quests.report(&"talk", id)` by the DialogueRunner) |
| `defeat` | `site` and/or `archetype` / `faction`, `count`, `near` + `radius`, `clear` (default true: the site's clear completes it) | each matching enemy defeated (killed, surrendered or fled) counts once |
| `collect` | `item`, `count`, `take` (remove on completion), `props` (pickups to spawn), `give` per prop | the inventory holds `count` |
| `use_ability` | `ability` id or `slot` (light / heavy / technique / defense / dodge / any), `mode` (`use`: Events.ability_used, `hit`: the player's hits), `on` (any / dummy / enemy), `near` | `count` matches |
| `discover` | `poi` | `GameState.discover_poi` (also when already discovered) |
| `interact` | `key`, `count`, `props` | `Quests.report(&"interact", key)` (quest props do this) |
| `escort` | `npc`, `to` (spec), `radius` | the NPC (following the player) reaches the destination |
| `challenge` | `challenge` (BendingChallenge spec), `npc` (started from dialogue) or `at` + `radius` (starts when the player arrives) | the challenge succeeds |

Target specs (`QuestTargets.resolve`): `{"poi": id}`, `{"npc": id}`, `{"anchor": {settlement, kind,
tags, index}}`, `{"site": id}`, `{"spawn": element}`, `{"port": id}`, `{"city": id}`,
`{"village": id}`, `{"pos": Vector3}`, plus `"offset"` and `"ground": true`. Anchors are matched by
settlement + kind + tags, never by numeric anchor id (those shift when a planner changes).

### State and persistence

Everything lives in `GameState.quests` (saved by SaveSystem with no extra code):

```
GameState.quests["wt_first_form"] = {"state": "active" | "completed" | "failed", "stage": 1,
	"objectives": {"posts": 1}, "log": [0, 1], "started": play_time, "completed": play_time,
	"taken": {"orders": [0]}}           # quest props already picked up
```

### HUD provider and compass

The quests hook calls `scene.set_quest_provider(Quests)`; `get_quest_display(id)` returns
`{id, title, objectives: [{text, done, count, target}], target}` where `target` is the first
unfinished objective's world position (NPC, POI, site, destination, nearest untaken prop) - the
HUD compass marks it with the distance.

### Journal API (for the journal UI)

`Quests.journal(filter)` returns active quests first (tracked, then main, then by start time),
then completed / failed ones (most recent first). Each entry (`journal_entry(id)`):

```
{id, title, kind, nation, state, tracked, summary, description, location, giver, giver_name,
 stage, stages: [{id, text, current, done, objectives: [{id, text, done, count, target, optional}]}],
 log: [stage texts reached], rewards, rewards_text, started, completed, target (Vector3 or INF)}
```

Only reached stages are listed (no spoilers). `Quests.track(id)` and `Quests.abandon(id)` (side
quests only) are the journal's actions; `quest_changed` tells it to refresh.

### Conditions (`QuestConditions.check`)

Used by `requires`, `auto_start`, dialogue `if` / `branch`, NPC `talk` selection and `present`.
A Dictionary whose keys must all hold: `quest: [id, none|active|completed|available|started|
not_completed|failed]`, `objective: [q, o]` (active, not done), `objective_done`, `stage: [q, n]`,
`flag` / `no_flag`, `element` (id or list), `item: [id, n]`, `currency`, `level`, `unlocked`,
`hour: [from, to]` (wraps midnight), `not`, `any`, `all`.

### Actions (`QuestActions`)

`["start_quest", id]`, `["complete_objective", q, o]`, `["give_item", id, n]`, `["take_item", id,
n]`, `["currency", n]` (negative pays), `["xp", n]`, `["flag", name, value]`, `["unlock",
[candidates]]`, `["skill_point", n]`, `["heal"]`, `["notify", text, kind]`, `["track", q]`, and the
UI actions that run after the conversation closes: `["shop", shop_id]`, `["train"]`,
`["travel", target spec, text]` (TravelSystem fast travel), `["challenge", q, o]`.

### Rewards and techniques

`QuestRewards.grant` gives XP, coins, items and skill points, and for `techniques` unlocks +
equips the first candidate that `AbilityRegistry` knows, that matches the player's element and is
not learned yet, then reloads the player's technique slots. When none of the candidates exists in
the build, the player gets a skill point instead (toast says so) - a reward is never lost. The
opening chains list the ids from GAME_DESIGN §4 (`water_surge`, `ice_wall`, `healing_waters`,
`earth_pillar`, `earth_stomp`, `fire_burst`, `fire_ring`, `jet_step`, `air_push`, `air_scooter`...).

## NPCs

### Streaming and budgets

```
Settlements anchors ──(main thread, once)──> NpcProvider index (64 m cells, crowd anchor kinds)
   WorldContent worker: NpcCrowd.records_for(cell anchors, density, claimed) ─> spawn records
   cell instantiation ─> NpcDirector.add_records(coord) ;  cell release ─> remove_records(coord)
NpcRegistry (named NPCs, placements) ───────────────────────────────┐
NpcDirector (4 Hz): present by schedule / `present` condition, ranked by distance (named first),
   keeps the nearest `max_npcs` within `crowd_range`, spawns 1 per frame, despawns with 14 m hysteresis
   (fading out within 45 m), nearest `tier_a` (< 40 m) get the full tier
```

| `NpcDirector.BUDGETS` (Settings.detail_level) | low / mobile | medium | high | ultra |
| --- | --- | --- | --- | --- |
| `max_npcs` (crowd + named) | 10 | 18 | 28 | 40 |
| `crowd_range` / `named_range` | 55 / 70 m | 66 / 90 m | 80 / 110 m | 100 / 130 m |
| full tier (`tier_a`) | 4 | 7 | 10 | 14 |
| anchor density | 0.85 | 0.9 | 1.0 | 1.25 |

The cap (`max_npcs`, `tier_a`) is what costs frames; density and range only decide who fills
it, so the low preset keeps a nearly full anchor density (a sparse plaza on phones read as a dead
city in the mobile playtest) and stays strictly within 10 NPCs.

* **Full tier** (near): `move_and_slide` with gravity, whisker steering, footsteps (snow trails,
  sounds), talk prompt. **Light tier**: kinematic stepping, a throttled ground probe, no
  footsteps; HumanoidRig auto-LOD does the rest (LOD 2-3 far / off-screen, 160 m fade).
* **Mesh variants are bounded**: `NpcLooks.crowd_look` picks presets / bodies / seeds from small
  sets (~20-25 variants per nation, CharacterMeshBuilder caches them); the home nation's variants
  are pre-built one per frame during loading (`NpcDirector.prewarm`), and spawns that need a new
  variant are spaced `variant_gap` (0.35 s) apart.
* Spawn records: `{key, named, settlement, nation, role, kind, pos, yaw, home, route, loop, look,
  hash, offset, tags, goods, interior, pair, wander}`.

### Roles, outfits and routines

| anchor kind | role | look (per nation) |
| --- | --- | --- |
| `home` (each resident of `capacity`) | resident: wander / stroll near the door, home at night | villager / nation preset; Air: monks |
| `market_stall` | merchant behind the counter, calls out goods; often a customer (`shopper`) milling about the stall in market hours | water_tribe / merchant (Fire: red robe); customers as residents |
| `guard_post`, `patrol`, gatekeepers | guard (post, stance, lantern at night) / patrol (route) | water_warrior, earth_soldier, fire_soldier; Air: monks with staffs |
| `worker`, `fisher`, `gardener` | work clips with props: hammer, carry + basket (docks, tea), sweep (salt pans, gardens), fish + rod | villagers |
| `child_play` | two kids running and cheering | children |
| `idle` | a pair talking face to face, sitters on benches, meditating monks | villagers / monks |
| `student`, `healer`, `trainer`, `quest_giver` | students run katas (combo clips in the nation style), elders, nobles | per role |

`NpcRoutines.SCHEDULES` gives each role its day (merchants 6:50-19:40, workers with a midday
break, kids 8:00-18:30, monks meditate at dawn, noon and dusk, guards and patrols always); each
record has a personal offset (±25 min) so streets empty gradually. At dusk an NPC walks to its
door and fades (sleeping indoors); at night only guards (with lanterns) and patrols walk.

### Behaviour (`NpcBrain`, 5 Hz)

Station activities (stand, guard, work, sit, talk, meditate, fish, train), patrol routes,
wander / stroll (random points validated with `NpcSteering.walkable`: no wall at knee / chest
height, floor within 1.2 m), kids' play, look-at the player within 4.5 m, fidgets. Reactions on
top, all timed: **flee + cower** (combat hits within 20 m, an enemy engaging nearby, bending
during combat), **watch** (guards, named NPCs, wary folk), **cheer** (kids and idlers when the
player trains: hits on training posts / sparring partners, bending out of combat),
**converse** (the player talks to them), **follow** (escort objectives), **go_home**.

Steering: whisker rays (0.2 s cache) push away from walls, separation from nearby NPCs, a berth
around the player (sidestep, wait when the player stands in the way). NPC bodies are on
`Layers.NPC` (the player cannot walk through them); NPCs are not damageable and not lockable.
An NPC turns see-through while the camera is inside / right behind it, and its marker and name
plate fade out near the camera.

**Facing.** Settlement plans do not all agree on which way an anchor yaw faces (the Water Tribe
interiors treat local +Z as forward, the contract says -Z), so a named or indoor NPC whose facing
runs into a wall within 4 m while its back is open turns around once (home + facing) as soon as
the ground collision under it exists (`NpcCharacter.ensure_open_facing`). Bending challenges
likewise raise their posts / partner in the most open of eight directions when the player's
facing has less than 6.5 m of floor.

**Escorts** follow the player (brisk walk, run when > 8 m behind, wait and call out beyond 45 m);
a follower that makes no progress for 4 s while 6-45 m behind (a wall, a ledge, a crowd) catches
up out of the camera's view (`NpcBrain._catch_up`, `NpcCharacter.warp`), so an escort can never
get stuck.

**Faction awareness** (`NpcBarks.attitude`): own nation `own`, Air Nomads friendly to all, the
Fire Nation and the other nations `wary` of each other: wary folk watch and mutter when the
player bends, greetings change ("A long way from home, stranger").

**Barks** (`data/dialogue/ambient.gd`): greetings when the player passes (45 s per NPC, global
cooldown), merchants calling their goods, flee / cheer / guard lines, night lines; floating
Label3D (subtitles setting), hidden during conversations.

### Named NPCs (`data/dialogue/npcs_*.gd`)

```gdscript
&"wt_siku": {
	"name": "Master Siku", "title": "Waterbending Master", "nation": &"water", "role": &"trainer",
	"look": {HumanoidRig config},
	"place": {"anchor": {"settlement": NWT, "kind": &"trainer", "tags": ["training_hall"]}},
	#   or {"spawn": &"water", "local": Vector3(...)}  /  {"poi": ..., "offset": ..., "ground": true, "face": spec}
	"idle": &"stand", "props": [...], "barks": ["..."], "shop": &"nwt_healer",
	"present": {condition},                 # e.g. only while a quest is active
	"trainer": {"element": &"water", "menu": "...", "lesson_lines": [...], "praise": [...], "fail": [...], "spar": "..."},
	"talk": [{"if": {condition}, "tree": &"siku_posts"}, ..., {"tree": &"siku_default"}],   # first match wins
}
```

Named NPCs always outrank the crowd in the budget and claim their anchors (the crowd leaves
them free). `NpcMarker` floats above them: a gold seal when they offer a quest, a pale diamond
when an active objective needs them, the element emblem for masters with a lesson ready, a pin for
merchants; their name and title fade in within 11 m.

## Dialogue

Trees (`TREES` in the same files) - see `DialogueTree` for the node keys:

```gdscript
&"siku_posts": {"nodes": {
	"start": {"text": "Six clean strikes on the posts. Ready?", "choices": [
		{"text": "Raise the posts.", "do": [["challenge", &"wt_first_form", &"posts"]], "next": "go"},
		{"text": "Give me a moment.", "next": "wait", "if": {condition}}]},
	"go": {"text": ["Variant A", "Variant B"], "end": true},
	"route": {"branch": [{"if": {...}, "next": "a"}, {"next": "b"}]},
	"wait": {"lines": ["First.", "Second."], "speaker": "...", "emote": &"bow", "do": [actions], "end": true}}}
```

`DialogueRunner.talk(npc)` (the NPC's talk prompt) holds the player in the Cinematic state, faces
both, frames an over-the-shoulder two-shot with `PlayerCamera.set_mode(&"cinematic")` (pulled in
when a wall is in the way; the left shoulder or a higher, tighter angle when a companion or a
passer-by stands in the spot, re-checked every line; the NPC sits in the upper half, clear of the
panel), shows lines on the
scene's `DialogueBox` (typewriter, mouth flaps while revealing), runs node / choice actions, then
reports the talk to the quests and runs the UI actions. `{player}`, `{element}`, `{bender}`,
`{nation}` are filled in. Unnamed townsfolk answer with a line of small talk (by nation and role);
stall merchants offer their wares. Every wait times out (90 s per line / choice: last option), B /
Esc on a choice picks the last option, so a conversation can never trap the player.

## Trainers

Masters (`"role": &"trainer"` + `trainer` block): Master Siku (Water Tribe training hall), Master
Bao Shan (Ba Sing Se training hall), Master Jinzo (Flame Kata Grounds), Master Tashi (Air Temple
sanctum). "Train me" opens `TrainerLessons.open`: one entry per technique of the master's element
whose `AbilityDef.unlock` names a trainer (any trainer id: the element modules own those ids),
the player meets `level` / `prerequisite`, and it is not learned; plus a sparring bout and "Not
now". A lesson runs a `BendingChallenge` (`unlock["lesson"]` when the technique supplies one; else
6 hits on training posts, or a sparring bout for signatures / level ≥ 8); passing sets
`trained_<unlock.trainer>_<id>` (the `AbilityRegistry.can_unlock` contract) and unlocks + equips
the technique - the lesson is the price, no skill points. Not ready yet: the master names the
level to come back at.

`BendingChallenge` kinds: `targets` (TrainingDummy posts placed on validated floor in an arc in
front of the player; hits with the right slot / ability count; wrong moves flash red) and `spar`
(a sparring partner: runtime archetypes `spar_water/earth/fire/air`, copies of the element
benders in nation clothes, no XP or loot, they yield at 30 % health; the master stops the bout
below 20 % player health). Fails on time out, death or walking 35 m away. `ChallengeHud` shows the
title, progress, a draining timer and the result.

## Merchants

* `TradeGoods.ITEMS` - every item id: herbs (heal), food, drink (chi), supplies, crafted goods,
  trinkets, materials (enemy loot, quarry pickups), quest items (not sellable). Values in copper
  coins (`GameState.currency`); `use` effects for consumables.
* `MerchantStock.SHOPS` - named shops (healer, outfitter, tea house, herbalist, apothecary,
  jeweller, temple kitchen, novices' crafts); every market-stall NPC sells its anchor's goods for
  its nation (`STALLS`: fish, pottery, furs, trinkets, vegetables, cloth, tea, spices...). Foreign
  goods cost 30 % more, merchants buy anything sellable at 45 % of value, limited stock restocks
  each game day (`world_flags["shops"]`).
* `ShopPanel` (CanvasLayer 45): BUY / SELL tabs over the blurred game, rows with the vector item
  icon, name, description, owned / left, price with a square-holed coin, BUY / SELL button; the
  purse; status line (not enough coins shakes the purse). Mouse, keyboard / controller (focus,
  Q / E tabs, Esc / B closes), touch (88 px rows when touch controls are on).

## Wildlife

`WildlifeProvider` (128 m cells, worker): per cell at most one herd per species where its rule
fits (biome, region, coast / lake / road, slope, outside towns, away from beast dens) and a bird
flock (gulls on coasts, hawks over mountains and the Air Temple, crows over fields and towns);
resting sky bison in the Air Temple's bison stalls. `WildlifeDirector` keeps the nearest herds
within budget, one animal per frame:

| species | where | behaviour |
| --- | --- | --- |
| otter penguin | arctic shores, snow / ice / beach in the Water Tribe and the wilds | waddle, preen, belly-slide away on snow |
| turtle duck | lakes, ponds and canals outside the cities (swimming) | paddle, preen, quack and paddle off |
| ostrich horse | Earth Kingdom grassland and fields beside the roads | graze, look around, gallop off |
| komodo rhino | Fire Nation grassland / volcanic fields, ≥ 260 m from the beast dens | graze, lumber away |
| sky bison | Air Temple stalls | lie in the stall, look at the player |

| `WildlifeDirector.BUDGETS` | low | medium | high | ultra |
| --- | --- | --- | --- | --- |
| animals / range | 5 / 70 m | 9 / 100 m | 14 / 140 m | 20 / 180 m |
| flocks / resting bison | 1 / 1 | 2 / 2 | 3 / 2 | 4 / 3 |

Animals flee from the player (species radius) and from combat or bending nearby; flocks startle
when the player runs at them. Medium and large animals carry a kinematic capsule on `Layers.NPC`.

## Content

| Nation | Opening chain (auto-starts on a new game) | Side quests | Master / merchants |
| --- | --- | --- | --- |
| Water | Born of the Tide (Elder Anaaya at the arrival, the training hall) -> The First Form (posts) -> Smoke on the Horizon (Chief Tulok, the Fire Navy Landing, the orders chest) -> Moon and Ocean (Princess Naalu, the koi pond, back to Siku: technique) | The Healer's Moss (Ice Flats pickups), Tangled Nets (harbour piers), Light for the Pale Moon (shrine), Trial on the Ice Flats (spar at the POI) | Siku; Healer Yara (shop + heal), Harbourmaster Oki (outfitter) |
| Earth | Stone Beneath the Sky (Guide Lin at the overlook) -> Rooted (posts) -> Smoke Beyond the Wall (Captain Jin, the Fire Nation Scout Camp) -> The Listening Earth (spar at Stonefist Training Yard: technique) | Lost in the Millet (escort Little Mei home), Mail for Omashu (deliver + discover the chutes), Jade for the Herbalist (Jade Quarry pickups) | Bao Shan; Tea Master Hu, Herbalist Wen |
| Fire | A Spark Returns (Envoy Kaida, the Flame Kata Grounds) -> Breath of Fire (posts) -> Smoke over the Cove (Captain Rina, Smugglers' Cove, the stolen crate) -> The Sun's Teaching (Sage Mirei, Shrine of the Eternal Flame: technique) | The Overgrown Sun Temple (ruin + ember stone), Kata Under the Sun (technique challenge), Komodo Trouble (Cinder Flats den) | Jinzo; Apothecary Suda, Jeweller Ashi |
| Air | The First Breath (Brother Pasang, the sanctum) -> Leaves on the Wind (posts) -> Shadow at the Gate (Brother Sonam, bison ride down, the Fire Nation scouting party) -> The Wind Remembers (Abbot Dorje, the Meditation Ledge: technique) | The Novice's Glider, Airball Champion (challenge), The Whistling Caves | Tashi, Sister Nima; Elder Yeshe (kitchen), Keeper Lhamo (crafts) |
| Travel | Letters Across the Strait (Water -> Northreach), White Dragon Tea (Ba Sing Se -> Air Temple), A Captain's Apology (Crimson Harbor -> Water Tribe), A Letter to the Sun (Air Temple -> Fire Nation capital); harbourmasters at Full Moon Bay and Crimson Harbor explain the ferry routes | | |

All writing is original. Every quest is reachable (auto-start, chain `next` or a `start_quest`
in a tree - tested), every NPC place and objective target resolves in the baked world (tested).

## Decisions

* **Anchors by query, not id.** Named NPCs and targets find anchors by settlement + kind + tags
  (+ index): stable across planner changes that renumber anchor ids.
* **Provider for data, director for nodes.** WorldContent streams crowd *records* on workers
  (cheap, deterministic, cleaned up with the cells); one director owns the actual NPC nodes so the
  budget is global and strict, named NPCs always win, and spawns are time-sliced.
* **No navmesh.** NPCs walk only where they verified a straight path (rays + floor probe) or on the
  planners' patrol routes; otherwise they idle at their anchors. Steering handles people.
* **Talk objectives complete at the end of a conversation** with that NPC; trees branch on the
  objective (`{"objective": [q, o]}`), so the right conversation is always picked.
* **Technique rewards are candidate lists** resolved against the registry at grant time, so quest
  data does not hard-depend on the element modules (skill point fallback).
* **Training is the price** of a trainer technique (no skill points); the registry flag is set for
  whatever trainer id the ability names.
* **Shops do not pause the game** (the pause menu owns pausing); the player is held in the
  Cinematic state (refreshed every 30 s) and the shop closes with Esc / B / CLOSE.

## Verification

* `tools/test.sh quests_npcs` - 24 unit tests + 1 integration test: quest state machine, stage
  actions, chains, rewards (XP / coins / items / technique candidates + skill point fallback),
  every objective type (go_to poll, talk, collect, use_ability use + hit filters, discover,
  interact, defeat counting each enemy once by site / faction), persistence through JSON and
  save / load, HUD display, journal, tracking, NPC markers, conditions, actions, data validation
  (ids, references, reachability, items, per-nation chains with a trainer, an encounter, a place and
  a technique reward, side + travel quests, a master per nation), world resolution of every NPC
  place / target / prop / POI / site, NPC budgets, crowd records (deterministic, claims, density,
  bounded variants), routines and attitudes, the director (nearest within budget, full tier cap,
  despawn), named NPC presence + marker, flee -> cower -> recover, merchants (buy / afford / sold
  out / restock / sell / quest items), trainers (gates, flags, unlock, spar archetypes), the
  dialogue runner (conditions, choices, actions, branch, placeholders), escorts (follow, catch up
  when stuck behind a wall, report on arrival), market customers, the hand-placed oasis spots
  staying on the baked lawn, and wildlife rules; the
  integration test boots the real world scene (Water), checks the hooks, the auto-started quest
  on the HUD, Elder Anaaya by the spawn, a real conversation advancing the quest, the compass
  target, and save / load.
* Playtests: see "Playtest results" below.

### Playtest results

All runs through the real world scene (`res://scenes/world/world.tscn`, new game, software
Vulkan / llvmpipe under Xvfb), inputs through the InputMap; long trips use the game's own fast
travel (`TravelSystem.travel_to`).

* **`quests_npcs_water_chain`** (1280x720, ~50 min wall clock on llvmpipe): Born of the Tide
  auto-starts on arrival (tracker + compass) -> Elder Anaaya at the spawn (6 lines, choice) ->
  fast travel to the training hall door, walk in through the gate past the pillars and the
  students, up the dais steps -> Master Siku (quest complete, The First Form starts) -> "Raise the
  posts": 3 posts in the open room, 6 hits with real light-attack Water Whip input -> report
  (waterskin) -> Chief Tulok in the palace -> fast travel east -> the Fire Navy Landing found
  (go_to) -> the camp fought for real (3 scouts driven off, ~33 s) -> the officer's chest prop
  ("Sealed Navy Orders") -> Chief Tulok -> Princess Naalu by the koi pond (Tui and La circling
  behind her) -> the pond prop ("Water of the Oasis") -> Siku: **Moon and Ocean complete, the Water
  opening chain done** (reward: a skill point, see Known issues) -> a trainer lesson ("Train me" ->
  lesson menu -> posts challenge -> technique unlocked and equipped) -> Healer Yara's shop (BUY
  with ui_accept: Wild Herbs, coins 160 -> 155; SELL tab; Esc closes; player free again).
* **`quests_npcs_city`** per home city (960x540, 11:00): townsfolk around the spawn (live within
  the budget of 28 on the desktop preset) - Water 19 (98 records in range), Earth 19 (91), Fire 24
  (84), Air 17 (55); the opening quest started and its giver spawned in every city (Elder Anaaya,
  Guide Lin, Envoy Kaida, Brother Pasang), a real conversation with each; then fast travel to the
  nearest market stall / guard post / kids' play spot: people at each (Water 6 / 3 / 2, Earth 6 /
  2 / 5, Fire 3 / 1 / 8, Air: kids' court 9; the Air Temple has no stalls or guard posts).
* **Mobile** (`RENDERER=mobile MOBILE=1`, low preset, budget 10): touch HUD + dialogue + trade
  panel work; the spawn plaza first showed only 2 townsfolk (density 0.55 / 45 m), so the low
  preset now keeps a near-full anchor density inside the same 10-NPC cap (re-run: 9 townsfolk
  around the spawn, 6 at the market stall, 3 at the guard post, 2 at the kids' spot, never more
  than 10 live).
* **`quests_npcs_wildlife`** (960x540): a herd of each species found by the provider's own rules,
  spawned when the player arrives, and each fled from a sprinting player: otter penguins on the
  arctic shore, ostrich horses beside an Earth Kingdom road, a komodo rhino on Fire Nation
  grassland, turtle ducks on Moonmirror Lake, resting sky bison in the Air Temple stalls.

Found through the screenshots and fixed: NPCs facing the wall in the Water Tribe interiors (the
plan's anchor yaw convention) and the chain teleporting the player behind the hall's back wall;
challenge posts spawned into the wall behind the master; huge marker / name plates when the camera
passed close to an NPC; barks overlapping name plates; the conversation camera inside the polar
bear dog (now steps to the other shoulder / a higher angle and re-checks every line); the trainer
menu opening invisible (DialogueBox closing fade race, waited out by the runner); Princess Naalu
waiting outside the oasis wall instead of by the pond; quest props out of walking reach; a sparse
plaza on the mobile preset; empty-looking markets (customers added).

## Changes outside the module

* `project.godot`: autoload `Quests="*res://src/quests/quest_system.gd"` (added after Router).
* `tests/integration/test_quests_npcs_world.gd` (new file, additive).
* No other module's files were edited. Worked around in this module instead: the Water Tribe
  interior anchors' yaw convention (`NpcCharacter.ensure_open_facing`) and the DialogueBox
  close / open fade race (`DialogueRunner._settle_box`).

## Known issues / next steps

* **Technique rewards on this branch are skill points.** The opening chains and trainers name
  technique candidates (`water_surge`, `ice_wall`, `earth_pillar`, `fire_burst`, `air_push`...);
  the element modules that register those lockable techniques are separate wave-3 branches, so
  here `QuestRewards` grants its fallback skill point (toast says so), and the chain playtest's
  trainer lesson uses a clearly named stand-in AbilityDef it registers itself ("Lesson Stand-in
  (Ice Shards)") to exercise the lesson -> unlock -> equip flow. After the merge the candidate
  ids must match the element modules' ids (the lists are data in `data/quests/*.gd`).
* Only the Water opening chain is played end to end in the world; the Earth, Fire and Air chains
  are covered by the data / reachability / world-resolution tests and an in-world check of their
  first quest and giver, not a full scripted run.
* **No navmesh**: crowd NPCs walk only straight lines they verified (rays + floor probe) or the
  planners' routes; in tight interiors they mostly hold their spots. A stuck escort catches up out
  of the camera's view rather than path-finding round the obstacle.
* The gameplay camera (player module) does not avoid NPCs; NPCs turn see-through when the camera
  is inside / right behind them instead.
* The Water Tribe plan's interior anchors face local +Z (the anchor contract says -Z); this module
  turns indoor / named NPCs to the open side at runtime. The source fix belongs to settlements_wa.
* `DialogueBox.close()` hides the box 0.15 s later even if `open()` ran meanwhile (UI module);
  the runner waits the fade out, a fix in `DialogueBox.open()` (kill the close tween) would be
  cleaner.
* `WorldData.get_water_height` tests lakes by radius while the lake surface follows its polygon
  (a companion swam where it reported dry ground); turtle duck herds spawn by the former.
* Crowd variety is bounded (~20-25 mesh variants per nation), so outfits repeat in a busy street;
  no voiced lines (text barks and dialogue only); shops do not pause the game.
* No dedicated frame-time measurement for the crowds; the strict per-preset caps (10 / 18 / 28 /
  40 NPCs, 4 / 7 / 10 / 14 in the full tier, one spawn per frame) bound the cost.
