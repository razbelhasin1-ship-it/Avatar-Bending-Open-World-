extends TestCase
## Companions in the real world scene (headless, streamed terrain collision): the world
## hook spawns the element's companion beside the player on real ground, links it to the
## player and the HUD, it follows the player walking over real terrain, a flyer takes off
## and lands on the real heightfield with the player riding, and saves carry its state.

const WORLD := "res://scenes/world/world.tscn"
const E := ElementDefs.Element

var _slots: Dictionary = {}


func before_each() -> void:
	WorldData.load_world()
	GameState.reset()
	_slots.clear()
	for i in SaveSystem.MAX_SLOTS:
		if SaveSystem.has_save(i):
			_slots[i] = FileAccess.get_file_as_string(SaveSystem.slot_path(i))
			SaveSystem.delete_save(i)


func after_each() -> void:
	for i in SaveSystem.MAX_SLOTS:
		SaveSystem.delete_save(i)
		if _slots.has(i):
			var f := FileAccess.open(SaveSystem.slot_path(i), FileAccess.WRITE)
			f.store_string(String(_slots[i]))
			f.close()
	GameState.reset()
	Engine.time_scale = 1.0
	for a in InputMap.get_actions():
		if Input.is_action_pressed(a):
			Input.action_release(a)


func _world(e: int) -> WorldScene:
	GameState.new_game(e)
	GameState.intro_done = true
	var w := (load(WORLD) as PackedScene).instantiate() as WorldScene
	w.options = {"new_game": true, "skip_intro": true, "no_content": true}
	add_child(w)
	var t0 := Time.get_ticks_msec()
	while not w.playing and Time.get_ticks_msec() - t0 < 90000:
		await get_tree().process_frame
	return w


func _game_seconds(t: float) -> void:
	await physics_frames(int(t * Engine.physics_ticks_per_second))


func _free(w: Node) -> void:
	w.queue_free()
	await frames(3)


func test_world_hook_spawns_and_follows() -> void:
	if not WorldData.has_world_data():
		return
	for e: int in [E.EARTH, E.WATER]:
		var w := await _world(e)
		if not expect(w.playing, "world %d playing" % e):
			await _free(w)
			continue
		var pl := w.player
		var c := pl.get_companion() as Companion
		if not expect(c != null, "companion spawned for element %d" % e):
			await _free(w)
			continue
		expect(c.species == CompanionProfile.species_for_element(e), "the element's companion (%s)" % c.species)
		expect(c.get_parent() == w.companion_root, "under the scene's Companions node")
		expect(w.hud.companion_panel.visible and not c.get_status_text().is_empty(), "HUD panel + status")
		await _game_seconds(1.0)
		var q := c.global_position
		expect(absf(q.y - WorldData.get_height(q.x, q.z)) < 0.6, "%s stands on the real terrain (dy %.2f)" % [c.species, q.y - WorldData.get_height(q.x, q.z)])
		expect(q.distance_to(pl.global_position) < 14.0, "%s next to the player (%.1f m)" % [c.species, q.distance_to(pl.global_position)])
		# Walk 6 s through the real world (InputMap actions).
		Input.action_press(&"move_forward")
		await _game_seconds(6.0)
		Input.action_release(&"move_forward")
		await _game_seconds(2.5)
		q = c.global_position
		expect(q.distance_to(pl.global_position) < 16.0, "%s followed (%.1f m)" % [c.species, q.distance_to(pl.global_position)])
		expect(q.y > WorldData.get_height(q.x, q.z) - 0.6, "%s never under the terrain" % c.species)
		# Saves carry the companion state.
		c.health.health = c.health.max_health * 0.7
		SaveSystem.save_game(1)
		expect(String(GameState.companion.get("type", "")) == String(c.species), "saved type")
		expect_near(float(GameState.companion.get("health_ratio", 0.0)), 0.7, 0.02, "saved health ratio")
		await _free(w)


func test_flyer_takes_off_and_lands_on_real_terrain() -> void:
	if not WorldData.has_world_data():
		return
	# The dragon over the Fire Nation caldera floor (wide, flat ground to land on again).
	var w := await _world(E.FIRE)
	if not expect(w.playing, "world playing"):
		await _free(w)
		return
	var pl := w.player
	var c := pl.get_companion() as Companion
	if not expect(c != null and c.species == &"dragon", "dragon"):
		await _free(w)
		return
	await _game_seconds(1.0)
	var fwd := CompanionNav.dir_of(c.motor.yaw)
	var stand := c.global_position - Vector3(-fwd.z, 0.0, fwd.x) * (c.prof.radius() + 1.2)
	stand.y = WorldData.get_height(stand.x, stand.z) + 0.1
	pl.teleport(Transform3D(Basis(), stand))
	await _game_seconds(0.3)
	var mounted := c.request_mount(pl)
	expect(mounted, "mount accepted")
	await _game_seconds(1.5)
	expect(c.mode == Companion.Mode.RIDDEN and pl.get_state() == PlayerCharacter.State.MOUNTED, "seated (%s)" % c.get_mode_name())
	Input.action_press(&"jump")
	await _game_seconds(0.2)
	Input.action_release(&"jump")
	await _game_seconds(3.0)
	expect(c.flight.phase == CompanionFlight.Phase.FLY, "flying (%s)" % c.flight.phase_name())
	Input.action_press(&"move_forward")
	var min_clear := INF
	for i in 30:
		await _game_seconds(0.2)
		var q := c.global_position
		min_clear = minf(min_clear, q.y - CompanionNav.surface_y(q.x, q.z))
	Input.action_release(&"move_forward")
	expect(min_clear > 0.3, "kept above the terrain (min %.1f m)" % min_clear)
	# Pull back (brake / hover) and descend: a near-vertical descent onto the ground below.
	Input.action_press(&"descend")
	Input.action_press(&"move_back")
	var t := 0.0
	while c.flight.is_active() and t < 40.0:
		await _game_seconds(0.25)
		t += 0.25
	Input.action_release(&"move_back")
	Input.action_release(&"descend")
	expect(not c.flight.is_active(), "landed (%s, alt %.1f)" % [c.flight.phase_name(), c.flight.altitude()])
	var q2 := c.global_position
	expect(absf(q2.y - CompanionNav.ground_y(c.get_world_3d().direct_space_state, q2, 2.0, 10.0, [c.get_rid()])) < 0.6, "on the ground")
	expect(pl.get_state() == PlayerCharacter.State.MOUNTED and pl.global_position.distance_to(c.rider.seat.global_position) < 0.1, "rider still seated")
	await _free(w)
