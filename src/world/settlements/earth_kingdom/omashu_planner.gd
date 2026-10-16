class_name OmashuPlanner
extends EkRingPlanner
## Lays out Omashu on its mountain (deterministic, main thread): the tiered city from the
## WorldData ring layout (Gate Terrace 160, Market Terraces 178, High Terraces 198, King's Summit
## 222), sandstone retaining walls on the measured tier steps with grand stairs over the three
## radial ramps, the crenellated wall along the chasm edge with gatehouses at the great bridge
## and the rock causeway, THE GREAT BRIDGE over the chasm (the LandmarkProvider's generic span
## is claimed and rebuilt walkable), the King's palace on the summit, three mail chutes spiralling
## down from the summit through the chute station, houses, markets, plazas and anchors.

const ID := &"omashu"
const BRIDGE_ID := &"omashu_great_bridge"
const RAMP_HALF := 8.5
const EDGE_R := 295.5
## House bands: [tier, front radius, depth, facing_in, kind weights].
const BANDS := [
	[&"gate", 230.0, 14.0, true, {&"row_house": 6, &"town_house": 3, &"tenement": 1}],
	[&"gate", 258.0, 13.0, false, {&"row_house": 6, &"town_house": 3}],
	[&"gate", 266.0, 15.0, true, {&"row_house": 5, &"town_house": 3, &"tenement": 2}],
	[&"market", 142.0, 14.0, true, {&"town_house": 5, &"row_house": 4, &"teahouse": 1}],
	[&"market", 170.0, 13.0, false, {&"town_house": 5, &"row_house": 3}],
	[&"market", 178.0, 18.0, true, {&"town_house": 4, &"court_house": 3, &"teahouse": 1}],
	[&"high", 72.0, 20.0, true, {&"court_house": 5, &"town_house": 2}],
	[&"high", 100.0, 22.0, true, {&"court_house": 4, &"mansion": 1, &"town_house": 2}],
]
const STREETS := [[&"gate", 226.0], [&"gate", 262.0], [&"gate", 286.0], [&"market", 138.0], [&"market", 174.0], [&"market", 201.0],
	[&"high", 68.0], [&"high", 96.0], [&"high", 125.0]]
## Mail chutes: [start bearing, end bearing] (from the summit edge down to the Gate Terrace).
const CHUTES := [[-30.0, 70.0], [150.0, 236.0], [262.0, 340.0]]

var th := {}
var gates: Array[Dictionary] = []


func build() -> SettlementPlan:
	plan = SettlementPlan.new(ID, &"earth_kingdom")
	if not WorldData.has_world_data():
		return plan
	L = RingLayout.from_city(ID)
	if not L.is_valid():
		return plan
	rng = ContentHash.rng(ContentHash.hash_name("omashu_plan"))
	cam = ArrivalClearance.new()
	plan.display_name = String(L.record.get("name", "Omashu"))
	plan.center = Vector3(L.center.x, 0.0, L.center.y)
	plan.radius = 420.0
	plan.cell_size = 128.0
	plan.y_range = Vector2(0.0, 60.0)
	for t in L.tiers:
		th[StringName(t["id"])] = float(t["height"])
	for rp: Dictionary in L.ramps:
		avenues.append(wrapf(float(rp["bearing"]), -180.0, 180.0))
	for g: Dictionary in L.record.get("gates", []):
		gates.append(g)
	plan.data["claims"] = [BRIDGE_ID]
	_districts()
	_reserve()
	_tier_walls()
	_edge_wall()
	_bridge()
	_palace()
	_chutes()
	_plazas()
	_markets()
	for b: Array in BANDS:
		band(b[0], h(b[0]), float(b[1]), float(b[2]), bool(b[3]), b[4], EkStyle.OMASHU)
	_street_props()
	_patrols()
	return plan


func h(tier_id: StringName) -> float:
	return float(th.get(tier_id, 160.0))


# --- districts + keep-outs -----------------------------------------------------------------------

func _districts() -> void:
	plan.add_district(&"omashu_palace", "King's Summit", Vector3(L.center.x, h(&"palace"), L.center.y), 60.0)
	for t: Array in [[&"high", "High Terraces", 97.0], [&"market", "Market Terraces", 172.0], [&"gate", "Gate Terrace", 256.0]]:
		var n := maxi(int(TAU * float(t[2]) / 110.0), 1)
		for k in n:
			plan.add_district(StringName("omashu_%s" % t[0]), String(t[1]), p3(float(t[2]), 360.0 * (k + 0.5) / n, h(t[0])),
					maxf(TAU * float(t[2]) / n * 0.62, 50.0))
	for br in WorldData.get_bridges():
		if StringName(br["id"]) == BRIDGE_ID:
			var a: Vector3 = br["a"]
			var b: Vector3 = br["b"]
			plan.add_district(&"omashu_bridge", String(br.get("name", "Great Bridge of Omashu")), (a + b) * 0.5, 40.0)
			plan.districts.push_front(plan.districts.pop_back())


