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
	await frames(2)
	WorldData.height_override = Callable()
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


# --- content data ---------------------------------------------------------------------------------

func _data_quests() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for q in QuestDefs.load_all():
		out.append(q)
	return out


func test_quest_and_dialogue_data_is_valid() -> void:
	var qs := _data_quests()
	expect(qs.size() >= 28, "quest count %d" % qs.size())
	var npc_ids: Array = NpcRegistry.ids()
	var items: Array = TradeGoods.ids()
	for e in QuestDefs.validate(qs, npc_ids, items):
		fail(e)
	for e2 in NpcRegistry.validate():
		fail(e2)
	# every quest can be obtained: auto-start, a chain `next`, or a start_quest action in a tree
	var reachable := {}
	for q in qs:
		if q.get("auto_start") != null:
			reachable[q["id"]] = true
		if q["next"] != &"":
			reachable[q["next"]] = true
	for tid: Variant in NpcRegistry.tree_ids():
		var t := NpcRegistry.dialogue_tree(StringName(str(tid)))
		for k: Variant in t["nodes"]:
			var n: Dictionary = t["nodes"][k]
			var acts: Array = (n.get("do", []) as Array).duplicate()
			for c: Variant in n.get("choices", []):
				acts.append_array((c as Dictionary).get("do", []))
			for a: Variant in acts:
				if StringName(str((a as Array)[0])) == &"start_quest":
					reachable[StringName(str((a as Array)[1]))] = true
	for q2 in qs:
		expect(reachable.has(q2["id"]), "quest %s can be started" % q2["id"])
	for q3 in qs:
		for st: Dictionary in q3["stages"]:
			for o: Dictionary in st["objectives"]:
				if o["type"] == &"collect":
					expect(TradeGoods.has_item(o["item"]), "%s: item %s in the catalog" % [q3["id"], o["item"]])


func test_each_nation_has_an_opening_chain_side_and_travel_quests() -> void:
	var qs := _data_quests()
	var by := {}
	for q in qs:
		by[q["id"]] = q
	for el: StringName in [&"water", &"earth", &"fire", &"air"]:
		var first: Dictionary = {}
		for q in qs:
			var a: Variant = q.get("auto_start")
			if a is Dictionary and StringName(str((a as Dictionary).get("element", ""))) == el:
				first = q
		if not expect(not first.is_empty(), "%s: auto-start opening quest" % el):
			continue
		var chain: Array[Dictionary] = [first]
		while chain[-1]["next"] != &"" and chain.size() < 10:
			chain.append(by[chain[-1]["next"]])
		expect(chain.size() >= 3 and chain.size() <= 4, "%s: chain of %d quests" % [el, chain.size()])
		var last: Dictionary = chain[-1]
		expect(not ((last["rewards"] as Dictionary).get("techniques", []) as Array).is_empty(), "%s: chain ends with a technique unlock" % el)
		var types := {}
		var has_trainer_talk := false
		for q in chain:
			for st: Dictionary in q["stages"]:
				for o: Dictionary in st["objectives"]:
					types[o["type"]] = true
					if o["type"] == &"talk_to" and NpcRegistry.get_npc(o["npc"]).get("role", &"") == &"trainer":
						has_trainer_talk = true
		expect(has_trainer_talk, "%s: chain introduces the trainer" % el)
		expect(types.has(&"defeat"), "%s: chain sends the player to an encounter" % el)
		expect(types.has(&"discover") or types.has(&"go_to"), "%s: chain visits a place" % el)
		var sides := 0
		var travel := 0
		for q in qs:
			if q["nation"] == el and (q["kind"] == &"side" or q["kind"] == &"training"):
				sides += 1
			if q["nation"] == el and q["kind"] == &"travel":
				travel += 1
		expect(sides >= 2, "%s: %d side quests" % [el, sides])
		expect(travel >= 1, "%s: a cross-nation quest" % el)
		var trainers := 0
		for id in NpcRegistry.ids():
			var d := NpcRegistry.get_npc(id)
			if d["nation"] == el and d.has("trainer"):
				trainers += 1
		expect(trainers >= 1, "%s: a bending master" % el)


