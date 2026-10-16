extends TestCase
## Settlements I (Northern Water Tribe + arctic villages, Southern Air Temple): plans from the
## WorldData layouts, cell builds (LOD meshes, shared AABB, collision), archetype cache, anchors
## API, determinism, keep-outs (spawns, ferry lane, ramps, canals), world hook registration.


func test_nwt_plan_counts() -> void:
	if not WorldData.has_world_data():
		return
	var t0 := Time.get_ticks_usec()
	var p := Settlements.plan(Settlements.WATER_TRIBE)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("    nwt plan: %d pieces, %d anchors, %.0f ms" % [p.pieces.size(), p.anchors.size(), ms])
	var counts := {}
	for pc in p.pieces:
		counts[pc["kind"]] = int(counts.get(pc["kind"], 0)) + 1
	print("    ", counts)
	expect(p.pieces.size() > 500, "a dense city")
	expect(int(counts.get(&"tier_wall", 0)) > 100, "retaining walls")
	expect(int(counts.get(&"grand_stair", 0)) >= 9, "a grand stair on every tier ramp")
	expect(int(counts.get(&"sea_wall", 0)) > 20, "sea wall chords")
	expect_eq(int(counts.get(&"sea_gate", 0)), 1, "sea gate")
	expect_eq(int(counts.get(&"palace", 0)), 1, "palace")
	expect_eq(int(counts.get(&"oasis", 0)), 1, "oasis")
	expect_eq(int(counts.get(&"canal_fall", 0)), 4, "canal falls")
	expect(int(counts.get(&"canal_bridge", 0)) >= 12, "canal bridges")
	expect(int(counts.get(&"pier", 0)) >= 6, "harbour piers")
	expect(int(counts.get(&"ship", 0)) >= 3, "ships")
	for k: StringName in [&"healer_hut", &"training_hall", &"family_home"]:
		expect_eq(int(counts.get(k, 0)), 1, "interior %s" % k)


func test_sat_plan_counts() -> void:
	if not WorldData.has_world_data():
		return
	var t0 := Time.get_ticks_usec()
	var p := Settlements.plan(Settlements.AIR_TEMPLE)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var counts := {}
	for pc in p.pieces:
		counts[pc["kind"]] = int(counts.get(pc["kind"], 0)) + 1
	print("    sat plan: %d pieces, %d anchors, %.0f ms" % [p.pieces.size(), p.anchors.size(), ms])
	print("    ", counts)
	expect(p.pieces.size() > 200, "a full temple")
	expect_eq(int(counts.get(&"great_spire", 0)), 1, "the great spire")
	expect_eq(int(counts.get(&"sanctuary", 0)), 1, "the sanctuary")
	expect_eq(int(counts.get(&"airball_court", 0)), 1, "the airball court")
	expect(int(counts.get(&"spire", 0)) >= 14, "a cluster of spires")
	expect(int(counts.get(&"stair", 0)) >= 8, "stairs on every ramp")
	expect(int(counts.get(&"tier_wall", 0)) > 60, "retaining walls")
	expect(int(counts.get(&"edge_rail", 0)) > 60, "cliff balustrades")
	expect(int(counts.get(&"sky_bridge", 0)) >= 8, "two suspended bridges in segments")
	expect(int(counts.get(&"stable", 0)) >= 1, "bison stables")
	expect(int(counts.get(&"pavilion", 0)) >= 5, "meditation pavilions")
	expect(int(counts.get(&"garden", 0)) >= 8, "gardens")


func test_sat_cells_build() -> void:
	if not WorldData.has_world_data():
		return
	var p := Settlements.plan(Settlements.AIR_TEMPLE)
	var b := Settlements.builder(Settlements.AIR_TEMPLE)
	var prov := SettlementProvider.new(p, b)
	prov.cfg = SettlementSettings.current()
	var far := SettlementFarProvider.new(p, b)
	far.cfg = prov.cfg
	var worst := 0.0
	var tris := 0
	for c: Vector2i in p.cells():
		var origin := Vector3((c.x + 0.5) * p.cell_size, 0, (c.y + 0.5) * p.cell_size)
		var t0 := Time.get_ticks_usec()
		var res := prov.build_lods(c, origin)
		worst = maxf(worst, (Time.get_ticks_usec() - t0) / 1000.0)
		tris += (res[0] as KitResult).triangle_count
		expect(not (res[0] as KitResult).surfaces.is_empty(), "cell %s has geometry" % c)
		var r2 := far.build_sub(c, origin)
		expect(r2.triangle_count < (res[0] as KitResult).triangle_count, "far LOD is lighter (%s)" % c)
	print("    %d cells, worst build %.0f ms, %d lod0 tris total" % [p.cells().size(), worst, tris])


