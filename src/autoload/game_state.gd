extends Node
## The player's persistent adventure state (autoload "GameState").
##
## Pure data + small helpers. Everything here is serialized by SaveSystem via
## to_dict()/from_dict(). Live scene objects (player, companion) write their
## transient state back here in `write_save_state()` (group &"persist").

const SAVE_VERSION := 1
const MAX_LEVEL := 30
const ABILITY_SLOTS := 4

var element: int = ElementDefs.Element.NONE
var player_name: String = "Wanderer"
var level: int = 1
var xp: int = 0
var skill_points: int = 0
## Ability ids (StringName) the player has learned.
var unlocked_abilities: Array[StringName] = []
## Ability ids equipped into the 4 technique slots ("" = empty).
var equipped_abilities: Array[StringName] = [&"", &"", &"", &""]
var inventory: Dictionary = {}          # item_id(String) -> count(int)
var currency: int = 0
## quest_id(String) -> {"state": "active"/"completed"/"failed", "objectives": {obj_id: progress}, "stage": int}
var quests: Dictionary = {}
var tracked_quest: StringName = &""
var discovered_pois: Dictionary = {}    # poi_id(String) -> true
var world_flags: Dictionary = {}        # arbitrary persistent flags
var stats: Dictionary = {}              # counters: enemies_defeated, abilities_used, ...
## Practice per ability (uses that landed) — drives mastery/unlocks.
var ability_practice: Dictionary = {}
var companion: Dictionary = {"type": "", "name": "", "bond": 0, "health_ratio": 1.0, "unlocked": true}
var player_position: Vector3 = Vector3.INF
var player_yaw: float = 0.0
var player_health_ratio: float = 1.0
var region: StringName = &""
var time_of_day: float = 9.0
var play_time: float = 0.0
## True while inside the tutorial (nothing is saved).
var is_tutorial: bool = false
## True after the arrival cinematic has been seen for this save.
var intro_done: bool = false


func _process(delta: float) -> void:
	if element != ElementDefs.Element.NONE and not get_tree().paused:
		play_time += delta


func reset() -> void:
	element = ElementDefs.Element.NONE
	player_name = "Wanderer"
	level = 1
	xp = 0
	skill_points = 0
	unlocked_abilities = []
	equipped_abilities = [&"", &"", &"", &""]
	inventory = {}
	currency = 0
	quests = {}
	tracked_quest = &""
	discovered_pois = {}
	world_flags = {}
	stats = {}
	ability_practice = {}
	companion = {"type": "", "name": "", "bond": 0, "health_ratio": 1.0, "unlocked": true}
	player_position = Vector3.INF
	player_yaw = 0.0
	player_health_ratio = 1.0
	region = &""
	time_of_day = 9.0
	play_time = 0.0
	is_tutorial = false
	intro_done = false


## Starts a fresh adventure. Starter abilities are granted by the bending module
## (BendingRegistry.starter_abilities) when the player spawns if none are unlocked.
func new_game(p_element: int, tutorial: bool = false) -> void:
	reset()
	element = p_element
	is_tutorial = tutorial
	var data := ElementDefs.get_data(p_element)
	companion["type"] = String(data.get("companion", ""))
	companion["name"] = String(data.get("companion_name", ""))
	region = data.get("home_region", &"")


func has_element() -> bool:
	return ElementDefs.is_valid(element)


# --- Progression ------------------------------------------------------------------

static func xp_for_level(lvl: int) -> int:
	return int(120.0 * pow(float(lvl), 1.45))


func add_xp(amount: int, reason: String = "") -> void:
	if amount <= 0 or level >= MAX_LEVEL:
		return
	xp += amount
	Events.xp_gained.emit(amount, reason)
	while level < MAX_LEVEL and xp >= xp_for_level(level):
		xp -= xp_for_level(level)
		level += 1
		skill_points += 1
		# One presentation per level-up: the progression LevelUpBanner (world), or the HUD's
		# toast where no banner exists (HUD._on_level_up). No toast from here.
		Events.player_level_up.emit(level)


