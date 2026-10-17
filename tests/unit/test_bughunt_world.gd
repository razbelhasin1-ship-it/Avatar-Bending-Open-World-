extends TestCase
## bughunt_world (wave 4 QA): regression tests for the world / streaming / settlements / quests /
## UI / save / mobile bugs found by the adversarial bug hunt (docs/qa/bughunt_world.md). Each test
## reproduces the original failure on the old code.

const E := ElementDefs.Element


func before_each() -> void:
	WorldData.use_flat_world(false)
	WorldData.load_world()


func after_each() -> void:
	WorldData.use_flat_world(false)
	WorldData.height_override = Callable()
	GroundSampler.clear_zones()
	for n in get_children():
		n.queue_free()
	await frames(2)


# --- water: gameplay water matches the drawn water ------------------------------------------------

## Points of an unfrozen lake whose ground lies below the lake level but outside the water the
## renderer draws (WorldRecords.lake_surface_polygon) - [Vector3 ground point, lake level].
func _dry_points_below_level(lk: Dictionary, step: float = 2.0) -> Array:
	var out: Array = []
	var c: Vector3 = lk["center"]
	var surf := WorldRecords.lake_surface_polygon(lk)
	var r := float(lk["radius"]) + 2.0
	var x := c.x - r
	while x <= c.x + r:
		var z := c.z - r
		while z <= c.z + r:
			var p := Vector2(x, z)
			if p.distance_to(Vector2(c.x, c.z)) <= float(lk["radius"]) and not Geometry2D.is_point_in_polygon(p, surf):
				var g := WorldData.get_height(x, z)
				if float(lk["level"]) - g > 2.0:
					out.append([Vector3(x, g, z), float(lk["level"])])
			z += step
		x += step
	return out


## The lake test used the bounding radius while the water is drawn by the (grown) polygon: below
## the Thundering Steps falls the outlet gorge lies 15-18 m under the pool level inside that
## radius, so the ground there counted as deep water. A player walking down the gorge "swam" -
## the motor pulls a swimmer up to the surface, i.e. 15 m into the air - and companions / safe
## ground / fast travel treated dry land as lake. Now water is reported exactly where it is drawn.
func test_lake_water_only_where_it_is_drawn() -> void:
	if not expect(WorldData.has_world_data(), "baked world data"):
		return
	var checked := 0
	var wrong: Array[String] = []
	for lk: Dictionary in WorldData.get_lakes():
		if lk["frozen"]:
			continue
		for e: Array in _dry_points_below_level(lk):
			var g: Vector3 = e[0]
			checked += 1
			if WorldData.get_water_height(g.x, g.z) > -INF and wrong.size() < 6:
				wrong.append("%s (%.0f, %.0f) ground %.1f, %.1f m under the level" % [lk["id"], g.x, g.z, g.y, float(e[1]) - g.y])
		# ...and inside the drawn water below the level it still is water
		var c: Vector3 = lk["center"]
		var gc := WorldData.get_height(c.x, c.z)
		if gc < float(lk["level"]) - 0.3:
			expect(WorldData.get_water_height(c.x, c.z) == float(lk["level"]), "%s: water at its centre" % lk["id"])
	expect(checked > 20, "found dry ground below lake levels to check (%d)" % checked)
	expect(wrong.is_empty(), "no water reported outside the drawn lakes: %s" % ", ".join(wrong))


## Saves into a private folder (user://saves_test is shared by every test / agent run).
func _private_saves() -> String:
	var dir := "user://saves_bughunt_world_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(dir)
	SaveSystem.save_dir = dir
	return dir


func _drop_saves(dir: String) -> void:
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)
	SaveSystem.save_dir = SaveSystem.TEST_SAVE_DIR


# --- NPC streaming ----------------------------------------------------------------------------------

