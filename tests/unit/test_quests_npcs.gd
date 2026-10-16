extends TestCase
## quests_npcs module: quest state machine, objective types, rewards, persistence, conditions,
## actions, dialogue data, HUD / journal APIs, NPC budgets and data, merchants, trainers, wildlife.

const TQ := &"test_q_main"
const TQ2 := &"test_q_next"

var _events: Array = []
var _saved_state: Dictionary = {}


func before_each() -> void:
	_saved_state = GameState.to_dict() if GameState.has_element() else {}
	GameState.reset()
	GameState.new_game(ElementDefs.Element.WATER)
	_events.clear()
	Quests.enabled = true


func after_each() -> void:
	for id: StringName in [TQ, TQ2, &"test_q_side", &"test_q_tech", &"test_q_ability", &"test_q_defeat"]:
		Quests.unregister_quest(id)
	for c in get_children():
		c.queue_free()
	GameState.reset()
	if not _saved_state.is_empty():
		GameState.from_dict(_saved_state)


func _quest() -> Dictionary:
	return {
		"id": TQ, "title": "Test of Tides", "kind": &"main", "nation": &"water", "giver": &"",
		"summary": "A test quest.",
		"stages": [
			{"id": &"one", "text": "Stage one log.", "objectives": [
				{"id": &"talk", "type": &"talk_to", "npc": &"test_npc", "text": "Talk to the tester"},
				{"id": &"herbs", "type": &"collect", "item": &"arctic_moss", "count": 3, "text": "Gather moss"}],
				"on_complete": [["flag", "test_stage_one_done"]]},
			{"id": &"two", "text": "Stage two log.", "objectives": [
				{"id": &"see", "type": &"discover", "poi": &"test_poi", "text": "Find the place"},
				{"id": &"press", "type": &"interact", "key": &"test_lever", "count": 2, "text": "Pull the levers"}]},
		],
		"rewards": {"xp": 50, "currency": 12, "items": {&"sea_prunes": 2}},
		"next": TQ2,
	}


func _connect_events() -> void:
	Events.quest_started.connect(_on_ev.bind(&"started"))
	Events.quest_completed.connect(_on_ev.bind(&"completed"))
	Events.objective_completed.connect(func(q: StringName, o: StringName) -> void: _events.append([&"objective", q, o]))


func _disconnect_events() -> void:
	for sig: Signal in [Events.quest_started, Events.quest_completed, Events.objective_completed]:
		for c: Dictionary in sig.get_connections():
			if (c["callable"] as Callable).get_object() == self:
				sig.disconnect(c["callable"])


func _on_ev(q: StringName, kind: StringName) -> void:
	_events.append([kind, q])


func test_quest_state_machine_and_rewards() -> void:
	Quests.register_quest(_quest())
	Quests.register_quest({"id": TQ2, "title": "Next", "stages": [{"objectives": [{"id": &"x", "type": &"talk_to", "npc": &"n2", "text": "x"}]}]})
	_connect_events()
	expect_eq(Quests.state(TQ), &"none")
	expect(Quests.is_available(TQ), "available before start")
	expect(Quests.start(TQ), "starts")
	expect(not Quests.start(TQ), "starts only once")
	expect_eq(Quests.state(TQ), &"active")
	expect_eq(GameState.tracked_quest, TQ, "main quest tracked")
	expect(Quests.is_objective_active(TQ, &"talk"), "talk objective active")
	# collect counts the inventory
	GameState.add_item(&"arctic_moss", 2)
	expect_eq(Quests.progress(TQ, &"herbs"), 2, "moss progress")
	Quests.report(&"talk", &"test_npc")
	expect(Quests.is_objective_done(TQ, &"talk"), "talked")
	expect_eq(Quests.current_stage(TQ), 0, "still stage one")
	GameState.add_item(&"arctic_moss", 1)
	expect_eq(Quests.current_stage(TQ), 1, "stage two after all objectives")
	expect(bool(GameState.get_flag("test_stage_one_done")), "stage on_complete action ran")
	# discover + interact
	Quests.report(&"interact", &"test_lever")
	expect_eq(Quests.progress(TQ, &"press"), 1)
	GameState.discover_poi(&"test_poi")
	expect(Quests.is_objective_done(TQ, &"see"), "discovered")
	var xp0 := GameState.xp + GameState.level * 100000
	var coins0 := GameState.currency
	Quests.report(&"interact", &"test_lever")
	expect_eq(Quests.state(TQ), &"completed", "completed")
	expect(GameState.xp + GameState.level * 100000 > xp0, "xp granted")
	expect_eq(GameState.currency, coins0 + 12, "coins")
	expect_eq(GameState.item_count(&"sea_prunes"), 2, "reward items")
	expect_eq(Quests.state(TQ2), &"active", "next quest auto-started")
	expect_eq(GameState.tracked_quest, TQ2, "tracking moved on")
	var kinds: Array = _events.map(func(e: Array) -> StringName: return e[0])
	expect(kinds.has(&"started") and kinds.has(&"completed") and kinds.count(&"objective") == 4, "events %s" % [kinds])
	_disconnect_events()


