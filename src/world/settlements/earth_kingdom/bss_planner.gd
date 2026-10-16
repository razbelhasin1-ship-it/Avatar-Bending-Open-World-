class_name BssPlanner
extends EkRingPlanner
## Lays out Ba Sing Se from its WorldData ring layout (deterministic, main thread): the colossal
## outer wall (r 700, 38 m, 22 m thick) and the inner wall (r 380) as chord pieces with bastions,
## gatehouses on the five avenues and wall stairs, the retaining walls of the Middle / Upper Ring
## steps and the palace podium on their MEASURED faces, avenue stairs / ramp cheeks, then
## BssDistricts (palace, Upper / Middle / Lower Ring, interiors, markets, street furniture,
## anchors) and BssFarmland (the Agrarian Zone: farmsteads, windmills, irrigation, water wheels).
##
## The earth element spawns on the Upper Ring overlook; its arrival flight comes in from the
## east over the palace: every tall piece is checked against it (ArrivalClearance).

const ID := &"ba_sing_se"
const OUT_CHORD := 20.0
const IN_CHORD := 18.0
const RING_CHORD := 12.0
## Avenue gaps (half widths, m) in the ring walls (the terrain ramps are 22 m wide).
const RAMP_HALF := 12.5
## Gatehouse sizes: [opening W, tower width Wt, depth D, opening height Ho].
const OUT_GATE := [18.0, 16.0, 32.0, 24.0]
const IN_GATE := [16.0, 12.0, 24.0, 17.0]
## Wall stair width and the number of chords it climbs.
const STAIR_W := 4.0
## The overlook sector of the Upper Ring edge (balustrade instead of a crenellated wall).
const OVERLOOK := [222.0, 292.0]

## Tier heights by id, wall records by id.
var th := {}
var walls := {}
## The WorldData gate records (their bearings are the five avenues).
var gates: Array[Dictionary] = []
## Wall bases (world y of the chord frames) and tops.
var out_base := 58.0
var in_base := 58.5


func build() -> SettlementPlan:
	plan = SettlementPlan.new(ID, &"earth_kingdom")
	if not WorldData.has_world_data():
		return plan
	L = RingLayout.from_city(ID)
	if not L.is_valid():
		return plan
	rng = ContentHash.rng(ContentHash.hash_name("bss_plan"))
	cam = ArrivalClearance.for_element(ElementDefs.Element.EARTH)
	plan.display_name = String(L.record.get("name", "Ba Sing Se"))
	plan.center = Vector3(L.center.x, 0.0, L.center.y)
	plan.radius = 735.0
	plan.cell_size = 128.0
	plan.y_range = Vector2(0.0, 72.0)
	for t in L.tiers:
		th[StringName(t["id"])] = float(t["height"])
	for w: Dictionary in L.record.get("walls", []):
		walls[StringName(w["id"])] = w
	for g: Dictionary in L.record.get("gates", []):
		gates.append(g)
		avenues.append(wrapf(float(g["bearing"]), -180.0, 180.0))
	out_base = _ring_ground(radius_of(&"outer_wall"), 0.35)
	in_base = _ring_ground(radius_of(&"inner_wall"), 0.35)
	_districts()
	_reserve_specials()
	_city_wall(&"outer_wall", OUT_CHORD, out_base, OUT_GATE, 125.0)
	_city_wall(&"inner_wall", IN_CHORD, in_base, IN_GATE, 95.0)
	_ring_walls()
	_avenue_steps()
	BssDistricts.new(self).build()
	BssFarmland.new(self).build()
	return plan


# --- helpers ---------------------------------------------------------------------------------------

func h(tier_id: StringName) -> float:
	return float(th.get(tier_id, 60.0))


func radius_of(wall_id: StringName) -> float:
	return float((walls.get(wall_id, {}) as Dictionary).get("radius", 0.0))


## Low quantile of the ground along a ring (a wall base that is buried rather than floating).
func _ring_ground(r: float, q: float) -> float:
	var ys: Array[float] = []
	for k in 72:
		var p := L.xz(r, k * 5.0)
		ys.append(ground(p.x, p.y))
	ys.sort()
	return snappedf(ys[int(q * (ys.size() - 1))], 0.1)


