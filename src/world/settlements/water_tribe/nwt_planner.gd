class_name NwtPlanner
extends RefCounted
## Lays out the Northern Water Tribe from its WorldData ring layout (deterministic, main thread):
## retaining walls on every tier step and the quay, grand stairs over the radial ramps, canal
## walls / bridges / falls / moored canoes, the sea wall with its gate and towers, the harbour
## piers and ships, then (NwtDistricts) the palace, Spirit Oasis, interiors, plazas, markets,
## houses on every tier band, street furniture and the NPC anchors.

const ID := &"northern_water_tribe"
const WALL_CHORD := 12.0
const FACE_IN := 2.6          # wall face this far in front of the tier boundary
const WALL_DEPTH := 5.6       # ... and its body reaches FACE_IN + 3 behind it
const RAMP_HALF := 7.9        # tier walls stop this far from a ramp axis (stair cheek faces)
const FALL_HALF := 7.6        # ... and from a canal fall axis
const MOUTH_HALF := 7.0       # quay wall gap at a harbour canal mouth
const GATE_GAP := 16.0        # edge walls stop this far (radially) from a land gate (its own walls)
## Canal walls stand this far inside the canal edge: the carved bank meets the water ~0.8 m
## outside it and coarse terrain LODs would show the slope above the waterline at the wall foot.
const CANAL_INSET := 0.5

var L: RingLayout
var plan: SettlementPlan
var rng: RandomNumberGenerator
## Tier heights by id.
var th := {}
## Canal records of the city: {id, pts: PackedVector2Array, w, level, bed, tier}.
var canals: Array[Dictionary] = []
## Canal fall records.
var falls: Array[Dictionary] = []
var sea_pts := PackedVector2Array()


func build() -> SettlementPlan:
	plan = SettlementPlan.new(ID, &"water_tribe")
	if not WorldData.has_world_data():
		return plan
	L = RingLayout.from_city(ID)
	if not L.is_valid():
		return plan
	rng = ContentHash.rng(ContentHash.hash_name("nwt_plan"))
	plan.display_name = String(L.record.get("name", "Northern Water Tribe"))
	plan.center = Vector3(L.center.x, 0.0, L.center.y)
	plan.radius = 760.0
	plan.y_range = Vector2(0.0, 70.0)
	for t in L.tiers:
		th[StringName(t["id"])] = float(t["height"])
	for c in WorldData.get_canals():
		if String(c["id"]).begins_with("nwt_"):
			canals.append({"id": c["id"], "pts": c["points"], "w": float(c["width"]), "level": float(c["level"]),
				"bed": float(c["bed"]), "tier": StringName(c.get("tier", &"middle"))})
	falls.assign(L.record.get("canal_falls", []))
	var sw: Dictionary = L.record.get("sea_wall", {})
	for p in sw.get("points", []):
		sea_pts.append(p if p is Vector2 else Vector2(p[0], p[1]))
	_districts()
	_reserve_specials()
	_tier_walls()
	_stairs()
	_canals()
	_sea_wall()
	_harbor()
	NwtDistricts.new(self).build()
	return plan


# --- helpers -------------------------------------------------------------------------------------

func h(tier_id: StringName) -> float:
	return float(th.get(tier_id, 0.0))


func p3(r: float, b: float, y: float) -> Vector3:
	return L.point(r, b, y)


## Yaw whose local -Z faces the ring centre from bearing b.
static func yaw_in(b: float) -> float:
	return RingLayout.yaw_of(b + 180.0)


## Yaw whose local -Z faces outward along bearing b.
static func yaw_out(b: float) -> float:
	return RingLayout.yaw_of(b)


## Yaw whose local -Z faces direction (x, z).
static func yaw_dir(d: Vector2) -> float:
	return atan2(-d.x, -d.y)


func ramp_bearings_at(r_boundary: float) -> Array:
	var out := []
	for rp in L.ramps:
		var b := float(rp["bearing"])
		var lower := L.tier_at(L.xz(r_boundary - 10.0, b).x, L.xz(r_boundary - 10.0, b).y)
		var upper := L.tier_at(L.xz(r_boundary + 10.0, b).x, L.xz(r_boundary + 10.0, b).y)
		if not lower.is_empty() and not upper.is_empty() and lower != upper:
			out.append(b)
	return out


func fall_bearings() -> Array:
	var out := []
	for f in falls:
		var p: Vector3 = f["position"]
		out.append(L.polar(p.x, p.z).y)
	return out