func test_named_npcs_and_targets_resolve_in_the_world() -> void:
	if not WorldData.has_world_data():
		return
	for id in NpcRegistry.ids():
		var xf := NpcRegistry.placement(id)
		if not expect(xf.origin.is_finite(), "npc %s has a place in the world" % id):
			continue
		var gy := WorldData.get_height(xf.origin.x, xf.origin.z)
		expect(xf.origin.y > gy - 6.0 and xf.origin.y < gy + 60.0, "npc %s stands near the ground (%s, terrain %.1f)" % [id, xf.origin, gy])
	for q in _data_quests():
		for st: Dictionary in q["stages"]:
			for o: Dictionary in st["objectives"]:
				for key: String in ["target", "to", "at", "near"]:
					if o.has(key):
						expect(QuestTargets.resolve(o[key]).is_finite(), "%s/%s: %s resolves" % [q["id"], o["id"], key])
				if o["type"] == &"discover":
					expect(not WorldData.get_poi(o["poi"]).is_empty(), "%s: poi %s exists" % [q["id"], o["poi"]])
				if o["type"] == &"defeat" and o["site"] != &"":
					expect(QuestTargets.site_center(o["site"]).is_finite(), "%s: site %s exists" % [q["id"], o["site"]])
				for pr: Variant in o.get("props", []):
					expect(QuestTargets.resolve((pr as Dictionary)["at"]).is_finite(), "%s/%s: prop place resolves" % [q["id"], o["id"]])
	# hand-placed spots at the Spirit Oasis stay on its lawn (pond rim .. garden wall) if the bake moves
	var oasis: Dictionary = RingLayout.from_city(Settlements.WATER_TRIBE).record.get("spirit_oasis", {})
	if not oasis.is_empty():
		var c: Vector3 = oasis["position"]
		var spots := {"naalu": NpcRegistry.placement(&"wt_naalu").origin}
		var moon := {}
		for q2 in _data_quests():
			if q2["id"] == &"wt_moon_and_ocean":
				moon = q2
		for st: Dictionary in moon.get("stages", []):
			for o: Dictionary in st["objectives"]:
				for pr: Variant in o.get("props", []):
					spots["bowl"] = QuestTargets.resolve((pr as Dictionary)["at"])
		for k: String in spots:
			var r := Vector2(spots[k].x - c.x, spots[k].z - c.z).length()
			expect(r > float(oasis["pond_radius"]) + 0.8 and r < float(oasis["radius"]) - 4.0, "%s on the oasis lawn (%.1f m from the pond centre)" % [k, r])


# --- NPC system -------------------------------------------------------------------------------------

func test_npc_budgets_scale_with_detail() -> void:
	var prev := -1
	for b: Dictionary in NpcDirector.BUDGETS:
		expect(int(b["max_npcs"]) > prev, "budget grows with detail")
		prev = int(b["max_npcs"])
		expect(int(b["tier_a"]) <= int(b["max_npcs"]), "full tier within budget")
	expect(int(NpcDirector.BUDGETS[0]["max_npcs"]) <= 10, "mobile budget stays small")
	expect(int(WildlifeDirector.BUDGETS[0]["animals"]) <= 6, "mobile wildlife budget stays small")


func test_crowd_records_are_deterministic_and_respect_claims() -> void:
	var anchors: Array = []
	for i in 40:
		anchors.append({"id": "test_settle_market_stall_%d" % i, "kind": &"market_stall", "settlement": &"northern_water_tribe",
			"position": Vector3(i * 3.0, 0, 0), "yaw": 0.0, "tags": [], "goods": "fish"})
	anchors.append({"id": "test_idle_pair", "kind": &"idle", "settlement": &"ba_sing_se", "position": Vector3.ZERO, "yaw": 0.0, "tags": []})
	var a := NpcCrowd.records_for(anchors, 1.0, {})
	var b := NpcCrowd.records_for(anchors, 1.0, {})
	expect_eq(a.size(), b.size(), "deterministic count")
	for i in mini(a.size(), b.size()):
		expect_eq(a[i]["key"], b[i]["key"], "deterministic keys")
		expect_eq(str(a[i]["look"]), str(b[i]["look"]), "deterministic looks")
	var merchants := a.filter(func(r: Dictionary) -> bool: return r["role"] == &"merchant").size()
	expect(merchants > 8 and merchants < 35, "about half the stalls are staffed (%d)" % merchants)
	var low := NpcCrowd.records_for(anchors, 0.5, {})
	expect(low.size() < a.size(), "lower density spawns fewer")
	var claims := {}
	for i2 in 40:
		claims["test_settle_market_stall_%d" % i2] = true
	var claimed := NpcCrowd.records_for(anchors, 1.0, claims)
	for r: Dictionary in claimed:
		expect(not String(r["key"]).begins_with("test_settle_market_stall_"), "claimed anchors skipped")
	for r2: Dictionary in a:
		expect((r2["look"] as Dictionary).has("preset"), "records carry a look")
		if r2["role"] == &"merchant":
			expect(r2["nation"] == &"water", "nation from the settlement")
	for nat: StringName in [&"water", &"earth", &"fire", &"air"]:
		var n := NpcLooks.variant_configs(nat).size()
		expect(n >= 6 and n <= 32, "%s crowd variants: %d" % [nat, n])


