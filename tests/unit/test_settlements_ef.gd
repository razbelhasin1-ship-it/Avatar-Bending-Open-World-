extends TestCase
## Settlements II (Ba Sing Se, Omashu, the Earth Kingdom villages, the Fire Nation capital,
## Crimson Harbor and the Fire Nation villages): plans from the WorldData layouts, cell builds
## (LOD meshes, budgets), anchors contract, lookups, determinism, registration (claims, tutorial
## skip tags), arrival-flight clearance and probe-capsule walk tests over the real collision.

const EF: Array[StringName] = [Settlements.BA_SING_SE, Settlements.OMASHU, Settlements.EK_VILLAGES, Settlements.FN_CAPITAL,
	Settlements.FN_HARBOR, Settlements.FN_VILLAGES]


func _counts(p: SettlementPlan) -> Dictionary:
	var counts := {}
	for pc in p.pieces:
		counts[pc["kind"]] = int(counts.get(pc["kind"], 0)) + 1
	return counts


func test_bss_plan_counts() -> void:
	if not WorldData.has_world_data():
		return
	var t0 := Time.get_ticks_usec()
	var p := Settlements.plan(Settlements.BA_SING_SE)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var counts := _counts(p)
	print("    bss plan: %d pieces, %d anchors, %d cells, %.0f ms" % [p.pieces.size(), p.anchors.size(), p.cells().size(), ms])
	print("    ", counts)
	expect(p.pieces.size() > 2000, "a vast city")
	expect(int(counts.get(&"city_wall", 0)) > 300, "outer + inner wall chords")
	expect_eq(int(counts.get(&"great_gate", 0)), 10, "a gatehouse on every avenue in both walls")
	expect(int(counts.get(&"wall_tower", 0)) > 40, "bastions")
	expect(int(counts.get(&"ring_wall", 0)) > 100, "Middle / Upper Ring walls")
	expect_eq(int(counts.get(&"grand_stair", 0)), 5, "Upper Ring stairs")
	expect(int(counts.get(&"row_house", 0)) > 300, "dense Lower Ring housing")
	expect(int(counts.get(&"mansion", 0)) > 10, "Upper Ring mansions")
	expect(int(counts.get(&"court_house", 0)) > 30, "Middle Ring courtyard houses")
	expect(int(counts.get(&"windmill", 0)) >= 8, "windmills")
	expect(int(counts.get(&"farmhouse", 0)) >= 30, "farmsteads")
	expect(int(counts.get(&"water_wheel", 0)) >= 5, "water wheels")
	expect_eq(int(counts.get(&"throne_hall", 0)), 1, "the throne hall")
	for k: StringName in [&"tea_shop", &"training_hall"]:
		expect_eq(int(counts.get(k, 0)), 1, "interior %s" % k)
	expect(ms < 3000.0, "plan builds in a bounded time")


## Every cell builds at every LOD; LOD2 lighter than LOD0; cell budgets (printed for the docs).
func _cells_build(sid: StringName, budget_ms: float) -> void:
	var p := Settlements.plan(sid)
	var b := Settlements.builder(sid)
	var prov := SettlementProvider.new(p, b)
	prov.cfg = SettlementSettings.current()
	var far := SettlementFarProvider.new(p, b)
	far.cfg = prov.cfg
	var cells := p.cells()
	cells.sort()
	var worst := 0.0
	var tris := 0
	var tris1 := 0
	var tris2 := 0
	var max_tris := 0
	var cache0 := KitCache.size()
	for c: Vector2i in cells:
		var origin := Vector3((c.x + 0.5) * p.cell_size, 0, (c.y + 0.5) * p.cell_size)
		var t0 := Time.get_ticks_usec()
		var res := prov.build_lods(c, origin)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		worst = maxf(worst, ms)
		var t := (res[0] as KitResult).triangle_count
		tris += t
		tris1 += (res[1] as KitResult).triangle_count
		var t2 := far.build_sub(c, origin).triangle_count
		tris2 += t2
		max_tris = maxi(max_tris, t)
		expect(t > 0, "%s cell %s has geometry" % [sid, c])
		expect(t2 <= t, "%s far LOD is lighter (%s)" % [sid, c])
	var n := maxi(cells.size(), 1)
	print("    %s: %d cells, worst build %.0f ms, lod0 tris avg %d max %d, lod1 avg %d, lod2 avg %d, +%d archetypes" % [sid, cells.size(), worst,
		tris / n, max_tris, tris1 / n, tris2 / n, KitCache.size() - cache0])
	expect(worst < budget_ms, "%s cell builds stay bounded (%.0f ms)" % [sid, worst])