## Splits [b0, b1] minus the gaps ([centre bearing, half width m]) into spans at radius r.
static func spans(b0: float, b1: float, r: float, gaps: Array) -> Array:
	var cuts := []
	for g: Array in gaps:
		var ha := RingLayout.half_angle(float(g[1]) * 2.0, r)
		cuts.append([float(g[0]) - ha, float(g[0]) + ha])
	cuts.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var out := []
	var cur := b0
	for c: Array in cuts:
		if c[1] <= cur or c[0] >= b1:
			continue
		if c[0] > cur:
			out.append([cur, c[0]])
		cur = maxf(cur, c[1])
	if cur < b1:
		out.append([cur, b1])
	return out


## Distance from x/z to the sea wall centre line.
func sea_dist(p: Vector2) -> float:
	var best := INF
	for i in sea_pts.size() - 1:
		best = minf(best, Geometry2D.get_closest_point_to_segment(p, sea_pts[i], sea_pts[i + 1]).distance_to(p))
	return best


## Wall chords along an arc (face at radius rf, facing the centre when `inward`), lower ground
## y_low, top y_top. opts: style, bottom (below y_low), v_seed, depth.
func wall_arc(rf: float, b0: float, b1: float, y_low: float, y_top: float, opts: Dictionary = {}) -> void:
	var len_m := RingLayout.arc_len(b1 - b0, rf)
	if len_m < 1.5:
		return
	var n := maxi(int(ceil(len_m / float(opts.get("chord", WALL_CHORD)))), 1)
	var inward: bool = opts.get("inward", true)
	for i in n:
		var ba := lerpf(b0, b1, float(i) / n)
		var bb := lerpf(b0, b1, float(i + 1) / n)
		var a := L.xz(rf, ba)
		var b := L.xz(rf, bb)
		var m := (a + b) * 0.5
		if sea_dist(m) < 13.0 + float(opts.get("sea_margin", 0.0)):
			continue
		var nrm := (L.center - m).normalized() if inward else (m - L.center).normalized()
		var spec := {"L": snappedf(a.distance_to(b) + 0.05, 0.1), "H": y_top - y_low, "bottom": float(opts.get("bottom", -1.2)),
			"style": opts.get("style", &"tier"), "v": int(ContentHash.hash4(int(m.x * 10.0), int(m.y * 10.0), 3) % 4),
			"depth": float(opts.get("depth", WALL_DEPTH)), "pilaster_end": i == 0 or i == n - 1}
		plan.add(&"tier_wall", Vector3(m.x, y_low, m.y), yaw_dir(nrm), spec, 2, NwtCivic.wall_arch(spec), a.distance_to(b) * 0.5)


## Wall chord between two arbitrary x/z points facing `face` (unit x/z towards the low side).
func wall_line(a: Vector2, b: Vector2, face: Vector2, y_low: float, y_top: float, opts: Dictionary = {}) -> void:
	var n := maxi(int(ceil(a.distance_to(b) / float(opts.get("chord", WALL_CHORD)))), 1)
	for i in n:
		var p0 := a.lerp(b, float(i) / n)
		var p1 := a.lerp(b, float(i + 1) / n)
		var m := (p0 + p1) * 0.5
		if sea_dist(m) < 13.0:
			continue
		var spec := {"L": snappedf(p0.distance_to(p1) + 0.05, 0.1), "H": y_top - y_low, "bottom": float(opts.get("bottom", -1.2)),
			"style": opts.get("style", &"end"), "v": i % 4, "depth": float(opts.get("depth", 3.0)), "pilaster_end": i == 0 or i == n - 1}
		plan.add(&"tier_wall", Vector3(m.x, y_low, m.y), yaw_dir(face), spec, 2, NwtCivic.wall_arch(spec), p0.distance_to(p1) * 0.5)


# --- districts + keep-outs -----------------------------------------------------------------------

