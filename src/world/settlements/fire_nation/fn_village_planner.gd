class_name FnVillagePlanner
extends FnRingPlanner
## The Fire Nation villages from the WorldData village records (deterministic, main thread), one
## district each:
##   Saltspark (fishing village): fishers' huts and houses round a brazier square on the pad, salt
##     evaporation pans on the seaward side, fish racks, boats drawn up, a fire shrine and a well
##   Ashleaf Terraces (tea village): tea farmers' houses round the square, rings of clipped tea
##     hedges on the outer pad, drying sheds, a fire shrine, tea pickers
##   Sunflare Isle (resort): white villas with red verandas on the upper terrace overlooking the
##     inner garden court (a great garden, hot springs with steam, beach cabanas, palm rows, a
##     temple pavilion), stone stairs up the terrace slope, lanterns everywhere

const ID := &"fn_villages"

var village: Dictionary = {}
var vid := ""


func build() -> SettlementPlan:
	plan = SettlementPlan.new(ID, &"fire_nation")
	plan.display_name = "Fire Nation villages"
	plan.cell_size = 128.0
	plan.y_range = Vector2(0.0, 30.0)
	if not WorldData.has_world_data():
		return plan
	cam = ArrivalClearance.new()
	plan.data["claims"] = []
	for v in WorldData.get_villages():
		if StringName(v.get("region", &"")) != &"fire_nation":
			continue
		village = v
		vid = String(v["id"])
		rng = ContentHash.rng(ContentHash.hash_name("fn_village_%s" % vid))
		_band_rng = rng
		var c: Vector3 = v["center"]
		L = RingLayout.new()
		L.id = StringName(vid)
		L.center = Vector2(c.x, c.z)
		avenues.clear()
		var terr: Array = v.get("terraces", [])
		var reach := float(terr[terr.size() - 1]["radius"]) + 8.0 if terr.size() > 1 else float(v.get("radius", 80.0)) + 10.0
		plan.add_district(StringName("fn_%s" % vid), String(v.get("name", vid)), Vector3(c.x, pad_y(), c.z), reach)
		plan.data.get_or_add("exclusions", []).append([Vector3(c.x, 0.0, c.z), reach - 4.0,
			ContentExclusions.TAG_TREES | ContentExclusions.TAG_ROCKS | ContentExclusions.TAG_PROPS])
		match StringName(v.get("kind", &"")):
			&"fishing_village": _saltspark()
			&"tea_village": _ashleaf()
			&"resort": _sunflare()
	return plan


func pad_y() -> float:
	return float(village.get("pad_height", (village["center"] as Vector3).y))


func _inside_pad(r_max: float, y: float) -> Callable:
	return func(w: Vector3) -> bool:
		return L.polar(w.x, w.z).x < r_max and absf(ground(w.x, w.z) - y) < 0.9


## Brazier square at the centre, radial lanes kept free.
func _square(r: float, lanes: Array, r1: float) -> Vector3:
	var c := Vector3(L.center.x, pad_y(), L.center.y)
	plan.add(&"fn_plaza", c, 0.0, {"r": r, "v": 0}, 1, "fn_plaza:%d:0" % int(r), r)
	plan.reserve(c.x, c.z, r + 1.5)
	plan.anchor(&"quest_giver", c + Vector3(r * 0.6, 0, r * 0.4), PI, {"tags": [vid, "elder"]})
	plan.anchor(&"child_play", c + Vector3(-r * 0.5, 0, -r * 0.5), 0.0, {"tags": [vid, "square"]})
	plan.anchor(&"idle", c + Vector3(0, 0, r * 0.8), 0.0, {"tags": [vid, "square"]})
	for b: float in lanes:
		avenues.append(wrapf(b, -180.0, 180.0))
		plan.reserve_line(L.xz(r, b), L.xz(r1, b), 2.6)
	return c