func test_bss_cells_build() -> void:
	if not WorldData.has_world_data():
		return
	_cells_build(Settlements.BA_SING_SE, 6000.0)


func test_omashu_plan_counts() -> void:
	if not WorldData.has_world_data():
		return
	var t0 := Time.get_ticks_usec()
	var p := Settlements.plan(Settlements.OMASHU)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var counts := _counts(p)
	print("    omashu plan: %d pieces, %d anchors, %d cells, %.0f ms" % [p.pieces.size(), p.anchors.size(), p.cells().size(), ms])
	print("    ", counts)
	expect_eq(int(counts.get(&"omashu_bridge", 0)), 1, "the great bridge")
	expect(int(counts.get(&"omashu_chute", 0)) >= 30, "three mail chutes")
	expect_eq(int(counts.get(&"omashu_chute_hub", 0)), 1, "the chute station")
	expect_eq(int(counts.get(&"grand_stair", 0)), 9, "a stair on every ramp of every tier step")
	expect_eq(int(counts.get(&"great_gate", 0)), 2, "bridge + causeway gates")
	expect(int(counts.get(&"ring_wall", 0)) > 40, "tier walls")
	expect(p.pieces.size() > 400, "a full city")
	expect((p.data.get("claims", []) as Array).has(&"omashu_great_bridge"), "the generic bridge is claimed")


func test_ek_villages_plan_counts() -> void:
	if not WorldData.has_world_data():
		return
	var p := Settlements.plan(Settlements.EK_VILLAGES)
	var counts := _counts(p)
	print("    ek villages: %d pieces, %d anchors, %d cells, districts %s" % [p.pieces.size(), p.anchors.size(), p.cells().size(),
		p.districts.map(func(d: Dictionary) -> StringName: return d["id"])])
	print("    ", counts)
	expect(p.districts.size() >= 4, "every Earth Kingdom village")
	expect(int(counts.get(&"harbor_quay", 0)) >= 2, "harbour quays")
	expect(int(counts.get(&"ek_pier", 0)) >= 2, "piers")
	expect(int(counts.get(&"farmhouse", 0)) >= 6, "farmsteads")
	expect(int(counts.get(&"row_house", 0)) >= 60, "town houses")


func test_omashu_and_villages_cells_build() -> void:
	if not WorldData.has_world_data():
		return
	_cells_build(Settlements.OMASHU, 6000.0)
	_cells_build(Settlements.EK_VILLAGES, 6000.0)


func test_fn_capital_plan_counts() -> void:
	if not WorldData.has_world_data():
		return
	var t0 := Time.get_ticks_usec()
	var p := Settlements.plan(Settlements.FN_CAPITAL)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var counts := _counts(p)
	print("    fn capital plan: %d pieces, %d anchors, %d cells, %.0f ms" % [p.pieces.size(), p.anchors.size(), p.cells().size(), ms])
	print("    ", counts)
	expect(p.pieces.size() > 1500, "a great city")
	for k: StringName in [&"fn_podium", &"fn_throne_hall", &"fn_palace_gate", &"sun_monument", &"kata_grounds", &"gate_fort", &"fn_dojo", &"noble_interior"]:
		expect_eq(int(counts.get(k, 0)), 1, "one %s" % k)
	expect_eq(int(counts.get(&"fn_hall", 0)), 2, "the palace side halls")
	expect(int(counts.get(&"flame_pillar", 0)) >= 4, "the courtyard's flame pillars")
	expect_eq(int(counts.get(&"fn_stair", 0)), 14, "a stair on every ramp of every step + the palace stair + the gorge stair")
	expect(int(counts.get(&"fn_tier_wall", 0)) > 150, "basalt tier walls")
	expect(int(counts.get(&"fn_curtain", 0)) >= 6, "curtain walls up the gorge")
	expect(int(counts.get(&"fn_house", 0)) > 600, "a dense Lower City")
	expect(int(counts.get(&"noble_house", 0)) > 50, "noble compounds")
	expect(int(counts.get(&"fn_brazier", 0)) > 60, "braziers everywhere")
	expect(int(counts.get(&"fn_stall", 0)) > 60, "markets")
	expect(p.data.has("gorge_gate") and p.data.has("palace") and p.data.has("spawn"), "gate, palace and spawn recorded")
	expect(ms < 3000.0, "plan builds in a bounded time")


