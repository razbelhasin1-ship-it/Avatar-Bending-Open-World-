class_name QuestConditions
extends RefCounted
## Condition evaluation shared by quests (`requires`, `auto_start`), dialogue trees (choice / node
## `if`, `branch`) and NPC talk selection (docs/modules/quests_npcs.md "Conditions").
##
## A condition is a Dictionary; every key must hold (AND). An empty / null condition is true.
##
##   {"quest": [&"wt_born_of_the_tide", "completed"]}   # none | active | completed | available | started | not_completed | not_started
##   {"objective": [&"wt_first_form", &"report"]}       # active objective (current stage, not done)
##   {"objective_done": [&"wt_first_form", &"targets"]}
##   {"stage": [&"wt_first_form", 1]}                   # active quest at stage >= 1
##   {"flag": "met_siku"} / {"flag": ["ferry_paid", 2]} / {"no_flag": "met_siku"}
##   {"element": &"water"} / {"element": [&"water", &"air"]}   # the player's element
##   {"item": [&"arctic_moss", 3]} / {"currency": 20} / {"level": 3} / {"unlocked": &"ice_shards"}
##   {"hour": [6.0, 20.0]}                              # time-of-day window (wraps midnight)
##   {"not": {...}} / {"any": [{...}, {...}]} / {"all": [{...}]}


static func check(cond: Variant) -> bool:
	if cond == null:
		return true
	if cond is Array:
		for c: Variant in cond:
			if not check(c):
				return false
		return true
	if not (cond is Dictionary):
		return bool(cond)
	var d: Dictionary = cond
	for key: Variant in d:
		if not _check_key(String(key), d[key]):
			return false
	return true


static func _check_key(key: String, v: Variant) -> bool:
	match key:
		"quest":
			var a := _arr(v)
			return _quest_state_matches(StringName(str(a[0])), String(a[1]) if a.size() > 1 else "completed")
		"objective":
			var a := _arr(v)
			return Quests.is_objective_active(StringName(str(a[0])), StringName(str(a[1])))
		"objective_done":
			var a := _arr(v)
			return Quests.is_objective_done(StringName(str(a[0])), StringName(str(a[1])))
		"stage":
			var a := _arr(v)
			var q := StringName(str(a[0]))
			return Quests.state(q) == &"active" and Quests.current_stage(q) >= int(a[1])
		"flag":
			if v is Array:
				var a: Array = v
				return GameState.get_flag(String(a[0]), null) == a[1]
			return bool(GameState.get_flag(String(v), false))
		"no_flag":
			return not bool(GameState.get_flag(String(v), false))
		"element":
			var me := ElementDefs.id_of(GameState.element)
			if v is Array:
				for e: Variant in v:
					if StringName(str(e)) == me:
						return true
				return false
			return StringName(str(v)) == me
		"item":
			var a := _arr(v)
			return GameState.item_count(StringName(str(a[0]))) >= (int(a[1]) if a.size() > 1 else 1)
		"currency":
			return GameState.currency >= int(v)
		"level":
			return GameState.level >= int(v)
		"unlocked":
			return GameState.is_unlocked(StringName(str(v)))
		"hour":
			var a := _arr(v)
			return in_hours(GameState.time_of_day, float(a[0]), float(a[1]))
		"not":
			return not check(v)
		"any":
			for c: Variant in _arr(v):
				if check(c):
					return true
			return false
		"all":
			return check(_arr(v))
	push_warning("QuestConditions: unknown condition key '%s'" % key)
	return false


static func _quest_state_matches(q: StringName, want: String) -> bool:
	var s := Quests.state(q)
	match want:
		"none", "not_started":
			return s == &"none"
		"active":
			return s == &"active"
		"completed":
			return s == &"completed"
		"not_completed":
			return s != &"completed"
		"started":
			return s == &"active" or s == &"completed"
		"available":
			return Quests.is_available(q)
		"failed":
			return s == &"failed"
	return false


## True when `hour` lies in [from, to) on a 24 h clock (wrapping past midnight when from > to).
static func in_hours(hour: float, from: float, to: float) -> bool:
	var h := fposmod(hour, 24.0)
	if from <= to:
		return h >= from and h < to
	return h >= from or h < to


static func _arr(v: Variant) -> Array:
	if v is Array:
		return v
	return [v]
