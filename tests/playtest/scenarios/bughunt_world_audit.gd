extends RefCounted
## bughunt_world: adversarial audit of the open world with the REAL player in the REAL world
## scene (docs/qa/bughunt_world.md). Parts (PART=travel,walk,npc - default all):
##
##   travel  every fast-travel point of the map (cities, villages, ports, shrines, training
##           grounds, docks) made known, then travelled to through MapModel.travel (the map's own
##           path): the player must arrive on dry, walkable floor - not swimming, not inside a
##           wall or on a roof, able to walk away in some direction.
##   walk    the main streets of every ring city: from outside the outer tier the player runs
##           along every ramp bearing to the palace (InputMap actions + camera yaw, like a
##           player), recording where the body is blocked, drops, or is rescued by the fall net.
##   npc     at each city, every live NPC is checked for a capsule buried in settlement geometry
##           and for walkers that stay stuck (NPCs walking into walls), over ~20 s of game time.
##   quests  every quest objective with a place, played for real: the quest is advanced to the
##           objective's stage, the player travels there; quest props must stand on reachable
##           floor and be collected with `interact` (the item / report arrives), go_to places must
##           complete when the player stands there, named NPCs (talk_to) must not be buried and
##           must have floor in front of them to talk from.
##
## Headless (fast numbers): godot --headless --path . res://tests/playtest/playtest.tscn -- --test
##   --scenario=bughunt_world_audit --out=<dir>  (PART=, CITY= to narrow). Rendered (screenshots
## at every finding): tools/playtest.sh bughunt_world_audit <dir> 960x540.
## Findings are written to <out>/audit.txt.

const E := ElementDefs.Element

var p: Playtest
var w: WorldScene
var pl: PlayerCharacter
var lines: Array[String] = []
var findings: Array[String] = []
var shots := 0


func run(pt: Playtest) -> void:
	p = pt
	SaveSystem.save_dir = "user://saves_bughunt_world_audit"
	DirAccess.make_dir_recursive_absolute(SaveSystem.save_dir)
	GameState.new_game(E.EARTH)
	GameState.intro_done = true
	w = await p.load_scene("res://scenes/world/world.tscn", {"new_game": true, "element": E.EARTH, "skip_intro": true, "time_of_day": 11.0}) as WorldScene
	var ok := await p.wait_until(func() -> bool: return w.is_ready and w.playing, 600.0)
	if not p.check(ok, "world ready %s" % str(w.load_report)):
		return
	pl = w.player
	pl.camera_rig.require_capture = false
	# a quiet world for the audit: no camps spawning around the player, never dying
	var d := EncounterDirector.instance()
	if d != null:
		d.spawn_radius = -1.0
	await p.wait_game(1.0)
	var parts := OS.get_environment("PART")
	if parts == "":
		parts = "travel,walk,npc"
	if "travel" in parts:
		await _audit_travel()
	if "walk" in parts:
		await _audit_walks()
	if "npc" in parts:
		await _audit_npcs()
	if "quests" in parts:
		await _audit_quests()
	if "tour" in parts:
		await _audit_tour()
	_write()


# --- helpers ---------------------------------------------------------------------------------------

func _log(s: String) -> void:
	lines.append(s)
	p.note(s)


func _finding(s: String) -> void:
	findings.append(s)
	_log("FINDING: " + s)


func _write() -> void:
	var f := FileAccess.open(p.out_dir.path_join("audit.txt"), FileAccess.WRITE)
	if f:
		f.store_string("\n".join(lines) + "\n\n== FINDINGS (%d)\n" % findings.size() + "\n".join(findings) + "\n")
	p.note("audit: %d findings (see audit.txt)" % findings.size())


func _shot(tag: String) -> void:
	if DisplayServer.get_name() == "headless" or shots >= 40:
		return
	shots += 1
	await p.wait_game(0.3)
	await p.screenshot("audit_%02d_%s" % [shots, tag.validate_filename().left(48)])


func _heal() -> void:
	if pl.health and pl.health.health < pl.health.max_health:
		pl.health.heal(pl.health.max_health)


## Describes the collider a ray / shape met: node name, its parent's name, class.
static func _who(obj: Object) -> String:
	if obj == null:
		return "-"
	var n := obj as Node
	if n == null:
		return obj.get_class()
	var par := n.get_parent()
	return "%s<%s>%s" % [n.name, n.get_class(), (" in " + String(par.name)) if par else ""]


