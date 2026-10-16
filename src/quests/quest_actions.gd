class_name QuestActions
extends RefCounted
## Actions shared by quest stages (`on_start`, stage `on_complete`) and dialogue nodes / choices
## (`do`). An action is an Array whose first entry is the verb:
##
##   ["start_quest", &"wt_first_form"]            ["complete_objective", &"wt_first_form", &"report"]
##   ["give_item", &"arctic_moss", 2]             ["take_item", &"letter_northreach", 1]
##   ["currency", 25]  (negative pays)            ["xp", 40]
##   ["flag", "met_siku"] / ["flag", "x", 3]      ["unlock", [&"water_surge", &"ice_wall"]]  (first available technique)
##   ["heal"]                                     ["notify", "text", &"info"]       ["track", &"wt_first_form"]
##   ["skill_point", 1]
## UI actions need the scene and run AFTER the conversation closes (returned to the caller):
##   ["shop", &"nwt_fishmonger"]   ["train"]   ["travel", {target spec}, "Flying to the Ice Flats"]
##   ["challenge", &"wt_first_form", &"targets"]

const UI_VERBS: Array[StringName] = [&"shop", &"train", &"travel", &"challenge"]


## Runs every data action of `actions` now and returns the UI actions (in order) for the caller.
static func run(actions: Variant, ctx: Dictionary = {}) -> Array:
	var deferred: Array = []
	if not (actions is Array):
		return deferred
	for a: Variant in actions:
		if not (a is Array) or (a as Array).is_empty():
			continue
		var act: Array = a
		var verb := StringName(str(act[0]))
		if UI_VERBS.has(verb):
			deferred.append(act)
			continue
		run_one(verb, act, ctx)
	return deferred


static func run_one(verb: StringName, a: Array, _ctx: Dictionary = {}) -> void:
	match verb:
		&"start_quest":
			Quests.start(StringName(str(a[1])))
		&"complete_objective":
			Quests.complete_objective(StringName(str(a[1])), StringName(str(a[2])))
		&"give_item":
			var n := int(a[2]) if a.size() > 2 else 1
			GameState.add_item(StringName(str(a[1])), n)
			Events.notify.emit("Received %s ×%d" % [TradeGoods.display_name(StringName(str(a[1]))), n], &"info")
		&"take_item":
			var n2 := int(a[2]) if a.size() > 2 else 1
			var id := StringName(str(a[1]))
			GameState.add_item(id, -mini(n2, GameState.item_count(id)))
		&"currency":
			var amount := int(a[1])
			GameState.currency = maxi(0, GameState.currency + amount)
			if amount > 0:
				Events.notify.emit("+%d coins" % amount, &"info")
		&"xp":
			GameState.add_xp(int(a[1]), String(a[2]) if a.size() > 2 else "")
		&"flag":
			GameState.set_flag(String(a[1]), a[2] if a.size() > 2 else true)
		&"unlock":
			QuestRewards.unlock_first(a[1] if a.size() > 1 else [], String(a[2]) if a.size() > 2 else "")
		&"skill_point":
			GameState.skill_points += int(a[1]) if a.size() > 1 else 1
			Events.notify.emit("+%d skill point" % (int(a[1]) if a.size() > 1 else 1), &"unlock")
		&"heal":
			var p := Quests.get_player()
			if p != null and p.get("health") is HealthComponent:
				var h: HealthComponent = p.get("health")
				h.health = h.max_health
				h.changed.emit(h.health, h.max_health)
		&"notify":
			Events.notify.emit(String(a[1]), StringName(str(a[2])) if a.size() > 2 else &"info")
		&"track":
			Quests.track(StringName(str(a[1])))
		_:
			push_warning("QuestActions: unknown action %s" % verb)
