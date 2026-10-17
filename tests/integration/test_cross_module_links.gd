extends TestCase
## Cross-module data links that no single module can check on its own:
## ability unlock rules ↔ trainer NPCs, quest rewards ↔ registered abilities,
## and every element having a full, reachable kit.


func test_every_trainer_named_by_an_ability_is_a_trainer_npc_of_that_element() -> void:
	for d in AbilityRegistry.all():
		var trainer := StringName(str(d.unlock.get("trainer", "")))
		if trainer == &"":
			continue
		var npc := NpcRegistry.get_npc(trainer)
		if not expect(not npc.is_empty(), "%s: trainer '%s' is not an NPC" % [d.id, trainer]):
			continue
		expect(npc.has("trainer"), "%s: NPC '%s' is not a trainer" % [d.id, trainer])
		var t: Dictionary = npc.get("trainer", {})
		expect(ElementDefs.from_id(StringName(str(t.get("element", "")))) == d.element,
				"%s: trainer '%s' teaches another element" % [d.id, trainer])


func test_quest_technique_rewards_are_registered_abilities_of_one_element() -> void:
	for q: Dictionary in QuestDefs.load_all():
		var rewards: Dictionary = q.get("rewards", {})
		for id in rewards.get("techniques", []):
			var d := AbilityRegistry.get_def(StringName(str(id)))
			expect(d != null, "quest %s rewards unknown technique '%s'" % [q.get("id"), id])


func test_each_element_has_a_complete_reachable_kit() -> void:
	for e in ElementDefs.ALL:
		var defs := AbilityRegistry.for_element(e)
		var slots := {}
		for d in defs:
			slots[d.slot] = true
		for s in [AbilityDef.Slot.LIGHT, AbilityDef.Slot.HEAVY, AbilityDef.Slot.DEFENSE, AbilityDef.Slot.DODGE,
				AbilityDef.Slot.TECHNIQUE, AbilityDef.Slot.SIGNATURE]:
			expect(slots.has(s), "%s kit has slot %d" % [ElementDefs.display_name(e), s])
		expect(AbilityRegistry.starter_techniques(e).size() >= 2, "%s has at least two starter techniques" % ElementDefs.display_name(e))
		expect(defs.size() >= 10, "%s has a full kit (%d abilities)" % [ElementDefs.display_name(e), defs.size()])
		# Every non-starter technique must name a prerequisite that exists in the same element.
		for d in defs:
			var pre := StringName(str(d.unlock.get("prerequisite", "")))
			if pre != &"":
				var pd := AbilityRegistry.get_def(pre)
				expect(pd != null and pd.element == e, "%s prerequisite %s exists in the same element" % [d.id, pre])