func test_nwt_cell_build_budget() -> void:
	if not WorldData.has_world_data():
		return
	var p := Settlements.plan(Settlements.WATER_TRIBE)
	var b := Settlements.builder(Settlements.WATER_TRIBE)
	var prov := SettlementProvider.new(p, b)
	prov.cfg = SettlementSettings.current()
	var cells := p.cells()
	cells.sort()
	var worst := 0.0
	var tris := 0
	var n := 0
	for k in range(0, cells.size(), maxi(cells.size() / 8, 1)):
		var c: Vector2i = cells[k]
		var origin := Vector3((c.x + 0.5) * p.cell_size, 0, (c.y + 0.5) * p.cell_size)
		var t0 := Time.get_ticks_usec()
		var res := prov.build_lods(c, origin)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		worst = maxf(worst, ms)
		tris += (res[0] as KitResult).triangle_count
		n += 1
	print("    %d cells sampled of %d, worst build %.0f ms, avg tris lod0 %d, cache %d archetypes" % [n, cells.size(), worst, tris / maxi(n, 1), KitCache.size()])
	expect(worst < 4000.0, "cell builds stay bounded")


# --- walkability: a probe capsule over the real collision ------------------------------------------

var _walk_root: Node3D = null
var _walk_cells: Dictionary = {}


func after_each() -> void:
	if _walk_root:
		_walk_root.queue_free()
		_walk_root = null
	_walk_cells.clear()


## Builds terrain heightfield collision over `rect` (world x/z) and the settlement collision of
## every cell of `sid` overlapping it.
func _walk_world(sid: StringName, rect: Rect2) -> void:
	if _walk_root == null:
		_walk_root = Node3D.new()
		_walk_root.name = "WalkRoot"
		add_child(_walk_root)
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD
	_walk_root.add_child(body)
	var tx0 := int(floor((rect.position.x + 4096.0) / 2.0))
	var tz0 := int(floor((rect.position.y + 4096.0) / 2.0))
	var tx1 := int(ceil((rect.end.x + 4096.0) / 2.0))
	var tz1 := int(ceil((rect.end.y + 4096.0) / 2.0))
	var tz := tz0
	while tz < tz1:
		var tx := tx0
		var d := mini(128, tz1 - tz + 1)
		while tx < tx1:
			var w := mini(128, tx1 - tx + 1)
			var shape := HeightMapShape3D.new()
			if WorldData.fill_height_map_shape(shape, tx, tz, w, d):
				var cs := CollisionShape3D.new()
				cs.shape = shape
				var c := WorldData.texel_block_center(tx, tz, w, d)
				cs.position = Vector3(c.x, 0.0, c.y)
				cs.scale = Vector3(2.0, 1.0, 2.0)
				body.add_child(cs)
			tx += w - 1
		tz += d - 1
	var p := Settlements.plan(sid)
	var prov := SettlementProvider.new(p, Settlements.builder(sid))
	prov.cfg = SettlementSettings.current()
	for c: Vector2i in p.cells():
		var cr := Rect2(c.x * p.cell_size, c.y * p.cell_size, p.cell_size, p.cell_size)
		if not cr.intersects(rect.grow(8.0)) or _walk_cells.has(c):
			continue
		var origin := Vector3((c.x + 0.5) * p.cell_size, 0, (c.y + 0.5) * p.cell_size)
		var r0: KitResult = prov.build_lods(c, origin)[0]
		var b := SettlementProvider.make_body({"boxes": r0.boxes, "faces": r0.faces})
		if b:
			b.position = origin
			_walk_root.add_child(b)
		_walk_cells[c] = true