func is_unlocked(ability_id: StringName) -> bool:
	return unlocked_abilities.has(ability_id)


func unlock_ability(ability_id: StringName, auto_equip: bool = true) -> void:
	if unlocked_abilities.has(ability_id):
		return
	unlocked_abilities.append(ability_id)
	Events.ability_unlocked.emit(ability_id)
	if auto_equip:
		var free := equipped_abilities.find(&"")
		if free != -1:
			equipped_abilities[free] = ability_id
			Events.abilities_equipped_changed.emit()


func equip_ability(slot: int, ability_id: StringName) -> void:
	if slot < 0 or slot >= ABILITY_SLOTS:
		return
	var existing := equipped_abilities.find(ability_id)
	if existing != -1 and ability_id != &"":
		equipped_abilities[existing] = equipped_abilities[slot]
	equipped_abilities[slot] = ability_id
	Events.abilities_equipped_changed.emit()


func add_practice(ability_id: StringName, amount: int = 1) -> void:
	ability_practice[String(ability_id)] = int(ability_practice.get(String(ability_id), 0)) + amount


func add_item(item_id: StringName, count: int = 1) -> void:
	var key := String(item_id)
	inventory[key] = int(inventory.get(key, 0)) + count
	if inventory[key] <= 0:
		inventory.erase(key)
	if count > 0:
		Events.item_collected.emit(item_id, count)


func item_count(item_id: StringName) -> int:
	return int(inventory.get(String(item_id), 0))


func incr_stat(stat: String, amount: int = 1) -> void:
	stats[stat] = int(stats.get(stat, 0)) + amount


func set_flag(flag: String, value: Variant = true) -> void:
	world_flags[flag] = value


func get_flag(flag: String, fallback: Variant = false) -> Variant:
	return world_flags.get(flag, fallback)


func discover_poi(poi_id: StringName) -> bool:
	if discovered_pois.has(String(poi_id)):
		return false
	discovered_pois[String(poi_id)] = true
	Events.poi_discovered.emit(poi_id)
	return true


# --- Serialization ------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"element": element,
		"player_name": player_name,
		"level": level,
		"xp": xp,
		"skill_points": skill_points,
		"unlocked_abilities": unlocked_abilities.map(func(a: StringName) -> String: return String(a)),
		"equipped_abilities": equipped_abilities.map(func(a: StringName) -> String: return String(a)),
		"inventory": inventory.duplicate(true),
		"currency": currency,
		"quests": quests.duplicate(true),
		"tracked_quest": String(tracked_quest),
		"discovered_pois": discovered_pois.duplicate(true),
		"world_flags": world_flags.duplicate(true),
		"stats": stats.duplicate(true),
		"ability_practice": ability_practice.duplicate(true),
		"companion": companion.duplicate(true),
		"player_position": [player_position.x, player_position.y, player_position.z] if player_position.is_finite() else null,
		"player_yaw": player_yaw,
		"player_health_ratio": player_health_ratio,
		"region": String(region),
		"time_of_day": time_of_day,
		"play_time": play_time,
		"intro_done": intro_done,
	}