# --- districts + keep-outs ---------------------------------------------------------------------

func _districts() -> void:
	var ring_d := func(d_id: StringName, d_name: String, r_mid: float, width: float, y: float) -> void:
		var n := maxi(int(TAU * r_mid / 120.0), 1)
		for k in n:
			var b := 360.0 * (k + 0.5) / n
			plan.add_district(d_id, d_name, p3(r_mid, b, y), maxf(TAU * r_mid / n * 0.62, width * 0.6))
	plan.add_district(&"bss_palace", "Royal Palace", Vector3(L.center.x, h(&"palace"), L.center.y), 58.0)
	ring_d.call(&"bss_upper_ring", "Upper Ring", 104.0, 92.0, h(&"upper_ring"))
	ring_d.call(&"bss_middle_ring", "Middle Ring", 207.0, 112.0, h(&"middle_ring"))
	ring_d.call(&"bss_lower_ring", "Lower Ring", 322.0, 118.0, h(&"lower_ring"))
	ring_d.call(&"bss_agrarian", "Agrarian Zone", 540.0, 320.0, h(&"agrarian"))
	# the outer wall belt (gatehouses, wall walk) reads as its own district
	ring_d.call(&"bss_outer_wall", "The Outer Wall", 704.0, 40.0, out_base + 38.0)


func _reserve_specials() -> void:
	# the earth element's spawn on the Upper Ring overlook (its plaza is built by BssDistricts)
	var sp := WorldData.get_spawn(ElementDefs.Element.EARTH)
	if L.tier_at(sp.origin.x, sp.origin.z).size() > 0:
		plan.data["spawn"] = sp.origin
		var f := -sp.basis.z
		plan.data["spawn_yaw"] = SettlementLayout.yaw_dir(Vector2(f.x, f.z))
		plan.reserve(sp.origin.x, sp.origin.z, 15.0)
	# the avenues: from the outer gate to the palace podium
	for b in avenues:
		plan.reserve_line(L.xz(62.0, b), L.xz(740.0, b), 13.0)


# --- outer + inner walls -------------------------------------------------------------------------