func _districts() -> void:
	plan.add_district(&"nwt_harbor", "Harbor Tier", p3(336, 0, h(&"harbor")), 0.0)
	plan.districts.clear()
	for t in L.tiers:
		var mid_r := (float(t["r_inner"]) + float(t["r_outer"])) * 0.5
		var arc: Variant = t.get("arc")
		var span := 360.0 if arc == null else float(arc[1]) - float(arc[0])
		# districts are recorded as circles; tiers are covered by a few circles along the arc
		var n := maxi(int(RingLayout.arc_len(span, mid_r) / 120.0), 1)
		for k in n:
			var b := -span * 0.5 + span * (k + 0.5) / n
			plan.add_district(StringName("nwt_%s" % t["id"]), String(t.get("name", t["id"])), p3(mid_r, b, float(t["height"])),
				maxf(RingLayout.arc_len(span / n, mid_r) * 0.62, (float(t["r_outer"]) - float(t["r_inner"])) * 0.6))
	var palace: Dictionary = L.record.get("palace", {})
	if not palace.is_empty():
		plan.districts.push_front({"id": &"nwt_palace", "name": "Chief's Palace", "center": palace["position"], "radius": float(palace["radius"]) + 20.0})
	var oasis: Dictionary = L.record.get("spirit_oasis", {})
	if not oasis.is_empty():
		plan.districts.push_front({"id": &"nwt_spirit_oasis", "name": "Spirit Oasis", "center": oasis["position"], "radius": float(oasis["radius"])})
	plan.districts.append({"id": &"nwt_sea_wall", "name": "The Great Wall", "center": Vector3(L.center.x, 35.0, L.center.y + 190.0), "radius": 120.0})


func _reserve_specials() -> void:
	# the sea wall
	for i in sea_pts.size() - 1:
		plan.reserve_line(sea_pts[i], sea_pts[i + 1], 16.0)
	# spawn plaza + arrival camera end (water element spawn)
	var sp := WorldData.get_spawn(ElementDefs.Element.WATER)
	if L.tier_at(sp.origin.x, sp.origin.z).size() > 0:
		plan.reserve(sp.origin.x, sp.origin.z, 16.0)
		plan.data["spawn"] = sp.origin
		var f := -sp.basis.z
		plan.data["spawn_yaw"] = yaw_dir(Vector2(f.x, f.z))
	# ferry landing at the harbour quay and its lane to the berth
	for port in WorldData.get_ports():
		if port.get("settlement") == ID:
			var q: Vector3 = port["quay"]
			var bth: Vector3 = port["berth"]
			plan.reserve(q.x, q.z, 14.0)
			plan.reserve_line(Vector2(q.x, q.z), Vector2(bth.x, bth.z), 12.0)
			plan.data["ferry_quay"] = q
	# ramps: stair strips + landings
	for rb in [372.0, 470.0, 562.0]:
		for b in ramp_bearings_at(rb):
			plan.reserve_line(L.xz(rb - 30.0, b), L.xz(rb + 32.0, b), 10.0)
	# canals: water + walls + a walkway on both sides
	for c in canals:
		var pts: PackedVector2Array = c["pts"]
		for i in pts.size() - 1:
			plan.reserve_line(pts[i], pts[i + 1], float(c["w"]) * 0.5 + 6.5)
	# palace platform + forecourt, Spirit Oasis
	var palace: Dictionary = L.record.get("palace", {})
	if not palace.is_empty():
		var pp: Vector3 = palace["position"]
		plan.reserve(pp.x, pp.z, float(palace["radius"]) + 16.0)
		var front := L.polar(pp.x, pp.z)
		plan.reserve_line(L.xz(front.x - 70.0, front.y), Vector2(pp.x, pp.z), 18.0)
	var oasis: Dictionary = L.record.get("spirit_oasis", {})
	if not oasis.is_empty():
		var op: Vector3 = oasis["position"]
		plan.reserve(op.x, op.z, float(oasis["radius"]) + 5.0)


# --- retaining walls -----------------------------------------------------------------------------