## Marches a capsule (r 0.33, 1.6 m) along the waypoints in 0.25 m steps: the floor must be
## found under every step (no holes), never more than 0.42 m higher (the player motor steps up
## 0.38 m) or 1.2 m lower than the last step, no steeper than 46 degrees, and the capsule raised
## 0.42 m over it (what the motor can step over) must touch nothing (no walls across the way).
## Returns "" or the failure.
func _walk(points: PackedVector3Array, label: String) -> String:
	var space := _walk_root.get_world_3d().direct_space_state
	var cap := CapsuleShape3D.new()
	cap.radius = 0.33
	cap.height = 1.6
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.collision_mask = Layers.WORLD
	var y := points[0].y
	var walked := 0.0
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var n := maxi(int(ceil(Vector2(b.x - a.x, b.z - a.z).length() / 0.25)), 1)
		for k in range(1, n + 1):
			var p := a.lerp(b, float(k) / n)
			var rq := PhysicsRayQueryParameters3D.create(Vector3(p.x, y + 1.6, p.z), Vector3(p.x, y - 3.0, p.z), Layers.WORLD)
			var hit := space.intersect_ray(rq)
			if hit.is_empty():
				return "%s: no floor at %s after %.0f m" % [label, p, walked]
			var fy: float = (hit["position"] as Vector3).y
			if fy - y > 0.42:
				return "%s: %.2f m step up at %s after %.0f m" % [label, fy - y, Vector3(p.x, fy, p.z), walked]
			if y - fy > 1.2:
				return "%s: %.2f m drop at %s after %.0f m" % [label, y - fy, Vector3(p.x, fy, p.z), walked]
			var nrm: Vector3 = hit["normal"]
			if nrm.y < cos(deg_to_rad(46.0)):
				return "%s: too steep (%.0f deg) at %s" % [label, rad_to_deg(acos(nrm.y)), Vector3(p.x, fy, p.z)]
			y = fy
			q.transform = Transform3D(Basis(), Vector3(p.x, y + 0.42 + 0.8, p.z))
			var touching := space.intersect_shape(q, 4)
			if not touching.is_empty():
				var what := []
				for t: Dictionary in touching:
					var co: Object = t["collider"]
					var sh: Variant = PhysicsServer3D.body_get_shape(t["rid"], t["shape"]) if t.has("rid") else null
					var st := ""
					if co is CollisionObject3D:
						var owner_id := (co as CollisionObject3D).shape_find_owner(int(t["shape"]))
						var cs := (co as CollisionObject3D).shape_owner_get_owner(owner_id) as CollisionShape3D
						if cs:
							st = "%s@%s" % [cs.shape.get_class(), (co as Node3D).global_transform * cs.position]
					what.append("%s %s" % [(co as Node).name if co is Node else str(co), st])
					if sh == null:
						pass
				return "%s: blocked at %s after %.0f m by %s" % [label, Vector3(p.x, y, p.z), walked, what]
			walked += 0.25
	return ""