func test_routines_and_attitudes() -> void:
	expect_eq(NpcRoutines.activity(&"merchant", 12.0), &"work")
	expect_eq(NpcRoutines.activity(&"merchant", 23.0), &"home", "merchants sleep indoors")
	expect_eq(NpcRoutines.activity(&"guard", 2.0), &"guard", "guards keep watch at night")
	expect_eq(NpcRoutines.activity(&"child", 3.0), &"home")
	expect_eq(NpcRoutines.activity(&"child", 10.0), &"play")
	expect_eq(NpcRoutines.activity(&"fisher", 6.0), &"fish")
	expect(NpcRoutines.is_present(&"patrol", 3.0), "patrols at night")
	expect(not NpcRoutines.is_present(&"resident", 2.0), "residents home at night")
	expect(absf(NpcRoutines.offset_for(12345)) < 0.5, "personal offsets are small")
	expect_eq(NpcBarks.attitude(&"fire", ElementDefs.Element.WATER), &"wary", "fire folk wary of a waterbender")
	expect_eq(NpcBarks.attitude(&"air", ElementDefs.Element.FIRE), &"friendly", "air nomads welcome everyone")
	expect_eq(NpcBarks.attitude(&"water", ElementDefs.Element.WATER), &"own")
	expect(not NpcBarks.line(&"water", &"greet").is_empty(), "water greetings exist")
	expect(not NpcBarks.small_talk(&"earth", &"guard").is_empty(), "earth guards have small talk")


func _flat_world() -> void:
	WorldData.height_override = func(_x: float, _z: float) -> float: return 0.0


func _floor_node() -> StaticBody3D:
	var f := StaticBody3D.new()
	f.collision_layer = Layers.WORLD
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(800, 1, 800)
	cs.shape = bx
	cs.position = Vector3(0, -0.5, 0)
	f.add_child(cs)
	return f


func _crowd_record(key: StringName, pos: Vector3, role: StringName = &"guard") -> Dictionary:
	return {"key": key, "named": &"", "nation": &"earth", "role": role, "pos": pos, "yaw": 0.0, "home": pos,
		"look": {"preset": &"villager_earth", "seed": 1}, "hash": 1, "offset": 0.0, "tags": [], "goods": "",
		"route": PackedVector3Array(), "pair": &"", "wander": 3.0}


func test_director_keeps_the_nearest_within_budget() -> void:
	_flat_world()
	add_child(_floor_node())
	var pl := Node3D.new()
	pl.add_to_group(&"player")
	add_child(pl)
	var d := NpcDirector.new()
	add_child(d)
	d.player = pl
	d.max_npcs = 6
	d.crowd_range = 50.0
	d.tier_a = 3
	d.variant_gap = 0.0
	GameState.time_of_day = 12.0
	for i in 20:
		d.add_record(_crowd_record(StringName("t_%d" % i), Vector3(i * 4.0, 0, 0)))
	await seconds(1.4)
	expect_eq(d.live_count(), 6, "spawned up to the budget")
	var far := 0.0
	var fulls := 0
	for n in d.live_npcs():
		far = maxf(far, n.global_position.x)
		if n.full:
			fulls += 1
	expect(far <= 21.0, "kept the nearest (farthest at %.1f)" % far)
	expect(fulls <= 3, "full tier capped (%d)" % fulls)
	pl.global_position = Vector3(400, 0, 0)
	await seconds(1.0)
	await frames(30)
	expect_eq(d.live_count(), 0, "despawned when the player left")
	WorldData.height_override = Callable()


