class_name QuestRewards
extends RefCounted
## Grants quest rewards: XP (GameState.add_xp), currency, items, skill points and technique
## unlocks. Techniques are listed as candidates in order of preference; the first one that the
## bending registry knows, that belongs to the player's element and is not learned yet is unlocked
## (and equipped into a free slot). When no candidate exists (a technique not implemented in this
## build) the player receives a skill point instead, so a reward is never silently lost.
##
##   "rewards": {"xp": 150, "currency": 30, "items": {&"arctic_moss": 2},
##               "techniques": [&"water_surge", &"ice_wall"], "skill_points": 1}


## Grants `rewards`; returns the toast parts ("+150 XP", "30 coins", "Water Surge learned"...).
static func grant(rewards: Dictionary, reason: String = "") -> PackedStringArray:
	var parts := PackedStringArray()
	var xp := int(rewards.get("xp", 0))
	if xp > 0:
		GameState.add_xp(xp, reason)
		parts.append("+%d XP" % xp)
	var coins := int(rewards.get("currency", 0))
	if coins > 0:
		GameState.currency += coins
		parts.append("%d coins" % coins)
	var items: Dictionary = rewards.get("items", {})
	for id: Variant in items:
		var n := int(items[id])
		if n > 0:
			GameState.add_item(StringName(str(id)), n)
			parts.append("%s ×%d" % [TradeGoods.display_name(StringName(str(id))), n])
	var sp := int(rewards.get("skill_points", 0))
	if sp > 0:
		GameState.skill_points += sp
		parts.append("+%d skill point%s" % [sp, "" if sp == 1 else "s"])
	var techs: Array = rewards.get("techniques", [])
	if not techs.is_empty():
		var got := unlock_first(techs, reason, false)
		if got != &"":
			parts.append("%s learned" % technique_name(got))
		else:
			parts.append("+1 skill point")
	return parts


## The first candidate that can be granted now (registered, the player's element, not learned).
static func pick_technique(candidates: Array) -> StringName:
	for c: Variant in candidates:
		var id := StringName(str(c))
		var d := AbilityRegistry.get_def(id)
		if d == null or GameState.is_unlocked(id):
			continue
		if GameState.has_element() and d.element != GameState.element:
			continue
		return id
	return &""


## Unlocks (and equips into a free slot) the first grantable candidate; falls back to a skill
## point. Returns the unlocked id (&"" when the fallback was used). Reloads the live player's
## technique slots so the move is usable at once.
static func unlock_first(candidates: Variant, reason: String = "", toast: bool = true) -> StringName:
	var list: Array = candidates if candidates is Array else [candidates]
	var id := pick_technique(list)
	if id == &"":
		GameState.skill_points += 1
		if toast:
			Events.notify.emit("Your training deepens  ·  +1 skill point", &"unlock")
		return &""
	GameState.unlock_ability(id, true)
	reload_player_techniques()
	if toast:
		Events.notify.emit("New technique: %s%s" % [technique_name(id), ("  ·  " + reason) if reason != "" else ""], &"unlock")
	return id


static func technique_name(id: StringName) -> String:
	var d := AbilityRegistry.get_def(id)
	return d.display_name if d != null and d.display_name != "" else String(id).capitalize()


## The player's BendingController re-reads GameState.equipped_abilities.
static func reload_player_techniques() -> void:
	var p := Quests.get_player()
	if p == null:
		return
	var c: Variant = p.get("controller")
	if c is BendingController:
		(c as BendingController).load_equipped()