func test_fn_harbor_plan_counts() -> void:
	if not WorldData.has_world_data():
		return
	var p := Settlements.plan(Settlements.FN_HARBOR)
	var counts := _counts(p)
	print("    crimson harbor plan: %d pieces, %d anchors, %d cells" % [p.pieces.size(), p.anchors.size(), p.cells().size()])
	print("    ", counts)
	expect(int(counts.get(&"warship", 0)) >= 8, "the Fire Navy in port")
	expect(int(counts.get(&"fn_pier", 0)) >= 6, "piers")
	expect(int(counts.get(&"fn_quay", 0)) >= 40, "the basin quay and the moles")
	expect(int(counts.get(&"crane", 0)) >= 10, "dock cranes")
	expect(int(counts.get(&"fn_warehouse", 0)) >= 20, "warehouses")
	expect_eq(int(counts.get(&"gate_fort", 0)), 3, "a gatehouse on every gate")
	expect(int(counts.get(&"watchtower", 0)) >= 2, "watchtowers on the moles")
	expect((p.data.get("stairs", []) as Array).size() >= 11, "a stair on every ramp of every step (the twin gate-road ramps share one at the quay)")
	expect(int(counts.get(&"lantern_string", 0)) >= 40, "the Lantern Steps")
	expect(int(counts.get(&"fn_stall", 0)) >= 50, "the Harbor Market")
	expect((p.data.get("claims", []) as Array).has(&"fn_crimson_harbor"), "the generic dock is claimed")
	# the ferry landing and the ferry's berth stay clear of piers, ships and props
	var q: Vector3 = p.data.get("ferry_quay", Vector3.INF)
	var berth: Vector3 = p.data.get("ferry_berth", Vector3.INF)
	expect(q.is_finite() and berth.is_finite(), "the ferry landing is known")
	for pc in p.pieces:
		if pc["kind"] in [&"fn_quay"]:
			continue
		var pos: Vector3 = pc["pos"]
		var d := Geometry2D.get_closest_point_to_segment(Vector2(pos.x, pos.z), Vector2(q.x, q.z), Vector2(berth.x, berth.z)).distance_to(Vector2(pos.x, pos.z))
		if d - float(pc["r"]) < 6.0:
			fail("%s at %s crowds the ferry landing (%.1f m)" % [pc["kind"], pos, d])
			return


func test_fn_villages_plan_counts() -> void:
	if not WorldData.has_world_data():
		return
	var p := Settlements.plan(Settlements.FN_VILLAGES)
	var counts := _counts(p)
	print("    fn villages: %d pieces, %d anchors, %d cells, districts %s" % [p.pieces.size(), p.anchors.size(), p.cells().size(),
		p.districts.map(func(d: Dictionary) -> StringName: return d["id"])])
	print("    ", counts)
	for d: StringName in [&"fn_saltspark", &"fn_ashleaf", &"fn_sunflare_resort"]:
		expect(p.districts.any(func(x: Dictionary) -> bool: return x["id"] == d), "district %s" % d)
	expect(int(counts.get(&"salt_pans", 0)) >= 2, "Saltspark's salt pans")
	expect(int(counts.get(&"fisher_hut", 0)) >= 15, "fishers' huts")
	expect(int(counts.get(&"tea_rows", 0)) >= 20, "Ashleaf's tea terraces")
	expect(int(counts.get(&"tea_house_fn", 0)) >= 4, "tea farmers' houses")
	expect(int(counts.get(&"fn_villa", 0)) >= 20, "resort villas")
	expect(int(counts.get(&"hot_spring", 0)) >= 2, "hot springs")
	expect(int(counts.get(&"cabana", 0)) >= 4, "cabanas")


