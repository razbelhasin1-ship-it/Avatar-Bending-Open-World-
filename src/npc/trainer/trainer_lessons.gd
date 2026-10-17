class_name TrainerLessons
extends RefCounted
## Bending masters (named NPCs with `"role": &"trainer"` and a `trainer` block) teach the
## techniques of their element whose AbilityDef.unlock names a trainer
## (`{"trainer": "<any id>"}`), once the player meets the level and prerequisite, through a short
## BendingChallenge. Passing sets GameState flag `trained_<unlock.trainer>_<ability>` (the
## contract AbilityRegistry.can_unlock checks) and unlocks + equips the technique (the lesson is
## the price: no skill points). Masters also offer sparring bouts against a student (XP).
##
## NPC data: "trainer": {"element": &"water", "lesson_lines": [...], "praise": [...], "fail": [...],
##   "spar": "Spar with Kallik"}
## A technique may carry its own lesson: AbilityDef.unlock["lesson"] = a BendingChallenge spec.

## Sparring partners copy an element bender (every one bends, the air one too: the temple's
## sparring monk, EnemyArchetypes.air_sparring_monk, with the Air techniques).
const SPAR_BASE := {&"water": &"water_pirate", &"earth": &"earth_rogue", &"fire": &"fire_soldier", &"air": &"air_sparring_monk"}
const SPAR_LOOK := {
	&"water": {"preset": &"water_tribe", "style": &"water", "body": "female", "seed": 2},
	&"earth": {"preset": &"earth_kingdom", "style": &"earth", "body": "male", "seed": 3},
	&"fire": {"preset": &"fire_nation", "style": &"fire", "body": "male", "seed": 2},
	&"air": {"preset": &"air_nomad", "style": &"air", "body": "male", "seed": 1},
}
const SPAR_NAMES := {&"water": "Senior Student Kallik", &"earth": "Senior Student Bao", &"fire": "Senior Student Azun", &"air": "Novice Tenzu"}


static func trainer_element(npc_id: StringName) -> int:
	var t: Dictionary = NpcRegistry.get_npc(npc_id).get("trainer", {})
	return ElementDefs.from_id(StringName(str(t.get("element", NpcRegistry.get_npc(npc_id).get("nation", "")))))


static func is_trainer(npc_id: StringName) -> bool:
	return NpcRegistry.get_npc(npc_id).has("trainer")


