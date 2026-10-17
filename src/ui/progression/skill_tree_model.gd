class_name SkillTreeModel
extends RefCounted
## Data + rules behind the bending skill tree (no UI): the element's techniques laid out
## by tier / column from `AbilityDef.unlock` (tier, branch, column - the layout keys every
## element kit publishes), what each one requires, learning with skill points and equipping
## into the four technique slots. Everything goes through the real contracts:
## `AbilityRegistry.can_unlock`, `GameState.unlock_ability` / `equip_ability`, and the live
## player's `BendingController.load_equipped()` so a change is usable the moment the book
## closes.
##
##   SkillTreeModel.nodes(e)           # [{id, def, tier, column, branch, requires, signature, starter}]
##   SkillTreeModel.state(id)          # &"learned" | &"available" | &"locked"
##   SkillTreeModel.requirements(id)   # [{kind, text, met, value, target}]
##   SkillTreeModel.learn(id)          # &"" or the AbilityRegistry.can_unlock reason
##   SkillTreeModel.equip(slot, id)    # &"" or &"locked" / &"not_technique" / &"element" / &"slot"
##   SkillTreeModel.unequip(slot)

const SLOTS := 4

const STATE_LEARNED := &"learned"
const STATE_AVAILABLE := &"available"
const STATE_LOCKED := &"locked"

## Display names of the kit branches (layout key `unlock.branch`).
const BRANCH_NAMES := {
	&"gale": "Gale", &"circle": "Circle", &"flight": "Flight",
	&"stone": "Stone", &"seismic": "Seismic", &"guard": "Guard",
	&"breath": "Breath", &"flame": "Flame", &"lightning": "Lightning",
	&"ice": "Ice", &"flow": "Flow", &"healing": "Healing",
}

## Slot kinds as the tree labels them.
const SLOT_LABELS := {
	AbilityDef.Slot.LIGHT: "Light Strike", AbilityDef.Slot.HEAVY: "Heavy Strike", AbilityDef.Slot.DEFENSE: "Defense",
	AbilityDef.Slot.DODGE: "Dodge", AbilityDef.Slot.TECHNIQUE: "Technique", AbilityDef.Slot.SIGNATURE: "Signature",
	AbilityDef.Slot.PASSIVE: "Passive", AbilityDef.Slot.INNATE: "Innate",
}

## Short element lore for the tree header (the show's philosophy of each art).
const LORE := {
	ElementDefs.Element.AIR: "The element of freedom. Airbenders detach from worldly concerns and find peace - and power - in letting go.",
	ElementDefs.Element.EARTH: "The element of substance. Earthbenders are diverse and strong, persistent and enduring: they wait, listen, and strike.",
	ElementDefs.Element.FIRE: "The element of power. Firebenders draw on drive and will; fire comes from the breath, not from rage.",
	ElementDefs.Element.WATER: "The element of change. Waterbenders adapt to many things, and take the force of the opponent as their own.",
}

## Status effects as the detail panel words them.
const STATUS_NAMES := {&"burn": "Burns", &"soaked": "Soaks", &"chill": "Chills", &"frozen": "Freezes"}

## Display name of each element's art.
const ART_NAMES := {
	ElementDefs.Element.AIR: "Airbending", ElementDefs.Element.EARTH: "Earthbending",
	ElementDefs.Element.FIRE: "Firebending", ElementDefs.Element.WATER: "Waterbending",
}


# --- layout ---------------------------------------------------------------------------------------

## The element's tree: techniques and the signature, sorted by tier then column.
## [{id, def: AbilityDef, tier, column, branch, requires, signature, starter}]
static func nodes(e: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for d in AbilityRegistry.for_element(e):
		if d.slot != AbilityDef.Slot.TECHNIQUE and d.slot != AbilityDef.Slot.SIGNATURE:
			continue
		if d.script_path.is_empty():
			continue
		var u := d.unlock
		out.append({"id": d.id, "def": d, "tier": maxi(1, int(u.get("tier", 1))), "column": maxi(0, int(u.get("column", 0))),
			"branch": StringName(str(u.get("branch", ""))), "requires": StringName(str(u.get("prerequisite", ""))),
			"signature": d.slot == AbilityDef.Slot.SIGNATURE, "starter": d.starter})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["tier"]) != int(b["tier"]):
			return int(a["tier"]) < int(b["tier"])
		if int(a["column"]) != int(b["column"]):
			return int(a["column"]) < int(b["column"])
		return String(a["id"]) < String(b["id"]))
	# Two techniques claiming the same cell (runtime registrations): push the later one right.
	var taken := {}
	for n in out:
		var key := Vector2i(int(n["column"]), int(n["tier"]))
		while taken.has(key):
			key.x += 1
		taken[key] = true
		n["column"] = key.x
	return out


