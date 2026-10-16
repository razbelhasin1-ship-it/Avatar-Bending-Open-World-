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
