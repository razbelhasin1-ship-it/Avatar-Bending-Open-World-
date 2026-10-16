extends RefCounted
## The real player walks the settlements over their streamed collision: the Air Temple's west
## bridge (terrace -> pinnacle) and a stair flight, the Water Tribe's grand stair from the harbour
## and into the healer's hut. Screenshots along the way; every walk must arrive without a fall
## or a stall.   WALKS=sat_bridge,nwt_healer tools/playtest.sh settlements_wa_walk out 960x540

var scene: Node = null


func run(p: Playtest) -> void:
	Settings.apply_preset("high")
	Settings.apply()
	scene = await p.load_scene("res://scenes/dev/settlements_wa.tscn")
	p.check(scene != null and WorldData.has_world_data(), "dev scene + world data loaded")
	if scene == null:
		return
	await p.wait_until(func() -> bool: return (scene.world as WorldRenderer).normal_baker.texture != null, 60.0)
	await p.wait_until(func() -> bool: return VegetationLibrary.is_ready(), 30.0)
	var want := OS.get_environment("WALKS")
	var walks := _walks()
	for k: String in walks:
		if want != "" and not want.split(",").has(k):
			continue
		var w: Dictionary = walks[k]
		await _walk(p, k, w["points"], float(w.get("hour", 10.0)), int(w.get("element", ElementDefs.Element.AIR)), float(w.get("below", 3.0)))
	scene.remove_player()


func _walks() -> Dictionary:
	var out := {}
	var sat := RingLayout.from_city(Settlements.AIR_TEMPLE)
	for br in WorldData.get_bridges():
		if StringName(br["id"]) == &"at_bridge_west":
			var a: Vector3 = br["a"]
			var b: Vector3 = br["b"]
			var dir := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
			out["sat_bridge"] = {"points": PackedVector3Array([a - dir * 5.0, b + dir * 4.0]), "hour": 10.5,
				"below": float(br.get("sag", 7.0)) + 3.0}
	out["sat_stairs"] = {"points": PackedVector3Array([sat.point(84.0, 25.0, 802.0), sat.point(134.0, 25.0, 782.0)]), "hour": 16.5}
	var nwt := Settlements.plan(Settlements.WATER_TRIBE)
	for s: Dictionary in nwt.data.get("stairs", []):
		if absf(float(s["bearing"])) < 0.5 and float(s["r"]) < 400.0:
			var foot: Vector3 = s["foot"]
			var top: Vector3 = s["top"]
			var dir := Vector3(top.x - foot.x, 0, top.z - foot.z).normalized()
			out["nwt_stair"] = {"points": PackedVector3Array([foot - dir * 5.0, top + dir * 4.0]), "hour": 9.5, "element": ElementDefs.Element.WATER}
	for it: Dictionary in nwt.data.get("interiors", []):
		if it["kind"] == &"healer_hut":
			var pos: Vector3 = it["position"]
			var yaw := float(it["yaw"])
			out["nwt_healer"] = {"points": PackedVector3Array([NwtDistricts.world(pos, yaw, Vector3(0, 0, -11.0)),
				NwtDistricts.world(pos, yaw, Vector3(0, 0, -3.2))]), "hour": 12.0, "element": ElementDefs.Element.WATER}
	return out


## Spawns the player at the first point facing the next, holds forward through the waypoints and
## checks that it arrives (within 2.5 m) without dropping more than `below` m under its path line.
func _walk(p: Playtest, label: String, pts: PackedVector3Array, hour: float, element: int, below: float) -> void:
	var world: WorldRenderer = scene.world
	var content: WorldContent = scene.content
	world.set_time_of_day(hour)
	world.set_weather(&"clear", 0.0)
	var start := pts[0]
	var dir := Vector3(pts[1].x - start.x, 0, pts[1].z - start.z).normalized()
	content.load_now(start)
	world.ensure_collision_now(start)
	await p.wait_until(func() -> bool: return world.is_collision_ready_at(start), 20.0)
	var pl: PlayerCharacter = scene.spawn_player(Transform3D(Basis.looking_at(dir), start + Vector3(0, 0.4, 0)), element)
	pl.camera_rig.set_yaw(atan2(-dir.x, -dir.z))
	await p.wait_game(0.8)
	var target := pts[pts.size() - 1]
	var total := Vector2(target.x - start.x, target.z - start.z).length()
	var lowest := INF
	var best := INF
	var stall := 0.0
	var t := 0.0
	var shot := 0
	p.hold(&"move_forward")
	while t < 90.0:
		await p.wait_game(0.25)
		t += 0.25
		var pos := pl.global_position
		# keep heading at the target (the camera steers the walk)
		var to := Vector3(target.x - pos.x, 0, target.z - pos.z)
		pl.camera_rig.set_yaw(atan2(-to.x, -to.z))
		var left := to.length()
		var along := 1.0 - left / maxf(total, 0.1)
		var path_y := lerpf(start.y, target.y, clampf(along, 0.0, 1.0))
		lowest = minf(lowest, pos.y - path_y)
		if (shot == 0 and along > 0.4) or (shot == 1 and along > 0.8):
			shot += 1
			await p.screenshot("settlements_wa_walk_%s_%d" % [label, shot])
		if left < 1.5:
			break
		if left < best - 0.05:
			best = left
			stall = 0.0
		else:
			stall += 0.25
			if stall > 3.0:
				p.note("%s: stalled %.1f m before the end at %s (state %s, on wall %s)" % [label, left, pos, pl.get_state_name(), pl.is_on_wall()])
				break
		if pos.y < path_y - below - 3.0:
			p.note("%s: fell to %s" % [label, pos])
			break
	p.release(&"move_forward")
	await p.wait_game(0.5)
	await p.screenshot("settlements_wa_walk_%s_end" % label)
	var end := pl.global_position
	var arrived := Vector2(end.x - target.x, end.z - target.z).length() < 2.5
	p.note("%s: %.1f s, end %s, lowest %.2f m relative to the path line" % [label, t, end, lowest])
	p.check(arrived, "%s: the player arrived" % label)
	p.check(lowest > -below, "%s: no fall (lowest %.2f m under the path line)" % [label, lowest])