func test_fn_cells_build() -> void:
	if not WorldData.has_world_data():
		return
	_cells_build(Settlements.FN_CAPITAL, 6000.0)
	_cells_build(Settlements.FN_HARBOR, 6000.0)
	_cells_build(Settlements.FN_VILLAGES, 6000.0)


## Anchor contract over the Settlements II ids: the keys the NPC module reads, unique ids, kinds per
## settlement, interior anchors flagged.
func test_ef_anchors() -> void:
	if not WorldData.has_world_data():
		return
	var ids := {}
	for sid in EF:
		for a in Settlements.plan(sid).anchors:
			for k in ["id", "settlement", "kind", "position", "yaw", "district", "tags"]:
				if not expect(a.has(k), "%s anchor has %s" % [sid, k]):
					return
			expect(not ids.has(a["id"]), "anchor id %s unique" % a["id"])
			ids[a["id"]] = true
			expect((a["position"] as Vector3).is_finite(), "anchor position finite")
			if a["kind"] == &"patrol":
				expect((a["points"] as PackedVector3Array).size() >= 2, "patrol has a route")
	var need := {
		Settlements.BA_SING_SE: [&"home", &"market_stall", &"guard_post", &"patrol", &"trainer", &"quest_giver", &"idle"],
		Settlements.OMASHU: [&"home", &"market_stall", &"guard_post", &"patrol", &"quest_giver"],
		Settlements.EK_VILLAGES: [&"home", &"quest_giver", &"fisher"],
		Settlements.FN_CAPITAL: [&"home", &"market_stall", &"guard_post", &"patrol", &"trainer", &"student", &"quest_giver", &"gardener"],
		Settlements.FN_HARBOR: [&"home", &"market_stall", &"guard_post", &"patrol", &"worker", &"quest_giver", &"fisher"],
		Settlements.FN_VILLAGES: [&"home", &"quest_giver", &"worker", &"idle"],
	}
	for sid: StringName in need:
		var kinds := {}
		for a in Settlements.get_anchors(sid):
			kinds[a["kind"]] = true
		for k: StringName in need[sid]:
			expect(kinds.has(k), "%s anchors include %s" % [sid, k])
	var inside := 0
	for sid: StringName in [Settlements.BA_SING_SE, Settlements.FN_CAPITAL]:
		for a in Settlements.get_anchors(sid):
			if a.get("interior", false):
				inside += 1
	expect(inside >= 8, "interior anchors (%d)" % inside)
	var dojo := Settlements.get_anchors(Settlements.FN_CAPITAL, &"trainer").filter(func(a: Dictionary) -> bool: return a.get("building") == &"fn_dojo")
	expect(dojo.size() == 1, "the dojo master")


func test_ef_lookups() -> void:
	if not WorldData.has_world_data():
		return
	var bss: Dictionary = Settlements.plan(Settlements.BA_SING_SE).data["palace"]
	expect_eq(Settlements.settlement_at(bss["center"]), Settlements.BA_SING_SE, "the Earth King's palace is in Ba Sing Se")
	var fnp: Dictionary = Settlements.plan(Settlements.FN_CAPITAL).data["palace"]
	expect_eq(Settlements.settlement_at(fnp["center"]), Settlements.FN_CAPITAL, "the Fire Lord's palace is in the capital")
	expect_eq(Settlements.district_at(fnp["center"]), &"fnc_palace", "palace district")
	expect_eq(Settlements.district_at(WorldData.get_poi(&"fn_plaza_of_the_sun")["position"]), &"fnc_plaza_of_the_sun", "Plaza of the Sun district")
	expect_eq(Settlements.district_at(WorldData.get_poi(&"fn_flame_kata_grounds")["position"]), &"fnc_kata_grounds", "kata grounds district")
	var gg: Dictionary = Settlements.plan(Settlements.FN_CAPITAL).data["gorge_gate"]
	expect_eq(Settlements.district_at(gg["position"]), &"fnc_gorge_gate", "the Dragon's Throat gate district")
	var q: Vector3 = Settlements.plan(Settlements.FN_HARBOR).data["ferry_quay"]
	expect_eq(Settlements.settlement_at(q), Settlements.FN_HARBOR, "the ferry landing is in Crimson Harbor")
	expect_eq(Settlements.settlement_at(WorldData.get_city(&"omashu")["center"]), Settlements.OMASHU, "Omashu centre")
	for v: Array in [[&"saltspark", &"fn_saltspark"], [&"ashleaf", &"fn_ashleaf"], [&"sunflare_resort", &"fn_sunflare_court"]]:
		var c: Vector3 = WorldData.get_city(v[0])["center"]
		expect_eq(Settlements.settlement_at(c), Settlements.FN_VILLAGES, "%s is a Fire Nation village" % v[0])
		expect_eq(Settlements.district_at(c), v[1], "%s district" % v[0])