func _tier_walls() -> void:
	var fb := fall_bearings()
	# quay (bay edge of the harbour tier)
	var hb: Dictionary = L.tier(&"harbor")
	var harbor: Dictionary = L.record.get("harbor", {})
	var water := float(harbor.get("water_level", 0.0))
	var floor_y := float(harbor.get("floor", -10.0))
	var arc_h: Array = hb["arc"]
	var gaps := []
	for b in fb:
		gaps.append([b, MOUTH_HALF])
	for s: Array in spans(float(arc_h[0]), float(arc_h[1]), float(hb["r_inner"]), gaps):
		wall_arc(float(hb["r_inner"]) - FACE_IN, s[0], s[1], water, h(&"harbor"), {"style": &"quay", "bottom": floor_y - water - 0.8})
	# tier steps
	for k in range(1, L.tiers.size()):
		var lo: Dictionary = L.tiers[k - 1]
		var up: Dictionary = L.tiers[k]
		var rb := float(up["r_inner"])
		var a_lo: Variant = lo.get("arc")
		var a_up: Variant = up.get("arc")
		var b0 := maxf(-180.0 if a_lo == null else float(a_lo[0]), -180.0 if a_up == null else float(a_up[0]))
		var b1 := minf(180.0 if a_lo == null else float(a_lo[1]), 180.0 if a_up == null else float(a_up[1]))
		var g := []
		for b in ramp_bearings_at(rb):
			g.append([b, RAMP_HALF])
		if StringName(lo["id"]) == &"harbor":
			for b in fb:
				g.append([b, FALL_HALF])
		for s: Array in spans(b0, b1, rb, g):
			wall_arc(rb - FACE_IN, s[0], s[1], float(lo["height"]), float(up["height"]))
			_wall_towers(rb, s[0], s[1], float(lo["height"]), float(up["height"]))
		# the ends of the upper tier's arc: edge walls along the radial cut
		if a_up != null:
			for side: float in [-1.0, 1.0]:
				var be: float = float(a_up[1]) if side > 0.0 else float(a_up[0])
				_edge_radial(be, side, float(up["r_inner"]) + FACE_IN + 3.0, float(up["r_outer"]) - 1.0, float(up["height"]))
	# back wall of the palace tier (free-standing city wall with towers)
	var pt: Dictionary = L.tier(&"palace")
	if not pt.is_empty():
		var arc_p: Array = pt["arc"]
		var rr := float(pt["r_outer"]) + 3.0
		wall_arc(rr, float(arc_p[0]) + 1.0, float(arc_p[1]) - 1.0, h(&"palace"), h(&"palace") + 9.0, {"style": &"end", "depth": 3.0, "chord": 14.0})
		var nt := 6
		for k in nt + 1:
			var b := lerpf(float(arc_p[0]) + 1.0, float(arc_p[1]) - 1.0, float(k) / nt)
			add_tower(p3(rr + 1.5, b, h(&"palace")), yaw_in(b), 4.0, 17.0 + (k % 2) * 4.0, 13.0, -1.5)


## A round tower with an ice spire (city_tower archetype keyed by its rounded dimensions).
func add_tower(pos: Vector3, yaw: float, r: float, height: float, spire: float, base: float) -> void:
	var spec := {"r": snappedf(r, 0.5), "h": roundf(height), "spire": roundf(spire), "base": snappedf(base, 0.5)}
	plan.add(&"city_tower", pos, yaw, spec, 2, "city_tower:%d:%d:%d:%d" % [int(spec["r"] * 10.0), int(spec["h"]), int(spec["spire"]), int(spec["base"] * 10.0)], r + 1.0)
	plan.reserve(pos.x, pos.z, r + 1.5)


## Towers standing against a tier wall every ~110 m, rising above the upper tier.
func _wall_towers(rb: float, b0: float, b1: float, y_low: float, y_top: float) -> void:
	var length := RingLayout.arc_len(b1 - b0, rb)
	var n := int(length / 110.0)
	if n < 1:
		return
	for k in n:
		var b := lerpf(b0, b1, (k + 0.5) / n)
		var pos := p3(rb - FACE_IN - 2.4, b, y_low)
		if sea_dist(Vector2(pos.x, pos.z)) < 20.0 or not plan.is_free(pos.x, pos.z, 4.0):
			continue
		var hh := y_top - y_low + 9.0 + float(ContentHash.hash4(int(b * 10.0), int(rb)) % 3) * 3.0
		add_tower(pos, yaw_in(b), 3.6, hh, 12.0 + float(ContentHash.hash4(int(b * 7.0)) % 3) * 2.0, -1.5)


## Edge wall along a radial line at bearing be (tier arc end), from r0 to r1 at tier height y.
## The far side (side = +1: larger bearings) is sampled: the wall faces the lower side.
## Not across a land gate: the gatehouses (NwtDistricts) stand on these cuts, and the low parapet
## used to run straight through their passage - nobody could walk through the east / west gates
## (wave 4 bug hunt). The gap matches the gatehouse's own wall gap (+-GATE_GAP).
func _edge_radial(be: float, side: float, r0: float, r1: float, y: float) -> void:
	var runs: Array = [[r0, r1]]
	for g: Dictionary in L.record.get("gates", []):
		var gp: Vector3 = g["position"]
		var pr := L.polar(gp.x, gp.z)
		if absf(RingLayout.bdiff(pr.y, be)) > 2.0:
			continue
		var cut: Array = []
		for run: Array in runs:
			if float(run[1]) <= pr.x - GATE_GAP or float(run[0]) >= pr.x + GATE_GAP:
				cut.append(run)
				continue
			if pr.x - GATE_GAP > float(run[0]):
				cut.append([float(run[0]), pr.x - GATE_GAP])
			if pr.x + GATE_GAP < float(run[1]):
				cut.append([pr.x + GATE_GAP, float(run[1])])
		runs = cut
	for run: Array in runs:
		if float(run[1]) - float(run[0]) > 1.0:
			_edge_radial_run(be, side, float(run[0]), float(run[1]), y)