## Seen in every fast travel of the world audit: "SCRIPT ERROR: Trying to assign invalid
## previously freed instance" in NpcDirector.remove_records (a settlement cell released behind the
## player). An NPC that faded out (vanish) frees itself before the director's next update prunes
## its live table; remove_records read it into a typed variable, the error aborted the loop and
## the rest of the cell's crowd records stayed registered.
func test_releasing_a_cell_with_a_vanished_npc() -> void:
	WorldData.height_override = func(_x: float, _z: float) -> float: return 0.0
	PlayerSim.ground(self, 200.0)
	var pl := Node3D.new()
	pl.add_to_group(&"player")
	add_child(pl)
	var d := NpcDirector.new()
	add_child(d)
	d.player = pl
	d.variant_gap = 0.0
	GameState.time_of_day = 12.0
	var recs: Array = []
	for i in 4:
		var pos := Vector3(3.0 + i * 2.0, 0, 2.0)
		recs.append({"key": StringName("bw_%d" % i), "named": &"", "nation": &"earth", "role": &"guard", "pos": pos, "yaw": 0.0,
			"home": pos, "look": {"preset": &"villager_earth", "seed": 1}, "hash": 1, "offset": 0.0, "tags": [], "goods": "",
			"route": PackedVector3Array(), "pair": &"", "wander": 3.0})
	d.add_records(Vector2i(7, 7), recs)
	await seconds(1.4)
	if not expect(d.live_count() == 4, "the cell's crowd spawned (%d)" % d.live_count()):
		WorldData.height_override = Callable()
		return
	var first := d.live_npc(&"bw_0")
	first.vanish(0.05)
	for i in 30:
		await frames(1)
		if not is_instance_valid(first):
			break
	expect(not is_instance_valid(first), "the NPC faded out and freed itself")
	d.remove_records(Vector2i(7, 7))      # before the director's next update
	expect_eq(d.record_count(), 0, "every record of the released cell is gone")
	await frames(2)
	expect_eq(d.live_npcs().size(), 0, "and every NPC of it")
	WorldData.height_override = Callable()


# --- settings ----------------------------------------------------------------------------------------

## A value the menu could set for `row` that differs from the current one (null = none).
static func _other_value(row: Dictionary) -> Variant:
	var cur: Variant = Settings.get_value(String(row["section"]), String(row["key"]))
	match String(row["kind"]):
		"toggle":
			return not bool(cur)
		"slider":
			var v := float(row["min"]) + float(row["step"]) * 3.0
			return v if not is_equal_approx(v, float(cur)) else float(row["min"]) + float(row["step"]) * 5.0
		"choice":
			for it: Dictionary in row.get("items", []):
				if it.get("disabled", false) or it["value"] == cur:
					continue
				return it["value"]
	return null


## Settings that do not survive a restart: every option of every settings tab is changed the way
## the menu does it (values from SettingsSchema rows), saved, the game "restarts" (defaults, then
## load_settings + apply like Settings._ready) - each value must come back with its type, and a
## rebound key must still be bound. Verified clean (no bug found): kept as a guard.
func test_every_settings_row_survives_a_restart() -> void:
	var before := Settings.snapshot()
	var path := "user://settings_bughunt_world_%d.cfg" % Time.get_ticks_usec()
	Settings.save_path = path
	var want := {}
	for tab: String in SettingsSchema.TABS:
		for row: Dictionary in SettingsSchema.rows(tab):
			if not row.has("key") or String(row.get("kind", "")) == "header" or String(row["key"]) == "preset":
				continue
			var v: Variant = _other_value(row)
			if v == null:
				continue
			Settings.set_value(String(row["section"]), String(row["key"]), v)
			want["%s.%s" % [row["section"], row["key"]]] = v
	Settings.set_binding(&"jump", "kbm", {"type": "key", "code": KEY_J})
	Settings.save()
	# restart
	Settings.restore_defaults()
	Settings.load_settings()
	Settings.apply()
	var lost: Array[String] = []
	for k: String in want:
		var parts := k.split(".")
		var got: Variant = Settings.get_value(parts[0], parts[1])
		var same: bool = got == want[k] if typeof(got) == typeof(want[k]) else (want[k] is float and got is float and is_equal_approx(got, want[k]))
		if not same:
			lost.append("%s: wanted %s (%s), got %s (%s)" % [k, str(want[k]), type_string(typeof(want[k])), str(got), type_string(typeof(got))])
	expect(want.size() >= 30, "changed %d options" % want.size())
	expect(lost.is_empty(), "every option survives the restart: %s" % "; ".join(lost))
	var jump_keys: Array = []
	for ev in InputMap.action_get_events(&"jump"):
		if ev is InputEventKey:
			jump_keys.append((ev as InputEventKey).physical_keycode)
	expect(jump_keys.has(KEY_J), "the rebound jump key is bound after the restart (%s)" % str(jump_keys))
	var master := AudioServer.get_bus_index("Master")
	expect_near(db_to_linear(AudioServer.get_bus_volume_db(master)), float(Settings.get_value("audio", "master")), 0.01, "master volume applied")
	# leave everything as it was
	DirAccess.remove_absolute(path)
	Settings.save_path = Settings.SAVE_PATH
	Settings.restore_snapshot(before)
	Settings.apply()