static func tier_count(e: int) -> int:
	var t := 1
	for n in nodes(e):
		t = maxi(t, int(n["tier"]))
	return t


static func column_count(e: int) -> int:
	var c := 1
	for n in nodes(e):
		c = maxi(c, int(n["column"]) + 1)
	return c


## Lowest level any technique of `tier` asks for (the tier's row label).
static func tier_level(e: int, tier: int) -> int:
	var lvl := 99
	for n in nodes(e):
		if int(n["tier"]) == tier:
			lvl = mini(lvl, int((n["def"] as AbilityDef).unlock.get("level", 1)))
	return 1 if lvl == 99 else lvl


## Branch label of a column (the branch of its lowest-tier technique).
static func column_branch(e: int, column: int) -> StringName:
	for n in nodes(e):
		if int(n["column"]) == column and n["branch"] != &"":
			return n["branch"]
	return &""


static func branch_name(branch: StringName) -> String:
	return String(BRANCH_NAMES.get(branch, String(branch).capitalize()))


## The core kit (light, heavy, defense, dodge) + innate / passive moves: shown as the tree's
## foundations (always known, never bought).
static func foundations(e: int) -> Array[AbilityDef]:
	var out: Array[AbilityDef] = []
	var kit := AbilityRegistry.core_kit(e)
	for k: StringName in [&"light", &"heavy", &"defense", &"dodge"]:
		if kit.has(k):
			out.append(kit[k])
	for d in AbilityRegistry.for_element(e):
		if d.slot == AbilityDef.Slot.INNATE or d.slot == AbilityDef.Slot.PASSIVE:
			out.append(d)
	return out


static func slot_label(d: AbilityDef) -> String:
	return String(SLOT_LABELS.get(d.slot, "Technique")) if d != null else ""


# --- state + requirements ---------------------------------------------------------------------------

static func is_foundation(d: AbilityDef) -> bool:
	return d != null and d.slot != AbilityDef.Slot.TECHNIQUE and d.slot != AbilityDef.Slot.SIGNATURE


static func state(id: StringName) -> StringName:
	var d := AbilityRegistry.get_def(id)
	if d == null:
		return STATE_LOCKED
	if GameState.is_unlocked(id) or is_foundation(d):
		return STATE_LEARNED
	return STATE_AVAILABLE if AbilityRegistry.can_unlock(id) == &"" else STATE_LOCKED


## True when a master teaches this technique (the lesson is the price: no skill points).
static func is_trainer_taught(d: AbilityDef) -> bool:
	return d != null and String(d.unlock.get("trainer", "")) != ""


static func cost(d: AbilityDef) -> int:
	if d == null:
		return 0
	return int(d.unlock.get("cost", 0 if d.starter else 1))