func _edge_radial_run(be: float, side: float, r0: float, r1: float, y: float) -> void:
	var step := WALL_CHORD
	var n := maxi(int(ceil((r1 - r0) / step)), 1)
	var tangent := Vector2(cos(deg_to_rad(be)), sin(deg_to_rad(be))) * side
	for i in n:
		var ra := lerpf(r0, r1, float(i) / n)
		var rb2 := lerpf(r0, r1, float(i + 1) / n)
		var a := L.xz(ra, be) + tangent * 1.5
		var b := L.xz(rb2, be) + tangent * 1.5
		var m := (a + b) * 0.5
		var outside := WorldData.get_height(m.x + tangent.x * 8.0, m.y + tangent.y * 8.0)
		if absf(outside - y) < 1.2:
			# level ground beyond: a low parapet wall
			wall_line(a, b, -tangent, y, y + 1.3, {"style": &"end", "depth": 1.0, "chord": 20.0})
		elif outside < y:
			wall_line(a, b, tangent, maxf(outside, -2.0), y, {"style": &"end", "depth": 3.0, "bottom": -1.5})
		else:
			wall_line(a - tangent * 3.0, b - tangent * 3.0, -tangent, y, outside, {"style": &"end", "depth": 3.0})


# --- grand stairs --------------------------------------------------------------------------------

func _stairs() -> void:
	for k in range(1, L.tiers.size()):
		var lo: Dictionary = L.tiers[k - 1]
		var up: Dictionary = L.tiers[k]
		var rb := float(up["r_inner"])
		for b in ramp_bearings_at(rb):
			var rp := L.ramp_at(b, rb)
			var length := float(rp.get("length", 48.0))
			var width := float(rp.get("width", 16.0))
			var y0 := float(lo["height"])
			var y1 := float(up["height"])
			var foot := p3(rb - length * 0.5, b, y0)
			plan.add(&"grand_stair", foot, yaw_out(b), {"H": y1 - y0, "R": length, "W": width, "half": length * 0.5}, 2, "", width)
			plan.data.get_or_add("stairs", []).append({"bearing": b, "r": rb, "foot": foot, "top": p3(rb + length * 0.5, b, y1)})
			# guards at the top of every stair
			for sx: float in [-1.0, 1.0]:
				var gp := L.xz(rb + length * 0.5 + 3.0, b + sx * RingLayout.half_angle(width + 3.0, rb + length * 0.5))
				plan.anchor(&"guard_post", Vector3(gp.x, y1, gp.y), yaw_in(b), {"tags": ["stair"]})


# --- canals --------------------------------------------------------------------------------------