## A city wall ring: chords between the gatehouses, bastions every ~`tower_step` m, a gatehouse
## on every avenue and a stair climbing the inner face clockwise of every gate.
func _city_wall(wall_id: StringName, chord: float, base: float, gate: Array, tower_step: float) -> void:
	var w: Dictionary = walls.get(wall_id, {})
	if w.is_empty():
		return
	var r := float(w["radius"])
	var H := float(w["height"])
	var T := float(w["thickness"])
	var top := base + H
	var gate_half := float(gate[0]) * 0.5 + float(gate[1])
	var bat := H * 0.06
	var stair_chords := maxi(int(ceil(H / (chord * 0.5))), 2)
	var wl := String(wall_id).trim_suffix("_wall")
	plan.data[StringName("%s_top" % wl)] = top
	var walk := PackedVector3Array()
	var stair_path := PackedVector3Array()
	var i_global := 0
	for span: Array in ring_spans(r, avenue_gaps(gate_half)):
		var chs := SettlementLayout.chords(L, r, float(span[0]), float(span[1]), chord)
		for ci in chs.size():
			var ch: Array = chs[ci]
			var a: Vector2 = ch[0]
			var b: Vector2 = ch[1]
			var m: Vector2 = ch[2]
			var bm := float(ch[3])
			var length := a.distance_to(b)
			var lo := minf(minf(ground(a.x, a.y), ground(b.x, b.y)), ground(m.x, m.y))
			var spec := {"L": snappedf(length * (1.0 + (T * 0.5 + bat) / r) + 0.12, 0.1), "H": H, "T": T,
				"bottom": snappedf(minf(lo - base - 2.0, -1.5), 0.5), "v": i_global % 4,
				"banner": i_global % 7 == 3, "door": i_global % 5 == 2 and ci > stair_chords + 1}
			# wall stair clockwise of the gate: the chords after the first one past the gatehouse (the
			# stair's foot stays clear of the gatehouse, the way onto it runs along the wall)
			var si := ci - 1
			if si >= 0 and si < stair_chords:
				var hl := length * 0.5
				var y0 := H * si / stair_chords
				var y1 := H * (si + 1) / stair_chords
				var sspec := {"L": snappedf(length, 0.1), "y0": snappedf(y0, 0.1), "y1": snappedf(y1, 0.1), "z0": T * 0.5 + 1.0 + bat * 0.35,
					"w": STAIR_W, "top": si == stair_chords - 1}
				plan.add(&"wall_stair", Vector3(m.x, base, m.y), yaw_out(bm), sspec, 1, EkWalls.arch_of(&"wall_stair", sspec), length * 0.5)
				var inner := L.xz(r - T * 0.5 - 3.6, bm)
				plan.reserve_line(L.xz(r - T * 0.5 - 3.6, float(span[0])), inner, 3.6)
				# the walking line up the stair (its centre over every chord, then the landing)
				var zc := float(sspec["z0"]) + (STAIR_W + 0.6) * 0.5
				var run_end := hl - (STAIR_W if si == stair_chords - 1 else 0.0)
				var o := Vector3(m.x, base, m.y)
				if si == 0:
					stair_path = PackedVector3Array()
					var ap := SettlementLayout.world(o, yaw_out(bm), Vector3(-hl - 6.0, 0, zc))
					stair_path.append(Vector3(ap.x, ground(ap.x, ap.z), ap.z))
					stair_path.append(SettlementLayout.world(o, yaw_out(bm), Vector3(-hl + 0.4, 0, zc)))
				stair_path.append(SettlementLayout.world(o + Vector3(0, y1, 0), yaw_out(bm), Vector3(run_end, 0, zc)))
				if si == stair_chords - 1:
					spec["gap"] = [snappedf(hl - STAIR_W, 0.1), snappedf(hl, 0.1)]
					stair_path.append(SettlementLayout.world(o + Vector3(0, y1, 0), yaw_out(bm), Vector3(hl - STAIR_W * 0.5, 0, zc)))
					var top_p := SettlementLayout.world(Vector3(m.x, top, m.y), yaw_out(bm), Vector3(hl - STAIR_W * 0.5, 0, T * 0.5 - 2.0))
					stair_path.append(top_p)
					plan.data.get_or_add("wall_stairs", []).append({"wall": wall_id, "foot": stair_path[0], "top": top_p, "path": stair_path,
						"bearing": float(span[0])})
			plan.add(&"city_wall", Vector3(m.x, base, m.y), yaw_out(bm), spec, 2, EkWalls.arch_of(&"city_wall", spec), length * 0.5 + 2.0)
			plan.reserve(m.x, m.y, T * 0.5 + 1.5)
			if i_global % 3 == 0:
				walk.append(p3(r, bm, top))
			i_global += 1
		# bastions along the span (clear of the gatehouses)
		var span_len := RingLayout.arc_len(float(span[1]) - float(span[0]), r)
		var nt := int((span_len - 60.0) / tower_step)
		for k in nt:
			var b := lerpf(float(span[0]), float(span[1]), (k + 1.0) / (nt + 1.0))
			var tp := L.xz(r, b)
			var lo := ground(tp.x, tp.y)
			var tspec := {"S": 14.0 if wall_id == &"outer_wall" else 11.0, "H": H, "T": T, "out": 5.0 if wall_id == &"outer_wall" else 3.5,
				"top": 8.0 if wall_id == &"outer_wall" else 6.0, "roof": true, "bottom": snappedf(minf(lo - base - 2.0, -1.5), 0.5), "v": k % 2}
			if not cam.ok(tp.x, tp.y, 10.0, top + float(tspec["top"]) + 8.0):
				tspec["roof"] = false
			plan.add(&"wall_tower", Vector3(tp.x, base, tp.y), yaw_out(b), tspec, 2, EkWalls.arch_of(&"wall_tower", tspec), 12.0)
			plan.reserve(tp.x, tp.y, T * 0.5 + 5.0)
			# guards on the bastion tops
			plan.anchor(&"guard_post", SettlementLayout.world(Vector3(tp.x, top + float(tspec["top"]), tp.y), yaw_out(b), Vector3(0, 0, -T * 0.5 - 2.0)),
					yaw_out(b), {"tags": [String(wall_id), "bastion"]})
	# gatehouses
	for g in gates:
		var b := wrapf(float(g["bearing"]), -180.0, 180.0)
		var gp := L.xz(r, b)
		var gspec := {"W": float(gate[0]), "Wt": float(gate[1]), "D": float(gate[2]), "Ho": float(gate[3]), "H": H, "T": T,
			"bottom": snappedf(minf(ground(gp.x, gp.y) - base - 2.0, -1.5), 0.5), "v": 0}
		plan.add(&"great_gate", Vector3(gp.x, base, gp.y), yaw_out(b), gspec, 2, EkWalls.arch_of(&"great_gate", gspec), float(gate[2]))
		plan.reserve(gp.x, gp.y, gate_half)
		var y := base
		var gy := ground(gp.x, gp.y)
		var D := float(gate[2])
		var gid := String(g.get("id", ""))
		for sx: float in [-1.0, 1.0]:
			# guards outside and inside the passage, and on the gate hall terrace
			plan.anchor(&"guard_post", SettlementLayout.world(Vector3(gp.x, gy, gp.y), yaw_out(b), Vector3(sx * (float(gate[0]) * 0.5 + 1.8), 0, -D * 0.5 - 4.0)),
					yaw_out(b), {"tags": [String(wall_id), "gate", gid]})
			plan.anchor(&"guard_post", SettlementLayout.world(Vector3(gp.x, gy, gp.y), yaw_out(b), Vector3(sx * (float(gate[0]) * 0.5 - 1.5), 0, D * 0.5 + 3.0)),
					yaw_in(b), {"tags": [String(wall_id), "gate", gid]})
			plan.anchor(&"guard_post", SettlementLayout.world(Vector3(gp.x, y + H + 6.0, gp.y), yaw_out(b), Vector3(sx * (float(gate[0]) * 0.5 + float(gate[1]) * 0.5), 0, -D * 0.5 + 2.0)),
					yaw_out(b), {"tags": [String(wall_id), "gate", "terrace", gid]})
		if wall_id == &"outer_wall":
			plan.anchor(&"quest_giver", SettlementLayout.world(Vector3(gp.x, gy, gp.y), yaw_out(b), Vector3(float(gate[0]) * 0.5 + 4.0, 0, D * 0.5 + 6.0)),
					yaw_in(b) + PI * 0.5, {"tags": ["gatekeeper", gid]})
		plan.data.get_or_add("gates", []).append({"wall": wall_id, "id": StringName(gid), "bearing": b, "position": Vector3(gp.x, gy, gp.y),
			"outside": p3(r + D * 0.5 + 8.0, b), "inside": p3(r - D * 0.5 - 8.0, b)})
	if walk.size() > 2:
		walk.append(walk[0])
		plan.anchor(&"patrol", walk[0], 0.0, {"points": walk, "loop": true, "tags": [String(wall_id), "wall_walk"]})