## Solid geometry (not the floor) inside the player's body: a capsule from 0.45 m to 1.65 m.
func _embedded_in(body: Node3D) -> String:
	var sh := CapsuleShape3D.new()
	sh.radius = 0.26
	sh.height = 1.2
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sh
	q.transform = Transform3D(Basis(), body.global_position + Vector3(0, 1.05, 0))
	q.collision_mask = Layers.WORLD | Layers.CONSTRUCT
	if body is CollisionObject3D:
		q.exclude = [(body as CollisionObject3D).get_rid()]
	var hits := body.get_world_3d().direct_space_state.intersect_shape(q, 4)
	var out: Array[String] = []
	for h: Dictionary in hits:
		out.append(_who(h.get("collider")))
	return ", ".join(out)


func _yaw_to(from: Vector3, to: Vector3) -> float:
	var d := Vector2(to.x - from.x, to.z - from.z)
	return atan2(-d.x, -d.y)


## Walks `secs` along camera yaw `yaw`; returns the horizontal distance covered.
func _walk_dir(yaw: float, secs: float) -> float:
	pl.camera_rig.set_yaw(yaw)
	var a := pl.global_position
	Input.action_press(&"move_forward")
	await p.wait_game(secs)
	Input.action_release(&"move_forward")
	await p.wait_game(0.15)
	return Vector2(pl.global_position.x - a.x, pl.global_position.z - a.z).length()


func _travel(xf: Transform3D) -> bool:
	_heal()
	var ok: bool = await w.travel.travel_to(xf, {"fade": 0.05, "autosave": false, "content_timeout": 10.0})
	await p.wait_game(0.6)
	return ok


# --- 1 fast travel ---------------------------------------------------------------------------------------

func _audit_travel() -> void:
	# know every place (as after a long journey)
	var visited := {}
	for pl_: Dictionary in MapModel.places():
		if pl_["kind"] == &"poi":
			GameState.discovered_pois[String(pl_["id"])] = true
		else:
			visited[String(pl_["id"])] = true
	GameState.set_flag("visited_places", visited)
	var points := MapModel.travel_points()
	_log("== TRAVEL: %d fast-travel points" % points.size())
	var only := OS.get_environment("CITY")
	for place: Dictionary in points:
		if only != "" and not String(place["id"]).contains(only):
			continue
		await _audit_travel_point(place)


func _audit_travel_point(place: Dictionary) -> void:
	var label := "%s (%s)" % [place["name"], place["id"]]
	var why := MapModel.travel_block_reason(place)
	var xf := MapModel.travel_transform(place)
	var ok := false
	if why == "":
		ok = await MapModel.travel(place)
		await p.wait_game(0.6)
	else:
		# already there (< MIN_TRAVEL_M): arrive from elsewhere first through the same transform
		ok = await _travel(xf)
	if not ok:
		_finding("travel %s: refused / failed (%s)" % [label, why])
		return
	await p.wait_game(1.2)
	var at := pl.global_position
	var issues: Array[String] = []
	var dist := Vector2(at.x - xf.origin.x, at.z - xf.origin.z).length()
	if dist > 8.0:
		issues.append("arrived %.1f m from the travel point" % dist)
	if pl.motor.swimming or pl.motor.water_depth > 0.4:
		issues.append("in water (depth %.1f, swimming %s)" % [pl.motor.water_depth, pl.motor.swimming])
	if not pl.motor.on_floor:
		issues.append("not on the floor (%s, vy %.1f)" % [pl.get_state_name(), pl.velocity.y])
	var emb := _embedded_in(pl)
	if emb != "":
		issues.append("body inside %s" % emb)
	var above := at.y - WorldData.get_height(at.x, at.z)
	if above > 3.5:
		issues.append("stands %.1f m above the terrain (roof / wall top?)" % above)
	if w.load_report.get("safety_floor", false):
		issues.append("landed on the temporary safety floor (no collision found)")
	# can the player walk away? four directions, back to the point between tries
	var best := 0.0
	var dirs: Array[String] = []
	for k in 4:
		var yaw := xf.basis.get_euler().y + k * PI * 0.5
		var dd: float = await _walk_dir(yaw, 0.9)
		dirs.append("%.1f" % dd)
		best = maxf(best, dd)
		pl.teleport(Transform3D(pl.global_basis, at))
		await p.wait_game(0.25)
	if best < 1.5:
		issues.append("cannot walk away (best %.1f m: %s)" % [best, " / ".join(dirs)])
	_log("travel %-42s at (%.0f, %.1f, %.0f) +%.1f m over terrain, walks %s %s" % [label, at.x, at.y, at.z, above,
		" / ".join(dirs), ("  ** " + "; ".join(issues)) if not issues.is_empty() else "ok"])
	if not issues.is_empty():
		_finding("travel %s: %s" % [label, "; ".join(issues)])
		pl.teleport(Transform3D(xf.basis, at))
		await _shot("travel_" + String(place["id"]))


