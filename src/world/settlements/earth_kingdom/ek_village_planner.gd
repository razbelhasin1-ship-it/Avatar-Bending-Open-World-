class_name EkVillagePlanner
extends EkRingPlanner
## The Earth Kingdom villages from the WorldData village records (deterministic, main thread),
## one district each:
##   port towns (Full Moon Bay, Northreach): a market square, house rings on the harbour pad,
##     the retaining wall of the upper terrace with stairs, houses and warehouses up there, the
##     harbour on the sea side of the terrace (quay platforms with stairs, piers, sampans, boat
##     houses, fish racks, a lighthouse); the ferry landing (worldscene FerryDock) is kept clear
##   farming village (Millet Hollow): farmsteads around the green, granaries, haystacks, a windmill
##   forest village (Cedar Rest): timber houses round a shrine, a sawmill and lumber piles, cedars

const ID := &"ek_villages"

var village: Dictionary = {}
var vid := ""


func build() -> SettlementPlan:
	plan = SettlementPlan.new(ID, &"earth_kingdom")
	plan.display_name = "Earth Kingdom villages"
	plan.cell_size = 128.0
	plan.y_range = Vector2(0.0, 30.0)
	if not WorldData.has_world_data():
		return plan
	cam = ArrivalClearance.new()
	plan.data["claims"] = []
	for v in WorldData.get_villages():
		if StringName(v.get("region", &"")) != &"earth_kingdom":
			continue
		village = v
		vid = String(v["id"])
		rng = ContentHash.rng(ContentHash.hash_name("ek_village_%s" % vid))
		_band_rng = rng
		var c: Vector3 = v["center"]
		L = RingLayout.new()
		L.id = StringName(vid)
		L.center = Vector2(c.x, c.z)
		avenues.clear()
		var reach := float(v.get("radius", 80.0)) + (80.0 if v.has("terraces") else 10.0)
		plan.add_district(StringName("ek_%s" % vid), String(v.get("name", vid)), Vector3(c.x, float(v.get("pad_height", c.y)), c.z), reach)
		# open-world trees / rocks / props stay out of the built-up area (the forest village keeps
		# its own cedars, planted by the planner)
		var keep := reach - 4.0 if v.has("terraces") else float(v.get("radius", 80.0)) + 2.0
		plan.data.get_or_add("exclusions", []).append([Vector3(c.x, 0.0, c.z), keep,
			ContentExclusions.TAG_TREES | ContentExclusions.TAG_ROCKS | ContentExclusions.TAG_PROPS])
		match StringName(v.get("kind", &"")):
			&"port_town": _port_town()
			&"farming_village": _farm_village()
			&"forest_village": _forest_village()
	return plan


func pad_y() -> float:
	return float(village.get("pad_height", (village["center"] as Vector3).y))


## Square + lanes: a plaza at the centre and four radial lanes to the edge (kept free).
func _square(r: float, v: int) -> void:
	var c := Vector3(L.center.x, pad_y(), L.center.y)
	plan.add(&"plaza", c, 0.0, {"r": r, "v": v}, 1, "ek_plaza:%d:%d" % [int(r), v], r)
	plan.reserve(c.x, c.z, r + 1.0)
	plan.anchor(&"quest_giver", c + Vector3(r * 0.6, 0, r * 0.3), PI, {"tags": [vid, "elder"]})
	plan.anchor(&"child_play", c + Vector3(-r * 0.5, 0, -r * 0.4), 0.0, {"tags": [vid, "square"]})
	for k in 2:
		plan.anchor(&"idle", c + Vector3(cos(k * 2.4) * r * 0.7, 0, sin(k * 2.4) * r * 0.7), k * 2.4, {"tags": [vid, "square"]})


func _lanes(bearings: Array, r1: float, half: float) -> void:
	for b: float in bearings:
		avenues.append(wrapf(b, -180.0, 180.0))
		plan.reserve_line(L.xz(4.0, b), L.xz(r1, b), half)


func _inside_pad(r_max: float, y: float) -> Callable:
	return func(w: Vector3) -> bool:
		return L.polar(w.x, w.z).x < r_max and absf(ground(w.x, w.z) - y) < 0.9