## World points of polar waypoints [[r, bearing, y], ...] of a ring layout city.
func _polar_path(L: RingLayout, pts: Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for p: Array in pts:
		out.append(L.point(float(p[0]), float(p[1]), float(p[2])))
	return out


func _path_rect(paths: Array) -> Rect2:
	var r := Rect2()
	var first := true
	for pts: PackedVector3Array in paths:
		for p in pts:
			if first:
				r = Rect2(p.x, p.z, 0, 0)
				first = false
			else:
				r = r.expand(Vector2(p.x, p.z))
	return r.grow(12.0)


func test_sat_walk_stairs_and_bridges() -> void:
	if not WorldData.has_world_data():
		return
	var L := RingLayout.from_city(Settlements.AIR_TEMPLE)
	var paths := {}
	# down from the arrival plaza: courtyard -> terrace -> landing over the two bearing-25 stairs
	# (into the courtyard, then along the stair axis through its top gateway)
	paths["stairs_25"] = _polar_path(L, [[100.0, 12.0, 802.0], [86.0, 14.0, 802.0], [86.0, 25.0, 802.0], [133.0, 25.0, 782.0],
		[185.0, 25.0, 762.0]])
	# up into the Sanctum through its gateway
	paths["sanctum_-30"] = _polar_path(L, [[76.0, -30.0, 802.0], [24.0, -30.0, 822.0]])
	# along the landing past the stables to the bison landing circle
	paths["landing"] = _polar_path(L, [[188.0, 25.0, 762.0], [196.0, 10.0, 762.0], [194.0, -6.0, 762.0], [196.0, -20.0, 762.0]])
	# the two suspended bridges, terrace -> pinnacle
	for br in WorldData.get_bridges():
		if not SatPlanner.CLAIMS.has(StringName(br["id"])):
			continue
		var a: Vector3 = br["a"]
		var b: Vector3 = br["b"]
		var dir := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
		paths[String(br["id"])] = PackedVector3Array([a - dir * 6.0, a, b, b + dir * 6.0])
	_walk_world(Settlements.AIR_TEMPLE, _path_rect(paths.values()))
	await physics_frames(3)
	for k: String in paths:
		var err := _walk(paths[k], k)
		expect(err == "", err)


func _nwt_walks(paths: Dictionary) -> void:
	_walk_world(Settlements.WATER_TRIBE, _path_rect(paths.values()))
	await physics_frames(3)
	for k: String in paths:
		var err := _walk(paths[k], k)
		expect(err == "", err)


func test_nwt_walk_grand_stairs() -> void:
	if not WorldData.has_world_data():
		return
	var p := Settlements.plan(Settlements.WATER_TRIBE)
	var paths := {}
	for s: Dictionary in p.data.get("stairs", []):
		var foot: Vector3 = s["foot"]
		var top: Vector3 = s["top"]
		var dir := Vector3(top.x - foot.x, 0, top.z - foot.z).normalized()
		paths["stair_%d_%d" % [int(s["r"]), int(s["bearing"])]] = PackedVector3Array([foot - dir * 6.0, foot, top, top + dir * 4.0])
	expect(paths.size() >= 9, "every ramp has a stair")
	await _nwt_walks(paths)


func test_nwt_walk_bridges_piers_interiors() -> void:
	if not WorldData.has_world_data():
		return
	var p := Settlements.plan(Settlements.WATER_TRIBE)
	var paths := {}
	for pc in p.pieces_of(&"canal_bridge"):
		var pos: Vector3 = pc["pos"]
		var fwd := Basis(Vector3.UP, float(pc["yaw"])) * Vector3.FORWARD
		# bank to bank (+0.8 m past each end post; plazas with monuments may follow)
		var half := float((pc["spec"] as Dictionary).get("span", 9.0)) * 0.5 + 3.0
		paths["bridge_%d_%d" % [int(pos.x), int(pos.z)]] = PackedVector3Array([pos - fwd * half, pos, pos + fwd * half])
	var n := 0
	for pc in p.pieces_of(&"pier"):
		if n >= 4:
			break
		var pos: Vector3 = pc["pos"]
		var fwd := Basis(Vector3.UP, float(pc["yaw"])) * Vector3.FORWARD
		paths["pier_%d_%d" % [int(pos.x), int(pos.z)]] = PackedVector3Array([pos - fwd * 5.0, pos + fwd * (float(pc["spec"]["L"]) - 1.5)])
		n += 1
	# into the interiors through their doors (stopping short of the healing pool / fire pit, past
	# the practice pillars of the training hall)
	var stops := {&"healer_hut": [Vector3(0, 0, -10.5), Vector3(0, 0, -3.0)],
		&"training_hall": [Vector3(0, 0, -12.0), Vector3(0, 0, -6.2), Vector3(2.0, 0, -6.2), Vector3(2.0, 0, 2.0)],
		&"family_home": [Vector3(0, 0, -7.5), Vector3(0, 0, -1.6)]}
	for it: Dictionary in p.data.get("interiors", []):
		var pos: Vector3 = it["position"]
		var yaw := float(it["yaw"])
		var pts := PackedVector3Array()
		for s: Vector3 in stops[it["kind"]]:
			pts.append(NwtDistricts.world(pos, yaw, s))
		paths["interior_%s" % it["kind"]] = pts
	expect(paths.size() >= 15, "bridges, piers and interiors to walk")
	await _nwt_walks(paths)