# --- 2 city walks ----------------------------------------------------------------------------------------

func _audit_walks() -> void:
	var only := OS.get_environment("CITY")
	for c: Dictionary in WorldData.get_cities():
		if only != "" and not String(c["id"]).contains(only):
			continue
		var L := RingLayout.from_city(c["id"])
		if not L.is_valid():
			continue
		_log("== WALK %s: %d ramps, %d gates" % [c["id"], L.ramps.size(), (c.get("gates", []) as Array).size()])
		# every ramp bearing from the lowest tier to the highest one (the main streets and ramps)
		var up_inward := float(L.tiers[0]["height"]) > float(L.tiers[-1]["height"])
		for rp: Dictionary in L.ramps:
			var b := float(rp["bearing"])
			var arc_tiers: Array[Dictionary] = []
			for t in L.tiers:
				if RingLayout.in_arc(b, t.get("arc")):
					arc_tiers.append(t)
			if arc_tiers.is_empty():
				continue
			var inner: Dictionary = arc_tiers[0]
			var outer: Dictionary = arc_tiers[-1]
			var r_top := float(inner["r_inner"]) + 4.0 if float(inner["r_inner"]) > 0.0 else float(inner["r_outer"]) - 6.0
			if up_inward:
				await _walk_line(c, L, b, float(outer["r_outer"]) - 6.0, r_top, "ramp")
			else:
				await _walk_line(c, L, b, float(inner["r_inner"]) + 10.0, float(outer["r_outer"]) - 6.0, "ramp")
		# every gate: from 30 m outside through the gateway into the city
		for g: Dictionary in c.get("gates", []):
			var gp: Variant = g.get("position")
			if not (gp is Vector3):
				continue
			var route := _road_route(L, gp, float(g.get("bearing", 0.0)))
			if route.size() >= 2:
				# a road runs through the gate (the Dragon's Throat bends off the radial axis): follow it
				await _walk_path(c, L, "%s gate %s (road)" % [c["id"], g.get("id", "?")], route)
				continue
			var ends := _gate_ends(L, gp, float(g.get("bearing", 0.0)), g)
			if ends.is_empty():
				_log("walk %s gate %s: no inside / outside found around it" % [c["id"], g.get("id", "?")])
				continue
			await _walk_straight(c, L, ends[0], ends[1], "%s gate %s" % [c["id"], g.get("id", "?")])


## [outside, inside] 30 m either side of a gate: the record's own points (Ba Sing Se), else the axis
## (radial, or along the ring for gates at the end of a tier's arc) with open ground outside the
## tiers on one side and a tier on the other.
func _gate_ends(L: RingLayout, gp: Vector3, bearing: float, g: Dictionary) -> Array:
	if g.get("outside") is Vector3:
		var o: Vector3 = g["outside"]
		var d := Vector3(gp.x - o.x, 0, gp.z - o.z).normalized()
		return [gp - d * 30.0, gp + d * 30.0]
	var radial := Vector3(RingLayout.dir(bearing).x, 0, RingLayout.dir(bearing).y)
	for axis: Vector3 in [radial, Vector3(-radial.z, 0, radial.x)]:
		for sgn: float in [1.0, -1.0]:
			var out_p := gp + axis * sgn * 30.0
			var in_p := gp - axis * sgn * 30.0
			if L.tier_at(out_p.x, out_p.z).is_empty() and not L.tier_at(in_p.x, in_p.z).is_empty():
				# never below the gate itself: Omashu's bridge gate opens onto a deck over the chasm
				# (dropping from the gate height onto ground that falls away outside is harmless)
				var out_y := maxf(WorldData.get_height(out_p.x, out_p.z), gp.y)
				return [Vector3(out_p.x, out_y, out_p.z), Vector3(in_p.x, gp.y, in_p.z)]
	return []


## Runs along `bearing` from radius r0 to r1 (InputMap move + sprint, camera yaw), recording blocks,
## drops and rescues. A player would jump and sidestep when blocked: so does the walker.
func _walk_line(c: Dictionary, L: RingLayout, bearing: float, r0: float, r1: float, what: String) -> void:
	var sgn := 1.0 if r1 > r0 else -1.0
	await _walk(c, L, "%s %s @%.0f" % [c["id"], what, bearing], L.point(r0, bearing),
		func(pos: Vector3) -> Vector3: return L.point(maxf(L.polar(pos.x, pos.z).x + sgn * 12.0, 0.0), bearing),
		func(pos: Vector3) -> float: return (r1 - L.polar(pos.x, pos.z).x) * sgn,
		absf(r1 - r0))