func _lamps(r: float, y: float, step_m: float, light_every: int = 3) -> void:
	var step := RingLayout.half_angle(2.0 * step_m, r)
	var b := 3.0
	var k := 0
	while b < 363.0:
		var p := p3(r, b, y)
		if plan.is_free(p.x, p.z, 0.7):
			plan.reserve(p.x, p.z, 0.7)
			plan.add(&"lamp_post", p, yaw_in(b), {"v": 0, "light": k % light_every == 0}, 1, "ek_lamp:0:%d" % int(k % light_every == 0), 0.7)
		b += step
		k += 1


# --- port towns ---------------------------------------------------------------------------------

func _port_town() -> void:
	var terr: Array = village.get("terraces", [])
	var r0 := float(terr[0]["radius"]) if terr.size() > 0 else float(village.get("radius", 120.0))
	var y0 := pad_y()
	var r1 := float(terr[1]["radius"]) if terr.size() > 1 else r0
	var y1 := float(terr[1]["height"]) if terr.size() > 1 else y0
	# the ferry landing (FerryDock at the port quay) and its approach stay clear
	var quay := Vector3.INF
	for port in WorldData.get_ports():
		if StringName(port.get("settlement", &"")) == StringName(vid):
			quay = port["quay"]
			plan.reserve(quay.x, quay.z, 12.0)
			plan.data["ferry_quay_%s" % vid] = quay
			plan.anchor(&"quest_giver", quay + Vector3(3.0, 0, 3.0), 0.0, {"tags": [vid, "harbor_master", "ferry"]})
	for poi in WorldData.get_pois():
		if poi["type"] == &"dock" and Vector2((poi["position"] as Vector3).x - L.center.x, (poi["position"] as Vector3).z - L.center.y).length() < r1 + 40.0:
			plan.data["claims"].append(StringName(poi["id"]))
	var qb := L.polar(quay.x, quay.z).y if quay.is_finite() else 0.0
	# stair bearings up the terrace step (four, avoiding the ferry landing)
	var stair_b: Array = []
	for k in 4:
		var b := wrapf(45.0 + 90.0 * k, -180.0, 180.0)
		if quay.is_finite() and absf(RingLayout.bdiff(b, qb)) < 14.0:
			b = qb + 12.0 * signf(RingLayout.bdiff(b, qb) + 0.01)
		stair_b.append(b)
	_square(14.0, 0)
	_lanes(stair_b, r1, 4.0)
	var inner := _inside_pad(r0 - 3.0, y0)
	# market stalls around the square
	for k in 10:
		var b := 18.0 + k * 36.0
		var p := p3(19.0, b, y0)
		if plan.is_free(p.x, p.z, 1.6):
			plan.reserve(p.x, p.z, 1.6)
			plan.add(&"stall", p, yaw_in(b), {"v": k % 6}, 1, "ek_stall:%d" % (k % 6), 1.6)
			plan.anchor(&"market_stall", SettlementLayout.world(p, yaw_in(b), Vector3(0, 0, 0.8)), yaw_in(b), {"tags": [vid, "market"], "goods": ["fish", "pottery", "cloth", "tea", "rope", "tools"][k % 6]})
	# houses on the pad: rings of back-to-back rows
	var r := 26.0
	while r + 12.0 < r0 - 4.0:
		band(&"", y0, r, 11.0, true, {&"row_house": 6, &"town_house": 2, &"tenement": 1}, EkStyle.LOWER, 0.0, 360.0, inner)
		if r + 36.0 < r0 - 2.0:
			band(&"", y0, r + 24.0, 11.0, false, {&"row_house": 6, &"town_house": 2}, EkStyle.LOWER, 0.0, 360.0, inner)
		r += 34.0
	_lamps(r0 - 6.0, y0, 22.0)
	# the terrace step: inward-facing retaining wall + stairs up
	if y1 - y0 > 1.5:
		var gaps := []
		for b: float in stair_b:
			gaps.append([b, 3.6])
		var faces := step_wall(ring_spans(r0, gaps), y0, y1, r0 + 14.0, r0 - 14.0, r0, 11.0, 1.1, &"balustrade", 2)
		plan.data["%s_faces" % vid] = faces
		for b: float in stair_b:
			var rf := SettlementLayout.face_r(L, b, r0 + 14.0, r0 - 14.0, y0 + 0.35) - 0.6
			var run := (y1 - y0) / 0.56
			var foot := p3(rf - run, b, y0)
			plan.add(&"grand_stair", foot, yaw_out(b), {"H": y1 - y0, "R": run, "W": 7.0, "half": run, "tone": 2}, 2, "", run * 0.5 + 4.0)
			plan.reserve_line(L.xz(rf - run - 2.0, b), L.xz(rf + 4.0, b), 4.0)
			plan.data.get_or_add("stairs", []).append({"village": vid, "bearing": b, "foot": foot, "top": p3(rf + 2.0, b, y1)})
		# the upper terrace: houses facing the town, warehouses / homes on the outer street
		var upper := func(w: Vector3) -> bool:
			var pr := L.polar(w.x, w.z)
			return pr.x > r0 + 4.0 and pr.x < r1 - 6.0 and absf(ground(w.x, w.z) - y1) < 0.9
		band(&"", y1, r0 + 12.0, 12.0, true, {&"row_house": 5, &"town_house": 3}, EkStyle.LOWER, 0.0, 360.0, upper)
		band(&"", y1, r0 + 46.0, 13.0, false, {&"row_house": 4, &"town_house": 2, &"tenement": 1}, EkStyle.LOWER, 0.0, 360.0, upper)
		_lamps(r0 + 7.0, y1, 26.0)
	_harbor(r1, y1)