func test_hud_display_and_journal() -> void:
	Quests.register_quest(_quest())
	Quests.start(TQ)
	GameState.add_item(&"arctic_moss", 1)
	var d := Quests.get_quest_display(TQ)
	expect_eq(String(d.get("title", "")), "Test of Tides")
	var objs: Array = d.get("objectives", [])
	expect_eq(objs.size(), 2, "two objectives shown")
	expect_eq(int((objs[1] as Dictionary).get("count", -1)), 1, "count")
	expect_eq(int((objs[1] as Dictionary).get("target", -1)), 3, "target")
	var j := Quests.journal()
	expect(j.size() >= 1 and (j[0] as Dictionary)["id"] == TQ, "journal lists the active quest first")
	var e := Quests.journal_entry(TQ)
	expect_eq((e["stages"] as Array).size(), 1, "only reached stages are listed")
	expect(String(e["rewards_text"]).contains("50 XP"), "rewards text")
	expect(Quests.journal(&"completed").is_empty(), "nothing completed yet")
	Quests.force_complete(TQ)
	expect_eq(Quests.state(TQ), &"completed")
	var done := Quests.journal(&"completed")
	expect(done.size() == 1 and ((done[0] as Dictionary)["stages"] as Array).size() == 2, "completed entry shows every stage")
	expect(Quests.get_quest_display(TQ).is_empty(), "no HUD display for completed quests")


func test_persistence_round_trip() -> void:
	Quests.register_quest(_quest())
	Quests.start(TQ)
	Quests.report(&"talk", &"test_npc")
	GameState.add_item(&"arctic_moss", 2)
	var saved := GameState.to_dict()
	var json := JSON.stringify(saved)
	var parsed: Dictionary = JSON.parse_string(json)
	GameState.reset()
	expect_eq(Quests.state(TQ), &"none", "reset clears quests")
	expect(GameState.from_dict(parsed), "loads")
	expect_eq(Quests.state(TQ), &"active", "active after load")
	expect(Quests.is_objective_done(TQ, &"talk"), "objective progress kept")
	expect_eq(Quests.progress(TQ, &"herbs"), 2, "count kept")
	expect_eq(GameState.tracked_quest, TQ, "tracking kept")
	GameState.add_item(&"arctic_moss", 1)
	expect_eq(Quests.current_stage(TQ), 1, "continues after load")


func test_use_ability_and_hits() -> void:
	Quests.register_quest({"id": &"test_q_ability", "title": "Forms", "kind": &"training", "stages": [{"objectives": [
		{"id": &"uses", "type": &"use_ability", "slot": &"technique", "count": 2, "text": "Use techniques"},
		{"id": &"hits", "type": &"use_ability", "mode": &"hit", "ability": &"water_whip", "on": &"dummy", "count": 2, "text": "Whip the targets"}]}]})
	Quests.start(&"test_q_ability")
	Events.ability_used.emit(&"water_whip")      # light: does not count for technique
	Events.ability_used.emit(&"ice_shards")
	expect_eq(Quests.progress(&"test_q_ability", &"uses"), 1, "technique counted, light ignored")
	var fake_player := Node3D.new()
	fake_player.add_to_group(&"player")
	add_child(fake_player)
	var dummy := Node3D.new()
	dummy.add_to_group(&"training_dummy")
	add_child(dummy)
	var other := Node3D.new()
	add_child(other)
	var hit := HitInfo.new()
	hit.source = fake_player
	hit.ability_id = &"water_whip"
	Events.hit_landed.emit(hit, other, Combat.Result.HIT)
	expect_eq(Quests.progress(&"test_q_ability", &"hits"), 0, "non-dummy target ignored")
	Events.hit_landed.emit(hit, dummy, Combat.Result.HIT)
	Events.hit_landed.emit(hit, dummy, Combat.Result.DODGED)
	expect_eq(Quests.progress(&"test_q_ability", &"hits"), 1, "dodged hit ignored")
	var h2 := HitInfo.new()
	h2.source = other
	h2.ability_id = &"water_whip"
	Events.hit_landed.emit(h2, dummy, Combat.Result.HIT)
	expect_eq(Quests.progress(&"test_q_ability", &"hits"), 1, "only the player's hits count")
	Events.hit_landed.emit(hit, dummy, Combat.Result.KILLED)
	Events.ability_used.emit(&"ice_shards")
	expect_eq(Quests.state(&"test_q_ability"), &"completed")