func _reserve() -> void:
	for b in avenues:
		plan.reserve_line(L.xz(50.0, b), L.xz(300.0, b), RAMP_HALF + 1.0)
	for ch: Array in CHUTES:
		var pts := chute_path(float(ch[0]), float(ch[1]))
		for i in pts.size() - 1:
			plan.reserve_line(Vector2(pts[i].x, pts[i].z), Vector2(pts[i + 1].x, pts[i + 1].z), 2.6)


# --- tier steps --------------------------------------------------------------------------------------

func _tier_walls() -> void:
	var steps := [[&"high", &"palace", 46.0, 76.0], [&"market", &"high", 118.0, 148.0], [&"gate", &"market", 196.0, 228.0]]
	for st: Array in steps:
		var lo: StringName = st[0]
		var hi: StringName = st[1]
		var nominal := float(L.tier(hi).get("r_outer", 60.0))
		var style := &"balustrade" if hi == &"palace" else &"crenel"
		var faces := step_wall(ring_spans(nominal, avenue_gaps(RAMP_HALF)), h(lo), h(hi), float(st[2]), float(st[3]), nominal, 11.0,
				1.2 if style == &"balustrade" else 2.4, style, 1)
		plan.data[StringName("%s_faces" % hi)] = faces
		# grand stairs over the ramps
		for b in avenues:
			var rp := L.ramp_at(b, nominal)
			var length := float(rp.get("length", 44.0))
			var foot := p3(nominal + length * 0.5, b, h(lo))
			plan.add(&"grand_stair", foot, yaw_in(b), {"H": h(hi) - h(lo), "R": length, "W": 16.0, "half": length * 0.5, "tone": 1}, 2, "", 24.0)
			plan.data.get_or_add("stairs", []).append({"bearing": b, "foot": foot, "top": p3(nominal - length * 0.5, b, h(hi))})
			for sx: float in [-1.0, 1.0]:
				var gp := p3(nominal - length * 0.5 - 2.5, b + sx * RingLayout.half_angle(2.0 * 7.5, nominal - length * 0.5), h(hi))
				plan.anchor(&"guard_post", gp, yaw_out(b), {"tags": ["stair", String(hi)]})
			if hi != &"palace":
				var arch_at := p3(nominal - length * 0.5 - 5.0, b, h(hi))
				plan.add(&"gate_arch", arch_at, yaw_in(b), {"span": 10.0, "height": 7.0}, 2, "gate_arch:10:7", 8.0)


