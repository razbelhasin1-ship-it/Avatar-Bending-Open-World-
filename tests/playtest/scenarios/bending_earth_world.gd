extends RefCounted
## Earth bending in the real world near the Earth Kingdom spawn (a new Earth
## game, intro skipped): on the open plains the bender stomps a crater into the
## real terrain, raises a pillar and rides another one up to look out over the
## land; on rocky ground the pillars are grey stone and Earth Spikes run over
## the terrain; on a beach the sand is loose (weaker, toast); at the shore the
## sea refuses (deep water); the marks stay on the terrain. Observer-camera
## screenshots of every step + checks on the ground kinds the abilities used.

const E := ElementDefs.Element

var p: Playtest
var w: Node
var pl: PlayerCharacter
var cam: Camera3D
var fails: Array = []


func run(pt: Playtest) -> void:
	p = pt
	GameState.new_game(E.EARTH)
	var t0 := Time.get_ticks_msec()
	w = await p.load_scene("res://scenes/world/world.tscn", {"new_game": true, "element": E.EARTH, "skip_intro": true})
	var ok := await p.wait_until(func() -> bool: return bool(w.get("is_ready")) and bool(w.get("playing")), 300.0)
	p.check(ok, "world ready (%.1f s)" % ((Time.get_ticks_msec() - t0) / 1000.0))
	if not ok:
		return
	pl = w.get("player") as PlayerCharacter
	pl.resources.infinite_chi = true
	pl.camera_rig.require_capture = false
	cam = Camera3D.new()
	cam.fov = 55.0
	w.add_child(cam)
	Events.ability_failed.connect(func(id: StringName, reason: StringName) -> void: fails.append([id, reason]))
	await p.wait_game(1.0)
	var home := pl.global_position
	p.note("spawn %s surface %s" % [str(home), GroundSampler.surface(home)])
	var plains := _find(home, [&"grass", &"dirt"], 30.0, 900.0)
	var rock := _find(home, [&"stone"], 30.0, 2500.0)
	var beach := _find(home, [&"sand"], 30.0, 3000.0)
	p.note("plains %s  rock %s  beach %s" % [str(plains), str(rock), str(beach)])
	p.check(plains.is_finite(), "found open plains near the spawn")
	if plains.is_finite():
		await _plains(plains)
	if rock.is_finite():
		await _rock(rock)
	else:
		p.note("no rocky ground found within 2.5 km")
	if beach.is_finite():
		await _beach(beach)
	else:
		p.note("no beach found within 3 km")


## A walkable, flat-ish point of one of `kinds` between r0 and r1 m from `near`, outside settlements.
func _find(near: Vector3, kinds: Array, r0: float, r1: float) -> Vector3:
	for r in range(int(r0), int(r1), 12):
		var n := 16 + r / 10
		for k in n:
			var a := TAU * float(k) / n + float(r) * 0.37
			var q := near + Vector3(cos(a), 0, sin(a)) * float(r)
			var h := WorldData.get_height(q.x, q.z)
			if h < WorldData.SEA_LEVEL + 0.5:
				continue
			var g := Vector3(q.x, h, q.z)
			if Settlements.settlement_at(g) != &"":
				continue
			if WorldData.get_normal(q.x, q.z).y < 0.95:
				continue
			# A flat 10 m disc (no cliffs right next to it).
			var flat := true
			for j in 6:
				var b := TAU * float(j) / 6.0
				var o := g + Vector3(cos(b), 0, sin(b)) * 6.0
				if absf(WorldData.get_height(o.x, o.z) - h) > 1.2:
					flat = false
					break
			if flat and kinds.has(GroundSampler.surface(g + Vector3.UP * 0.05)):
				return g
	return Vector3.INF


func _go(at: Vector3, yaw: float = 0.0) -> void:
	for c in BendingConstruct.live.duplicate():
		(c as BendingConstruct).crumble()
	var ok: bool = await w.get("travel").travel_to(Transform3D(Basis(Vector3.UP, yaw), at + Vector3.UP * 0.1), {"fade": 0.1, "autosave": false})
	p.check(ok, "travelled to %s" % str(at))
	await p.wait_game(1.5)
	pl.controller.reset_cooldowns()
	pl.camera_rig.snap_behind(pl)
	await p.wait_game(0.4)


func _equip(id: StringName) -> void:
	var d := AbilityRegistry.get_def(id)
	pl.controller.set_slot(&"signature" if d.slot == AbilityDef.Slot.SIGNATURE else &"technique_1", d)
	pl.controller.reset_cooldowns()


func _press(action: StringName, hold: float = 0.06) -> void:
	Input.action_press(action)
	await p.wait_game(hold)
	Input.action_release(action)


func _tick_until(cond: Callable, timeout: float = 5.0) -> bool:
	for i in int(timeout * 60.0):
		if cond.call():
			return true
		await p.get_tree().physics_frame
	return cond.call()


func _obs(shot: String, focus: Vector3, angle_deg: float = 40.0, dist: float = 8.0, height: float = 3.0) -> void:
	var a := deg_to_rad(angle_deg) + pl.rotation.y
	var pos := focus + Vector3(sin(a), 0.0, cos(a)) * dist
	pos.y = maxf(focus.y + height, WorldData.get_height(pos.x, pos.z) + 1.0)
	cam.look_at_from_position(pos, focus, Vector3.UP)
	cam.make_current()
	await p.screenshot(shot)
	pl.camera_rig.make_current()