## Techniques this master can teach right now (the player's element must match).
static func lessons_for(npc_id: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	if not is_trainer(npc_id):
		return out
	var e := trainer_element(npc_id)
	if e != GameState.element:
		return out
	for d in AbilityRegistry.for_element(e):
		if _trainer_taught(d) and not GameState.is_unlocked(d.id) and _requirements_met(d):
			out.append(d.id)
	out.sort_custom(func(a: StringName, b: StringName) -> bool:
		return int(AbilityRegistry.get_def(a).unlock.get("level", 1)) < int(AbilityRegistry.get_def(b).unlock.get("level", 1)))
	return out


## Trainer-taught techniques not ready yet: [{id, name, level, prerequisite}].
static func future_lessons(npc_id: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var e := trainer_element(npc_id)
	if e != GameState.element:
		return out
	for d in AbilityRegistry.for_element(e):
		if _trainer_taught(d) and not GameState.is_unlocked(d.id) and not _requirements_met(d):
			out.append({"id": d.id, "name": d.display_name, "level": int(d.unlock.get("level", 1)),
				"prerequisite": StringName(str(d.unlock.get("prerequisite", "")))})
	return out


static func _trainer_taught(d: AbilityDef) -> bool:
	return (d.slot == AbilityDef.Slot.TECHNIQUE or d.slot == AbilityDef.Slot.SIGNATURE) and String(d.unlock.get("trainer", "")) != "" \
		and not d.script_path.is_empty()


static func _requirements_met(d: AbilityDef) -> bool:
	if GameState.level < int(d.unlock.get("level", 1)):
		return false
	var pre := StringName(str(d.unlock.get("prerequisite", "")))
	return pre == &"" or GameState.is_unlocked(pre)


## The challenge a lesson runs.
static func lesson_spec(id: StringName) -> Dictionary:
	var d := AbilityRegistry.get_def(id)
	if d == null:
		return {}
	if d.unlock.has("lesson") and d.unlock["lesson"] is Dictionary:
		return d.unlock["lesson"]
	if d.slot == AbilityDef.Slot.SIGNATURE or int(d.unlock.get("level", 1)) >= 8:
		return {"kind": &"spar", "title": "Prove yourself", "archetype": spar_archetype(ElementDefs.id_of(d.element)), "time": 120.0}
	return {"kind": &"targets", "title": "Lesson: %s" % d.display_name, "count": 3, "hits": 6, "slot": &"any", "time": 50.0}


## Marks the lesson learned and unlocks the technique.
static func complete_lesson(npc_id: StringName, id: StringName) -> void:
	var d := AbilityRegistry.get_def(id)
	if d == null:
		return
	var trainer := String(d.unlock.get("trainer", String(npc_id)))
	GameState.set_flag("trained_%s_%s" % [trainer, id], true)
	GameState.set_flag("trained_%s_%s" % [npc_id, id], true)
	# Techniques go into a free slot; a signature has its own slot (R) and must never fill
	# a technique slot (the controller would leave that slot dead).
	GameState.unlock_ability(id, d.slot == AbilityDef.Slot.TECHNIQUE)
	QuestRewards.reload_player_techniques()
	GameState.incr_stat("lessons_learned")
	Events.notify.emit("New technique: %s  ·  taught by %s%s" % [d.display_name, NpcRegistry.display_name(npc_id),
		QuestRewards.slot_hint(id)], &"unlock")


static func spar_archetype(nation: StringName) -> StringName:
	return StringName("spar_%s" % nation)


## Registers the sparring partners (copies of the element benders in the nation's clothes,
## no XP / loot, they yield at low health).
static func ensure_spar_archetypes() -> void:
	for nation: StringName in SPAR_BASE:
		var id := spar_archetype(nation)
		if EnemyArchetypes.has(id):
			continue
		var a := EnemyArchetypes.get_archetype(SPAR_BASE[nation]).duplicate(true)
		a["display_name"] = SPAR_NAMES[nation]
		a["faction"] = &"sparring"
		a["look"] = SPAR_LOOK[nation]
		a["loot"] = []
		a["xp"] = 0
		a["health"] = 70.0
		a["flee"] = {"health": 0.3, "flee": 0.0, "surrender": 1.0}
		EnemyArchetypes.register(id, a)


## The trainer conversation: lessons, sparring, or later. Runs challenges and their outcome.
static func open(runner: DialogueRunner, npc: NpcCharacter) -> void:
	if npc == null or runner == null:
		return
	var id := npc.npc_id
	var t: Dictionary = NpcRegistry.get_npc(id).get("trainer", {})
	if trainer_element(id) != GameState.element:
		await runner.say_lines(npc, [String(t.get("other_element", "I can only teach my own element. Seek the master of yours."))])
		return
	var lessons := lessons_for(id)
	var options: Array = []
	for l in lessons:
		options.append("Teach me %s" % AbilityRegistry.get_def(l).display_name)
	options.append(String(t.get("spar", "Spar with a student")))
	options.append("Not now.")
	var prompt := String(t.get("menu", "What would you learn today?"))
	if lessons.is_empty():
		var fut := future_lessons(id)
		if fut.is_empty():
			prompt = String(t.get("done", "I have taught you all I know for now. Practise, and keep your breath steady."))
		else:
			var lvl := 99
			for f in fut:
				lvl = mini(lvl, int(f["level"]))
			prompt = "You are not ready for my next lesson. Come back when you have reached level %d." % lvl
	var pick: int = await runner.ask(npc, prompt, options)
	if pick < lessons.size():
		var tech := lessons[pick]
		var lines: Array = t.get("lesson_lines", ["Watch closely. Then show me."])
		await runner.say_lines(npc, [String(lines[randi() % lines.size()])])
		var ok := await run_challenge(npc, lesson_spec(tech))
		if ok:
			complete_lesson(id, tech)
			var praise: Array = t.get("praise", ["Good. That is the beginning of mastery, not the end."])
			await runner.say_lines(npc, [String(praise[randi() % praise.size()])])
		else:
			var fail: Array = t.get("fail", ["Again, when your breath is calm."])
			await runner.say_lines(npc, [String(fail[randi() % fail.size()])])
	elif pick == lessons.size():
		var ok2 := await run_challenge(npc, {"kind": &"spar", "title": String(t.get("spar", "Sparring bout")),
			"archetype": spar_archetype(ElementDefs.id_of(trainer_element(id))), "time": 120.0})
		if ok2:
			GameState.add_xp(40, "Sparring")
			Events.notify.emit("Sparring bout won  ·  +40 XP", &"info")
			GameState.incr_stat("spars_won")


## Runs a challenge in front of the player near `npc`; returns success.
static func run_challenge(npc: Node3D, spec: Dictionary) -> bool:
	var pl := Quests.get_player()
	if pl == null or spec.is_empty():
		return false
	var host: Node = npc.get_tree().get_first_node_in_group(&"playable_scene")
	if host == null:
		host = npc.get_tree().current_scene
	var c := BendingChallenge.begin(host, spec, pl)
	var ok: bool = await c.finished
	return ok