## Every requirement of a technique, in the order AbilityRegistry.can_unlock checks them:
## [{kind: &"level"|&"prerequisite"|&"trainer"|&"quest"|&"practice"|&"skill_points",
##   text, met: bool, value, target}]
static func requirements(id: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var d := AbilityRegistry.get_def(id)
	if d == null or is_foundation(d):
		return out
	var u := d.unlock
	var learned := GameState.is_unlocked(id)
	var lvl := int(u.get("level", 1))
	if lvl > 1:
		out.append({"kind": &"level", "met": learned or GameState.level >= lvl, "value": GameState.level, "target": lvl,
			"text": "Level %d" % lvl if (learned or GameState.level >= lvl) else "Reach level %d  (you are level %d)" % [lvl, GameState.level]})
	var pre := StringName(str(u.get("prerequisite", "")))
	if pre != &"":
		var pre_name := display_name(pre)
		var ok := learned or GameState.is_unlocked(pre)
		out.append({"kind": &"prerequisite", "met": ok, "value": 1 if ok else 0, "target": 1,
			"text": ("Knows %s" if ok else "Learn %s first") % pre_name})
	var trainer := String(u.get("trainer", ""))
	if trainer != "":
		var m := master_for(d.element)
		var who := String(m.get("name", "")) if not m.is_empty() else String(_kit_trainer(d.element, StringName(trainer)).get("name", "a bending master"))
		var where := String(m.get("place", ""))
		var ok2 := learned or bool(GameState.get_flag("trained_" + trainer + "_" + String(id), false))
		var txt := ("Taught by %s" % who) if ok2 else ("Train with %s%s" % [who, ("  ·  " + where) if where != "" else ""])
		out.append({"kind": &"trainer", "met": ok2, "value": 1 if ok2 else 0, "target": 1, "text": txt,
			"npc": m.get("id", &""), "trainer": StringName(trainer)})
	var quest := StringName(str(u.get("quest", "")))
	if quest != &"":
		var qstate := String((GameState.quests.get(String(quest), {}) as Dictionary).get("state", ""))
		var qok := learned or qstate == "completed"
		var title := String(Quests.get_def(quest).get("title", String(quest).capitalize())) if Quests != null else String(quest)
		out.append({"kind": &"quest", "met": qok, "value": 1 if qok else 0, "target": 1, "quest": quest,
			"text": ("Completed %s" if qok else "Complete the quest %s") % title})
	var practice := int(u.get("practice", 0))
	if practice > 0 and pre != &"":
		var have := int(GameState.ability_practice.get(String(pre), 0))
		var pok := learned or have >= practice
		out.append({"kind": &"practice", "met": pok, "value": mini(have, practice), "target": practice,
			"text": "Practise %s  %d / %d" % [display_name(pre), mini(have, practice), practice]})
	if not is_trainer_taught(d) and not d.starter:
		var c := cost(d)
		if c > 0:
			var cok := learned or GameState.skill_points >= c
			out.append({"kind": &"skill_points", "met": cok, "value": GameState.skill_points, "target": c,
				"text": ("%d skill point%s" % [c, "" if c == 1 else "s"]) if learned else
					("%d skill point%s  (you have %d)" % [c, "" if c == 1 else "s", GameState.skill_points])})
	return out


## The first unmet requirement kind (matches AbilityRegistry.can_unlock), &"" when learnable,
## &"unlocked" when known.
static func blocker(id: StringName) -> StringName:
	return AbilityRegistry.can_unlock(id)


## Short reason line for a locked technique ("Reach level 5", "Train with Master Siku" ...).
static func lock_text(id: StringName) -> String:
	for r in requirements(id):
		if not bool(r["met"]):
			return String(r["text"])
	return ""


# --- actions ----------------------------------------------------------------------------------------

## Learns a technique with skill points (non-trainer techniques). Returns &"" on success or
## the can_unlock reason. Equips it into a free slot (GameState.unlock_ability) and reloads
## the live player's loadout.
static func learn(id: StringName) -> StringName:
	var why := AbilityRegistry.can_unlock(id)
	if why != &"":
		return why
	var d := AbilityRegistry.get_def(id)
	var c := cost(d)
	GameState.skill_points = maxi(0, GameState.skill_points - c)
	GameState.unlock_ability(id, d.slot == AbilityDef.Slot.TECHNIQUE)
	GameState.incr_stat("techniques_learned")
	reload_player()
	return &""


## Equips `id` into technique slot `slot` (0..3). A technique already in another slot swaps
## with what was here (GameState.equip_ability). Returns &"" or a reason.
static func equip(slot: int, id: StringName) -> StringName:
	if slot < 0 or slot >= SLOTS:
		return &"slot"
	var d := AbilityRegistry.get_def(id)
	if d == null:
		return &"unknown"
	if d.slot != AbilityDef.Slot.TECHNIQUE:
		return &"not_technique"
	if GameState.has_element() and d.element != GameState.element:
		return &"element"
	if not GameState.is_unlocked(id):
		return &"locked"
	GameState.equip_ability(slot, id)
	reload_player()
	return &""


static func unequip(slot: int) -> void:
	if slot < 0 or slot >= SLOTS:
		return
	if GameState.equipped_abilities[slot] == &"":
		return
	GameState.equip_ability(slot, &"")
	reload_player()


## Technique slot holding `id`, -1 if not equipped.
static func slot_of(id: StringName) -> int:
	return GameState.equipped_abilities.find(id) if id != &"" else -1


static func equipped(slot: int) -> StringName:
	return GameState.equipped_abilities[slot] if slot >= 0 and slot < GameState.equipped_abilities.size() else &""


## The signature in use: the element's first learned signature (BendingController.load_equipped).
static func signature_id(e: int) -> StringName:
	for id: StringName in GameState.unlocked_abilities:
		var d := AbilityRegistry.get_def(id)
		if d != null and d.element == e and d.slot == AbilityDef.Slot.SIGNATURE:
			return id
	return &""


## Re-reads GameState.equipped_abilities into the live player's BendingController.
static func reload_player() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var p := tree.get_first_node_in_group(&"player")
	if p == null:
		return
	var c: Variant = p.get("controller")
	if c is BendingController:
		(c as BendingController).load_equipped()


## Techniques that can be learned right now (skill points / requirements met).
static func learnable(e: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for n in nodes(e):
		if state(n["id"]) == STATE_AVAILABLE:
			out.append(n["id"])
	return out


# --- text helpers -----------------------------------------------------------------------------------

static func display_name(id: StringName) -> String:
	var d := AbilityRegistry.get_def(id)
	return d.display_name if d != null and d.display_name != "" else String(id).capitalize()


## The bending master of an element (named NPC with a `trainer` block): {id, name, title, place}.
static func master_for(e: int) -> Dictionary:
	var best: Dictionary = {}
	for id: StringName in NpcRegistry.ids():
		var npc := NpcRegistry.get_npc(id)
		var t: Variant = npc.get("trainer")
		if not (t is Dictionary):
			continue
		var te := ElementDefs.from_id(StringName(str((t as Dictionary).get("element", npc.get("nation", "")))))
		if te != e:
			continue
		var title := String(npc.get("title", ""))
		var entry := {"id": id, "name": String(npc.get("name", String(id))), "title": title, "place": _place_text(npc)}
		if best.is_empty() or (title.contains("Master") and not String(best.get("title", "")).contains("Master")):
			best = entry
	return best


static func _place_text(npc: Dictionary) -> String:
	var place: Dictionary = npc.get("place", {})
	var anchor: Dictionary = place.get("anchor", {})
	var sid := StringName(str(anchor.get("settlement", "")))
	if sid != &"":
		var c := WorldData.get_city(sid)
		if not c.is_empty():
			return String(c.get("name", ""))
	if place.has("poi"):
		var p := WorldData.get_poi(StringName(str(place["poi"])))
		if not p.is_empty():
			return String(p.get("name", ""))
	return ""


static func _kit_trainer(e: int, trainer: StringName) -> Dictionary:
	var path := ""
	match e:
		ElementDefs.Element.AIR: path = "res://src/bending/kits/air/air_kit.gd"
		ElementDefs.Element.EARTH: path = "res://src/bending/kits/earth/earth_kit.gd"
		ElementDefs.Element.FIRE: path = "res://src/bending/kits/fire/fire_kit.gd"
		ElementDefs.Element.WATER: path = "res://src/bending/kits/water/water_kit.gd"
	if path == "" or not ResourceLoader.exists(path):
		return {}
	var s := load(path) as GDScript
	var consts := s.get_script_constant_map()
	var tr: Dictionary = consts.get("TRAINERS", {})
	return tr.get(trainer, {})


## "24 chi  ·  8 s cooldown" / "100 Focus" stat line for a def.
static func stat_line(d: AbilityDef) -> String:
	if d == null:
		return ""
	var parts := PackedStringArray()
	if d.focus_cost > 0.0:
		parts.append("%d Focus" % int(d.focus_cost))
	if d.chi_cost > 0.0:
		parts.append("%d Chi" % int(round(d.chi_cost)))
	elif d.slot == AbilityDef.Slot.LIGHT:
		parts.append("Free")
	var upkeep := float(d.params.get("upkeep", d.params.get("hover_upkeep", 0.0)))
	if upkeep > 0.0:
		parts.append("%d Chi/s held" % int(round(upkeep)))
	if d.cooldown > 0.0:
		parts.append(("%.1f s cooldown" % d.cooldown).replace(".0 s", " s"))
	if d.charge_time > 0.0 and d.slot != AbilityDef.Slot.SIGNATURE:
		parts.append(("hold %.1f s to charge" % d.charge_time).replace(".0 s", " s"))
	return "  ·  ".join(parts)


## Damage / reaction summary from the hit data ("26 damage  ·  Knockdown").
static func hit_line(d: AbilityDef) -> String:
	if d == null or d.hit.is_empty():
		return ""
	var dmg := float(d.hit.get("damage", 0.0))
	var parts := PackedStringArray()
	if dmg > 0.0:
		parts.append("%d damage" % int(round(dmg)))
	var reaction := int(d.hit.get("reaction", HitInfo.Reaction.NONE))
	var rname := ""
	for k: String in HitInfo.Reaction.keys():
		if int(HitInfo.Reaction[k]) == reaction:
			rname = k.capitalize()
	if rname != "" and rname != "None":
		parts.append(rname)
	var status: Dictionary = d.hit.get("status", {})
	for s: Variant in status:
		var sname := String(STATUS_NAMES.get(StringName(str(s)), String(s).capitalize()))
		if sname == "Freezes" and rname == "Freeze":
			continue
		parts.append(sname)
	if bool(d.hit.get("unblockable", false)):
		parts.append("Unblockable")
	return "  ·  ".join(parts)