## The crenellated wall along the chasm edge of the Gate Terrace, with gatehouses at the bridge
## and the causeway and bastions between them.
func _edge_wall() -> void:
	var base := h(&"gate")
	var H := 8.0
	var T := 4.0
	var gate_half := 14.0
	var gaps := []
	for g in gates:
		gaps.append([wrapf(float(g["bearing"]), -180.0, 180.0), gate_half])
	var walk := PackedVector3Array()
	var i := 0
	for span: Array in ring_spans(EDGE_R, gaps):
		var chs := SettlementLayout.chords(L, EDGE_R, float(span[0]), float(span[1]), 12.0)
		for ch: Array in chs:
			var m: Vector2 = ch[2]
			var length := (ch[0] as Vector2).distance_to(ch[1])
			var spec := {"L": snappedf(length * (1.0 + (T * 0.5 + 0.5) / EDGE_R) + 0.1, 0.1), "H": H, "T": T, "bottom": -2.0, "v": i % 4,
				"banner": i % 6 == 2, "door": false, "tone": 1}
			plan.add(&"city_wall", Vector3(m.x, base, m.y), yaw_out(float(ch[3])), spec, 2, EkWalls.arch_of(&"city_wall", spec), length * 0.5 + 1.0)
			plan.reserve(m.x, m.y, 4.0)
			if i % 4 == 0:
				walk.append(Vector3(m.x, base + H, m.y))
			i += 1
		var span_len := RingLayout.arc_len(float(span[1]) - float(span[0]), EDGE_R)
		var nt := int((span_len - 30.0) / 70.0)
		for k in nt:
			var b := lerpf(float(span[0]), float(span[1]), (k + 1.0) / (nt + 1.0))
			var tp := L.xz(EDGE_R, b)
			var tspec := {"S": 9.0, "H": H, "T": T, "out": 2.0, "top": 6.0, "roof": true, "bottom": -2.0, "v": k % 2, "tone": 1}
			plan.add(&"wall_tower", Vector3(tp.x, base, tp.y), yaw_out(b), tspec, 2, EkWalls.arch_of(&"wall_tower", tspec), 7.0)
			plan.reserve(tp.x, tp.y, 6.0)
			plan.anchor(&"guard_post", Vector3(tp.x, base + H + 6.0, tp.y), yaw_out(b), {"tags": ["omashu_wall", "bastion"]})
	if walk.size() > 2:
		plan.anchor(&"patrol", walk[0], 0.0, {"points": walk, "loop": false, "tags": ["omashu_wall", "wall_walk"]})
	for g in gates:
		var b := wrapf(float(g["bearing"]), -180.0, 180.0)
		var gp := L.xz(EDGE_R, b)
		var gspec := {"W": 12.0, "Wt": 8.0, "D": 12.0, "Ho": 7.5, "H": H, "T": T, "bottom": -2.0, "v": 1, "tone": 1}
		plan.add(&"great_gate", Vector3(gp.x, base, gp.y), yaw_out(b), gspec, 2, EkWalls.arch_of(&"great_gate", gspec), 14.0)
		plan.reserve(gp.x, gp.y, gate_half)
		var gid := String(g.get("id", ""))
		for sx: float in [-1.0, 1.0]:
			plan.anchor(&"guard_post", SettlementLayout.world(Vector3(gp.x, base, gp.y), yaw_out(b), Vector3(sx * 8.0, 0, 9.0)), yaw_in(b) + PI,
					{"tags": ["omashu_gate", gid]})
		plan.anchor(&"quest_giver", SettlementLayout.world(Vector3(gp.x, base, gp.y), yaw_out(b), Vector3(9.0, 0, 12.0)), yaw_out(b), {"tags": ["gatekeeper", gid]})
		plan.data.get_or_add("gates", []).append({"id": StringName(gid), "bearing": b, "position": Vector3(gp.x, base, gp.y),
			"inside": p3(EDGE_R - 16.0, b, base)})


# --- the great bridge ----------------------------------------------------------------------------

func _bridge() -> void:
	for br in WorldData.get_bridges():
		if StringName(br["id"]) != BRIDGE_ID:
			continue
		var a: Vector3 = br["a"]          # rim end
		var b: Vector3 = br["b"]          # city end
		var dir := Vector3(a.x - b.x, 0, a.z - b.z).normalized()
		# the deck runs from the gatehouse's outer face to the rim, over the whole chasm
		var city := Vector3(b.x, h(&"gate"), b.z) + dir * 6.0
		var rim := Vector3(a.x, WorldData.get_height(a.x, a.z), a.z) + dir * 4.0
		var mid := (city + rim) * 0.5
		var yaw := SettlementLayout.yaw_dir(Vector2(dir.x, dir.z))
		var length := Vector2(rim.x - city.x, rim.z - city.z).length()
		var floor_y := float((L.record.get("chasm", {}) as Dictionary).get("floor", 92.0))
		var spec := {"L": length, "W": float(br.get("width", 14.0)), "y0": city.y - mid.y, "y1": rim.y - mid.y, "floor": floor_y - mid.y}
		plan.add(&"omashu_bridge", mid, yaw, spec, 2, "", length * 0.5)
		plan.reserve_line(Vector2(city.x, city.z) - Vector2(dir.x, dir.z) * 4.0, Vector2(rim.x, rim.z), 9.0)
		plan.data["bridge"] = {"city": city, "rim": rim, "yaw": yaw}
		for sx: float in [-1.0, 1.0]:
			var side := Vector3(-dir.z, 0, dir.x) * sx
			plan.anchor(&"guard_post", rim + side * 6.0 + dir * 2.0, yaw + PI, {"tags": ["bridge", "rim"]})
		var pts := PackedVector3Array([city, mid + Vector3(0, 1.5, 0), rim])
		plan.anchor(&"patrol", city, yaw, {"points": pts, "loop": false, "tags": ["bridge"]})
		plan.anchor(&"idle", mid + Vector3(-dir.z * 5.0, 1.5, dir.x * 5.0), yaw + PI * 0.5, {"tags": ["bridge", "view"]})


# --- the King's Summit ------------------------------------------------------------------------

