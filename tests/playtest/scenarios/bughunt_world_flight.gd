extends RefCounted
## bughunt_world: a long session on the dragon across the whole world (docs/qa/bughunt_world.md).
## The REAL player calls the dragon (G), mounts it (F), takes off (jump) and flies with the
## InputMap like a player (move_forward + sprint = boost, jump / descend for height, camera yaw to
## steer) over all four nations: Fire Nation Capital -> Northern Water Tribe -> Ba Sing Se ->
## Southern Air Temple -> back to the Fire Nation Capital (LOOPS= times, default 1). Every game
## second it records memory, object / node / orphan / resource counts, the content streaming
## state (active cells, pooled nodes and the MultiMesh instances they still hold), NPCs, enemies,
## wildlife and the frame times, and checks that nothing grows from one visit of a place to the
## next. CSV + summary in <out>/flight.csv, <out>/flight.txt.
##
## Headless (numbers): godot --headless --fixed-fps 60 --path . res://tests/playtest/playtest.tscn
##   -- --test --scenario=bughunt_world_flight --out=<dir>
## Rendered (screenshots over each city): tools/playtest.sh bughunt_world_flight <dir> 960x540
##   (SHORT=1 flies only the first leg's last 1.5 km: llvmpipe is too slow for 18 km).

const E := ElementDefs.Element
## [id, label] in flight order; the first entry is also the start and the end.
const ROUTE := [[&"fire_nation_capital", "Fire Nation Capital"], [&"northern_water_tribe", "Northern Water Tribe"],
	[&"ba_sing_se", "Ba Sing Se"], [&"southern_air_temple", "Southern Air Temple"], [&"fire_nation_capital", "Fire Nation Capital"]]
const CRUISE_AGL := 70.0

var p: Playtest
var w: WorldScene
var pl: PlayerCharacter
var c: Companion
var rows: Array[String] = []
var lines: Array[String] = []
var _frame_us: Array[int] = []
var _last_us := 0
var _t := 0.0
var visits: Array[Dictionary] = []


func run(pt: Playtest) -> void:
	p = pt
	SaveSystem.save_dir = "user://saves_bughunt_world_flight"
	DirAccess.make_dir_recursive_absolute(SaveSystem.save_dir)
	GameState.new_game(E.FIRE)
	GameState.intro_done = true
	w = await p.load_scene("res://scenes/world/world.tscn", {"new_game": true, "element": E.FIRE, "skip_intro": true, "time_of_day": 10.0}) as WorldScene
	var ok := await p.wait_until(func() -> bool: return w.is_ready and w.playing, 600.0)
	if not p.check(ok, "world ready %s" % str(w.load_report)):
		return
	pl = w.player
	pl.camera_rig.require_capture = false
	p.get_tree().process_frame.connect(_on_frame)
	rows.append("t,leg,x,z,agl,speed,mem_static_mb,objects,nodes,orphans,resources,vmem_mb,cells_active,cells_released,mmi_pool,mmi_pool_instances,mesh_pool,npcs,enemies,wildlife,frame_ms_max")
	if not await _mount_dragon():
		_write()
		return
	var loops := maxi(1, int(OS.get_environment("LOOPS")) if OS.get_environment("LOOPS") != "" else 1)
	var short := OS.get_environment("SHORT") != ""
	_sample("takeoff")
	if not short:
		await _visit(ROUTE[0][0], String(ROUTE[0][1]), -1)     # the reference visit of the start
	for loop in loops:
		for i in range(1, ROUTE.size()):
			var id: StringName = ROUTE[i][0]
			var city := WorldData.get_city(id)
			var to: Vector3 = city["center"]
			if short:
				var here := pl.global_position
				var d := Vector2(to.x - here.x, to.z - here.z)
				if d.length() > 1500.0:
					var start := to - Vector3(d.x, 0, d.y).normalized() * 1500.0
					start.y = WorldData.get_height(start.x, start.z) + CRUISE_AGL
					c.global_position = start
					c.flight.heading = atan2(-d.x, -d.y)
			var leg := "%d:%s" % [loop + 1, ROUTE[i][1]]
			var arrived: bool = await _fly_to(Vector3(to.x, 0, to.z), leg)
			p.check(arrived, "flew to %s (loop %d)" % [ROUTE[i][1], loop + 1])
			await _visit(id, String(ROUTE[i][1]), loop)
			if short:
				break
		if short:
			break
	Input.action_release(&"move_forward")
	Input.action_release(&"sprint")
	Input.action_release(&"jump")
	Input.action_release(&"descend")
	_report()
	_write()


# --- flight ---------------------------------------------------------------------------------------