# --- quests ------------------------------------------------------------------------------------------

## Journal -> ABANDON on a side quest that hands out an item (a letter, a parcel, incense) kept the
## item; starting the quest again handed out another. Only one is ever delivered, so every abandon
## left an unsellable quest item in the bag for good. Items gathered from the quest's props stayed
## too while the props came back on the restart (gather, abandon, gather again - and sell).
func test_abandoning_a_quest_takes_back_its_handouts() -> void:
	GameState.new_game(E.WATER)
	var q := &"wt_pale_moon_shrine"
	if not expect(Quests.has_quest(q), "quest data present"):
		return
	expect(Quests.start(q, {"silent": true}), "started")
	expect_eq(GameState.item_count(&"spirit_incense"), 1, "incense handed out")
	expect(Quests.abandon(q), "abandoned")
	expect_eq(GameState.item_count(&"spirit_incense"), 0, "the incense goes back with the quest")
	Quests.start(q, {"silent": true})
	Quests.abandon(q)
	Quests.start(q, {"silent": true})
	expect_eq(GameState.item_count(&"spirit_incense"), 1, "after two abandons the bag holds one incense, not three")
	Quests.reset_quest(q)
	GameState.add_item(&"spirit_incense", -GameState.item_count(&"spirit_incense"))
	# gathered prop items go back too (only what the props gave: moss bought elsewhere stays)
	var moss := &"wt_healers_moss"
	GameState.add_item(&"arctic_moss", -GameState.item_count(&"arctic_moss"))
	Quests.start(moss, {"silent": true})
	for i in 2:
		QuestProps.mark_taken(moss, &"moss", i)
		GameState.add_item(&"arctic_moss", 1)
	GameState.add_item(&"arctic_moss", 1)                      # one bought at a stall
	expect_eq(Quests.progress(moss, &"moss"), 3, "three of four held (%d)" % Quests.progress(moss, &"moss"))
	Quests.abandon(moss)
	expect_eq(GameState.item_count(&"arctic_moss"), 1, "the gathered moss went back, the bought one stayed")
	Quests.start(moss, {"silent": true})
	expect_eq(Quests.progress(moss, &"moss"), 1, "a restart counts what the player really holds")
	expect(not QuestProps.is_taken(moss, &"moss", 0), "and its props are back in the world")
	Quests.reset_quest(moss)


## Every action a conversation can reach in the current state: branches are routed as the runner
## routes them, every visible choice is a path the player may take.
static func _reachable_actions(tree: Dictionary) -> Array:
	var out: Array = []
	var seen := {}
	var stack: Array[String] = [String(tree.get("start", "start"))]
	while not stack.is_empty():
		var key: String = stack.pop_back()
		if key == "" or seen.has(key):
			continue
		seen[key] = true
		var node := DialogueTree.get_node_data(tree, key)
		if node.is_empty():
			continue
		out.append_array(node.get("do", []))
		if node.has("branch") and not node.has("text") and not node.has("lines"):
			stack.append(DialogueTree.route(node))
			continue
		var choices := DialogueTree.visible_choices(node)
		for c in choices:
			out.append_array(c.get("do", []))
			if not bool(c.get("end", false)):
				stack.append(String(c.get("next", "")))
		if choices.is_empty():
			stack.append(DialogueTree.route(node) if node.has("branch") else ("" if bool(node.get("end", false)) else String(node.get("next", ""))))
	return out


static func _has_action(actions: Array, verb: StringName, args: Array) -> bool:
	for a: Variant in actions:
		if not (a is Array) or (a as Array).size() < args.size() + 1 or StringName(str(a[0])) != verb:
			continue
		var ok := true
		for i in args.size():
			if StringName(str(a[i + 1])) != StringName(str(args[i])):
				ok = false
		if ok:
			return true
	return false


## The element a quest is played with (its `requires` element, else its nation).
static func _quest_element(d: Dictionary) -> int:
	var req: Variant = d.get("requires")
	if req is Dictionary and (req as Dictionary).has("element"):
		var e: Variant = req["element"]
		return ElementDefs.from_id(StringName(str(e[0] if e is Array else e)))
	var n := ElementDefs.from_id(StringName(str(d.get("nation", "water"))))
	return n if ElementDefs.is_valid(n) else E.WATER