## Registration: Omashu's bridge and Crimson Harbor's dock are claimed from worldcontent; the
## tutorial's skip tag leaves the Flame Kata Grounds out of their cell.
func test_ef_register_claims_and_kata_tag() -> void:
	if not WorldData.has_world_data():
		return
	var content := WorldContent.new()
	content.use_default_providers = false
	add_child(content)
	var provs := Settlements.register(content, {"only": EF, "skip_tags": [&"flame_kata_grounds"]})
	expect_eq(provs.size(), EF.size() * 2, "near + far provider per Settlements II id")
	for c: StringName in [&"omashu_great_bridge", &"fn_crimson_harbor"]:
		expect(ContentClaims.is_claimed(c), "%s claimed" % c)
	var near: SettlementProvider = content.get_provider(&"settlement_fire_nation_capital")
	expect(near != null and near.skip_tags.has(&"flame_kata_grounds"), "skip tags reach the capital")
	var kata: Vector3 = WorldData.get_poi(&"fn_flame_kata_grounds")["position"]
	var p := near.plan
	var coord := p.coord_of(kata.x, kata.z)
	var origin := Vector3((coord.x + 0.5) * p.cell_size, 0, (coord.y + 0.5) * p.cell_size)
	near.cfg = SettlementSettings.current()
	var with_skip: int = (near.build_lods(coord, origin)[0] as KitResult).triangle_count
	near.skip_tags = []
	var full: int = (near.build_lods(coord, origin)[0] as KitResult).triangle_count
	expect(with_skip < full, "kata grounds left out for the tutorial (%d < %d tris)" % [with_skip, full])
	var tagged := p.pieces.filter(func(pc: Dictionary) -> bool: return (pc["spec"] as Dictionary).get("tag") == &"flame_kata_grounds")
	expect_eq(tagged.size(), 1, "the kata grounds piece is tagged")
	Settlements.unregister(content)
	content.queue_free()
	for c: StringName in [&"omashu_great_bridge", &"fn_crimson_harbor"]:
		ContentClaims.release(c)


## The earth and fire arrival flights pass over Ba Sing Se's palace and the Fire Lord's palace: a
## 1.2 m sphere swept along each camera path (1 m steps) touches nothing of the city's collision.
func test_arrival_flights_are_clear() -> void:
	if not WorldData.has_world_data():
		return
	for e: Array in [[ElementDefs.Element.EARTH, Settlements.BA_SING_SE], [ElementDefs.Element.FIRE, Settlements.FN_CAPITAL]]:
		var cam := ArrivalClearance.for_element(int(e[0]))
		var p := Settlements.plan(e[1])
		var pts := PackedVector3Array()
		for q in cam.path:
			if Vector2(q.x - p.center.x, q.z - p.center.z).length() < p.radius:
				pts.append(q)
		if not expect(pts.size() > 10, "%s: the flight crosses the city" % e[1]):
			continue
		_walk_world(e[1], _path_rect([pts]))
		await physics_frames(3)
		var space := _walk_root.get_world_3d().direct_space_state
		var sq := PhysicsShapeQueryParameters3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 1.2
		sq.shape = sphere
		sq.collision_mask = Layers.WORLD
		var checked := 0
		var clear := true
		for i in pts.size() - 1:
			var n := maxi(int(ceil(pts[i].distance_to(pts[i + 1]))), 1)
			for k in n:
				sq.transform = Transform3D(Basis(), pts[i].lerp(pts[i + 1], float(k) / n))
				checked += 1
				if clear and not space.intersect_shape(sq, 1).is_empty():
					fail("%s: the arrival camera touches the city at %s" % [e[1], sq.transform.origin])
					clear = false
		expect(checked > 100, "%s: the flight was swept (%d points)" % [e[1], checked])
		after_each()


