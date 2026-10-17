extends RefCounted
## Water bending in the real world near the Northern Water Tribe (a new Water
## game, intro skipped): on a snowy shore next to the open sea the bender draws
## water out of the sea (Water Surge), pulls snow up from the ground away from
## the water, freezes the sea into an ice floe and walks onto it, raises an ice
## wall on the sea and rides a Water Wave out over the water. Observer-camera
## screenshots of every step + checks on the water sources the abilities used.

const E := ElementDefs.Element

var p: Playtest
var w: WorldScene
var pl: PlayerCharacter
var cam: Camera3D


func run(pt: Playtest) -> void:
	p = pt
	GameState.new_game(E.WATER)
	var t0 := Time.get_ticks_msec()
	w = await p.load_scene("res://scenes/world/world.tscn", {"new_game": true, "element": E.WATER, "skip_intro": true}) as WorldScene
	var ok := await p.wait_until(func() -> bool: return w.is_ready and w.playing, 300.0)
	p.check(ok, "world ready (%.1f s)" % ((Time.get_ticks_msec() - t0) / 1000.0))
	if not ok:
		return
	pl = w.player
	pl.resources.infinite_chi = true
	pl.camera_rig.require_capture = false
	cam = Camera3D.new()
	cam.fov = 55.0
	w.add_child(cam)
	await p.wait_game(1.0)
	var shore := _find_shore(pl.global_position)
	p.check(shore.is_finite(), "found a shore near the Water Tribe spawn (%s)" % str(shore))
	if not shore.is_finite():
		return
	var sea_dir: Vector3 = _sea_dir(shore)
	p.note("shore %s, sea toward %s, surface %s" % [shore, sea_dir, GroundSampler.surface(shore)])
	var ok2: bool = await w.travel.travel_to(Transform3D(Basis(Vector3.UP, atan2(-sea_dir.x, -sea_dir.z)), shore), {"fade": 0.1, "autosave": false})
	p.check(ok2, "travelled to the shore")
	await p.wait_game(1.0)
	pl.camera_rig.snap_behind(pl)
	# Let the region banner fade.
	await p.wait_game(4.5)
	await _surge_from_sea(sea_dir)
	await _floe(sea_dir)
	await _ice_wall(sea_dir)
	await _wave_ride(sea_dir)
	await _snow_draw(sea_dir)


## A dry, walkable point 4-9 m from open sea within 1.6 km of `near`, outside the city.
func _find_shore(near: Vector3) -> Vector3:
	var best := Vector3.INF
	var best_d := INF
	for r in range(20, 1600, 15):
		var n := 24 + r / 8
		for k in n:
			var a := TAU * float(k) / n
			var q := near + Vector3(cos(a), 0, sin(a)) * float(r)
			var h := WorldData.get_height(q.x, q.z)
			if h < WorldData.SEA_LEVEL + 0.4 or h > WorldData.SEA_LEVEL + 3.0:
				continue
			# Open coast outside the city (its canals are water too, but walled in).
			if Settlements.settlement_at(Vector3(q.x, h, q.z)) != &"":
				continue
			if WorldData.get_normal(q.x, q.z).y < 0.94:
				continue
			var d := _sea_distance(Vector3(q.x, h, q.z))
			if d >= 4.0 and d <= 9.0 and float(r) < best_d:
				best = Vector3(q.x, h, q.z)
				best_d = float(r)
		if best.is_finite():
			return best
	return best


func _sea_distance(p0: Vector3) -> float:
	var best := INF
	for k in 16:
		var a := TAU * float(k) / 16.0
		for d in [2.0, 4.0, 6.0, 8.0, 10.0, 12.0]:
			var q: Vector3 = p0 + Vector3(cos(a), 0, sin(a)) * float(d)
			if WorldData.get_water_height(q.x, q.z) > WorldData.get_height(q.x, q.z) + 1.0:
				best = minf(best, float(d))
				break
	return best


func _sea_dir(p0: Vector3) -> Vector3:
	var acc := Vector3.ZERO
	for k in 24:
		var a := TAU * float(k) / 24.0
		var dir := Vector3(cos(a), 0, sin(a))
		var q: Vector3 = p0 + dir * 10.0
		if WorldData.get_water_height(q.x, q.z) > WorldData.get_height(q.x, q.z) + 1.0:
			acc += dir
	return acc.normalized() if acc.length() > 0.1 else Vector3.FORWARD