## Loads from a dict, tolerating missing keys, older versions and damaged values: a field of the
## wrong type (JSON writes a NaN as null, a hand-edited file...) falls back to its default instead
## of aborting the load with a script error - one bad number no longer makes a journey unloadable
## (wave 4 bug hunt, docs/qa/bughunt_world.md).
func from_dict(d: Dictionary) -> bool:
	reset()
	var e := int(_num(d.get("element"), ElementDefs.Element.NONE))
	if not ElementDefs.is_valid(e):
		return false
	element = e
	player_name = String(d.get("player_name", player_name)) if d.get("player_name") is String else player_name
	level = clampi(int(_num(d.get("level"), 1)), 1, MAX_LEVEL)
	xp = maxi(0, int(_num(d.get("xp"), 0)))
	skill_points = maxi(0, int(_num(d.get("skill_points"), 0)))
	unlocked_abilities.clear()
	for a: Variant in _arr(d.get("unlocked_abilities")):
		if a is String or a is StringName:
			unlocked_abilities.append(StringName(str(a)))
	var eq := _arr(d.get("equipped_abilities"))
	for i in ABILITY_SLOTS:
		equipped_abilities[i] = StringName(str(eq[i])) if i < eq.size() and (eq[i] is String or eq[i] is StringName) else &""
	inventory = _ints(_dict(d.get("inventory")))
	currency = maxi(0, int(_num(d.get("currency"), 0)))
	quests = _dict(d.get("quests"))
	for q: Variant in quests:
		var rec: Variant = quests[q]
		if rec is Dictionary:
			# "taken": the quest props already picked up (QuestProps.is_taken looks them up by int)
			for key: String in ["stage", "log", "objectives", "taken"]:
				if (rec as Dictionary).has(key):
					rec[key] = _ints(rec[key])
	tracked_quest = StringName(str(d.get("tracked_quest", ""))) if d.get("tracked_quest") is String else &""
	discovered_pois = _dict(d.get("discovered_pois"))
	world_flags = _dict(d.get("world_flags"))
	stats = _ints(_dict(d.get("stats")))
	ability_practice = _ints(_dict(d.get("ability_practice")))
	var comp := _dict(d.get("companion"))
	for k: String in comp:
		if comp[k] != null:
			companion[k] = comp[k]
	companion["bond"] = int(_num(_ints(companion.get("bond", 0)), 0))
	companion["health_ratio"] = clampf(_num(companion.get("health_ratio"), 1.0), 0.0, 1.0)
	if not (companion.get("type") is String) or companion.get("type", "") == "":
		companion["type"] = String(ElementDefs.get_data(element).get("companion", ""))
	var p: Variant = d.get("player_position")
	if p is Array and (p as Array).size() == 3:
		var v := Vector3(_num(p[0], INF), _num(p[1], INF), _num(p[2], INF))
		if v.is_finite():
			player_position = v
	player_yaw = _num(d.get("player_yaw"), 0.0)
	player_health_ratio = clampf(_num(d.get("player_health_ratio"), 1.0), 0.05, 1.0)
	region = StringName(str(d.get("region", ""))) if d.get("region") is String else &""
	time_of_day = fposmod(_num(d.get("time_of_day"), 9.0), 24.0)
	play_time = maxf(0.0, _num(d.get("play_time"), 0.0))
	intro_done = bool(d.get("intro_done")) if d.get("intro_done") is bool else true
	return true


static func _dict(v: Variant) -> Dictionary:
	return (v as Dictionary).duplicate(true) if v is Dictionary else {}


static func _arr(v: Variant) -> Array:
	return v if v is Array else []


## A finite number from a save field, else `fallback` (JSON null from a NaN, strings, objects).
static func _num(v: Variant, fallback: float) -> float:
	if (v is float or v is int) and is_finite(float(v)):
		return float(v)
	return fallback


## JSON has one number type: a save brings every count back as a float (2 -> 2.0). Whole
## numbers in the integer-valued records (inventory, stats, practice, quest stages / logs /
## objective progress) are turned back into ints, so `[0, 1].has(1)` style lookups and
## printed counts behave exactly as before the save (Array.has(1) is false for [1.0]).
static func _ints(v: Variant) -> Variant:
	if v is float and is_finite(v) and float(v) == floorf(v) and absf(v) < 9.0e15:
		return int(v)
	if v is Array:
		var a: Array = (v as Array).duplicate()
		for i in a.size():
			a[i] = _ints(a[i])
		return a
	if v is Dictionary:
		var d: Dictionary = (v as Dictionary).duplicate()
		for k: Variant in d:
			d[k] = _ints(d[k])
		return d
	return v