func _palace() -> void:
	var c := Vector3(L.center.x, h(&"palace"), L.center.y)
	var yaw := yaw_out(90.0)          # faces the great bridge (east)
	var at := func(lx: float, lz: float, y: float = 0.0) -> Vector3: return SettlementLayout.world(c, yaw, Vector3(lx, y, lz))
	var pod: Vector3 = at.call(0.0, 6.0)
	plan.add(&"palace_podium", pod, yaw, {"w": 46.0, "d": 36.0, "h": 3.5}, 2, "", 28.0)
	plan.reserve(pod.x, pod.z, 30.0)
	plan.add(&"throne_hall", at.call(0.0, 11.0, 3.5), yaw, {"w": 28.0, "d": 16.0}, 2, "", 18.0)
	for sx: float in [-1.0, 1.0]:
		var pg: Vector3 = at.call(sx * 32.0, 18.0)
		plan.add(&"pagoda", pg, yaw, {"tiers": 4, "w": 8.0}, 2, "pagoda:4:8", 7.0)
		plan.reserve(pg.x, pg.z, 8.0)
		var gd: Vector3 = at.call(sx * 32.0, -14.0)
		plan.add(&"garden", gd, yaw, {"w": 16.0, "d": 18.0, "v": int(sx > 0.0), "plants": 2}, 1, "", 11.0)
		plan.reserve(gd.x, gd.z, 10.0)
		plan.anchor(&"gardener", SettlementLayout.world(gd, yaw, Vector3(3.0, 0, 4.0)), yaw, {"tags": ["palace", "garden"]})
		plan.anchor(&"guard_post", at.call(sx * 6.0, -18.0), yaw, {"tags": ["palace", "stair"]})
	var gate: Vector3 = at.call(0.0, -38.0)
	plan.add(&"palace_gate", gate, yaw, {"w": 22.0, "d": 9.0}, 2, "palace_gate:22", 12.0)
	plan.reserve(gate.x, gate.z, 12.0)
	plan.anchor(&"quest_giver", at.call(0.0, 2.0, 5.1), yaw, {"tags": ["king", "palace", "throne_hall"]})
	plan.data["palace"] = {"center": c, "yaw": yaw}


# --- mail chutes ---------------------------------------------------------------------------------

## The chute's path: from the summit edge (r 58, y 224.5) spiralling to the Gate Terrace
## (r 288, y 163), always clear above the terraces below.
func chute_path(b0: float, b1: float) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var n := 18
	for k in n + 1:
		var t := float(k) / n
		var r := lerpf(58.0, 288.0, t)
		var b := lerpf(b0, b1, t) + sin(t * PI * 3.0) * 4.0
		var y := lerpf(h(&"palace") + 2.5, h(&"gate") + 3.0, pow(t, 0.92))
		var q := L.xz(r, b)
		y = maxf(y, ground(q.x, q.y) + 2.6)
		pts.append(Vector3(q.x, y, q.y))
	return pts


func _chutes() -> void:
	var ci := 0
	for ch: Array in CHUTES:
		var pts := chute_path(float(ch[0]), float(ch[1]))
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var m := (a + b) * 0.5
			var gm := ground(m.x, m.z)
			var dir := Vector2(b.x - a.x, b.z - a.z)
			var yaw := SettlementLayout.yaw_dir(dir.normalized())
			# local frame: origin at the segment middle on the ground, chute along -Z
			var la := Vector3(0, a.y - gm, dir.length() * 0.5)
			var lb := Vector3(0, b.y - gm, -dir.length() * 0.5)
			var spec := {"a": la, "b": lb, "ga": ground(a.x, a.z) - gm, "gb": ground(b.x, b.z) - gm, "v": ci}
			plan.add(&"omashu_chute", Vector3(m.x, gm, m.z), yaw, spec, 2, "", dir.length() * 0.5)
		ci += 1
		# a delivery stop at the bottom
		var end := pts[pts.size() - 1]
		plan.anchor(&"worker", Vector3(end.x, ground(end.x, end.z), end.z) + Vector3(1.5, 0, 1.5), 0.0, {"tags": ["mail", "chute"]})
	# the chute station of the Market Terraces (the WorldData landmark)
	var poi := WorldData.get_poi(&"ek_mail_chutes")
	if not poi.is_empty():
		var pp: Vector3 = poi["position"]
		var pr := L.polar(pp.x, pp.z)
		var pos := p3(pr.x, pr.y, h(&"market"))
		var yaw := yaw_in(pr.y)
		plan.reserve(pos.x, pos.z, 9.0)
		plan.add(&"omashu_chute_hub", pos, yaw, {"v": 0}, 2, "", 8.0)
		plan.anchor(&"quest_giver", SettlementLayout.world(pos, yaw, Vector3(0, 0, -6.0)), yaw + PI, {"tags": ["mail_clerk", "chutes"]})
		plan.anchor(&"child_play", SettlementLayout.world(pos, yaw, Vector3(4.0, 0, -4.0)), yaw, {"tags": ["chutes"]})
		plan.add_district(&"omashu_chutes", String(poi.get("name", "Mail Chutes")), pos, 14.0)
		plan.districts.push_front(plan.districts.pop_back())
		plan.data["claims"].append(StringName(poi["id"]))