func _mount_dragon() -> bool:
	c = pl.get_companion() as Companion
	if not p.check(c != null and c.prof.can_fly, "flying companion present"):
		return false
	await p.tap(&"companion_call")
	var landed := await p.wait_until(func() -> bool: return c.global_position.distance_to(pl.global_position) < 18.0 and not c.is_airborne() and c.mode != Companion.Mode.CALLED, 60.0)
	p.check(landed, "G calls the %s (%s, %.1f m)" % [c.species, c.get_mode_name(), c.global_position.distance_to(pl.global_position)])
	# step beside it (harness), then F like a player
	var dir := CompanionNav.dir_of(c.motor.yaw)
	var side := Vector3(-dir.z, 0.0, dir.x)
	var stand := c.global_position - side * (c.prof.radius() + 1.3)
	stand.y = WorldData.get_height(stand.x, stand.z) + 0.1
	pl.teleport(Transform3D(Basis(Vector3.UP, CompanionNav.yaw_of(CompanionNav.flat_dir(c.global_position - stand))), stand))
	await p.wait_game(0.5)
	await p.tap(&"mount")
	var ok := await p.wait_until(func() -> bool: return c.mode == Companion.Mode.RIDDEN and pl.get_state() == PlayerCharacter.State.MOUNTED, 8.0)
	if not p.check(ok, "F mounts the %s" % c.species):
		return false
	await p.tap(&"jump")
	ok = await p.wait_until(func() -> bool: return c.flight.phase == CompanionFlight.Phase.FLY, 10.0)
	return p.check(ok, "jump takes off (%s)" % c.flight.phase_name())


## Flies (boost) toward `to` (x/z) at ~CRUISE_AGL above the ground; returns on arrival (< 120 m).
func _fly_to(to: Vector3, leg: String) -> bool:
	var limit := 900.0
	var t := 0.0
	var sample_t := 0.0
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	while t < limit:
		if pl.get_state() != PlayerCharacter.State.MOUNTED or c.flight.phase == CompanionFlight.Phase.NONE:
			p.check(false, "%s: still riding in flight (%s / %s)" % [leg, pl.get_state_name(), c.flight.phase_name()])
			return false
		var pos := c.global_position
		var dv := Vector2(to.x - pos.x, to.z - pos.z)
		if dv.length() < 120.0:
			return true
		var want := atan2(-dv.x, -dv.y)
		var turn := clampf(wrapf(want - c.flight.heading, -PI, PI), -1.1, 1.1)
		pl.camera_rig.set_yaw(c.flight.heading + turn)
		var agl := pos.y - maxf(WorldData.get_height(pos.x, pos.z), WorldData.SEA_LEVEL)
		if agl < CRUISE_AGL - 15.0:
			Input.action_press(&"jump")
			Input.action_release(&"descend")
		elif agl > CRUISE_AGL + 25.0:
			Input.action_release(&"jump")
			Input.action_press(&"descend")
		else:
			Input.action_release(&"jump")
			Input.action_release(&"descend")
		await p.wait_game(0.1)
		t += 0.1
		_t += 0.1
		sample_t += 0.1
		if sample_t >= 1.0:
			sample_t = 0.0
			_sample(leg)
	return false


## Circles low over a city for a few seconds (settlement close LODs, NPCs, collision in range).
func _visit(id: StringName, label: String, loop: int) -> void:
	var city := WorldData.get_city(id)
	var center: Vector3 = city["center"]
	var t := 0.0
	var ticks := 0
	while t < 14.0:
		var pos := c.global_position
		var dv := Vector2(center.x - pos.x, center.z - pos.z)
		var want := atan2(-dv.x, -dv.y) + (0.9 if dv.length() < 90.0 else 0.0)
		pl.camera_rig.set_yaw(c.flight.heading + clampf(wrapf(want - c.flight.heading, -PI, PI), -1.1, 1.1))
		Input.action_release(&"sprint")
		var agl := pos.y - maxf(WorldData.get_height(pos.x, pos.z), WorldData.SEA_LEVEL)
		if agl > 55.0:
			Input.action_press(&"descend")
			Input.action_release(&"jump")
		elif agl < 35.0:
			Input.action_press(&"jump")
			Input.action_release(&"descend")
		else:
			Input.action_release(&"jump")
			Input.action_release(&"descend")
		await p.wait_game(0.1)
		t += 0.1
		_t += 0.1
		ticks += 1
		if ticks % 10 == 0:
			_sample("over:" + label)
	Input.action_press(&"sprint")
	await p.screenshot("flight_%d_%s" % [loop + 1, String(id)])
	var s := _snapshot()
	s["place"] = String(id)
	s["loop"] = loop
	visits.append(s)
	lines.append("visit %-24s loop %d  mem %.1f MB  objects %d  nodes %d  orphans %d  resources %d  cells %d  pool %d MMI (%d inst) / %d mesh  npcs %d enemies %d wildlife %d" % [label, loop + 1,
		s["mem"], s["objects"], s["nodes"], s["orphans"], s["resources"], s["cells"], s["mmi_pool"], s["mmi_inst"], s["mesh_pool"], s["npcs"], s["enemies"], s["wildlife"]])
	p.note(lines[-1])


# --- measurements ----------------------------------------------------------------------------------

func _on_frame() -> void:
	var now := Time.get_ticks_usec()
	if _last_us > 0:
		_frame_us.append(now - _last_us)
	_last_us = now