## Some present NPC's conversation in the current state can start `q`.
static func _offered(q: StringName) -> bool:
	for id in NpcRegistry.ids():
		var tid := NpcRegistry.pick_tree(id)
		if tid != &"" and QuestConditions.check(NpcRegistry.get_npc(id).get("present")) \
				and _has_action(_reachable_actions(NpcRegistry.dialogue_tree(tid)), &"start_quest", [q]):
			return true
	return false


## Puts the journey where `q` can be offered: its element, max level, required quests completed.
func _make_available(q: StringName) -> void:
	var d := Quests.get_def(q)
	GameState.new_game(_quest_element(d))
	GameState.level = GameState.MAX_LEVEL
	var req: Variant = d.get("requires")
	var reqs: Array = [req] if req is Dictionary else (req if req is Array else [])
	for r: Variant in reqs:
		if r is Dictionary and (r as Dictionary).has("quest"):
			var qa: Array = r["quest"] if r["quest"] is Array else [r["quest"]]
			if String(qa[1] if qa.size() > 1 else "completed") in ["completed", "started"]:
				Quests.force_complete(StringName(str(qa[0])))


## Dialogue dead ends: a quest that should be on offer but no NPC conversation in that state can
## start it; a challenge objective whose NPC's conversation never offers the challenge; an NPC a
## talk / challenge / escort objective needs who is not in the world at that point of the quest.
func test_no_dialogue_dead_ends_in_any_quest() -> void:
	var dead: Array[String] = []
	var checked := 0
	var started_by_chain := {}
	for q: StringName in Quests.order:
		var nx: StringName = Quests.get_def(q).get("next", &"")
		if nx != &"":
			started_by_chain[nx] = true
	for q: StringName in Quests.order:
		if String(q).begins_with("test_"):
			continue
		var d := Quests.get_def(q)
		# 1. on offer -> some NPC's conversation in this state starts it
		if d.get("auto_start") == null and not started_by_chain.has(q):
			_make_available(q)
			if not Quests.is_available(q):
				dead.append("%s: could not be made available (requires %s)" % [q, str(d.get("requires"))])
			else:
				checked += 1
				var found := _offered(q)
				# a giver busy with another quest's line offers it once the player moves that one on
				var rounds := 0
				while not found and rounds < 4 and Quests.is_available(q):
					rounds += 1
					for other in Quests.active_quests():
						for o3: Dictionary in Quests.stage_def(other).get("objectives", []):
							Quests.complete_objective(other, o3["id"])
					found = _offered(q)
				if not found:
					dead.append("%s: available, but no present NPC's conversation can start it (giver %s talks with %s)" % [q,
						d.get("giver"), NpcRegistry.pick_tree(StringName(str(d.get("giver", ""))))])
		# 2. every NPC-bound objective, at its stage
		var stages: Array = d.get("stages", [])
		for si in stages.size():
			for od: Dictionary in (stages[si] as Dictionary)["objectives"]:
				var npc := StringName(str(od.get("npc", "")))
				if npc == &"":
					continue
				_make_available(q)
				Quests.reset_quest(q)
				Quests.start(q, {"silent": true})
				var guard := 0
				while Quests.is_active(q) and Quests.current_stage(q) < si and guard < 16:
					guard += 1
					for o2: Dictionary in Quests.stage_def(q).get("objectives", []):
						if Quests.current_stage(q) < si:
							Quests.complete_objective(q, o2["id"])
				if not Quests.is_objective_active(q, od["id"]):
					dead.append("%s/%s: could not reach the objective" % [q, od["id"]])
					continue
				checked += 1
				var present := false
				for hr in 24:
					GameState.time_of_day = float(hr) + 0.5
					if QuestConditions.check(NpcRegistry.get_npc(npc).get("present")):
						present = true
						break
				GameState.time_of_day = 12.0
				if not present:
					dead.append("%s/%s: %s is never in the world while it is due" % [q, od["id"], npc])
				if od["type"] == &"challenge" and not od.has("at"):
					var tid2 := NpcRegistry.pick_tree(npc)
					if not _has_action(_reachable_actions(NpcRegistry.dialogue_tree(tid2)), &"challenge", [q, od["id"]]):
						dead.append("%s/%s: %s's conversation (%s) never offers the challenge" % [q, od["id"], npc, tid2])
		Quests.reset_quest(q)
	GameState.new_game(E.WATER)
	for q2: StringName in Quests.order:
		Quests.reset_quest(q2)
	expect(checked > 40, "checked %d offers / objectives" % checked)
	expect(dead.is_empty(), "dialogue dead ends:\n    %s" % "\n    ".join(dead))