func _lights(r: float, y: float, step_m: float, brazier_every: int = 4) -> void:
	var step := RingLayout.half_angle(2.0 * step_m, r)
	var b := 5.0
	var k := 0
	while b < 365.0:
		var p := p3(r, b, y)
		if plan.is_free(p.x, p.z, 0.8) and absf(ground(p.x, p.z) - y) < 0.6:
			plan.reserve(p.x, p.z, 0.8)
			if brazier_every > 0 and k % brazier_every == brazier_every - 1:
				plan.add(&"fn_brazier", p, 0.0, {"v": 0}, 1, "fn_brazier:0", 0.9)
			else:
				plan.add(&"fn_lamp", p, yaw_in(b), {"v": k % 2, "light": k % 3 == 0}, 1, "fn_lamp:%d:%d" % [k % 2, int(k % 3 == 0)], 0.7)
		b += step
		k += 1


## Places a piece where its footprint is free and on the pad; returns true when placed.
func _try(kind: StringName, pos: Vector3, yaw: float, fp: Vector2, spec: Dictionary, arch: String, inside: Callable, lod: int = 2) -> bool:
	if not SettlementLayout.fits(plan, pos, yaw, fp, inside):
		return false
	SettlementLayout.reserve_rect(plan, pos, yaw, fp)
	plan.add(kind, pos, yaw, spec, lod, arch, maxf(fp.x, fp.y) * 0.5)
	return true


func _shrine(r: float, b: float, y: float, inside: Callable) -> void:
	var p := p3(r, b, y)
	if _try(&"fire_shrine", p, yaw_in(b), Vector2(4.6, 4.6), {"v": 0}, "fire_shrine:0", inside):
		plan.anchor(&"quest_giver", SettlementLayout.world(p, yaw_in(b), Vector3(1.6, 0, -3.6)), yaw_in(b) + PI, {"tags": [vid, "shrine", "sage"]})


# --- Saltspark ---------------------------------------------------------------------------------

func _saltspark() -> void:
	var y := pad_y()
	var R := float(village.get("radius", 80.0))
	var inside := _inside_pad(R + 4.0, y)
	_square(7.0, [318.0, 45.0, 140.0, 235.0], R)
	# salt pans on the seaward (south-west) side
	var pans := 0
	for b: float in [192.0, 214.0, 258.0, 280.0]:
		var p := p3(R - 12.0, b, y)
		if _try(&"salt_pans", p, yaw_in(b), Vector2(20.0, 15.0), {"w": 18.0, "d": 12.0, "nx": 3, "nz": 2}, "salt_pans:18:12", inside, 1):
			plan.anchor(&"worker", SettlementLayout.world(p, yaw_in(b), Vector3(-3.0, 0, -8.6)), yaw_in(b) + PI, {"tags": [vid, "salt", "rake"]})
			pans += 1
	plan.data["salt_pans_%s" % vid] = pans
	# houses round the square
	for band_def: Array in [[15.0, 9.0, {&"fisher_hut": 2, &"fn_house": 3}], [36.0, 9.5, {&"fisher_hut": 3, &"fn_house": 2}],
			[56.0, 9.0, {&"fisher_hut": 4, &"fn_house": 1}]]:
		band(StringName(vid), y, float(band_def[0]), float(band_def[1]), true, band_def[2], FnStyle.VILLAGE, 0.0, 360.0, inside, Vector2(1.2, 3.4))
	# fish racks, boats drawn up for repair, the well, the shrine
	for t: Array in [[236.0, 46.0, &"fish_rack"], [170.0, 66.0, &"fish_rack"], [300.0, 68.0, &"fish_rack"], [120.0, 62.0, &"fish_rack"]]:
		var p := p3(float(t[1]), float(t[0]), y)
		if _try(t[2], p, yaw_in(float(t[0])), Vector2(4.6, 2.6), {"v": int(t[0]) % 3}, "fish_rack:%d" % (int(t[0]) % 3), inside, 1):
			plan.anchor(&"fisher", SettlementLayout.world(p, yaw_in(float(t[0])), Vector3(0, 0, -2.2)), yaw_in(float(t[0])) + PI, {"tags": [vid, "fish"]})
	for k in 3:
		var b := 196.0 + k * 34.0
		var p := p3(30.0, b, y + 0.35)
		_try(&"sampan", p, yaw_in(b) + 1.2, Vector2(3.0, 8.0), {}, "sampan", inside, 1)
	_try(&"well", p3(12.0, 100.0, y), 0.0, Vector2(2.6, 2.6), {"v": 0}, "well:0", inside, 1)
	_shrine(72.0, 20.0, y, inside)
	_lights(26.0, y, 22.0, 3)
	_lights(48.0, y, 26.0, 4)
	courtyard_trees()