## Harbour on the sea side of the town: quay platforms under the terrace edge where the sea comes
## up to it, with piers, sampans, boat houses, fish racks and a lighthouse.
func _harbor(r1: float, y_top: float) -> void:
	var sea: Array = []
	var b := 0.0
	while b < 360.0:
		var probe := L.xz(r1 + 14.0, b)
		var edge_r := SettlementLayout.face_r(L, b, r1 - 30.0, r1 + 30.0, y_top - 1.5)
		var out := L.xz(edge_r + 10.0, b)
		if ground(probe.x, probe.y) < -0.5 and ground(out.x, out.y) < 0.5:
			sea.append([b, edge_r])
		b += 3.0
	if sea.is_empty():
		return
	var k := 0
	var last_b := -999.0
	var lighthouse := false
	for s: Array in sea:
		var sb := float(s[0])
		if absf(RingLayout.bdiff(sb, last_b)) < RingLayout.half_angle(2.0 * 40.0, r1) * 2.0:
			continue
		var er := float(s[1])
		var top := p3(er - 1.0, sb, y_top)
		var water := 0.0
		var floor_y := ground(L.xz(er + 14.0, sb).x, L.xz(er + 14.0, sb).y)
		var yaw := yaw_out(sb)
		var H := y_top - water
		plan.add(&"harbor_quay", top, yaw, {"L": 34.0, "D": 10.0, "H": snappedf(H, 0.5), "bottom": snappedf(minf(floor_y, -2.0) - y_top - 2.0, 0.5)}, 2, "", 18.0)
		plan.reserve(top.x, top.z, 18.0)
		last_b = sb
		var deck := Vector3(top.x, water + 2.0, top.z)
		var fwd := Vector3(RingLayout.dir(sb).x, 0, RingLayout.dir(sb).y)
		var side := Vector3(-fwd.z, 0, fwd.x)
		var pier_at := deck + fwd * 10.0 - side * 6.0
		var dep := maxf(2.0 - ground(pier_at.x + fwd.x * 12.0, pier_at.z + fwd.z * 12.0), 4.0)
		plan.add(&"ek_pier", pier_at, yaw, {"L": 22.0, "W": 3.2, "depth": snappedf(dep, 0.5), "head": 8.0 if k % 2 == 0 else 0.0}, 1, "", 12.0)
		plan.anchor(&"fisher", pier_at + fwd * 20.0, yaw, {"tags": [vid, "pier"]})
		for sx: float in [-1.0, 1.0]:
			var bp := pier_at + fwd * (9.0 + sx * 4.0) + side * sx * 3.6
			bp.y = 0.0
			plan.add(&"sampan", bp, yaw + PI * 0.5 * (1.0 if sx > 0.0 else 0.0), {"v": 0}, 1, "ek_sampan", 4.0)
			plan.anchor(&"boat", bp, yaw, {"tags": [vid, "harbor"]})
		var bh := deck + fwd * 8.0 + side * 10.0
		bh.y = 0.0
		plan.add(&"boathouse", bh + Vector3(0, 2.0, 0), yaw + PI, {"v": k % 3}, 1, "ek_boathouse:%d" % (k % 3), 6.0)
		plan.add(&"fish_rack", deck - side * 13.0 + fwd * 4.0, yaw + PI * 0.5, {"v": k % 2}, 1, "ek_fish_rack:%d" % (k % 2), 2.5)
		plan.anchor(&"worker", deck + fwd * 5.0, yaw + PI, {"tags": [vid, "harbor", "dock_worker"]})
		if not lighthouse:
			var lp := p3(er - 8.0, sb + RingLayout.half_angle(2.0 * 28.0, er), y_top)
			if plan.is_free(lp.x, lp.z, 4.0):
				plan.reserve(lp.x, lp.z, 4.0)
				plan.add(&"lighthouse", lp, yaw, {"h": 14.0}, 2, "ek_lighthouse:14", 4.0)
				plan.anchor(&"guard_post", lp + Vector3(0, 15.2, 0), yaw, {"tags": [vid, "lighthouse"]})
				lighthouse = true
		# warehouses behind the quay
		var wp := p3(er - 16.0, sb - RingLayout.half_angle(2.0 * 14.0, er), y_top)
		if SettlementLayout.fits(plan, wp, yaw + PI, Vector2(17.0, 9.0)):
			SettlementLayout.reserve_rect(plan, wp, yaw + PI, Vector2(17.0, 9.0))
			plan.add(&"warehouse", wp, yaw + PI, {"v": k % 2}, 2, "ek_warehouse:%d" % (k % 2), 9.0)
			plan.anchor(&"worker", SettlementLayout.world(wp, yaw + PI, Vector3(3.0, 0, -6.0)), yaw, {"tags": [vid, "warehouse"]})
		k += 1
		if k >= 4:
			break