func _canals() -> void:
	for c in canals:
		var pts: PackedVector2Array = c["pts"]
		var w := float(c["w"])
		var level := float(c["level"])
		var ground := h(c["tier"])
		var bed := float(c["bed"])
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var d := (b - a).normalized()
			var perp := Vector2(-d.y, d.x)
			var seg := a.distance_to(b)
			var n := maxi(int(ceil(seg / 10.0)), 1)
			for side: float in [-1.0, 1.0]:
				for k in n:
					var q0 := a.lerp(b, float(k) / n) + perp * side * (w * 0.5 - CANAL_INSET)
					var q1 := a.lerp(b, float(k + 1) / n) + perp * side * (w * 0.5 - CANAL_INSET)
					var m := (q0 + q1) * 0.5
					if _in_other_canal(m, c["id"], 0.8) or _near_fall(m, 7.5) or L.polar(m.x, m.y).x < float(L.tier(&"harbor")["r_inner"]) + 0.5:
						continue
					var spec := {"L": snappedf(q0.distance_to(q1) + 0.08, 0.1), "H": ground - level, "bottom": bed - level - 0.8,
						"style": &"canal", "v": k % 2, "depth": 2.5}
					plan.add(&"tier_wall", Vector3(m.x, level, m.y), yaw_dir(-perp * side), spec, 1, NwtCivic.wall_arch(spec), seg / n * 0.5)
		# end walls where a canal stops in the tier (not at a fall, the bay or another canal)
		for end in [0, pts.size() - 1]:
			var e := pts[end]
			var into := (pts[1] - pts[0]).normalized() if end == 0 else (pts[end - 1] - pts[end]).normalized()
			if _near_fall(e, 8.0) or L.polar(e.x, e.y).x < float(L.tier(&"harbor")["r_inner"]) + 2.0 or _in_other_canal(e - into * 2.0, c["id"], 0.0):
				continue
			var spec2 := {"L": w + 0.6, "H": ground - level, "bottom": bed - level - 0.8, "style": &"canal", "v": 1, "depth": 2.5}
			plan.add(&"tier_wall", Vector3(e.x, level, e.y), yaw_dir(into), spec2, 1, NwtCivic.wall_arch(spec2), w * 0.5)
			plan.reserve(e.x, e.y, w * 0.5 + 3.0)
	# falls
	for f in falls:
		var p: Vector3 = f["position"]
		var b := L.polar(p.x, p.z).y
		plan.add(&"canal_fall", Vector3(p.x, float(f["top"]), p.z), yaw_in(b), {"W": float(f["width"]), "drop": float(f["top"]) - float(f["bottom"]),
			"H": h(&"middle") - float(f["top"]), "bed": 3.0}, 2, "", 8.0)
	_bridges()
	for c in canals:
		_canal_boats(c)


func _in_other_canal(p: Vector2, self_id: StringName, margin: float) -> bool:
	for c in canals:
		if c["id"] == self_id:
			continue
		var pts: PackedVector2Array = c["pts"]
		for i in pts.size() - 1:
			if Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1]).distance_to(p) < float(c["w"]) * 0.5 + margin:
				return true
	return false


func _near_fall(p: Vector2, r: float) -> bool:
	for f in falls:
		var q: Vector3 = f["position"]
		if Vector2(q.x, q.z).distance_to(p) < r:
			return true
	return false


func _bridges() -> void:
	var ring: Dictionary = {}
	for c in canals:
		if String(c["id"]).ends_with("ring"):
			ring = c
	var fb := fall_bearings()
	var ground := h(&"middle")
	if not ring.is_empty():
		var pts: PackedVector2Array = ring["pts"]
		var pr := L.polar(pts[0].x, pts[0].y)
		var rr := pr.x
		var b_lo := minf(pr.y, L.polar(pts[pts.size() - 1].x, pts[pts.size() - 1].y).y)
		var b_hi := maxf(pr.y, L.polar(pts[pts.size() - 1].x, pts[pts.size() - 1].y).y)
		var list := [0.0]
		for b in ramp_bearings_at(470.0):
			if not list.has(b):
				list.append(b)
		var bb := -88.0
		while bb <= 88.0:
			var ok := true
			for x in list + fb:
				if absf(RingLayout.bdiff(bb, float(x))) < 6.0:
					ok = false
			if ok:
				list.append(bb)
			bb += 11.0
		for b in list:
			if b < b_lo + 3.0 or b > b_hi - 3.0:
				continue
			var wide := absf(float(b)) < 0.1 or ramp_bearings_at(470.0).has(b)
			var p := p3(rr, b, ground)
			plan.add(&"canal_bridge", p, yaw_out(b), {"span": float(ring["w"]), "width": 8.0 if wide else 5.0, "hump": 0.9, "v": int(absf(b)) % 2},
					1, "canal_bridge:%d:%d" % [int(wide), int(absf(b)) % 2], 8.0)
			plan.data.get_or_add("bridges", []).append(p)
	# radial canals: bridges across them (tangential crossings)
	for c in canals:
		if String(c["id"]).ends_with("ring"):
			continue
		var pts: PackedVector2Array = c["pts"]
		var a := L.polar(pts[0].x, pts[0].y)
		var e := L.polar(pts[pts.size() - 1].x, pts[pts.size() - 1].y)
		var b := (a.y + e.y) * 0.5
		var tier: StringName = c["tier"]
		var radii: Array = [376.5, 401.0] if tier == &"middle" else [307.0, 341.0]
		for r in radii:
			var p := p3(r, b, h(tier))
			plan.add(&"canal_bridge", p, RingLayout.yaw_of(b + 90.0), {"span": float(c["w"]), "width": 5.0, "hump": 0.6 if tier == &"middle" else 0.9, "v": 0},
					1, "canal_bridge:r:%d" % int(tier == &"middle"), 7.0)
			plan.data.get_or_add("bridges", []).append(p)