# --- walkability ---------------------------------------------------------------------------------

func _walks(sid: StringName, paths: Dictionary) -> void:
	_walk_world(sid, _path_rect(paths.values()))
	await physics_frames(3)
	for k: String in paths:
		var err := _walk(paths[k], k)
		expect(err == "", err)


func _stair_paths(p: SettlementPlan, out: Dictionary, prefix: String, before: float = 6.0, after: float = 4.0) -> void:
	for s: Dictionary in p.data.get("stairs", []):
		var foot: Vector3 = s["foot"]
		var top: Vector3 = s["top"]
		var dir := Vector3(top.x - foot.x, 0, top.z - foot.z).normalized()
		out["%s_stair_%d_%d" % [prefix, int(foot.x), int(foot.z)]] = PackedVector3Array([foot - dir * before, foot, top, top + dir * after])


func _interior_paths(p: SettlementPlan, out: Dictionary, stops: Dictionary) -> void:
	for it: Dictionary in p.data.get("interiors", []):
		var pts := PackedVector3Array()
		for s: Vector3 in stops[it["kind"]]:
			pts.append(SettlementLayout.world(it["position"], float(it["yaw"]), s))
		out["interior_%s" % it["kind"]] = pts


## The earth and fire spawns stand on open floor: 10 m ahead, 8 m to either side and back.
func test_ef_spawns_are_clear() -> void:
	if not WorldData.has_world_data():
		return
	for e: Array in [[ElementDefs.Element.EARTH, Settlements.BA_SING_SE], [ElementDefs.Element.FIRE, Settlements.FN_CAPITAL]]:
		var sp := WorldData.get_spawn(int(e[0]))
		var sid: StringName = e[1]
		if not expect_eq(Settlements.settlement_at(sp.origin), sid, "%s spawn is in %s" % [e[0], sid]):
			continue
		_walk_world(sid, Rect2(sp.origin.x - 24.0, sp.origin.z - 24.0, 48.0, 48.0))
		await physics_frames(3)
		var f := -sp.basis.z
		f = Vector3(f.x, 0, f.z).normalized()
		var side := Vector3(-f.z, 0, f.x)
		for d: Array in [[f, 10.0, "ahead"], [side, 8.0, "right"], [-side, 8.0, "left"], [-f, 8.0, "back"]]:
			var err := _walk(PackedVector3Array([sp.origin, sp.origin + (d[0] as Vector3) * float(d[1])]), "%s spawn %s" % [sid, d[2]])
			expect(err == "", err)
		after_each()


func test_bss_walk_walls_gates_stairs() -> void:
	if not WorldData.has_world_data():
		return
	var p := Settlements.plan(Settlements.BA_SING_SE)
	var paths := {}
	# up the stairs onto the wall tops at the south gates (the arrival side)
	for s: Dictionary in p.data.get("wall_stairs", []):
		var b := float(s["bearing"])
		if absf(RingLayout.bdiff(b, 252.0)) > 40.0:
			continue
		paths["wall_stair_%s_%d" % [s["wall"], int(b)]] = s["path"]
	# through the gates (outside -> gate -> inside)
	for g: Dictionary in p.data.get("gates", []):
		if absf(RingLayout.bdiff(float(g["bearing"]), 252.0)) > 60.0:
			continue
		paths["gate_%s_%s" % [g["wall"], g["id"]]] = PackedVector3Array([g["outside"], g["position"], g["inside"]])
	expect(paths.size() >= 2, "wall stairs and gates to walk")
	await _walks(Settlements.BA_SING_SE, paths)