# --- plazas, markets, props --------------------------------------------------------------------

func _plazas() -> void:
	for g: Dictionary in plan.data.get("gates", []):
		var c: Vector3 = g["inside"]
		var b := float(g["bearing"])
		plan.add(&"plaza", c, yaw_in(b), {"r": 10.0, "v": 1}, 1, "ek_plaza:10:1", 10.0)
		plan.reserve(c.x, c.z, 11.0)
		for sx: float in [-1.0, 1.0]:
			plan.add(&"banner_pole", SettlementLayout.world(c, yaw_in(b), Vector3(sx * 11.5, 0, 0)), yaw_in(b), {"v": 1}, 2, "ek_banner_pole:1", 0.8)
		plan.anchor(&"child_play", SettlementLayout.world(c, yaw_in(b), Vector3(4.0, 0, 3.0)), 0.0, {"tags": ["plaza"]})
	# badgermole statues at the stair heads of the Market Terraces
	for b in avenues:
		var sp := p3(201.0, b + RingLayout.half_angle(2.0 * 12.0, 201.0), h(&"market"))
		if plan.is_free(sp.x, sp.z, 2.0):
			plan.reserve(sp.x, sp.z, 2.0)
			plan.add(&"statue", sp, yaw_out(b), {"v": 0}, 2, "ek_statue:0", 2.0)


func _markets() -> void:
	var y := h(&"market")
	var n := 0
	for arc: Array in [[8.0, 34.0], [184.0, 206.0], [290.0, 312.0]]:
		var b := float(arc[0])
		while b < float(arc[1]):
			for rs: float in [-1.0, 1.0]:
				var p := p3(174.0 + rs * 2.6, b, y)
				if plan.is_free(p.x, p.z, 1.6):
					var yaw := yaw_in(b) if rs > 0.0 else yaw_out(b)
					var v := n % 6
					plan.add(&"stall", p, yaw, {"v": v}, 1, "ek_stall:%d" % v, 1.6)
					plan.reserve(p.x, p.z, 1.6)
					plan.anchor(&"market_stall", SettlementLayout.world(p, yaw, Vector3(0, 0, 0.8)), yaw, {"tags": ["market"], "goods": EkProps.GOODS[v]})
					n += 1
			b += RingLayout.half_angle(2.0 * 4.2, 174.0)
		plan.anchor(&"quest_giver", p3(174.0, (float(arc[0]) + float(arc[1])) * 0.5, y), 0.0, {"tags": ["market", "merchant"]})


func _street_props() -> void:
	for st: Array in STREETS:
		var tier: StringName = st[0]
		var r: float = st[1]
		var y := h(tier)
		var step := RingLayout.half_angle(2.0 * 24.0, r)
		var b := 2.0
		var k := 0
		while b < 362.0:
			var bb := wrapf(b, -180.0, 180.0)
			var p := p3(r + (2.2 if k % 2 == 0 else -2.2), bb, y)
			if plan.is_free(p.x, p.z, 0.7) and not on_avenue(bb, r, 9.0):
				plan.reserve(p.x, p.z, 0.7)
				plan.add(&"lamp_post", p, yaw_in(bb), {"v": k % 2, "light": k % 3 == 0}, 1, "ek_lamp:%d:%d" % [k % 2, int(k % 3 == 0)], 0.7)
				if k % 5 == 2:
					var bp := p3(r - (2.2 if k % 2 == 0 else -2.2), bb, y)
					if plan.is_free(bp.x, bp.z, 1.1):
						plan.reserve(bp.x, bp.z, 1.1)
						plan.add(&"bench", bp, yaw_in(bb + 90.0), {"v": 0}, 0, "ek_bench:0", 1.1)
						plan.anchor(&"idle", bp, yaw_in(bb + 90.0), {"tags": [String(tier), "bench"]})
			b += step
			k += 1


func _patrols() -> void:
	for st: Array in [[&"gate", 262.0], [&"market", 174.0], [&"high", 96.0]]:
		var pts := PackedVector3Array()
		for k in 25:
			pts.append(p3(float(st[1]), k * 15.0, h(st[0])))
		plan.anchor(&"patrol", pts[0], 0.0, {"points": pts, "loop": true, "tags": ["omashu", String(st[0])]})