## Canoes moored along the canal walls.
func _canal_boats(c: Dictionary) -> void:
	var pts: PackedVector2Array = c["pts"]
	var w := float(c["w"])
	var level := float(c["level"])
	var crng := ContentHash.rng(ContentHash.hash_name(String(c["id"])))
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var seg := a.distance_to(b)
		var d := (b - a).normalized()
		var perp := Vector2(-d.y, d.x)
		var t := crng.randf_range(4.0, 12.0)
		while t < seg - 4.0:
			var side := 1.0 if crng.randf() < 0.5 else -1.0
			var q := a + d * t + perp * side * (w * 0.5 - CANAL_INSET - 0.75)
			if not _near_fall(q, 14.0) and not _in_other_canal(q, c["id"], 3.0) and not _near_bridge(q, 8.0):
				plan.add(&"canoe", Vector3(q.x, level, q.y), yaw_dir(d if crng.randf() < 0.5 else -d), {"v": crng.randi() % 3}, 1,
						"canoe:%d" % (crng.randi() % 3), 2.5)
				plan.anchor(&"boat", Vector3(q.x, level, q.y), yaw_dir(d), {"tags": ["canal"]})
			t += crng.randf_range(14.0, 30.0)


func _near_bridge(p: Vector2, r: float) -> bool:
	for q: Vector3 in plan.data.get("bridges", []):
		if Vector2(q.x, q.z).distance_to(p) < r:
			return true
	return false


# --- sea wall ------------------------------------------------------------------------------------

func _sea_wall() -> void:
	var sw: Dictionary = L.record.get("sea_wall", {})
	if sea_pts.size() < 2:
		return
	var top := float(sw.get("base", -7.0)) + float(sw.get("height", 42.0))
	var base := float(sw.get("base", -7.0))
	var gate: Dictionary = sw.get("gate", {})
	var gc: Vector2 = gate.get("center", Vector2.INF) if gate.get("center") is Vector2 else Vector2.INF
	var gw := float(gate.get("width", 46.0))
	var gate_clear := gw * 0.5 + 18.0
	var chord := 20.0
	for i in sea_pts.size() - 1:
		var a := sea_pts[i]
		var b := sea_pts[i + 1]
		var d := (b - a).normalized()
		var seg := a.distance_to(b)
		var t0 := 0.0
		var t1 := seg
		if gc.is_finite():
			if a.distance_to(gc) < 1.0:
				t0 = gate_clear
			if b.distance_to(gc) < 1.0:
				t1 = seg - gate_clear
		var n := maxi(int(ceil((t1 - t0) / chord)), 1)
		var out := Vector2(-d.y, d.x)
		if out.dot((a + b) * 0.5 - L.center) < 0.0:
			out = -out
		for k in n:
			var p0 := a + d * lerpf(t0, t1, float(k) / n)
			var p1 := a + d * lerpf(t0, t1, float(k + 1) / n)
			var m := (p0 + p1) * 0.5
			var spec := {"L": snappedf(p0.distance_to(p1) + 0.1, 0.1), "top": top, "base": base, "v": k % 3}
			plan.add(&"sea_wall", Vector3(m.x, 0.0, m.y), yaw_dir(out), spec, 2, "sea_wall:%d:%d" % [int(spec["L"] * 10.0), k % 3], 14.0)
	# towers at the bends and ends
	for i in sea_pts.size():
		var p := sea_pts[i]
		if gc.is_finite() and p.distance_to(gc) < 1.0:
			continue
		var end := i == 0 or i == sea_pts.size() - 1
		plan.add(&"sea_tower", Vector3(p.x, 0.0, p.y), 0.0, {"r": 9.0 if end else 7.5, "base": base, "h": top + (14.0 if end else 9.0),
			"spire": 18.0 if end else 0.0}, 2, "sea_tower:%d" % int(end), 10.0)
		plan.anchor(&"guard_post", Vector3(p.x, top, p.y) + Vector3(0, 0, 0), 0.0, {"tags": ["sea_wall"]})
	if gc.is_finite():
		var dd := (sea_pts[mini(3, sea_pts.size() - 1)] - sea_pts[1]).normalized()
		var outg := Vector2(-dd.y, dd.x)
		if outg.dot(gc - L.center) < 0.0:
			outg = -outg
		plan.add(&"sea_gate", Vector3(gc.x, 0.0, gc.y), yaw_dir(outg), {"W": gw, "top": top, "base": base}, 2, "", 40.0)
		for sx: float in [-1.0, 1.0]:
			var gp := gc + dd * sx * (gw * 0.5 + 9.0)
			plan.anchor(&"guard_post", Vector3(gp.x, top, gp.y), yaw_dir(outg), {"tags": ["sea_gate"]})
	# patrol along the wall walk
	var walk := PackedVector3Array()
	for p in sea_pts:
		walk.append(Vector3(p.x, top, p.y))
	plan.anchor(&"patrol", walk[0], 0.0, {"points": walk, "loop": false, "tags": ["sea_wall"]})


