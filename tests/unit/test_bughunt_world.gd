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