func test_bss_walk_grand_stairs_and_interiors() -> void:
	if not WorldData.has_world_data():
		return
	var p := Settlements.plan(Settlements.BA_SING_SE)
	var paths := {}
	_stair_paths(p, paths, "bss")
	expect(paths.size() >= 5, "the Upper Ring stairs")
	var hd_t := EkPlaces.TEA_D * 0.5
	var hd_h := EkPlaces.HALL_D * 0.5
	_interior_paths(p, paths, {&"tea_shop": [Vector3(0, 0, -hd_t - 4.0), Vector3(0, 0, -hd_t - 1.6), Vector3(0, 0, -hd_t + 1.4)],
		&"training_hall": [Vector3(0, 0, -hd_h - 5.0), Vector3(0, 0, -hd_h - 2.4), Vector3(0, 0, 2.0)]})
	await _walks(Settlements.BA_SING_SE, paths)


func test_omashu_walk_bridge_and_stairs() -> void:
	if not WorldData.has_world_data():
		return
	var p := Settlements.plan(Settlements.OMASHU)
	var paths := {}
	var br: Dictionary = p.data["bridge"]
	var city: Vector3 = br["city"]
	var rim: Vector3 = br["rim"]
	var dir := Vector3(rim.x - city.x, 0, rim.z - city.z).normalized()
	# from inside the bridge gate, through the gatehouse, over the chasm to the far rim
	var bridge_gate: Dictionary = {}
	for g: Dictionary in p.data.get("gates", []):
		if bridge_gate.is_empty() or Vector2(g["position"].x - city.x, g["position"].z - city.z).length() \
				< Vector2(bridge_gate["position"].x - city.x, bridge_gate["position"].z - city.z).length():
			bridge_gate = g
	paths["great_bridge"] = PackedVector3Array([bridge_gate["inside"], bridge_gate["position"], city.lerp(rim, 0.5), rim - dir * 1.13])
	_stair_paths(p, paths, "omashu")
	await _walks(Settlements.OMASHU, paths)


func test_fn_capital_walk_stairs_gorge_interiors() -> void:
	if not WorldData.has_world_data():
		return
	var p := Settlements.plan(Settlements.FN_CAPITAL)
	var paths := {}
	_stair_paths(p, paths, "fnc", 6.0, 3.0)
	var gg: Dictionary = p.data["gorge_gate"]
	var st_top: Vector3 = gg["stair_top"]
	var st_foot: Vector3 = gg["stair_foot"]
	var sdir := Vector3(st_foot.x - st_top.x, 0, st_foot.z - st_top.z).normalized()
	# down the gorge stair and out through the Dragon's Throat gatehouse
	paths["gorge"] = PackedVector3Array([st_top - sdir * 4.0, st_top, st_foot, gg["inside"], gg["position"], gg["outside"]])
	var hd_d := FnPlaces.DOJO_D * 0.5
	var hd_n := FnPlaces.NOBLE_D * 0.5
	_interior_paths(p, paths, {&"fn_dojo": [Vector3(0, 0, -hd_d - 6.0), Vector3(0, 0, -hd_d - 2.8), Vector3(0, 0, -hd_d + 2.0), Vector3(0, 0, 1.0)],
		&"noble_interior": [Vector3(0, 0, -hd_n - 6.0), Vector3(0, 0, -hd_n - 3.4), Vector3(0, 0, -hd_n + 1.2), Vector3(0, 0, -1.5)]})
	# the palace axis: up the grand stair, through the gate pavilion, into the courtyard
	var pal: Dictionary = p.data["palace"]
	var court: Vector3 = pal["courtyard"]
	var foot180: Vector3 = Vector3.INF
	for s: Dictionary in p.data["stairs"]:
		if absf(float(s["bearing"]) - 180.0) < 0.1:
			foot180 = s["foot"]
	if expect(foot180.is_finite(), "the palace stair"):
		paths["palace_axis"] = PackedVector3Array([foot180 + Vector3(0, 0, 6.0), foot180, court])
	await _walks(Settlements.FN_CAPITAL, paths)