func _obs(shot: String, focus: Vector3, side: float = 1.0, dist: float = 8.0, height: float = 3.0) -> void:
	var a := pl.global_position + Vector3.UP
	var f := focus - a
	f.y = 0.0
	var fwd := f.normalized() if f.length() > 0.5 else -pl.global_basis.z
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var mid := a.lerp(focus, 0.45)
	var pos := mid + right * side * dist - fwd * dist * 0.35 + Vector3.UP * height
	pos.y = maxf(pos.y, WorldData.get_height(pos.x, pos.z) + 1.0)
	# Keep a clear view: pull in front of anything between the action and the camera.
	var q := PhysicsRayQueryParameters3D.create(mid, pos, Layers.WORLD)
	q.exclude = [pl.get_rid()]
	var hit := pl.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		pos = mid.lerp(hit["position"], 0.85)
	cam.look_at_from_position(pos, mid, Vector3.UP)
	cam.make_current()
	# The companion stays out of the shot.
	var comp := pl.get_companion()
	if comp:
		comp.visible = false
	await p.screenshot(shot)
	if comp and is_instance_valid(comp):
		comp.visible = true
	pl.camera_rig.make_current()


func _equip(id: StringName) -> void:
	pl.controller.set_slot(&"technique_1", AbilityRegistry.get_def(id))
	pl.controller.reset_cooldowns()


func _tap1() -> void:
	Input.action_press(&"ability_1")
	await p.wait_game(0.06)
	Input.action_release(&"ability_1")


func _face(dir: Vector3) -> void:
	pl.motor.face(dir)
	pl.camera_rig.snap_behind(pl)
	await p.wait_game(0.2)


## Water Surge with the sea behind the bender: the mass is pulled out of the sea.
func _surge_from_sea(sea_dir: Vector3) -> void:
	_equip(&"water_surge")
	await _face(-sea_dir.rotated(Vector3.UP, 0.6))
	var src := WaterSource.find(pl.get_bending_context())
	p.check(bool(src.get("found", false)) and src.get("kind") == &"water", "the sea is the water source (%s)" % str(src))
	await _tap1()
	await p.wait_game(0.2)
	await _obs("world_1_surge_draw", pl.global_position + sea_dir * 4.0, 1.0, 8.0, 3.0)
	await p.wait_game(0.25)
	await _obs("world_2_surge_gathered", pl.global_position - sea_dir * 3.0, -1.0, 7.0, 2.5)
	await p.wait_until(func() -> bool: return not pl.controller.is_busy(), 3.0)
	await p.wait_game(0.15)
	await _obs("world_3_surge_wave", pl.global_position - sea_dir * 6.0, 1.0, 9.0, 3.0)
	await p.wait_game(0.6)


## Ice floe frozen out of the sea; the bender steps onto it.
func _floe(sea_dir: Vector3) -> void:
	_equip(&"ice_trap")
	await _face(sea_dir)
	var target := pl.global_position + sea_dir * 9.0
	pl.ctx.aim_provider = func() -> Dictionary:
		return {"direction": (target - pl.ctx.hands_pos()).normalized(), "target": null, "point": target}
	await _tap1()
	await p.wait_until(func() -> bool: return not pl.controller.is_busy(), 3.0)
	pl.ctx.aim_provider = pl.aim
	await p.wait_game(0.4)
	var floe: IceFloe = IceFloe.live.back() if not IceFloe.live.is_empty() else null
	p.check(floe != null, "ice trap on the sea froze a floe")
	await _obs("world_4_floe", target, 1.0, 9.0, 4.0)
	if floe == null:
		return
	pl.teleport(Transform3D(pl.global_basis, Vector3(floe.global_position.x, floe.top_y() + 0.3, floe.global_position.z)))
	await p.wait_game(0.8)
	p.check(pl.motor.on_floor and not pl.motor.swimming, "standing on the floe out at sea (swim %s)" % pl.motor.swimming)
	await _obs("world_5_on_floe", pl.global_position, -1.0, 7.0, 3.0)