# --- farming + forest villages ------------------------------------------------------------------

func _farm_village() -> void:
	var y := pad_y()
	var R := float(village.get("radius", 90.0))
	_square(10.0, 2)
	_lanes([0.0, 90.0, 180.0, 270.0], R, 3.0)
	var inside := _inside_pad(R - 4.0, y)
	# farmsteads in two rings facing the green
	for rr: float in [26.0, 56.0]:
		var n := 6 if rr < 40.0 else 9
		for k in n:
			var b := (k + 0.5) * 360.0 / n + rng.randf_range(-6.0, 6.0)
			var v := rng.randi() % 6
			var fp := EkHomes.footprint(&"farmhouse", v)
			var pos := p3(rr + fp.y * 0.5, b, y)
			var yaw := yaw_in(b)
			if SettlementLayout.fits(plan, pos, yaw, fp, inside):
				SettlementLayout.reserve_rect(plan, pos, yaw, fp)
				plan.add(&"farmhouse", pos, yaw, {"v": v, "style": EkStyle.FARM}, 2, "ek_farmhouse:%d" % v, maxf(fp.x, fp.y) * 0.5)
				plan.anchor(&"home", SettlementLayout.world(pos, yaw, Vector3(0, 0, -fp.y * 0.5 - 1.0)), yaw + PI, {"tags": [vid, "farm"],
					"building": &"farmhouse", "capacity": 4})
				plan.anchor(&"worker", SettlementLayout.world(pos, yaw, Vector3(fp.x * 0.3, 0, fp.y * 0.5 + 4.0)), yaw, {"tags": [vid, "farmer"]})
	# granaries, haystacks, a windmill, a shrine
	for k in 4:
		var b := 45.0 + k * 90.0
		var gp := p3(R - 12.0, b, y)
		if plan.is_free(gp.x, gp.z, 3.5):
			plan.reserve(gp.x, gp.z, 3.5)
			plan.add(&"granary" if k % 2 == 0 else &"haystack", gp, yaw_in(b), {"v": k % 3}, 2 if k % 2 == 0 else 1,
					("ek_granary:%d" if k % 2 == 0 else "ek_haystack:%d") % (k % 2), 3.0)
	var wm := p3(R - 6.0, 300.0, y)
	if plan.is_free(wm.x, wm.z, 5.0):
		plan.reserve(wm.x, wm.z, 5.0)
		plan.add(&"windmill", wm, deg_to_rad(90.0), {"v": 1}, 2, "ek_windmill:1", 4.0)
	var sh := p3(15.0, 135.0, y)
	if plan.is_free(sh.x, sh.z, 3.0):
		plan.reserve(sh.x, sh.z, 3.0)
		plan.add(&"shrine", sh, yaw_in(135.0), {"v": 0}, 1, "ek_shrine", 2.5)
	plan.add(&"well", p3(14.0, 315.0, y), 0.0, {"v": 0}, 1, "ek_well", 1.2)
	_lamps(18.0, y, 16.0, 2)
	_gardens(R, y, 18, 0.9)