func test_named_npc_presence_and_marker() -> void:
	NpcRegistry.register_npc(&"test_giver_npc", {"name": "Test Giver", "nation": &"water", "place": {"pos": Vector3(3, 0, 3)},
		"present": {"flag": "test_giver_here"}, "talk": [{"tree": &"test_tree"}]})
	NpcRegistry.register_tree(&"test_tree", {"nodes": {"start": {"text": "Hello.", "end": true}}})
	Quests.register_quest({"id": &"test_q_side", "title": "Side", "giver": &"test_giver_npc", "stages": [{"objectives": [
		{"id": &"t", "type": &"talk_to", "npc": &"test_giver_npc", "text": "t"}]}]})
	_flat_world()
	add_child(_floor_node())
	var pl := Node3D.new()
	pl.add_to_group(&"player")
	add_child(pl)
	var d := NpcDirector.new()
	add_child(d)
	d.player = pl
	d.variant_gap = 0.0
	await seconds(0.6)
	expect(NpcRegistry.live_npc(&"test_giver_npc") == null, "absent while its condition fails")
	GameState.set_flag("test_giver_here", true)
	await seconds(0.8)
	var n := NpcRegistry.live_npc(&"test_giver_npc") as NpcCharacter
	if expect(n != null, "spawned once present"):
		expect(n.global_position.distance_to(Vector3(3, 0, 3)) < 0.5, "at its placement")
		expect_eq(Quests.npc_marker(&"test_giver_npc"), &"available")
		await seconds(0.7)
		expect_eq(n.marker.get_state(), &"available", "marker shows the available quest")
		expect(n.talk.get_interaction_text(pl).contains("Test Giver"), "talk prompt names the NPC")
	WorldData.height_override = Callable()
	NpcRegistry._npcs.erase(&"test_giver_npc")
	NpcRegistry._order.erase(&"test_giver_npc")
	NpcRegistry._trees.erase(&"test_tree")
	NpcRegistry.clear_placements()


func test_npc_reacts_to_combat_and_recovers() -> void:
	_flat_world()
	add_child(_floor_node())
	var pl := Node3D.new()
	pl.add_to_group(&"player")
	add_child(pl)
	pl.global_position = Vector3(0, 0, 30)
	var d := NpcDirector.new()
	add_child(d)
	d.player = pl
	d.variant_gap = 0.0
	GameState.time_of_day = 12.0
	d.add_record(_crowd_record(&"civ", Vector3.ZERO, &"resident"))
	await seconds(0.8)
	var n := d.live_npc(&"civ")
	if not expect(n != null, "civilian spawned"):
		WorldData.height_override = Callable()
		return
	var start := n.global_position
	n.react_threat(Vector3(0, 0, 3), 1.0)
	await seconds(0.3)
	expect(n.brain.override == &"flee" or n.brain.override == &"cower", "flees from combat (%s)" % n.brain.override)
	await seconds(2.0)
	expect(n.global_position.distance_to(Vector3(0, 0, 3)) > start.distance_to(Vector3(0, 0, 3)) + 2.0, "ran away from the danger")
	await seconds(9.0)
	expect_eq(n.brain.override, &"", "calmed down (no stuck reaction)")
	WorldData.height_override = Callable()


func test_escort_follows_catches_up_and_reports() -> void:
	NpcRegistry.register_npc(&"test_escortee", {"name": "Little Tester", "nation": &"earth", "place": {"pos": Vector3(0, 0, 0)},
		"talk": [{"tree": &"test_escort_tree"}]})
	NpcRegistry.register_tree(&"test_escort_tree", {"nodes": {"start": {"text": "Lead the way.", "end": true}}})
	Quests.register_quest({"id": &"test_q_side", "title": "Escort", "stages": [{"objectives": [
		{"id": &"home", "type": &"escort", "npc": &"test_escortee", "to": {"pos": Vector3(0, 0, -20)}, "radius": 4.0, "text": "e"}]}]})
	_flat_world()
	add_child(_floor_node())
	# a long wall the follower cannot walk round
	var wall := StaticBody3D.new()
	wall.collision_layer = Layers.WORLD
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(80, 3, 0.6)
	cs.shape = bx
	wall.add_child(cs)
	add_child(wall)
	wall.global_position = Vector3(0, 1.5, -6)
	var pl := Node3D.new()
	pl.add_to_group(&"player")
	add_child(pl)
	pl.global_position = Vector3(0, 0, 3)
	var d := NpcDirector.new()
	add_child(d)
	d.player = pl
	d.variant_gap = 0.0
	Quests.start(&"test_q_side", {"silent": true})
	await seconds(1.0)
	var n := NpcRegistry.live_npc(&"test_escortee") as NpcCharacter
	if expect(n != null, "escortee spawned"):
		expect_eq(n.brain.override, &"follow", "follows the player once the escort is active")
		pl.global_position = Vector3(0, 0, -12)          # the player crosses where the NPC cannot
		await seconds(6.5)
		expect(n.global_position.distance_to(pl.global_position) < 5.0,
			"caught up after being stuck behind the wall (%.1f m)" % n.global_position.distance_to(pl.global_position))
		pl.global_position = Vector3(0, 0, -20)
		await seconds(5.0)
		expect(Quests.is_completed(&"test_q_side"), "escort reported on arrival (npc %s)" % n.global_position)
		expect(n.brain.override != &"follow", "stops following at the destination")
	WorldData.height_override = Callable()
	NpcRegistry._npcs.erase(&"test_escortee")
	NpcRegistry._order.erase(&"test_escortee")
	NpcRegistry._trees.erase(&"test_escort_tree")
	NpcRegistry.clear_placements()


