class_name NpcBarks
extends RefCounted
## Ambient writing lookups (data/dialogue/ambient.gd): barks by nation and situation, small talk
## by nation and role, the nations' attitude toward the player's element (simple faction
## awareness), and display titles of unnamed townsfolk.

const DATA_PATH := "res://data/dialogue/ambient.gd"

static var _barks: Dictionary = {}
static var _talk: Dictionary = {}
static var _loaded := false


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var s := load(DATA_PATH) as GDScript
	if s == null:
		return
	var c := s.get_script_constant_map()
	_barks = c.get("BARKS", {})
	_talk = c.get("SMALL_TALK", {})


## A bark for `situation` (nation lines first, then the shared ones). "" when none exist.
static func line(nation: StringName, situation: StringName, rng: RandomNumberGenerator = null) -> String:
	_ensure()
	var pool: Array = []
	var n: Dictionary = _barks.get(nation, {})
	pool.append_array(n.get(situation, []))
	if pool.is_empty():
		pool.append_array((_barks.get(&"any", {}) as Dictionary).get(situation, []))
	if pool.is_empty():
		return ""
	var i := rng.randi_range(0, pool.size() - 1) if rng != null else randi() % pool.size()
	return String(pool[i])


## Lines an unnamed NPC may say when the player talks to them (role pool + nation pool).
static func small_talk(nation: StringName, role: StringName) -> Array[String]:
	_ensure()
	var out: Array[String] = []
	var n: Dictionary = _talk.get(nation, {})
	for l: Variant in n.get(role, []):
		out.append(String(l))
	if out.size() < 2:
		for l2: Variant in n.get(&"any", []):
			out.append(String(l2))
	return out


## How a nation's people regard the player's element: &"own", &"friendly" or &"wary".
static func attitude(nation: StringName, player_element: int) -> StringName:
	var pe := ElementDefs.id_of(player_element)
	if pe == nation:
		return &"own"
	if nation == &"air":
		return &"friendly"
	if pe == &"fire" or nation == &"fire":
		return &"wary"
	return &"friendly"


## Greeting situation for this NPC's nation and the player's element.
static func greeting(nation: StringName, player_element: int) -> StringName:
	if NpcRoutines.is_night(GameState.time_of_day):
		return &"night"
	match attitude(nation, player_element):
		&"own":
			return &"greet_own"
		&"wary":
			return &"greet_wary"
	return &"greet"


## What the prompt calls an unnamed NPC ("fishmonger", "guard", "townswoman"...).
static func role_title(role: StringName, nation: StringName, goods: String = "") -> String:
	match role:
		&"merchant":
			if goods == "furs":
				return "Furrier" if nation == &"water" else "Clothier"
			var titles := {"fish": "Fishmonger", "pottery": "Potter", "trinkets": "Trinket Seller", "vegetables": "Greengrocer",
				"cloth": "Clothier", "spices": "Spice Seller", "fireworks": "Fireworks Seller", "tea": "Tea Seller", "fruit": "Fruit Seller",
				"jade": "Jade Carver", "silk": "Silk Merchant", "noodles": "Noodle Seller", "bread": "Baker", "herbs": "Herbalist",
				"cabbages": "Cabbage Seller", "tools": "Toolmaker"}
			return String(titles.get(goods, "Merchant"))
		&"guard", &"patrol":
			return "Monk" if nation == &"air" else "Guard"
		&"child":
			return "Child"
		&"fisher":
			return "Fisher"
		&"worker":
			return "Worker"
		&"gardener":
			return "Gardener"
		&"student":
			return "Novice" if nation == &"air" else "Student"
		&"monk":
			return "Monk"
		&"elder":
			return "Elder"
		&"noble":
			return "Noble"
	return {&"water": "Tribesperson", &"earth": "Citizen", &"fire": "Citizen", &"air": "Monk"}.get(nation, "Villager")
