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