# --- tier steps ----------------------------------------------------------------------------------

func _ring_walls() -> void:
	# Middle Ring wall (lower ring 60 -> middle ring 67) and Upper Ring wall (67 -> 86)
	_step_wall(&"middle_wall", h(&"lower_ring"), h(&"middle_ring"), 240.0, 300.0, 2.8, &"crenel")
	_step_wall(&"upper_wall", h(&"middle_ring"), h(&"upper_ring"), 130.0, 180.0, 2.8, &"crenel")
	# the palace podium edge (86 -> 91): a marble balustrade
	_step_wall(&"palace_edge", h(&"upper_ring"), h(&"palace"), 40.0, 76.0, 1.2, &"balustrade")


## Retaining wall chords on the measured face of a tier step between radii r_hi (upper side)
## and r_lo (lower side), interrupted by the avenue ramps, with towers flanking every ramp.
func _step_wall(wall_id: StringName, y_lo: float, y_hi: float, r_hi: float, r_lo: float, P: float, style: StringName) -> void:
	var H := y_hi - y_lo
	var nominal := radius_of(wall_id) if radius_of(wall_id) > 0.0 else (r_hi + r_lo) * 0.5
	var style_at := Callable()
	if wall_id == &"upper_wall":
		style_at = func(bm: float) -> Array:
			return [&"balustrade", 1.2] if RingLayout.in_arc(wrapf(bm, 0.0, 360.0), OVERLOOK) else [style, P]
	var faces := step_wall(ring_spans(nominal, avenue_gaps(RAMP_HALF)), y_lo, y_hi, r_hi, r_lo, nominal, RING_CHORD, P, style, 0, style_at)
	plan.data[StringName("%s_faces" % wall_id)] = faces
	# guard towers flanking the avenue ramps of the Middle / Upper Ring walls
	if wall_id == &"palace_edge":
		return
	for b in avenues:
		for sx: float in [-1.0, 1.0]:
			var tb := b + sx * RingLayout.half_angle((RAMP_HALF + 5.5) * 2.0, nominal)
			var r_f := SettlementLayout.face_r(L, tb, r_hi, r_lo, y_lo + 0.35) + 0.6
			var tp := L.xz(r_f + 1.0, tb)
			var tspec := {"S": 9.0, "H": H + 1.0, "T": 6.0, "out": 1.0, "top": P + 4.5, "roof": true, "bottom": -1.5, "v": int(sx > 0.0)}
			if not cam.ok(tp.x, tp.y, 8.0, y_lo + H + 1.0 + P + 4.5 + 8.0):
				tspec["roof"] = false
			plan.add(&"wall_tower", Vector3(tp.x, y_lo - 1.0, tp.y), yaw_out(tb), tspec, 2, EkWalls.arch_of(&"wall_tower", tspec), 7.0)
			plan.reserve(tp.x, tp.y, 6.0)
			plan.anchor(&"guard_post", Vector3(tp.x, y_lo, tp.y) + Vector3(RingLayout.dir(tb).x, 0, RingLayout.dir(tb).y) * 6.0,
					yaw_out(tb), {"tags": [String(wall_id), "ramp"]})


