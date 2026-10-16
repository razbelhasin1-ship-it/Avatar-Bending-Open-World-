extends TestCase
## World scene module (worldscene): spawns and arrival paths per element, region director
## hysteresis + first visits + POI discovery, respawn points, ferry routes and travel, save
## consistency, the playable World scene end to end (headless) incl. clean exits, and the
## tutorial director.

const WORLD := "res://scenes/world/world.tscn"


func before_each() -> void:
	WorldData.load_world()
	GameState.reset()


func after_each() -> void:
	GameState.reset()
	Engine.time_scale = 1.0
	get_tree().paused = false


## Instantiates the world scene with options and waits until it is ready (or timeout).
func _load_world(opts: Dictionary, timeout: float = 90.0) -> WorldScene:
	var w := (load(WORLD) as PackedScene).instantiate() as WorldScene
	w.options = opts
	add_child(w)
	var t0 := Time.get_ticks_msec()
	while not w.is_ready and Time.get_ticks_msec() - t0 < int(timeout * 1000.0):
		await get_tree().process_frame
	return w


func _free_world(w: WorldScene) -> void:
	if is_instance_valid(w):
		w.queue_free()
	await frames(3)


# --- integration ------------------------------------------------------------------------------------

func test_world_new_game_spawns_on_ground() -> void:
	GameState.new_game(ElementDefs.Element.FIRE)
	var t0 := Time.get_ticks_msec()
	var w := await _load_world({"new_game": true, "skip_intro": true, "no_content": true})
	print("world ready in %d ms: %s" % [Time.get_ticks_msec() - t0, str(w.load_report)])
	if not expect(w.is_ready, "world became ready"):
		await _free_world(w)
		return
	await physics_frames(30)
	var p := w.player
	expect(p != null, "player spawned")
	var spawn := WorldData.get_spawn(ElementDefs.Element.FIRE)
	expect(p.global_position.distance_to(spawn.origin) < 1.5, "at the fire spawn (%s vs %s)" % [p.global_position, spawn.origin])
	expect(p.motor.on_floor, "standing on the ground")
	expect(absf(p.global_position.y - WorldData.get_height(p.global_position.x, p.global_position.z)) < 0.4, "on the terrain")
	expect(w.hud.player == p, "HUD bound")
	expect(w.playing, "playing (no intro)")
	expect(w.region_director.current_region == &"fire_nation", "home region tracked (%s)" % w.region_director.current_region)
	await _free_world(w)