func test_defeat_objective_counts_each_enemy_once() -> void:
	Quests.register_quest({"id": &"test_q_defeat", "title": "Scouts", "stages": [{"objectives": [
		{"id": &"site", "type": &"defeat", "site": &"test_site", "count": 2, "clear": false, "text": "Defeat the scouts"},
		{"id": &"any_fire", "type": &"defeat", "faction": &"fire_nation", "count": 3, "text": "Defeat soldiers"}]}]})
	Quests.start(&"test_q_defeat")
	var a := _fake_enemy(&"test_site", &"fire_nation")
	var b := _fake_enemy(&"other_site", &"fire_nation")
	var c := _fake_enemy(&"test_site", &"bandits")
	Events.enemy_killed.emit(a, null)
	Events.enemy_killed.emit(a, null)
	expect_eq(Quests.progress(&"test_q_defeat", &"site"), 1, "same enemy counts once")
	Events.enemy_killed.emit(b, null)
	expect_eq(Quests.progress(&"test_q_defeat", &"site"), 1, "other site ignored")
	expect_eq(Quests.progress(&"test_q_defeat", &"any_fire"), 2, "faction counted")
	Events.enemy_killed.emit(c, null)
	expect(Quests.is_objective_done(&"test_q_defeat", &"site"), "site done")
	expect_eq(Quests.progress(&"test_q_defeat", &"any_fire"), 2, "bandit is not fire nation")


func _fake_enemy(site: StringName, faction: StringName) -> Node3D:
	var s := GDScript.new()
	s.source_code = "extends Node3D\nvar site_id: StringName\nvar faction: StringName\nvar archetype_id: StringName = &\"fire_soldier\"\n"
	s.reload()
	var n: Node3D = s.new()
	n.set("site_id", site)
	n.set("faction", faction)
	add_child(n)
	return n


func test_go_to_polls_player_position() -> void:
	Quests.register_quest({"id": TQ, "title": "Walk", "stages": [{"objectives": [
		{"id": &"there", "type": &"go_to", "target": {"pos": Vector3(100, 0, 0)}, "radius": 5.0, "text": "Walk there"}]}]})
	var p := Node3D.new()
	p.add_to_group(&"player")
	add_child(p)
	Events.player_spawned.emit(p)
	Quests.start(TQ)
	await seconds(0.35)
	expect(Quests.is_active(TQ), "far away: still active")
	p.global_position = Vector3(98, 0, 1)
	await seconds(0.4)
	expect_eq(Quests.state(TQ), &"completed", "arrived")