func test_fn_harbor_walk_stairs_piers_gates() -> void:
	if not WorldData.has_world_data():
		return
	var p := Settlements.plan(Settlements.FN_HARBOR)
	var paths := {}
	_stair_paths(p, paths, "fh")
	for pc in p.pieces_of(&"fn_pier").slice(0, 3):
		var pos: Vector3 = pc["pos"]
		var fwd := Basis(Vector3.UP, float(pc["yaw"])) * Vector3.FORWARD
		# (5.13 m back so no sample lands exactly on the quay / pier seam)
		paths["pier_%d_%d" % [int(pos.x), int(pos.z)]] = PackedVector3Array([pos - fwd * 5.13, pos + fwd * (float(pc["spec"]["L"]) - 1.5)])
	for g: Dictionary in p.data.get("gates", []):
		paths["gate_%s" % g["id"]] = PackedVector3Array([g["inside"], g["position"], g["outside"]])
	expect(paths.size() >= 12, "stairs, piers and gates to walk")
	await _walks(Settlements.FN_HARBOR, paths)


# --- probe-capsule walk helpers (as in test_settlements_wa.gd) ------------------------------------

var _walk_root: Node3D = null
var _walk_cells: Dictionary = {}


func after_each() -> void:
	if _walk_root:
		_walk_root.queue_free()
		_walk_root = null
	_walk_cells.clear()


## Terrain heightfield collision over `rect` (world x/z) + the settlement collision of every cell
## of `sid` overlapping it.
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


## Marches a capsule (r 0.33, 1.6 m) along the waypoints in 0.25 m steps: floor under every step,
## at most 0.42 m up / 1.2 m down per step, no steeper than 46 degrees, nothing in the way of the
## capsule raised 0.42 m. Returns "" or the failure.
func _walk(points: PackedVector3Array, label: String) -> String:
	var space := _walk_root.get_world_3d().direct_space_state
	var cap := CapsuleShape3D.new()
	cap.radius = 0.33
	cap.height = 1.6
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.collision_mask = Layers.WORLD
	var y := points[0].y
	# start on whatever floor is under the first waypoint (paving over the terrain, a deck)
	var h0 := space.intersect_ray(PhysicsRayQueryParameters3D.create(points[0] + Vector3(0, 2.0, 0), points[0] - Vector3(0, 3.0, 0), Layers.WORLD))
	if not h0.is_empty():
		y = (h0["position"] as Vector3).y
	var walked := 0.0
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var n := maxi(int(ceil(Vector2(b.x - a.x, b.z - a.z).length() / 0.25)), 1)
		for k in range(1, n + 1):
			var p := a.lerp(b, float(k) / n)
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(p.x, y + 1.6, p.z), Vector3(p.x, y - 3.0, p.z), Layers.WORLD))
			if hit.is_empty():
				return "%s: no floor at %s after %.0f m" % [label, p, walked]
			if (hit["normal"] as Vector3).y < cos(deg_to_rad(46.0)):
				# a ray exactly on the edge of a deck or step reports its side face: probe 6 cm either side
				var along := Vector3(b.x - a.x, 0, b.z - a.z).normalized() * 0.06
				for o: Vector3 in [along, -along]:
					var h2 := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(p.x, y + 1.6, p.z) + o, Vector3(p.x, y - 3.0, p.z) + o, Layers.WORLD))
					if not h2.is_empty() and (h2["normal"] as Vector3).y >= cos(deg_to_rad(46.0)):
						hit = h2
						break
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
					var st := ""
					if co is CollisionObject3D:
						var owner_id := (co as CollisionObject3D).shape_find_owner(int(t["shape"]))
						var cs := (co as CollisionObject3D).shape_owner_get_owner(owner_id) as CollisionShape3D
						if cs:
							st = "%s@%s" % [cs.shape.get_class(), (co as Node3D).global_transform * cs.position]
					what.append("%s %s" % [(co as Node).name if co is Node else str(co), st])
				return "%s: blocked at %s after %.0f m by %s" % [label, Vector3(p.x, y, p.z), walked, what]
			walked += 0.25
	return ""


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