# --- harbour -------------------------------------------------------------------------------------

func _harbor() -> void:
	var hb: Dictionary = L.tier(&"harbor")
	var r_in := float(hb["r_inner"])
	var deck := h(&"harbor")
	var harbor: Dictionary = L.record.get("harbor", {})
	var depth := deck - float(harbor.get("floor", -10.0))
	var fb := fall_bearings()
	var bearings := [-102.0, -88.0, -62.0, -46.0, -22.0, 0.0, 16.0, 44.0, 62.0, 88.0, 102.0]
	var hrng := ContentHash.rng(ContentHash.hash_name("nwt_harbor"))
	var ship_i := 0
	for b in bearings:
		var bad := false
		for x in fb:
			if absf(RingLayout.bdiff(b, x)) < 6.0:
				bad = true
		var base := L.xz(r_in - FACE_IN + 0.2, b)
		if bad or sea_dist(base) < 30.0 or not plan.is_free(base.x, base.y, 4.0):
			continue
		var length := 30.0 if absf(b) < 0.1 else hrng.randf_range(20.0, 30.0)
		var width := 7.0 if absf(b) < 0.1 else hrng.randf_range(4.0, 5.0)
		var head := 14.0 if absf(b) < 0.1 or int(absf(b)) % 3 == 0 else 0.0
		var tip := L.xz(r_in - FACE_IN - length, b)
		plan.reserve_line(base, tip, width * 0.5 + 1.0)
		plan.add(&"pier", Vector3(base.x, deck, base.y), yaw_in(b), {"L": length, "W": width, "depth": depth, "head": head}, 1, "", length * 0.5)
		plan.anchor(&"fisher", Vector3(tip.x, deck, tip.y), yaw_in(b), {"tags": ["pier"]})
		# a ship alongside every other pier, canoes along the rest
		var dir := (tip - base).normalized()
		var side := Vector2(-dir.y, dir.x) * (1.0 if hrng.randf() < 0.5 else -1.0)
		if ship_i < 5 and absf(b) > 0.1 and int(absf(b)) % 2 == 0:
			var sc := base + dir * (length * 0.55) + side * (width * 0.5 + 4.2)
			plan.add(&"ship", Vector3(sc.x, 0.0, sc.y), yaw_dir(dir), {"v": ship_i % 2}, 2, "ship:%d" % (ship_i % 2), 12.0)
			plan.anchor(&"boat", Vector3(sc.x, 1.4, sc.y), yaw_dir(dir), {"tags": ["ship"]})
			ship_i += 1
		else:
			for k in 2:
				var cp := base + dir * (6.0 + k * 9.0) + side * (width * 0.5 + 1.0)
				plan.add(&"canoe", Vector3(cp.x, 0.0, cp.y), yaw_dir(dir), {"v": (k + ship_i) % 3}, 1, "canoe:%d" % ((k + ship_i) % 3), 2.5)
	# canoes along the quay
	var b2 := -110.0
	while b2 < 110.0:
		var q := L.xz(r_in - FACE_IN - 1.2, b2)
		if plan.is_free(q.x, q.y, 2.5) and sea_dist(q) > 16.0:
			var tdir := Vector2(cos(deg_to_rad(b2)), sin(deg_to_rad(b2)))
			plan.add(&"canoe", Vector3(q.x, 0.0, q.y), yaw_dir(tdir), {"v": int(absf(b2)) % 3}, 1, "canoe:%d" % (int(absf(b2)) % 3), 2.5)
			plan.reserve(q.x, q.y, 2.5)
		b2 += hrng.randf_range(6.0, 14.0)