func test_conditions() -> void:
	Quests.register_quest(_quest())
	expect(QuestConditions.check(null), "null is true")
	expect(QuestConditions.check({}), "empty is true")
	expect(QuestConditions.check({"element": &"water"}), "element")
	expect(not QuestConditions.check({"element": [&"fire", &"air"]}), "element list")
	expect(QuestConditions.check({"quest": [TQ, "none"]}), "quest none")
	expect(QuestConditions.check({"quest": [TQ, "available"]}), "available")
	Quests.start(TQ)
	expect(QuestConditions.check({"quest": [TQ, "active"], "objective": [TQ, &"talk"]}), "active + objective")
	expect(not QuestConditions.check({"objective_done": [TQ, &"talk"]}), "not done")
	GameState.add_item(&"arctic_moss", 2)
	expect(QuestConditions.check({"item": [&"arctic_moss", 2]}) and not QuestConditions.check({"item": [&"arctic_moss", 3]}), "item count")
	GameState.set_flag("x", 3)
	expect(QuestConditions.check({"flag": ["x", 3]}) and QuestConditions.check({"flag": "x"}) and QuestConditions.check({"no_flag": "y"}), "flags")
	expect(QuestConditions.check({"any": [{"level": 99}, {"element": &"water"}]}), "any")
	expect(not QuestConditions.check({"not": {"element": &"water"}}), "not")
	expect(QuestConditions.in_hours(23.0, 21.0, 5.0) and QuestConditions.in_hours(2.0, 21.0, 5.0) and not QuestConditions.in_hours(12.0, 21.0, 5.0), "hours wrap midnight")
	expect(QuestConditions.check({"currency": 0}) and not QuestConditions.check({"currency": 1}), "currency")


func test_actions() -> void:
	Quests.register_quest(_quest())
	var ui := QuestActions.run([["start_quest", TQ], ["give_item", &"rope_coil", 2], ["take_item", &"rope_coil", 1],
		["currency", 30], ["currency", -10], ["flag", "door_open"], ["shop", &"some_shop"], ["xp", 5],
		["complete_objective", TQ, &"talk"], ["travel", {"poi": &"x"}, "Going"]])
	expect_eq(Quests.state(TQ), &"active", "start_quest")
	expect_eq(GameState.item_count(&"rope_coil"), 1, "give/take")
	expect_eq(GameState.currency, 20, "currency")
	expect(bool(GameState.get_flag("door_open")), "flag")
	expect(Quests.is_objective_done(TQ, &"talk"), "complete_objective")
	expect_eq(ui.size(), 2, "UI actions deferred to the caller")
	expect_eq(StringName(str((ui[0] as Array)[0])), &"shop")


func test_technique_reward_unlocks_registered_candidate() -> void:
	var d := AbilityRegistry.get_def(&"ice_shards").duplicate() as AbilityDef
	d.id = &"test_tech_wave"
	d.display_name = "Test Wave"
	d.starter = false
	d.unlock = {"level": 1, "trainer": "test_master"}
	AbilityRegistry.register(d)
	Quests.register_quest({"id": &"test_q_tech", "title": "Lesson", "stages": [{"objectives": [
		{"id": &"t", "type": &"talk_to", "npc": &"x", "text": "t"}]}],
		"rewards": {"techniques": [&"not_a_real_technique", &"test_tech_wave"]}})
	Quests.start(&"test_q_tech")
	var sp := GameState.skill_points
	Quests.report(&"talk", &"x")
	expect(GameState.is_unlocked(&"test_tech_wave"), "first registered candidate unlocked")
	expect(GameState.equipped_abilities.has(&"test_tech_wave"), "equipped into a free slot")
	expect_eq(GameState.skill_points, sp, "no fallback skill point")
	# nothing left to grant -> skill point instead
	var got := QuestRewards.unlock_first([&"test_tech_wave", &"nope"])
	expect_eq(got, &"", "already learned")
	expect_eq(GameState.skill_points, sp + 1, "fallback skill point")
	# element filter: a fire technique is never granted to a waterbender
	expect_eq(QuestRewards.pick_technique([&"flame_sweep"]), &"", "other element skipped")
	AbilityRegistry._defs.erase(&"test_tech_wave")


func test_npc_marker_and_availability() -> void:
	Quests.register_quest({"id": &"test_q_side", "title": "Side", "giver": &"test_giver", "requires": {"level": 2},
		"stages": [{"objectives": [{"id": &"t", "type": &"talk_to", "npc": &"test_giver", "text": "t"}]}]})
	expect_eq(Quests.npc_marker(&"test_giver"), &"", "requires not met")
	GameState.level = 2
	expect_eq(Quests.npc_marker(&"test_giver"), &"available", "offers the quest")
	expect(Quests.available_from(&"test_giver").has(&"test_q_side"))
	Quests.start(&"test_q_side")
	expect_eq(Quests.npc_marker(&"test_giver"), &"turn_in", "talk objective -> turn in")
	expect(Quests.abandon(&"test_q_side"), "side quests can be abandoned")
	expect_eq(Quests.state(&"test_q_side"), &"none")