# --- Ashleaf Terraces --------------------------------------------------------------------------

func _ashleaf() -> void:
	var y := pad_y()
	var inside := _inside_pad(94.0, y)
	var lanes := [57.0, 150.0, 240.0, 330.0]
	_square(7.0, lanes, 92.0)
	for band_def: Array in [[15.0, 10.0, {&"tea_house_fn": 3, &"fn_house": 2}], [34.0, 10.0, {&"tea_house_fn": 2, &"fn_house": 2}]]:
		band(StringName(vid), y, float(band_def[0]), float(band_def[1]), true, band_def[2], FnStyle.VILLAGE, 0.0, 360.0, inside, Vector2(1.6, 3.6))
	# drying sheds between the houses and the tea
	for b: float in [100.0, 200.0, 290.0]:
		var p := p3(52.0, b, y)
		if _try(&"tea_shed", p, yaw_in(b), Vector2(10.0, 7.0), {"v": int(b) % 3}, "tea_shed:%d" % (int(b) % 3), inside):
			plan.anchor(&"worker", SettlementLayout.world(p, yaw_in(b), Vector3(0, 0, -4.2)), yaw_in(b) + PI, {"tags": [vid, "tea", "drying"]})
	_shrine(50.0, 20.0, y, inside)
	# rings of clipped tea hedges on the outer pad
	var rows := 0
	for rr: float in [66.0, 77.0, 88.0]:
		var b := 2.0
		while b < 360.0:
			var seg := 15.0
			var bc := b + RingLayout.half_angle(seg, rr)
			var p := p3(rr, bc, y)
			var yaw := yaw_out(bc)
			if SettlementLayout.fits(plan, SettlementLayout.world(p, yaw, Vector3(0, 0, 2.9)), yaw, Vector2(seg + 1.0, 7.0), inside, 0.3):
				SettlementLayout.reserve_rect(plan, SettlementLayout.world(p, yaw, Vector3(0, 0, 2.9)), yaw, Vector2(seg + 1.0, 7.0))
				plan.add(&"tea_rows", p, yaw, {"L": seg, "n": 4, "gap": 1.9}, 1, "tea_rows:%d" % int(seg), seg * 0.5)
				if rows % 4 == 1:
					plan.anchor(&"worker", SettlementLayout.world(p, yaw, Vector3(0, 0, 1.0)), yaw, {"tags": [vid, "tea", "picker"]})
				rows += 1
			b += RingLayout.half_angle(2.0 * (seg + 2.0), rr)
	plan.data["tea_rows_%s" % vid] = rows
	_lights(25.0, y, 20.0, 3)
	_lights(45.0, y, 26.0, 0)


# --- Sunflare Isle resort ----------------------------------------------------------------------