func _kind_here() -> StringName:
	return EarthEnv.feet(pl.get_bending_context())["kind"]


func _plains(at: Vector3) -> void:
	await _go(at)
	var kind := _kind_here()
	p.note("plains ground: %s" % kind)
	p.check(kind == &"grass" or kind == &"dirt", "plains are earth (%s)" % kind)
	# Earth Stomp into the terrain.
	_equip(&"earth_stomp")
	await _press(&"ability_1")
	await _tick_until(func() -> bool: return not EarthShockwave.live.is_empty(), 1.5)
	await p.wait_game(0.1)
	await _obs("world_1_stomp", pl.global_position, 35.0, 7.0, 2.6)
	await _tick_until(func() -> bool: return not pl.controller.is_busy(), 2.0)
	# Earth Pillar ahead (cover / a stepping block).
	_equip(&"earth_pillar")
	await _press(&"ability_1")
	await _tick_until(func() -> bool: return not pl.controller.is_busy(), 2.0)
	await p.wait_game(0.3)
	await _obs("world_2_pillar", pl.global_position - pl.global_basis.z * 3.0, 60.0, 8.0, 2.0)
	# Hold: ride a column up and look out over the land.
	pl.controller.reset_cooldowns()
	var y0 := pl.global_position.y
	Input.action_press(&"ability_1")
	await p.wait_game(0.55)
	Input.action_release(&"ability_1")
	await _tick_until(func() -> bool: return not pl.controller.is_busy(), 2.0)
	await p.wait_game(0.6)
	p.check(pl.global_position.y > y0 + 2.5 and pl.is_on_floor(), "rode the column up on real terrain (%.1f m)" % (pl.global_position.y - y0))
	await _obs("world_3_lookout", pl.global_position, -50.0, 9.0, 1.0)
	pl.camera_rig.snap_behind(pl)
	await p.wait_game(0.3)
	await p.screenshot("world_4_lookout_view")
	# Jump down: the marks stay on the terrain.
	pl.teleport(Transform3D(pl.global_basis, at + Vector3(2.5, 0.1, 2.5)))
	await p.wait_game(1.0)
	await _obs("world_5_marks", at, 20.0, 6.0, 5.0)


func _rock(at: Vector3) -> void:
	await _go(at)
	var kind := _kind_here()
	p.note("rocky ground: %s" % kind)
	p.check(kind == &"stone", "rocky ground is stone (%s)" % kind)
	_equip(&"earth_spikes")
	await _press(&"ability_1")
	await _tick_until(func() -> bool: return not EarthSpikeLine.live.is_empty(), 1.5)
	await p.wait_game(0.4)
	await _obs("world_6_stone_spikes", pl.global_position - pl.global_basis.z * 5.0, 70.0, 9.0, 2.6)
	await _tick_until(func() -> bool: return not pl.controller.is_busy(), 2.0)
	_equip(&"earth_pillar")
	await _press(&"ability_1")
	await _tick_until(func() -> bool: return not pl.controller.is_busy(), 2.0)
	await p.wait_game(0.3)
	await _obs("world_7_stone_pillar", pl.global_position - pl.global_basis.z * 3.0, 50.0, 7.0, 2.0)


func _beach(at: Vector3) -> void:
	await _go(at)
	var kind := _kind_here()
	p.note("beach ground: %s" % kind)
	p.check(kind == &"sand", "beach is sand (%s)" % kind)
	_equip(&"earth_stomp")
	await _press(&"ability_1")
	await _tick_until(func() -> bool: return not EarthShockwave.live.is_empty(), 1.5)
	await p.wait_game(0.1)
	await _obs("world_8_sand_stomp", pl.global_position, 35.0, 7.0, 2.6)
	await _tick_until(func() -> bool: return not pl.controller.is_busy(), 2.0)
	# Face the sea and try to raise a pillar in it: deep water refuses.
	var sea := Vector3.INF
	for k in 24:
		var a := TAU * float(k) / 24.0
		for d in [6.0, 9.0, 12.0, 16.0, 20.0]:
			var q: Vector3 = at + Vector3(cos(a), 0, sin(a)) * float(d)
			if WorldData.get_water_height(q.x, q.z) > WorldData.get_height(q.x, q.z) + 1.0:
				sea = q
				break
		if sea.is_finite():
			break
	if not sea.is_finite():
		p.note("no deep water within 20 m of the beach point")
		return
	var to := sea - pl.global_position
	to.y = 0.0
	pl.teleport(Transform3D(Basis(Vector3.UP, atan2(-to.x, -to.z)), pl.global_position))
	pl.camera_rig.snap_behind(pl)
	await p.wait_game(0.4)
	_equip(&"earth_pillar")
	var n0 := fails.size()
	# Aim straight at the water (no target: the aim point decides).
	pl.ctx.aim_provider = func() -> Dictionary: return {"direction": to.normalized(), "target": null, "point": sea}
	await _press(&"ability_1")
	await p.wait_game(0.2)
	await p.screenshot("world_9_sea_refused")
	p.check(fails.size() > n0 and fails[fails.size() - 1][1] == &"no_earth", "pillar in deep water refused: %s" % str(fails.slice(n0)))