# --- merchants, trainers, dialogue --------------------------------------------------------------------

func test_merchant_buy_sell_and_restock() -> void:
	GameState.currency = 30
	var stock := MerchantStock.stock(&"nwt_healer")
	expect(stock.size() >= 3, "healer sells several remedies")
	var salve := {}
	for r in stock:
		if r["item"] == &"healing_salve":
			salve = r
	expect(int(salve.get("left", -2)) == 4, "limited stock")
	expect_eq(MerchantStock.buy(&"nwt_healer", &"healing_salve"), &"", "bought")
	expect_eq(GameState.item_count(&"healing_salve"), 1)
	expect_eq(GameState.currency, 30 - int(salve["price"]))
	GameState.currency = 0
	expect_eq(MerchantStock.buy(&"nwt_healer", &"healing_salve"), &"coins", "cannot afford")
	GameState.currency = 500
	for i in 3:
		MerchantStock.buy(&"nwt_healer", &"healing_salve")
	expect_eq(MerchantStock.buy(&"nwt_healer", &"healing_salve"), &"sold_out", "sold out")
	GameState.play_time += MerchantStock.DAY_SECONDS
	expect_eq(MerchantStock.buy(&"nwt_healer", &"healing_salve"), &"", "restocked the next day")
	var before := GameState.currency
	GameState.add_item(&"jade_shard", 2)
	expect(MerchantStock.sell(&"jade_shard") > 0, "sold jade")
	expect(GameState.currency > before and GameState.item_count(&"jade_shard") == 1, "coins up, item down")
	GameState.add_item(&"navy_orders", 1)
	expect_eq(MerchantStock.sell(&"navy_orders"), 0, "quest items are not for sale")
	expect(not MerchantStock.stock(&"stall_water_fish").is_empty(), "fish stall stock")
	expect(MerchantStock.price(&"stall_earth_", &"carved_whale_tooth") > TradeGoods.buy_price(&"carved_whale_tooth"), "foreign goods cost more")
	expect(TradeGoods.is_usable(&"arctic_moss") and not TradeGoods.is_usable(&"rope_coil"), "use effects")


func test_trainer_teaches_trainer_techniques() -> void:
	var d := AbilityRegistry.get_def(&"ice_shards").duplicate() as AbilityDef
	d.id = &"test_trainer_tech"
	d.display_name = "Test Tide"
	d.starter = false
	d.unlock = {"level": 2, "trainer": "water_master"}
	AbilityRegistry.register(d)
	expect(not TrainerLessons.lessons_for(&"wt_siku").has(&"test_trainer_tech"), "level gate")
	expect(TrainerLessons.future_lessons(&"wt_siku").size() >= 1, "listed as a future lesson")
	GameState.level = 2
	expect(TrainerLessons.lessons_for(&"wt_siku").has(&"test_trainer_tech"), "teachable at level 2")
	expect(TrainerLessons.lessons_for(&"fn_jinzo").is_empty(), "a fire master teaches no waterbender")
	expect_eq(AbilityRegistry.can_unlock(&"test_trainer_tech"), &"trainer", "registry wants the trainer")
	var spec := TrainerLessons.lesson_spec(&"test_trainer_tech")
	expect(spec.get("kind") == &"targets" and int(spec.get("hits", 0)) > 0, "lesson challenge spec")
	TrainerLessons.complete_lesson(&"wt_siku", &"test_trainer_tech")
	expect(GameState.is_unlocked(&"test_trainer_tech"), "learned")
	expect(bool(GameState.get_flag("trained_water_master_test_trainer_tech")), "trainer flag for the registry contract")
	TrainerLessons.ensure_spar_archetypes()
	for nat: StringName in [&"water", &"earth", &"fire", &"air"]:
		var a := EnemyArchetypes.get_archetype(StringName("spar_%s" % nat))
		expect(not a.is_empty() and int(a["xp"]) == 0 and (a["loot"] as Array).is_empty(), "spar_%s has no rewards" % nat)
	AbilityRegistry._defs.erase(&"test_trainer_tech")