## Vegetable plots and fruit trees in the free spots of a village pad (covers the paving).
func _gardens(R: float, y: float, count: int, tree_share: float) -> void:
	var trees: Array = []
	var placed := 0
	var tries := 0
	while placed < count and tries < count * 12:
		tries += 1
		var b := rng.randf() * 360.0
		var r := rng.randf_range(18.0, R - 8.0)
		var p := p3(r, b, y)
		var fp := Vector2(rng.randf_range(8.0, 14.0), rng.randf_range(6.0, 10.0))
		var yaw := yaw_in(b) + rng.randf_range(-0.3, 0.3)
		if not SettlementLayout.fits(plan, p, yaw, fp + Vector2(1, 1), _inside_pad(R - 2.0, y)):
			continue
		SettlementLayout.reserve_rect(plan, p, yaw, fp + Vector2(1, 1))
		plan.add(&"veg_plot", p, yaw, {"w": snappedf(fp.x, 1.0), "d": snappedf(fp.y, 1.0), "v": placed % 3}, 1,
				"ek_veg_plot:%d:%d:%d" % [int(snappedf(fp.x, 1.0)), int(snappedf(fp.y, 1.0)), placed % 3], maxf(fp.x, fp.y) * 0.5)
		plan.anchor(&"gardener", SettlementLayout.world(p, yaw, Vector3(0, 0, -fp.y * 0.5 - 0.8)), yaw, {"tags": [vid, "garden"]})
		if rng.randf() < tree_share:
			var tp := SettlementLayout.world(p, yaw, Vector3(fp.x * 0.5 + 2.5, 0, 0))
			if plan.is_free(tp.x, tp.z, 2.0):
				plan.reserve(tp.x, tp.z, 2.0)
				trees.append([&"maple" if placed % 3 == 0 else &"oak", tp, rng.randf_range(0.7, 0.95)])
		placed += 1
	if not trees.is_empty():
		plan.add(&"orchard", trees[0][1], 0.0, {"plants": trees}, 0, "", 4.0)


func _forest_village() -> void:
	var y := pad_y()
	var R := float(village.get("radius", 80.0))
	_square(9.0, 1)
	_lanes([20.0, 140.0, 260.0], R, 3.0)
	var inside := _inside_pad(R - 4.0, y)
	band(&"", y, 22.0, 11.0, true, {&"row_house": 3, &"farmhouse": 2}, EkStyle.FARM, 0.0, 360.0, inside)
	band(&"", y, 48.0, 13.0, true, {&"farmhouse": 3, &"row_house": 2}, EkStyle.FARM, 0.0, 360.0, inside)
	var sm := p3(R - 14.0, 200.0, y)
	if plan.is_free(sm.x, sm.z, 7.0):
		plan.reserve(sm.x, sm.z, 9.0)
		plan.add(&"sawmill", sm, yaw_in(200.0), {"v": 0}, 2, "ek_sawmill:0", 8.0)
		plan.anchor(&"worker", SettlementLayout.world(sm, yaw_in(200.0), Vector3(0, 0, -2.0)), yaw_in(200.0) + PI, {"tags": [vid, "lumberjack"]})
	for k in 4:
		var lp := p3(R - 10.0, 60.0 + k * 22.0, y)
		if plan.is_free(lp.x, lp.z, 3.0):
			plan.reserve(lp.x, lp.z, 3.0)
			plan.add(&"lumber_pile", lp, yaw_in(60.0 + k * 22.0) + PI * 0.5, {"v": k % 2}, 1, "ek_lumber_pile:%d" % (k % 2), 2.6)
	var sh := Vector3(L.center.x, y, L.center.y) + Vector3(0, 0, -4.0)
	plan.add(&"shrine", sh, 0.0, {"v": 0}, 1, "ek_shrine", 2.5)
	# cedars between the houses
	var trees: Array = []
	for k in 14:
		var b := rng.randf() * 360.0
		var p := p3(rng.randf_range(30.0, R - 6.0), b, y)
		if plan.is_free(p.x, p.z, 2.5):
			plan.reserve(p.x, p.z, 2.5)
			trees.append(p)
	if not trees.is_empty():
		plan.add(&"tree_row", trees[0], 0.0, {"points": trees, "species": &"cypress"}, 0, "", 4.0)
	_lamps(14.0, y, 14.0, 2)
	_gardens(R, y, 8, 0.6)