# --- saves -------------------------------------------------------------------------------------------

## A slot file damaged on disk (a crash mid-write on a platform without atomic rename, storage
## corruption, a quota-truncated write) used to read as "no save": the journey was simply gone.
## The previous save is now kept as `.bak` and read when the slot itself is unreadable.
func test_damaged_save_falls_back_to_the_previous_one() -> void:
	var dir := _private_saves()
	GameState.new_game(E.FIRE)
	GameState.level = 6
	expect(SaveSystem.save_game(0), "first save")
	GameState.level = 7
	expect(SaveSystem.save_game(0), "second save")
	var f := FileAccess.open(SaveSystem.slot_path(0), FileAccess.WRITE)
	f.store_string("{\n\t\"element\": 2,\n\t\"level\": 7,\n\t\"inv")      # truncated mid-file
	f.close()
	expect(SaveSystem.has_save(0), "the slot still counts as a save")
	var info := SaveSystem.get_save_info(0)
	expect(not info.is_empty() and int(info.get("level", 0)) == 6, "the previous save is offered (%s)" % str(info))
	GameState.reset()
	expect(SaveSystem.load_game(0), "loading recovers the journey")
	expect(GameState.element == E.FIRE and GameState.level == 6, "previous save loaded (element %d level %d)" % [GameState.element, GameState.level])
	_drop_saves(dir)


## A crash between writing the temp file and renaming it (the old code removed the slot first)
## left only `slot_0.json.tmp`: the menu showed no CONTINUE. A complete temp file is recovered.
func test_save_interrupted_before_the_rename_is_recovered() -> void:
	var dir := _private_saves()
	GameState.new_game(E.AIR)
	GameState.level = 4
	var json := JSON.stringify(GameState.to_dict(), "\t")
	var f := FileAccess.open(SaveSystem.slot_path(0) + ".tmp", FileAccess.WRITE)
	f.store_string(json)
	f.close()
	expect(SaveSystem.has_save(0) and SaveSystem.has_any_save(), "the interrupted save is found")
	GameState.reset()
	expect(SaveSystem.load_game(0) and GameState.element == E.AIR and GameState.level == 4, "and loads (element %d level %d)" % [GameState.element, GameState.level])
	# a normal save then replaces it cleanly and leaves no temp file behind
	expect(SaveSystem.save_game(0), "saves again")
	expect(not FileAccess.file_exists(SaveSystem.slot_path(0) + ".tmp"), "no temp file left")
	SaveSystem.delete_save(0)
	expect(not SaveSystem.has_save(0), "delete removes the slot, its temp and backup files")
	_drop_saves(dir)


## JSON writes a NaN float as null; GameState.from_dict then called int(null) / float(null),
## aborting the whole load with a script error ("Nonexistent 'int' constructor") - CONTINUE failed
## for the journey. Damaged / wrongly typed fields now fall back to their defaults.
func test_damaged_fields_do_not_make_a_journey_unloadable() -> void:
	var save := {"version": null, "element": E.EARTH, "level": "7", "xp": null, "skill_points": null, "currency": null,
		"player_yaw": null, "time_of_day": null, "play_time": null, "player_health_ratio": null,
		"equipped_abilities": "oops", "unlocked_abilities": 5, "inventory": [], "quests": "x", "tracked_quest": null,
		"companion": {"bond": null, "health_ratio": null, "type": null}, "player_position": [1.0, null, 3.0],
		"region": null, "intro_done": null}
	expect(GameState.from_dict(save), "from_dict accepts the damaged save")
	expect(GameState.element == E.EARTH and GameState.level == 1 and GameState.xp == 0, "defaults where values were damaged")
	expect(GameState.equipped_abilities.size() == 4 and GameState.equipped_abilities[0] == &"", "loadout reset")
	expect(not GameState.player_position.is_finite(), "a broken position is dropped (spawn used instead)")
	expect(GameState.companion["type"] == String(ElementDefs.get_data(E.EARTH)["companion"]), "companion species restored")
	expect(is_finite(GameState.player_yaw) and is_finite(GameState.time_of_day) and GameState.intro_done, "numbers finite")
	# a real NaN round trip through a save file
	var dir := _private_saves()
	GameState.new_game(E.WATER)
	GameState.player_yaw = NAN
	GameState.companion["health_ratio"] = NAN
	expect(SaveSystem.save_game(0), "a save with a NaN is written")
	GameState.reset()
	expect(SaveSystem.load_game(0) and GameState.element == E.WATER, "and loads back")
	_drop_saves(dir)


