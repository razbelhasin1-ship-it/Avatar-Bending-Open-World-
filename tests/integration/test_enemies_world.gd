extends TestCase
## Enemies in the real world scene (headless, streamed terrain collision): the world hook
## installs the EncounterDirector, a road patrol activates near the player and walks its
## road on the real terrain (no falling, no wandering off the road, no stuck members), and
## an outpost garrison engages a player who walks in (combat state on, at most 2 attackers).

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


func _site(id: StringName) -> EncounterSite:
	for s in EncounterSites.build_all():
		if s.id == id:
			return s
	return null


func _world(spawn: Transform3D) -> WorldScene:
	GameState.new_game(E.EARTH)
	GameState.intro_done = true
	var w := (load(WORLD) as PackedScene).instantiate() as WorldScene
	w.options = {"new_game": false, "spawn": spawn, "no_content": true}
	add_child(w)
	var t0 := Time.get_ticks_msec()
	while not w.playing and Time.get_ticks_msec() - t0 < 90000:
		await get_tree().process_frame
	return w


func _game_seconds(t: float) -> void:
	await physics_frames(int(t * Engine.physics_ticks_per_second))


static func _dist_to_route(p: Vector3, route: PackedVector3Array) -> float:
	var best := INF
	for i in route.size() - 1:
		var a := Vector2(route[i].x, route[i].z)
		var b := Vector2(route[i + 1].x, route[i + 1].z)
		var q := Vector2(p.x, p.z)
		var ab := b - a
		var u := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 1e-4), 0.0, 1.0)
		best = minf(best, q.distance_to(a + ab * u))
	return best


func test_road_patrol_walks_the_road() -> void:
	if not WorldData.has_world_data():
		return
	var info := _site(&"ek_omashu_road_patrol")
	if not expect(info != null, "patrol site exists"):
		return
	# Stand 50 m beside the middle of the route: close enough to keep it awake, out of sight.
	var mid := info.route[info.route.size() / 2]
	var nxt := info.route[info.route.size() / 2 + 1]
	var along := (nxt - mid)
	along.y = 0.0
	var side := Vector3(-along.z, 0, along.x).normalized()
	var at := mid + side * 50.0
	at.y = WorldData.get_height(at.x, at.z)
	var w := await _world(Transform3D(Basis(), at + Vector3.UP * 0.3))
	if not expect(w.playing, "world ready"):
		w.queue_free()
		return
	w.player.health.invulnerable = true
	var d := EncounterDirector.instance()
	expect(d != null, "the world hook installed the encounter director")
	if d:
		# Keep them fully simulated (physics walking on the real terrain), not dormant.
		d.sim_radius = 400.0
	var site := d.get_site(info.id) if d else null
	var t0 := Time.get_ticks_msec()
	while site != null and not site.active and Time.get_ticks_msec() - t0 < 8000:
		await get_tree().process_frame
	expect(site != null and site.active, "the patrol activated near the player")
	var members: Array[EnemyBase] = []
	if site:
		for m in site.members:
			if m["node"] != null:
				members.append(m["node"])
	expect(members.size() == site.members.size() if site else false, "all members spawned (%d)" % members.size())
	var start: Array[Vector3] = []
	for e in members:
		start.append(e.global_position)
	await _game_seconds(14.0)
	var route_pts := site.route if site else PackedVector3Array()
	for i in members.size():
		var e := members[i]
		if not is_instance_valid(e):
			fail("patrol member freed")
			continue
		var moved := Vector2(e.global_position.x - start[i].x, e.global_position.z - start[i].z).length()
		expect(moved > 8.0, "%s walked the route (%.1f m)" % [e.display_name, moved])
		expect(e.state == EnemyBase.State.PATROL and not e.dormant, "%s patrolling (%s, dormant %s)" % [e.display_name, e.get_state_name(), e.dormant])
		expect(_dist_to_route(e.global_position, route_pts) < 6.0, "%s stays on the road (%.1f m off)" % [e.display_name,
				_dist_to_route(e.global_position, route_pts)])
		var gy := WorldData.get_height(e.global_position.x, e.global_position.z)
		expect(absf(e.global_position.y - gy) < 1.5, "%s on the ground (%.2f vs %.2f)" % [e.display_name, e.global_position.y, gy])
	w.queue_free()
	await frames(3)


func test_outpost_garrison_engages_the_player() -> void:
	if not WorldData.has_world_data():
		return
	var info := _site(&"ek_fire_scout_camp")
	if not expect(info != null, "outpost site exists"):
		return
	var gate := Basis(Vector3.UP, info.yaw) * Vector3.FORWARD
	var at := info.center + gate * 9.0
	at.y = WorldData.get_height(at.x, at.z)
	var to := info.center - at
	var w := await _world(Transform3D(Basis(Vector3.UP, atan2(-to.x, -to.z)), at + Vector3.UP * 0.3))
	if not expect(w.playing, "world ready"):
		w.queue_free()
		return
	w.player.health.invulnerable = true
	var d := EncounterDirector.instance()
	var site := d.get_site(info.id) if d else null
	var combat := [false]
	var cb := func(on: bool) -> void:
		if on:
			combat[0] = true
	Events.combat_state_changed.connect(cb)
	var max_attackers := 0
	var engaged := 0
	for f in 60 * 12:
		await get_tree().physics_frame
		if site == null:
			break
		var attacking := 0
		engaged = 0
		for m in site.members:
			var e: EnemyBase = m["node"]
			if e != null and is_instance_valid(e) and e.is_alive():
				if e.perception.engaged:
					engaged += 1
				if e.state == EnemyBase.State.ATTACK:
					attacking += 1
		max_attackers = maxi(max_attackers, attacking)
	Events.combat_state_changed.disconnect(cb)
	expect(site != null and site.active, "outpost active")
	expect(engaged >= 3, "the garrison engaged the intruder (%d)" % engaged)
	expect(combat[0] and d.in_combat, "combat state on")
	expect(max_attackers <= 2 and max_attackers >= 1, "attackers capped by tokens (%d)" % max_attackers)
	expect(w.player.health.health > 0.0, "player alive (invulnerable)")
	w.queue_free()
	await frames(3)