func _snapshot() -> Dictionary:
	var content: WorldContent = w.content
	var st: Dictionary = content.get_stats() if content else {}
	var pool: Array = content.get("_mmi_pool") if content else []
	var inst := 0
	for m: Variant in pool:
		if is_instance_valid(m) and (m as MultiMeshInstance3D).multimesh:
			inst += (m as MultiMeshInstance3D).multimesh.instance_count
	var mesh_pool: Array = content.get("_mesh_pool") if content else []
	var active := 0
	if content:
		for pr: ContentProvider in content.get_providers():
			for cell: ContentCell in content.get_cells(pr.id):
				if cell.state == ContentCell.State.ACTIVE:
					active += 1
	return {
		"mem": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"vmem": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		"cells": active, "released": int(st.get("cells_released", 0)),
		"mmi_pool": pool.size(), "mmi_inst": inst, "mesh_pool": mesh_pool.size(),
		"npcs": p.get_tree().get_nodes_in_group(&"npc").size(),
		"enemies": p.get_tree().get_nodes_in_group(&"enemy").size(),
		"wildlife": p.get_tree().get_nodes_in_group(&"wildlife").size(),
	}


func _sample(leg: String) -> void:
	var s := _snapshot()
	var pos := c.global_position if c else pl.global_position
	var agl := pos.y - maxf(WorldData.get_height(pos.x, pos.z), WorldData.SEA_LEVEL)
	var fmax := 0
	for f in _frame_us:
		fmax = maxi(fmax, f)
	_all_frames.append_array(_frame_us)
	_frame_us.clear()
	rows.append("%.1f,%s,%.0f,%.0f,%.0f,%.1f,%.1f,%d,%d,%d,%d,%.1f,%d,%d,%d,%d,%d,%d,%d,%d,%.1f" % [_t, leg, pos.x, pos.z, agl,
		c.flight.speed if c else 0.0, s["mem"], s["objects"], s["nodes"], s["orphans"], s["resources"], s["vmem"], s["cells"], s["released"],
		s["mmi_pool"], s["mmi_inst"], s["mesh_pool"], s["npcs"], s["enemies"], s["wildlife"], fmax / 1000.0])


var _all_frames: Array[int] = []


func _report() -> void:
	_all_frames.sort()
	var n := _all_frames.size()
	if n > 0:
		lines.append("frames %d: p50 %.1f ms, p95 %.1f ms, p99 %.1f ms, max %.1f ms; > 50 ms: %d, > 100 ms: %d" % [n,
			_all_frames[n / 2] / 1000.0, _all_frames[int(n * 0.95)] / 1000.0, _all_frames[int(n * 0.99)] / 1000.0, _all_frames[n - 1] / 1000.0,
			_all_frames.filter(func(f: int) -> bool: return f > 50000).size(), _all_frames.filter(func(f: int) -> bool: return f > 100000).size()])
	# the same place visited twice: nothing may have grown in between (pools plateau)
	var start_v: Dictionary = visits[0] if not visits.is_empty() else {}
	for v in visits:
		if not start_v.is_empty() and v != start_v and v["place"] == start_v["place"]:
			lines.append("revisit %s: mem %+.1f MB, objects %+d, nodes %+d, orphans %+d, resources %+d" % [v["place"],
				v["mem"] - start_v["mem"], v["objects"] - start_v["objects"], v["nodes"] - start_v["nodes"], v["orphans"] - start_v["orphans"],
				v["resources"] - start_v["resources"]])
	# the same city on the next loop (same approach, same circling): pools and caches plateau
	for v in visits:
		for u in visits:
			if u["place"] == v["place"] and int(u["loop"]) == int(v["loop"]) + 1 and int(v["loop"]) >= 0:
				lines.append("loop %d -> %d over %s: mem %+.1f MB, objects %+d, nodes %+d, resources %+d, cells %+d" % [int(v["loop"]) + 1,
					int(u["loop"]) + 1, u["place"], u["mem"] - v["mem"], u["objects"] - v["objects"], u["nodes"] - v["nodes"],
					u["resources"] - v["resources"], u["cells"] - v["cells"]])
	# the content pools are orphan nodes by design (out of the tree until reused): count the rest
	var orph := 0
	for v in visits:
		orph = maxi(orph, int(v["orphans"]) - int(v["mmi_pool"]) - int(v["mesh_pool"]))
	p.check(orph < 60, "no orphan nodes pile up besides the content pools (max %d)" % orph)
	var inst := 0
	for v in visits:
		inst = maxi(inst, int(v["mmi_inst"]))
	p.check(inst == 0, "pooled MultiMeshes hold no instances (max %d)" % inst)
	for l in lines:
		p.note(l)


func _write() -> void:
	var f := FileAccess.open(p.out_dir.path_join("flight.csv"), FileAccess.WRITE)
	if f:
		f.store_string("\n".join(rows) + "\n")
	var g := FileAccess.open(p.out_dir.path_join("flight.txt"), FileAccess.WRITE)
	if g:
		g.store_string("\n".join(lines) + "\n")