## The road through a gate (a WorldData road passing within 15 m of it), as a path from 40 m
## outside along the road, through the gate, to 40 m inside along the gate's bearing (the city
## streets / stairs past the road's end). Empty when no road passes through.
func _road_route(L: RingLayout, gp: Vector3, bearing: float) -> PackedVector3Array:
	var gr := L.polar(gp.x, gp.z).x
	var g2 := Vector2(gp.x, gp.z)
	for rd: Dictionary in WorldData.get_roads():
		var pts: PackedVector3Array = rd.get("points", PackedVector3Array())
		var near := false
		for i in pts.size() - 1:
			var q := Geometry2D.get_closest_point_to_segment(g2, Vector2(pts[i].x, pts[i].z), Vector2(pts[i + 1].x, pts[i + 1].z))
			near = near or q.distance_to(g2) < 15.0
		if not near:
			continue
		var by_r: Array = []
		for pt in pts:
			var r := L.polar(pt.x, pt.z).x
			if r <= gr + 40.0 and r >= gr - 20.0 and Vector2(pt.x, pt.z).distance_to(g2) < 60.0:
				by_r.append([r, pt])
		by_r.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
		var out := PackedVector3Array()
		for e: Array in by_r:
			var pt: Vector3 = e[1]
			out.append(Vector3(pt.x, maxf(pt.y, WorldData.get_height(pt.x, pt.z)), pt.z))
		if out.is_empty() or float(by_r[0][0]) < gr + 10.0:
			continue          # no road outside the gate (Omashu's bridge is not a road)
		out.append(L.point(gr - 40.0, bearing))
		return out
	return PackedVector3Array()


## Walks a polyline (aims 12 m ahead of the closest point along it).
func _walk_path(c: Dictionary, L: RingLayout, label: String, path: PackedVector3Array) -> void:
	var cum := PackedFloat32Array([0.0])
	for i in range(1, path.size()):
		cum.append(cum[i - 1] + Vector2(path[i].x - path[i - 1].x, path[i].z - path[i - 1].z).length())
	var total := cum[cum.size() - 1]
	var along := func(pos: Vector3) -> float:
		var best := INF
		var s := 0.0
		for i in path.size() - 1:
			var a2 := Vector2(path[i].x, path[i].z)
			var b2 := Vector2(path[i + 1].x, path[i + 1].z)
			var q := Geometry2D.get_closest_point_to_segment(Vector2(pos.x, pos.z), a2, b2)
			var d := q.distance_to(Vector2(pos.x, pos.z))
			if d < best:
				best = d
				s = cum[i] + q.distance_to(a2)
		return s
	var at := func(s: float) -> Vector3:
		s = clampf(s, 0.0, total)
		for i in path.size() - 1:
			if s <= cum[i + 1] or i == path.size() - 2:
				var seg := maxf(cum[i + 1] - cum[i], 0.001)
				return path[i].lerp(path[i + 1], clampf((s - cum[i]) / seg, 0.0, 1.0))
		return path[path.size() - 1]
	await _walk(c, L, label, path[0],
		func(pos: Vector3) -> Vector3: return at.call(float(along.call(pos)) + 12.0),
		func(pos: Vector3) -> float: return total - float(along.call(pos)),
		total)


func _walk_straight(c: Dictionary, L: RingLayout, a: Vector3, b: Vector3, label: String) -> void:
	var d := Vector3(b.x - a.x, 0, b.z - a.z)
	var length := d.length()
	d /= maxf(length, 0.01)
	await _walk(c, L, label, a,
		func(pos: Vector3) -> Vector3:
			var along := clampf((pos - a).dot(d) + 12.0, 0.0, length + 12.0)
			return a + d * along,
		func(pos: Vector3) -> float: return length - (pos - a).dot(d),
		length)