## A swimmer pressing jump against a wall climbs out only when standing room is found above it.
## The check looked 1.8 m above the swimmer (who floats 1.3 m under the surface): only ledges up to
## ~0.5 m above the water could be climbed. The Water Tribe's canals run 1.8 m below their walkways
## (+ a 0.3 m curb), so a player who stepped over the curb into a canal (the city walk audit did, at
## the end of the ring canal) could not get out anywhere along it - no bending while swimming
## either. Ledges up to 2.3 m above the water are climbable now; low ledges work as before.
func _swim_climb(ledge: float, curb: float = 0.0) -> Dictionary:
	WorldData.height_override = func(_x: float, _z: float) -> float: return -4.0      # sea at 0, 4 m deep
	PlayerSim.box(self, Vector3(0, -4.5, 0), Vector3(40, 1, 40))
	# the canal wall: face at x = 2, top `ledge` above the water, walkway 6 m deep
	PlayerSim.box(self, Vector3(5, (ledge - 4.0) * 0.5, 0), Vector3(6, ledge + 4.0, 20))
	if curb > 0.0:
		PlayerSim.box(self, Vector3(2.4, ledge + curb * 0.5, 0), Vector3(0.45, curb, 20))
	var p := PlayerSim.player(self, E.FIRE, Vector3(0.6, -1.3, 0))
	p.motor.yaw = -PI * 0.5                       # facing +x, the wall
	p.rotation.y = -PI * 0.5
	await PlayerSim.step(p, 30)
	var swam := p.motor.swimming
	p.input.press(&"move_right")
	await PlayerSim.step(p, 90)                   # swim up against the wall
	p.input.press(&"jump")
	await PlayerSim.step(p, 4)
	p.input.release(&"jump")
	await PlayerSim.step(p, 90)
	p.input.release_all()
	var out := {"swam": swam, "out": not p.motor.swimming and p.global_position.y > ledge - 0.3 and p.global_position.x > 2.3,
		"pos": p.global_position}
	p.queue_free()
	for n in get_children():
		n.queue_free()
	await frames(2)
	return out


func test_swimmer_climbs_out_of_a_canal() -> void:
	for spec: Array in [[0.3, 0.0], [1.8, 0.32], [2.2, 0.0]]:
		var r: Dictionary = await _swim_climb(spec[0], spec[1])
		expect(r["swam"], "swimming in the canal first (ledge %.1f)" % spec[0])
		expect(r["out"], "climbs onto a ledge %.1f m above the water (+%.2f m curb): now at %s" % [spec[0], spec[1], str(r["pos"])])
	WorldData.height_override = Callable()


## The real symptom: a player standing on the dry gorge floor below the falls pool did not stand,
## it swam (and rose towards the pool level, high above the ground).
func test_player_below_a_falls_pool_walks_instead_of_swimming() -> void:
	var spot := Vector3.INF
	var level := 0.0
	for lk: Dictionary in WorldData.get_lakes():
		if lk["frozen"]:
			continue
		for e: Array in _dry_points_below_level(lk, 1.0):
			if float(e[1]) - (e[0] as Vector3).y > 6.0:
				spot = e[0]
				level = e[1]
				break
		if spot.is_finite():
			break
	if not expect(spot.is_finite(), "a dry point well below a lake level exists"):
		return
	PlayerSim.box(self, spot + Vector3(0, -0.5, 0), Vector3(30, 1, 30))
	var p := PlayerSim.player(self, E.EARTH, spot + Vector3.UP * 0.05)
	await PlayerSim.step(p, 90)
	expect(not p.motor.swimming, "not swimming on dry ground %.1f m below the pool level (depth read %.1f)" % [level - spot.y, p.motor.water_depth])
	expect(p.global_position.y < spot.y + 0.6, "stays on the ground (y %.2f, ground %.2f)" % [p.global_position.y, spot.y])
