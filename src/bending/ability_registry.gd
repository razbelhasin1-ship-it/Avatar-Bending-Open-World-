class_name AbilityRegistry
extends RefCounted
## Every bending ability by id and element, the core kit per element, the
## starter set (granted on a new game) and unlock rules for the skill tree.
## Built-in abilities come from the element kits (src/bending/kits/*/*_kit.gd);
## other modules may register more at runtime with register().
##
##   AbilityRegistry.get_def(&"air_sweep")             # AbilityDef or null
##   AbilityRegistry.core_kit(ElementDefs.Element.FIRE)  # {&"light": def, &"heavy": def, ...}
##   AbilityRegistry.starter_techniques(e)               # Array[StringName]
##   AbilityRegistry.grant_starters(e)                   # unlock + equip (new game)
##   AbilityRegistry.can_unlock(id) -> &"" or reason      # level / prerequisite / trainer / quest / practice

const KITS := [
	"res://src/bending/kits/air/air_kit.gd",
	"res://src/bending/kits/earth/earth_kit.gd",
	"res://src/bending/kits/fire/fire_kit.gd",
	"res://src/bending/kits/water/water_kit.gd",
]

static var _defs: Dictionary = {}
static var _loaded := false


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	for path: String in KITS:
		var s := load(path) as GDScript
		if s == null:
			push_error("AbilityRegistry: cannot load kit %s" % path)
			continue
		for d: AbilityDef in s.call(&"defs"):
			register(d)


## Adds (or replaces) an ability definition.
static func register(d: AbilityDef) -> void:
	if d == null or d.id == &"":
		push_warning("AbilityRegistry: refusing a def without id")
		return
	_defs[d.id] = d


static func get_def(id: StringName) -> AbilityDef:
	_ensure()
	return _defs.get(id, null)


static func has(id: StringName) -> bool:
	_ensure()
	return _defs.has(id)


static func all() -> Array[AbilityDef]:
	_ensure()
	var out: Array[AbilityDef] = []
	for id: StringName in _defs:
		out.append(_defs[id])
	return out


static func for_element(e: int) -> Array[AbilityDef]:
	var out: Array[AbilityDef] = []
	for d in all():
		if d.element == e:
			out.append(d)
	return out


## {&"light", &"heavy", &"defense", &"dodge"} -> AbilityDef for the element.
static func core_kit(e: int) -> Dictionary:
	var out := {}
	for d in for_element(e):
		match d.slot:
			AbilityDef.Slot.LIGHT: out[&"light"] = d
			AbilityDef.Slot.HEAVY: out[&"heavy"] = d
			AbilityDef.Slot.DEFENSE: out[&"defense"] = d
			AbilityDef.Slot.DODGE: out[&"dodge"] = d
	return out


## Technique ids granted on a new game (implemented starters only).
static func starter_techniques(e: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for d in for_element(e):
		if d.starter and (d.slot == AbilityDef.Slot.TECHNIQUE or d.slot == AbilityDef.Slot.SIGNATURE) and not d.script_path.is_empty():
			out.append(d.id)
	out.sort()
	return out


## New game: unlocks + equips the element's starters if the player has none of
## this element's techniques yet. Returns the granted ids.
static func grant_starters(e: int) -> Array[StringName]:
	var granted: Array[StringName] = []
	for id: StringName in GameState.unlocked_abilities:
		var d := get_def(id)
		if d != null and d.element == e and d.slot == AbilityDef.Slot.TECHNIQUE:
			return granted
	for id in starter_techniques(e):
		if not GameState.is_unlocked(id):
			GameState.unlock_ability(id, true)
			granted.append(id)
	return granted


## &"" if the ability can be learned now, else the first missing requirement:
## &"unknown", &"unlocked", &"level", &"prerequisite", &"trainer", &"quest", &"practice", &"skill_points".
static func can_unlock(id: StringName) -> StringName:
	var d := get_def(id)
	if d == null:
		return &"unknown"
	if GameState.is_unlocked(id):
		return &"unlocked"
	var u := d.unlock
	if GameState.level < int(u.get("level", 1)):
		return &"level"
	var pre: StringName = StringName(u.get("prerequisite", &""))
	if pre != &"" and not GameState.is_unlocked(pre):
		return &"prerequisite"
	var trainer := String(u.get("trainer", ""))
	if trainer != "" and not bool(GameState.get_flag("trained_" + trainer + "_" + String(id), false)):
		return &"trainer"
	var quest := String(u.get("quest", ""))
	if quest != "" and String((GameState.quests.get(quest, {}) as Dictionary).get("state", "")) != "completed":
		return &"quest"
	var practice := int(u.get("practice", 0))
	if practice > 0 and pre != &"" and int(GameState.ability_practice.get(String(pre), 0)) < practice:
		return &"practice"
	if int(u.get("cost", 1)) > GameState.skill_points:
		return &"skill_points"
	return &""