## Avenue stairs over the Upper Ring ramps and cheek walls along the Middle Ring ramps, with a
## paifang at every ramp head.
func _avenue_steps() -> void:
	for b in avenues:
		var rp := L.ramp_at(b, 200.0)
		var length := float(rp.get("length", 60.0))
		# Upper Ring: 19 m over 60 m -> a grand stair
		var rb := float(L.tier(&"upper_ring").get("r_outer", 150.0))
		var foot := p3(rb + length * 0.5, b, h(&"middle_ring"))
		plan.add(&"grand_stair", foot, yaw_in(b), {"H": h(&"upper_ring") - h(&"middle_ring"), "R": length, "W": 24.0, "half": length * 0.5}, 2, "", 30.0)
		plan.data.get_or_add("stairs", []).append({"bearing": b, "foot": foot, "top": p3(rb - length * 0.5, b, h(&"upper_ring"))})
		var arch_at := p3(rb - length * 0.5 - 6.0, b, h(&"upper_ring"))
		if cam.ok(arch_at.x, arch_at.z, 12.0, arch_at.y + 9.0):
			plan.add(&"gate_arch", arch_at, yaw_in(b), {"span": 12.0, "height": 8.0}, 2, "gate_arch:12:8", 10.0)
		# Middle Ring: 7 m over 60 m -> the terrain ramp between cheek walls
		var rm := float(L.tier(&"middle_ring").get("r_outer", 262.0))
		var mfoot := p3(rm + length * 0.5, b, h(&"lower_ring"))
		plan.add(&"ramp_cheeks", mfoot, yaw_in(b), {"H": h(&"middle_ring") - h(&"lower_ring"), "R": length, "W": 26.0, "half": length * 0.5}, 2, "", 30.0)
		var march := p3(rm - length * 0.5 - 4.0, b, h(&"middle_ring"))
		plan.add(&"gate_arch", march, yaw_in(b), {"span": 12.0, "height": 7.5}, 2, "gate_arch:12:7.5", 10.0)
		for sx: float in [-1.0, 1.0]:
			plan.anchor(&"guard_post", SettlementLayout.world(march, yaw_in(b), Vector3(sx * 9.0, 0, 1.5)), yaw_out(b), {"tags": ["middle_gate"]})