## The walker: from `start`, steering at aim(pos), until left(pos) <= 0 (metres still to go).
func _walk(c: Dictionary, L: RingLayout, label: String, start: Vector3, aim: Callable, left: Callable, total: float) -> void:
	var aim0: Vector3 = aim.call(start)
	if not await _travel(Transform3D(Basis(Vector3.UP, _yaw_to(start, aim0)), start + Vector3.UP * 0.3)):
		_finding("walk %s: could not travel to the start" % label)
		return
	await p.wait_game(0.6)
	var t := 0.0
	var last := pl.global_position
	var win_t := 0.0
	var win_from := pl.global_position
	var blocks: Array[String] = []
	var unstick := 0
	var block_at := Vector3.INF
	var best := 0.0
	var y_track := pl.global_position.y
	var limit := total / 4.0 + 30.0
	Input.action_press(&"sprint")
	while t < limit:
		_heal()
		var pos := pl.global_position
		var rem: float = left.call(pos)
		best = maxf(best, total - rem)
		if rem <= 0.0:
			break
		var target: Vector3 = aim.call(pos)
		pl.camera_rig.set_yaw(_yaw_to(pos, target))
		Input.action_press(&"move_forward")
		await p.wait_game(0.1)
		t += 0.1
		var now := pl.global_position
		var r := L.polar(now.x, now.z).x
		if now.distance_to(last) > 25.0:
			_finding("walk %s: jumped %.0f m in one step at r=%.0f (fall net / rescue?) from (%.0f, %.1f, %.0f) to (%.0f, %.1f, %.0f)" % [label,
				now.distance_to(last), r, last.x, last.y, last.z, now.x, now.y, now.z])
			_point(label, "rescue", last, _yaw_to(last, target))
			await _shot("rescue_" + label)
			break
		if y_track - now.y > 4.0 and pl.motor.on_floor:
			_finding("walk %s: dropped %.1f m at r=%.0f (%.0f, %.1f, %.0f) tier %s - off a ledge / through a hole?" % [label, y_track - now.y, r,
				now.x, now.y, now.z, String(L.tier_at(now.x, now.z).get("id", "-"))])
			_point(label, "drop", now, _yaw_to(now, target))
			await _shot("drop_" + label)
		if pl.motor.on_floor:
			y_track = now.y
		last = now
		win_t += 0.1
		if win_t >= 1.5:
			var moved := Vector2(now.x - win_from.x, now.z - win_from.z).length()
			if moved < 1.2:
				var info := _block_info()
				if not block_at.is_finite() or block_at.distance_to(now) > 4.0:
					block_at = now
					unstick = 0
					blocks.append("r=%.0f" % r)
					_finding("walk %s: blocked at r=%.0f (%.0f, %.1f, %.0f) tier %s, %s" % [label, r, now.x, now.y, now.z,
						String(L.tier_at(now.x, now.z).get("id", "-")), info])
					_point(label, "block", now, _yaw_to(now, target))
					await _shot("block_" + label)
				unstick += 1
				if unstick > 3:
					_log("walk %s: gives up at r=%.0f" % [label, r])
					break
				await p.tap(&"jump")
				var side := &"move_right" if unstick % 2 == 1 else &"move_left"
				Input.action_press(side)
				await p.wait_game(0.9)
				Input.action_release(side)
				t += 1.0
			win_t = 0.0
			win_from = pl.global_position
	Input.action_release(&"move_forward")
	Input.action_release(&"sprint")
	await p.wait_game(0.2)
	var reached: bool = float(left.call(pl.global_position)) <= 1.0
	_log("walk %-40s %s in %.0f s (%.0f of %.0f m) %d block(s) %s" % [label, "REACHED" if reached else "stopped",
		t, best, total, blocks.size(), ", ".join(blocks)])


var points: Array = []


## PART=tour (rendered): POINTS=<walk_points.json of a headless walk run>; the player is placed at
## every recorded block / drop and photographed from behind looking along the walk.
func _audit_tour() -> void:
	var path := OS.get_environment("POINTS")
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if path != "" else null
	if not (data is Array):
		p.check(false, "tour: POINTS=<walk_points.json> needed")
		return
	var i := 0
	for e: Dictionary in data:
		i += 1
		var a: Array = e["pos"]
		var at := Vector3(float(a[0]), float(a[1]), float(a[2]))
		var yaw := float(e["yaw"])
		if not await _travel(Transform3D(Basis(Vector3.UP, yaw), at + Vector3.UP * 0.2)):
			continue
		# a few steps back so the camera sees what stopped the walker
		pl.teleport(Transform3D(Basis(Vector3.UP, yaw), at + Basis(Vector3.UP, yaw) * Vector3(0, 0.2, 2.5)))
		pl.camera_rig.set_yaw(yaw)
		await p.wait_game(1.2)
		var pp := pl.global_position
		_log("tour %02d %s %s at (%.0f, %.1f, %.0f); player at (%.0f, %.1f, %.0f) %s floor %s cam %s" % [i, e["kind"], e["label"], at.x, at.y, at.z,
			pp.x, pp.y, pp.z, pl.get_state_name(), pl.motor.on_floor, str(p.get_viewport().get_camera_3d().global_position.round()) if p.get_viewport().get_camera_3d() else "-"])
		shots = mini(shots, 39)
		await _shot("tour_%02d_%s_%s" % [i, e["kind"], String(e["label"]).replace(" ", "_")])