func _sunflare() -> void:
	var y := pad_y()
	var terr: Array = village.get("terraces", [])
	var r0 := float(terr[0]["radius"]) if terr.size() > 0 else 90.0
	var r1 := float(terr[1]["radius"]) if terr.size() > 1 else r0 + 50.0
	var y1 := float(terr[1]["height"]) if terr.size() > 1 else y
	var inner := _inside_pad(r0 - 4.0, y)
	var upper := func(w: Vector3) -> bool:
		var r := L.polar(w.x, w.z).x
		return r > r0 + 4.0 and r < r1 + 2.0 and absf(ground(w.x, w.z) - y1) < 0.9
	var c := Vector3(L.center.x, y, L.center.y)
	plan.add(&"lawn", c, 0.0, {"r": r0 - 14.0}, 1, "lawn:%d" % int(r0 - 14.0), r0 - 14.0)
	# the great garden court at the centre with the temple pavilion on its north side
	plan.add(&"fn_garden", c + Vector3(0, 0.05, 0), 0.0, {"w": 40.0, "d": 30.0, "v": 0, "plants": 4}, 1, "", 25.0)
	SettlementLayout.reserve_rect(plan, c, 0.0, Vector2(42.0, 32.0))
	var tp := c + Vector3(0, 0, -26.0)
	plan.add(&"fn_temple", tp, PI, {"w": 11.0, "d": 9.0}, 2, "fn_temple:11:9", 9.0)
	plan.reserve(tp.x, tp.z, 9.0)
	plan.anchor(&"quest_giver", tp + Vector3(0, 0, 7.0), 0.0, {"tags": [vid, "resort_keeper"]})
	plan.add_district(&"fn_sunflare_court", "Sunflare Isle Resort", c, 50.0)
	plan.districts.push_front(plan.districts.pop_back())
	# promenade paths kept free (to the west road, the south pier, the stairs)
	for b: float in [0.0, 90.0, 180.0, 280.0, 149.0]:
		avenues.append(wrapf(b, -180.0, 180.0))
		plan.reserve_line(L.xz(22.0, b), L.xz(r1 + 4.0, b), 3.0)
	# hot springs and beach cabanas on the court
	for t: Array in [[52.0, 40.0], [300.0, 42.0], [128.0, 58.0]]:
		var p := p3(float(t[1]), float(t[0]), y)
		if _try(&"hot_spring", p, 0.0, Vector2(12.0, 12.0), {"r": 5.0}, "hot_spring:5", inner):
			for k in 3:
				var a := TAU * k / 3.0 + 0.4
				plan.anchor(&"idle", p + Vector3(cos(a) * 4.0, 0.2, sin(a) * 4.0), a + PI, {"tags": [vid, "guest", "hot_spring"]})
	var cab := 0
	for b: float in [20.0, 70.0, 110.0, 160.0, 205.0, 250.0, 320.0, 340.0]:
		var p := p3(64.0, b, y)
		if _try(&"cabana", p, yaw_in(b), Vector2(6.6, 6.6), {"v": cab % 3}, "cabana:%d" % (cab % 3), inner, 1):
			plan.anchor(&"idle", SettlementLayout.world(p, yaw_in(b), Vector3(0, 0.3, 0.4)), yaw_in(b) + PI, {"tags": [vid, "guest", "cabana"]})
			cab += 1
	# palm rows round the court
	for rr: float in [34.0, 76.0]:
		var pts := PackedVector3Array()
		var b := 8.0
		while b < 368.0:
			var p := p3(rr, b, NAN)
			if plan.is_free(p.x, p.z, 1.6) and absf(p.y - y) < 0.8:
				plan.reserve(p.x, p.z, 1.2)
				pts.append(p)
			b += RingLayout.half_angle(2.0 * (11.0 if rr < 50.0 else 14.0), rr)
		if pts.size() > 0:
			plan.add(&"tree_row", pts[0], 0.0, {"points": pts, "species": &"palm", "scale": 0.8}, 0, "", 4.0)
	# villas on the upper terrace overlooking the court
	band(StringName(vid), y1, r0 + 12.0, 15.0, true, {&"fn_villa": 1}, FnStyle.RESORT, 0.0, 360.0, upper, Vector2(3.0, 6.0))
	band(StringName(vid), y1, r1 - 3.0, 15.0, false, {&"fn_villa": 1}, FnStyle.RESORT, 0.0, 360.0, upper, Vector2(4.0, 8.0))
	# stone stairs up the terrace slope on the promenades
	for b: float in [0.0, 90.0, 180.0]:
		var foot := p3(r0 - 12.0, b, y)
		var top := p3(r0 + 9.0, b, y1)
		plan.add(&"fn_stair", foot, yaw_out(b), {"H": y1 - y, "R": top.distance_to(Vector3(foot.x, y1, foot.z)), "W": 8.0, "half": 21.0}, 2, "", 11.0)
	_lights(28.0, y, 18.0, 4)
	_lights(70.0, y, 22.0, 4)
	_lights(r0 + 6.0, y1, 24.0, 0)