## Ice wall raised on the sea (on its own floe).
func _ice_wall(sea_dir: Vector3) -> void:
	_equip(&"ice_wall")
	await _face(sea_dir)
	var spot := pl.global_position + sea_dir * 4.0
	pl.ctx.aim_provider = func() -> Dictionary:
		return {"direction": (spot - pl.ctx.hands_pos()).normalized(), "target": null, "point": spot}
	await _tap1()
	await p.wait_until(func() -> bool: return not pl.controller.is_busy(), 3.0)
	pl.ctx.aim_provider = pl.aim
	await p.wait_game(0.3)
	var wall: BendingConstruct = BendingConstruct.live.back() if not BendingConstruct.live.is_empty() else null
	p.check(wall != null and wall.kind == &"ice", "ice wall raised on the sea")
	await _obs("world_6_ice_wall_sea", pl.global_position + sea_dir * 3.4, 1.0, 8.0, 3.0)


## Ride a wave from the floe across the sea back to the shore.
func _wave_ride(sea_dir: Vector3) -> void:
	for c in BendingConstruct.live.duplicate():
		(c as BendingConstruct).crumble()
	_equip(&"water_wave")
	await _face(sea_dir.rotated(Vector3.UP, PI * 0.5))
	Input.action_press(&"ability_1")
	await p.wait_game(0.5)
	await _obs("world_7_wave_ride", pl.global_position - pl.global_basis.z * 3.0, 1.0, 7.0, 2.0)
	await p.wait_game(0.5)
	await _obs("world_8_wave_ride_far", pl.global_position, -1.0, 9.0, 3.0)
	Input.action_release(&"ability_1")
	await p.wait_until(func() -> bool: return not pl.controller.is_busy(), 3.0)
	await p.wait_game(0.6)
	p.check(not pl.motor.swimming, "the ride ends dry (floe or shore), y %.2f" % pl.global_position.y)
	await _obs("world_9_after_ride", pl.global_position, 1.0, 7.0, 3.0)


## Away from the sea, on snow: the water comes up out of the snow at the feet.
func _snow_draw(sea_dir: Vector3) -> void:
	var inland := Vector3.INF
	var o := pl.global_position
	for r in range(20, 900, 20):
		var n := 16 + r / 10
		for k in n:
			var a := TAU * float(k) / n
			var q := o + Vector3(cos(a), 0, sin(a)) * float(r)
			q.y = WorldData.get_height(q.x, q.z)
			if q.y > WorldData.SEA_LEVEL + 1.0 and q.y < WorldData.SEA_LEVEL + 45.0 and GroundSampler.surface(q) == &"snow" and WorldData.get_normal(q.x, q.z).y > 0.92 \
					and Settlements.settlement_at(q) == &"" and _sea_distance(q) == INF:
				inland = q
				break
		if inland.is_finite():
			break
	if not inland.is_finite():
		p.note("no flat snow inland found; skipping the snow draw")
		return
	var ok: bool = await w.travel.travel_to(Transform3D(pl.global_basis, inland), {"fade": 0.1, "autosave": false})
	await p.wait_game(0.8)
	var src := WaterSource.find(pl.get_bending_context())
	p.check(ok and src.get("kind") == &"snow", "inland the snow is the source (%s)" % str(src))
	_equip(&"ice_shards")
	pl.camera_rig.snap_behind(pl)
	await p.wait_game(0.3)
	await _tap1()
	await p.wait_game(0.18)
	await _obs("world_10_snow_draw", pl.global_position - pl.global_basis.z * 2.0, 1.0, 5.0, 1.8)
	await p.wait_until(func() -> bool: return not pl.controller.is_busy(), 3.0)
	_equip(&"water_surge")
	await _tap1()
	await p.wait_game(0.45)
	await _obs("world_11_snow_surge", pl.global_position - pl.global_basis.z * 3.0, -1.0, 7.0, 2.5)
	await p.wait_until(func() -> bool: return not pl.controller.is_busy(), 3.0)
	await p.wait_game(0.2)
	await _obs("world_12_snow_wave", pl.global_position - pl.global_basis.z * 7.0, 1.0, 9.0, 3.0)