func _point(label: String, kind: String, at: Vector3, yaw: float) -> void:
	points.append({"label": label, "kind": kind, "pos": [at.x, at.y, at.z], "yaw": yaw})
	var f := FileAccess.open(p.out_dir.path_join("walk_points.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(points, "\t"))


## What stops the player: rays ahead at knee and chest height, plus the step in front.
func _block_info() -> String:
	var space := pl.get_world_3d().direct_space_state
	var fwd := -pl.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var out: Array[String] = []
	for hgt: float in [0.35, 1.2]:
		var a := pl.global_position + Vector3(0, hgt, 0)
		var q := PhysicsRayQueryParameters3D.create(a, a + fwd * 1.4, Layers.SOLID | Layers.NPC | Layers.COMPANION)
		q.exclude = [pl.get_rid()]
		var r := space.intersect_ray(q)
		out.append("%.2fm:%s" % [hgt, _who(r.get("collider")) if not r.is_empty() else "free"])
	var ahead := pl.global_position + fwd * 1.0
	var qd := PhysicsRayQueryParameters3D.create(ahead + Vector3.UP * 3.0, ahead + Vector3.DOWN * 4.0, Layers.SOLID)
	qd.exclude = [pl.get_rid()]
	var rd := space.intersect_ray(qd)
	if not rd.is_empty():
		out.append("step %+.2f m" % ((rd["position"] as Vector3).y - pl.global_position.y))
	out.append(pl.get_state_name())
	return " ".join(out)


# --- 3 NPCs -----------------------------------------------------------------------------------------------

func _audit_npcs() -> void:
	var only := OS.get_environment("CITY")
	for c: Dictionary in WorldData.get_cities():
		if only != "" and not String(c["id"]).contains(only):
			continue
		var place := MapModel.place_by_id(c["id"])
		var xf := MapModel.travel_transform(place) if not place.is_empty() else Transform3D(Basis(), WorldData.get_safe_ground(c["center"]))
		if not await _travel(xf):
			continue
		await p.wait_game(3.0)
		var buried: Dictionary = {}
		var stuck: Dictionary = {}
		var seen: Dictionary = {}
		var last_pos: Dictionary = {}
		var still_t: Dictionary = {}
		for i in 40:
			_heal()
			for n: Node in p.get_tree().get_nodes_in_group(&"npc"):
				var npc := n as NpcCharacter
				if npc == null or not npc.is_inside_tree() or npc.is_vanishing():
					continue
				var k := String(npc.key)
				seen[k] = npc.full
				var emb := _embedded_in(npc)
				if emb != "" and not buried.has(k):
					buried[k] = "%s %s at (%.1f, %.1f, %.1f) in %s" % ["full" if npc.full else "lite", npc.display_name(), npc.global_position.x,
						npc.global_position.y, npc.global_position.z, emb]
				if npc.is_moving():
					var lp: Vector3 = last_pos.get(k, npc.global_position)
					if lp.distance_to(npc.global_position) < 0.05:
						still_t[k] = float(still_t.get(k, 0.0)) + 0.5
						if float(still_t[k]) >= 3.0 and not stuck.has(k):
							stuck[k] = "%s at (%.1f, %.1f, %.1f) wants to walk but has not moved for 3 s" % [npc.display_name(),
								npc.global_position.x, npc.global_position.y, npc.global_position.z]
					else:
						still_t[k] = 0.0
				last_pos[k] = npc.global_position
			await p.wait_game(0.5)
		_log("npc %s: %d NPCs seen (%d full), %d buried in geometry, %d stuck walkers" % [c["id"], seen.size(),
			seen.values().count(true), buried.size(), stuck.size()])
		for k: String in buried:
			_finding("npc %s: buried: %s" % [c["id"], buried[k]])
		for k: String in stuck:
			_finding("npc %s: stuck: %s" % [c["id"], stuck[k]])
		if not buried.is_empty():
			await _shot("npc_" + String(c["id"]))


# --- 4 quests ---------------------------------------------------------------------------------------------

## A floor point where a player can stand within r_min..r_max of `at` (no wall in the body), or INF.
func _standing_spot(at: Vector3, r_min: float, r_max: float) -> Vector3:
	var space := pl.get_world_3d().direct_space_state
	for rr: float in [r_min, (r_min + r_max) * 0.5, r_max]:
		for k in 12:
			var a := TAU * k / 12.0
			var q := at + Vector3(cos(a), 0, sin(a)) * rr
			var rq := PhysicsRayQueryParameters3D.create(q + Vector3.UP * 2.5, q + Vector3.DOWN * 3.0, Layers.WORLD | Layers.CONSTRUCT)
			rq.exclude = [pl.get_rid()]
			var hit := space.intersect_ray(rq)
			if hit.is_empty():
				continue
			var g: Vector3 = hit["position"]
			if absf(g.y - at.y) > 1.3 or WorldData.get_water_height(g.x, g.z) > g.y + 0.6:
				continue
			var sh := CapsuleShape3D.new()
			sh.radius = 0.3
			sh.height = 1.2
			var sq := PhysicsShapeQueryParameters3D.new()
			sq.shape = sh
			sq.transform = Transform3D(Basis(), g + Vector3(0, 1.05, 0))
			sq.collision_mask = Layers.WORLD | Layers.CONSTRUCT
			sq.exclude = [pl.get_rid()]
			if space.intersect_shape(sq, 1).is_empty():
				return g
	return Vector3.INF


func _advance_to(q: StringName, stage: int) -> bool:
	Quests.reset_quest(q)
	if not Quests.start(q, {"silent": true}):
		return false
	var guard := 0
	while Quests.is_active(q) and Quests.current_stage(q) < stage and guard < 16:
		guard += 1
		for od: Dictionary in Quests.stage_def(q).get("objectives", []):
			if Quests.is_active(q) and Quests.current_stage(q) < stage:
				Quests.complete_objective(q, od["id"])
	return Quests.is_active(q) and Quests.current_stage(q) == stage


func _audit_quests() -> void:
	var props_node := w.props_root.get_node_or_null("QuestProps") as QuestProps
	var only := OS.get_environment("QUEST")
	_log("== QUESTS")
	for q: StringName in Quests.order:
		if only != "" and not String(q).contains(only):
			continue
		var stages: Array = Quests.get_def(q).get("stages", [])
		for si in stages.size():
			for od: Dictionary in (stages[si] as Dictionary)["objectives"]:
				var props: Array = od.get("props", [])
				if not props.is_empty():
					await _audit_props(q, si, od, props_node)
				elif od["type"] == &"go_to":
					await _audit_go_to(q, si, od)
				elif od["type"] == &"talk_to" or od["type"] == &"escort":
					await _audit_named(q, od)
		Quests.reset_quest(q)


func _audit_props(q: StringName, stage: int, od: Dictionary, props_node: QuestProps) -> void:
	var label := "%s/%s" % [q, od["id"]]
	if not _advance_to(q, stage):
		_finding("quest %s: could not advance to stage %d" % [label, stage])
		return
	var before := GameState.item_count(od.get("item", &"")) if od["type"] == &"collect" else 0
	var props: Array = od["props"]
	var got := 0
	for i in props.size():
		var at := QuestTargets.resolve((props[i] as Dictionary).get("at"))
		var stand := WorldData.get_safe_ground(at + Vector3(2.5, 0, 0))
		if absf(stand.y - at.y) > 3.0:
			stand = Vector3(at.x + 2.5, at.y + 0.3, at.z)
		if not await _travel(Transform3D(Basis(), stand)):
			_finding("quest %s prop %d: travel failed" % [label, i])
			continue
		props_node.refresh()
		await p.wait_game(0.3)
		var node: Node3D = null
		for n in props_node.live_props():
			var qp := n as QuestProps.QuestPropNode
			if qp and qp.quest_id == q and qp.objective["id"] == od["id"] and qp.index == i:
				node = qp
		if node == null:
			if not Quests.is_objective_active(q, od["id"]):
				break
			_finding("quest %s prop %d: did not spawn at (%.0f, %.1f, %.0f)" % [label, i, at.x, at.y, at.z])
			continue
		var pp := node.global_position
		var issues: Array[String] = []
		var above := pp.y - WorldData.get_height(pp.x, pp.z)
		if WorldData.get_water_height(pp.x, pp.z) > pp.y + 0.3:
			issues.append("under water (%.1f m)" % (WorldData.get_water_height(pp.x, pp.z) - pp.y))
		var emb := _embedded_in(node)
		if emb != "":
			issues.append("inside %s" % emb)
		var spot := _standing_spot(pp, 1.0, 1.9)
		if not spot.is_finite():
			issues.append("no floor to stand on within 2 m")
		else:
			pl.teleport(Transform3D(Basis(Vector3.UP, _yaw_to(spot, pp)), spot + Vector3.UP * 0.05))
			await p.wait_game(0.6)
			await p.tap(&"interact")
			await p.wait_game(1.0)
			if QuestProps.is_taken(q, od["id"], i):
				got += 1
			else:
				issues.append("interact did not take it (player %.1f m away, state %s)" % [pl.global_position.distance_to(pp), pl.get_state_name()])
		_log("prop %-40s #%d at (%.0f, %.1f, %.0f) +%.1f m %s" % [label, i, pp.x, pp.y, pp.z, above, ("** " + "; ".join(issues)) if not issues.is_empty() else "ok, taken"])
		if not issues.is_empty():
			_finding("quest %s prop %d at (%.0f, %.1f, %.0f): %s" % [label, i, pp.x, pp.y, pp.z, "; ".join(issues)])
			await _shot("prop_%s_%d" % [label, i])
		if not Quests.is_objective_active(q, od["id"]):
			break
	if Quests.is_objective_active(q, od["id"]) and Quests.current_stage(q) == stage:
		var have := GameState.item_count(od.get("item", &"")) - before
		_finding("quest %s: objective still open after taking %d of %d props (+%d items, needs %d)" % [label, got, props.size(), have, int(od["count"])])


func _audit_go_to(q: StringName, stage: int, od: Dictionary) -> void:
	var label := "%s/%s" % [q, od["id"]]
	if not _advance_to(q, stage):
		_finding("quest %s: could not advance to stage %d" % [label, stage])
		return
	var t := QuestTargets.resolve(od.get("target"))
	var spot := WorldData.get_safe_ground(t)
	var r := float(od.get("radius", 20.0))
	if Vector2(spot.x - t.x, spot.z - t.z).length() > r * 0.8:
		_finding("quest %s: no safe ground within the radius (nearest %.0f m, radius %.0f)" % [label, Vector2(spot.x - t.x, spot.z - t.z).length(), r])
	if not await _travel(Transform3D(Basis(), spot)):
		_finding("quest %s: travel failed" % label)
		return
	await p.wait_game(1.0)
	var done := not Quests.is_objective_active(q, od["id"])
	_log("go_to %-40s target (%.0f, %.1f, %.0f) r %.0f: %s" % [label, t.x, t.y, t.z, r, "completed" if done else "** still open"])
	if not done:
		var pp := pl.global_position
		_finding("quest %s: standing at (%.0f, %.1f, %.0f), %.0f m from the target (r %.0f, dy %.1f) does not complete it" % [label,
			pp.x, pp.y, pp.z, Vector2(pp.x - t.x, pp.z - t.z).length(), r, pp.y - t.y])
		await _shot("goto_" + label)


var _named_done := {}


func _audit_named(q: StringName, od: Dictionary) -> void:
	var id: StringName = od["npc"]
	if _named_done.has(id):
		return
	_named_done[id] = true
	var xf := NpcRegistry.placement(id)
	if not xf.origin.is_finite():
		_finding("npc %s (%s): no placement" % [id, q])
		return
	var front := xf.origin + (xf.basis * Vector3.FORWARD) * 2.5
	var stand := WorldData.get_safe_ground(front)
	if absf(stand.y - xf.origin.y) > 3.0:
		stand = front + Vector3.UP * 0.3
	if not await _travel(Transform3D(Basis(Vector3.UP, _yaw_to(stand, xf.origin)), stand)):
		return
	await p.wait_game(2.5)
	var npc := NpcRegistry.live_npc(id) as NpcCharacter
	if npc == null:
		_finding("npc %s (%s): not spawned near its placement (%.0f, %.1f, %.0f)" % [id, q, xf.origin.x, xf.origin.y, xf.origin.z])
		return
	var issues: Array[String] = []
	var emb := _embedded_in(npc)
	if emb != "":
		issues.append("buried in %s" % emb)
	var spot := _standing_spot(npc.global_position, 1.2, 2.2)
	if not spot.is_finite():
		issues.append("no floor to talk from within 2.2 m")
	if WorldData.get_water_height(npc.global_position.x, npc.global_position.z) > npc.global_position.y + 0.4:
		issues.append("stands in water")
	_log("npc %-24s at (%.0f, %.1f, %.0f) %s" % [id, npc.global_position.x, npc.global_position.y, npc.global_position.z, ("** " + "; ".join(issues)) if not issues.is_empty() else "ok"])
	if not issues.is_empty():
		_finding("npc %s (%s) at (%.0f, %.1f, %.0f): %s" % [id, q, npc.global_position.x, npc.global_position.y, npc.global_position.z, "; ".join(issues)])
		await _shot("named_" + String(id))