func test_dialogue_runner_conditions_choices_and_actions() -> void:
	var holder := GDScript.new()
	holder.source_code = "extends Node\nvar dialogue: DialogueBox\n"
	holder.reload()
	var sc: Node = holder.new()
	var box: DialogueBox = (load("res://scenes/ui/dialogue_box.tscn") as PackedScene).instantiate()
	sc.set("dialogue", box)
	sc.add_child(box)
	add_child(sc)
	sc.add_to_group(&"playable_scene")
	var runner := DialogueRunner.new()
	add_child(runner)
	Quests.register_quest({"id": &"test_q_side", "title": "Side", "stages": [{"objectives": [{"id": &"t", "type": &"talk_to", "npc": &"zz", "text": "t"}]}]})
	var tree := DialogueTree.normalize(&"t", {"nodes": {
		"start": {"text": "Hello {player}.", "next": "ask"},
		"ask": {"text": "Choose.", "choices": [
			{"text": "Hidden", "if": {"level": 99}, "next": "never"},
			{"text": "Take quest", "do": [["start_quest", &"test_q_side"], ["give_item", &"rope_coil", 1]], "next": "route"}]},
		"route": {"branch": [{"if": {"quest": [&"test_q_side", "active"]}, "next": "yes"}, {"next": "never"}]},
		"yes": {"text": "Good.", "do": [["flag", "test_dialogue_done"]], "end": true},
		"never": {"text": "Never.", "end": true}}})
	var seen := {"choices": -1}
	var driver := func() -> void:
		for i in 600:
			await get_tree().process_frame
			if not is_instance_valid(runner) or not is_instance_valid(box) or (not runner.busy and i > 2):
				return
			if box.choices.size() > 0:
				seen["choices"] = box.choices.size()
				box.choose(0)
			else:
				box.advance()
	driver.call()
	await runner.run_tree(null, tree)
	expect_eq(int(seen["choices"]), 1, "hidden choice filtered")
	expect(Quests.is_active(&"test_q_side"), "start_quest action ran")
	expect_eq(GameState.item_count(&"rope_coil"), 1, "give_item action ran")
	expect(bool(GameState.get_flag("test_dialogue_done")), "branch routed to the active-quest node")
	var texts: Array = runner.transcript.map(func(l: Array) -> String: return String(l[1]))
	expect(texts.has("Hello %s." % GameState.player_name), "placeholders formatted")
	expect(not texts.has("Never."), "never reached the wrong branch")


func test_wildlife_rules_find_species_where_they_live() -> void:
	if not WorldData.has_world_data():
		return
	var prov := WildlifeProvider.new(null)
	prov.configure()
	var found := {}
	var cells: Array[Vector2i] = []
	for x in range(-6, 8):
		for y in range(-25, -19):
			cells.append(Vector2i(x, y))
	for x2 in range(5, 12):
		for y2 in range(-2, 5):
			cells.append(Vector2i(x2, y2))
	for x3 in range(-28, -20):
		for y3 in range(18, 26):
			cells.append(Vector2i(x3, y3))
	for c in cells:
		var cell := ContentCell.new(prov, c)
		prov.build_cell(cell)
		for r: Dictionary in (cell.payload as CellPayload).data["wildlife"]:
			found[r.get("species", r.get("flock", &""))] = true
			if r.has("species") and r["species"] != &"sky_bison" and r["species"] != &"turtle_duck":
				expect(Settlements.settlement_at(r["pos"]) == &"", "wild %s stays out of the cities" % r["species"])
	for sp: StringName in [&"otter_penguin", &"ostrich_horse", &"komodo_rhino"]:
		expect(found.has(sp), "%s lives somewhere in its biome (found %s)" % [sp, found.keys()])
	expect(prov._bison_spots.size() >= 2, "bison stalls at the Air Temple")
