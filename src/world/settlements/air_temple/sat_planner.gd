class_name SatPlanner
extends RefCounted
## Lays out the Southern Air Temple from its WorldData ring layout (deterministic, main thread):
## the 20 m retaining walls of every tier step (heights read from the terrain, so the 40 m drop
## of the courtyard over the open south court is faced too), grand stairs on the radial ramps,
## the balustrade along the cliff edge of the landing ring and around the pinnacles, the two
## suspended bridges (claimed from LandmarkProvider, rebuilt in Air Nomad style in segments),
## then (SatDistricts) the Great Spire, the sanctuary, courtyard, terraces, landing and the NPC
## anchors.
##
## The air element's arrival cinematic flies low past the Sanctum (WorldData arrival camera):
## `cam_ok()` keeps every piece that rises more than 1.5 m clear of that flight path.

const ID := &"southern_air_temple"
const FACE_OUT := 2.4         # wall face this far beyond the tier boundary (towards the lower tier)
const WALL_DEPTH := 5.6       # ... and its body reaches FACE_OUT + 3.2 behind it
const RAMP_HALF := 6.2        # walls stop this far from a ramp axis (stair cheek walls)
const CHORD := 11.0
const BRIDGE_SEG := 24.0
const CLAIMS: Array[StringName] = [&"at_bridge_west", &"at_bridge_east", &"at_meditation_ledge"]

var L: RingLayout
var plan: SettlementPlan
var rng: RandomNumberGenerator
## Tier boundaries [r, upper tier id] (inner first).
var steps: Array = []
## Ramp records actually present in the terrain: [bearing, boundary r, y_low, y_high].
var ramps: Array = []
## Arrival camera samples (world) for the clearance check.
var cam_path := PackedVector3Array()
## Bridge abutments (world, the temple end) and pinnacle records.
var bridge_ends: Array[Vector3] = []
var pinnacles: Array[Dictionary] = []


func build() -> SettlementPlan:
	plan = SettlementPlan.new(ID, &"air_nomads")
	if not WorldData.has_world_data():
		return plan
	L = RingLayout.from_city(ID)
	if not L.is_valid():
		return plan
	rng = ContentHash.rng(ContentHash.hash_name("sat_plan"))
	plan.display_name = String(L.record.get("name", "Southern Air Temple"))
	plan.center = Vector3(L.center.x, float(L.record.get("center", Vector3.ZERO).y), L.center.y)
	plan.radius = 240.0
	plan.cell_size = 96.0
	plan.y_range = Vector2(0.0, 135.0)
	for p in L.record.get("pinnacles", []):
		pinnacles.append(p)
	_camera_path()
	_find_ramps()
	_districts()
	_reserve_specials()
	_walls()
	_stairs()
	_cliff_edges()
	_bridges()
	SatDistricts.new(self).build()
	_tag_tutorial_site()
	plan.data["claims"] = CLAIMS.duplicate()
	var excl: Array = []
	for p in pinnacles:
		excl.append([p["position"], float(p["radius"]) + 4.0, ContentExclusions.TAG_ALL])
	plan.data["exclusions"] = excl
	return plan


# --- helpers -------------------------------------------------------------------------------------

func p3(r: float, b: float, y: float = NAN) -> Vector3:
	return L.point(r, b, y)


func ground(x: float, z: float) -> float:
	return WorldData.get_height(x, z)


static func yaw_in(b: float) -> float:
	return RingLayout.yaw_of(b + 180.0)


static func yaw_out(b: float) -> float:
	return RingLayout.yaw_of(b)


static func yaw_dir(d: Vector2) -> float:
	return atan2(-d.x, -d.y)


## Height of the flat tier at (r, b) sampled a little away from steps (terrain truth).
func tier_y(r: float, b: float) -> float:
	var p := L.xz(r, b)
	return snappedf(ground(p.x, p.y), 0.5)


## Splits [b0, b1] minus the gaps ([centre bearing, half width m]) into spans at radius r.
static func spans(b0: float, b1: float, r: float, gaps: Array) -> Array:
	return NwtPlanner.spans(b0, b1, r, gaps)


## Arrival flight of the air element (same cubic Bezier as ArrivalCinematic._build_curve).
func _camera_path() -> void:
	var cam := WorldData.get_arrival_camera(ElementDefs.Element.AIR)
	if cam.is_empty():
		return
	var p0: Vector3 = (cam["start"] as Transform3D).origin
	var p3v: Vector3 = (cam["end"] as Transform3D).origin
	var span := p3v - p0
	var flat := Vector3(span.x, 0.0, span.z)
	var c1 := p0 + flat * 0.42 + Vector3.UP * maxf(0.0, -span.y) * 0.04
	var c2 := p3v - flat.normalized() * minf(flat.length() * 0.22, 120.0) + Vector3.UP * minf(absf(span.y) * 0.18, 40.0)
	for i in 121:
		var e := float(i) / 120.0
		var u := 1.0 - e
		cam_path.append(p0 * (u * u * u) + c1 * (3.0 * u * u * e) + c2 * (3.0 * u * e * e) + p3v * (e * e * e))


## True when a piece (footprint radius `rad` at x/z, rising to `top`) stays clear of the
## arrival flight: 6 m sideways or 6 m below. Pieces lower than 1.5 m over their ground pass.
func cam_ok(x: float, z: float, rad: float, top: float, base: float = NAN) -> bool:
	if is_nan(base):
		base = ground(x, z)
	if top - base < 1.5:
		return true
	for p in cam_path:
		var d := Vector2(p.x - x, p.z - z).length()
		if d < rad + 6.0 and p.y < top + 6.0:
			return false
	return true


## Flight clearance of a tall round structure described by a radius profile: [[y0, y1, radius],
## ...] (world heights). Each camera sample at height y must stay 4 m outside the radius there.
func cam_ok_profile(x: float, z: float, profile: Array) -> bool:
	for p in cam_path:
		var d := Vector2(p.x - x, p.z - z).length()
		for seg: Array in profile:
			if p.y >= float(seg[0]) - 4.0 and p.y <= float(seg[1]) + 4.0 and d < float(seg[2]) + 4.0:
				return false
	return true


## Adds a piece only when its footprint is free and it clears the flight; reserves it.
## `cam_r` (default r) is the radius checked against the flight (e.g. a spire's eaves).
func place(kind: StringName, pos: Vector3, yaw: float, spec: Dictionary, lod: int, arch: String, r: float, top: float,
		cam_r: float = -1.0) -> Dictionary:
	if not plan.is_free(pos.x, pos.z, r) or not cam_ok(pos.x, pos.z, r if cam_r < 0.0 else cam_r, top, pos.y):
		return {}
	plan.reserve(pos.x, pos.z, r)
	return plan.add(kind, pos, yaw, spec, lod, arch, r)


func _find_ramps() -> void:
	for rp in L.ramps:
		# wrapped like the wall spans (-180..180): the 220 ramp got no gap in the courtyard and
		# sanctum walls, which ran straight across its stairs (wave 4 bug hunt)
		var b := wrapf(float(rp["bearing"]), -180.0, 180.0)
		for rb: float in [46.0, 112.0, 162.0]:
			var lo := tier_y(rb + 20.0, b)
			var hi := tier_y(rb - 20.0, b)
			var mid := tier_y(rb, b)
			# a ramp: the boundary itself sits half way between the two tiers
			if hi - lo > 10.0 and absf(mid - (lo + hi) * 0.5) < 3.0:
				ramps.append([b, rb, lo, hi])


func ramp_gaps(rb: float) -> Array:
	var out := []
	for r: Array in ramps:
		if absf(float(r[1]) - rb) < 1.0:
			out.append([float(r[0]), RAMP_HALF])
	return out


# --- districts + keep-outs -----------------------------------------------------------------------

func _districts() -> void:
	var c := Vector3(L.center.x, 0.0, L.center.y)
	plan.add_district(&"sat_sanctum", "Sanctum Spire", p3(0, 0, 822.0), 50.0)
	var sanct := p3(66.0, 180.0, 802.0)
	plan.add_district(&"sat_sanctuary", "The Sanctuary", sanct, 24.0)
	var court := WorldData.get_poi(&"at_airball_courts")
	if not court.is_empty():
		plan.add_district(&"sat_airball_court", "Airball Courts", court["position"], 24.0)
	var stables := WorldData.get_poi(&"at_bison_stables")
	if not stables.is_empty():
		plan.add_district(&"sat_bison_stables", "Sky Bison Stables", stables["position"], 40.0)
	for k in 8:
		var b := -180.0 + 45.0 * k + 22.5
		plan.add_district(&"sat_courtyard", "Temple Courtyard", p3(80.0, b, 802.0), 42.0)
		if absf(b) < 150.0:
			plan.add_district(&"sat_terraces", "Prayer Terraces", p3(137.0, b, 782.0), 40.0)
		plan.add_district(&"sat_landing" if absf(b) < 100.0 else &"sat_lower_court", "Bison Landing" if absf(b) < 100.0 else "Cloud Court",
				p3(190.0, b, 762.0), 46.0)
	plan.add_district(&"sat_lower_court", "Cloud Court", p3(160.0, 180.0, 762.0), 50.0)
	for p in pinnacles:
		var id := StringName("sat_%s" % p["id"])
		plan.add_district(id, "West Pinnacle" if String(p["id"]).begins_with("west") else "East Pinnacle", p["position"], float(p["radius"]) + 6.0)
	# the arrival plaza
	var sp := WorldData.get_spawn(ElementDefs.Element.AIR)
	plan.data["spawn"] = sp.origin
	plan.add_district(&"sat_arrival", "Arrival Plaza", sp.origin, 14.0)
	plan.districts.sort_custom(func(a: Dictionary, b2: Dictionary) -> bool: return float(a["radius"]) < float(b2["radius"]))
	plan.data["center"] = c


func _reserve_specials() -> void:
	var sp: Vector3 = plan.data["spawn"]
	plan.reserve(sp.x, sp.z, 9.0)
	# ramps: stair strips + clear landings at both ends
	for r: Array in ramps:
		plan.reserve_line(L.xz(float(r[1]) - 27.0, float(r[0])), L.xz(float(r[1]) + 27.0, float(r[0])), 7.5)
	# bridge anchors on the terraces and on the pinnacles
	for br in WorldData.get_bridges():
		if not CLAIMS.has(StringName(br["id"])):
			continue
		var a: Vector3 = br["a"]
		var bb: Vector3 = br["b"]
		plan.reserve(a.x, a.z, 7.0)
		plan.reserve(bb.x, bb.z, 7.0)
		# nothing tall under the span
		plan.reserve_line(Vector2(a.x, a.z), Vector2(bb.x, bb.z), 6.0)
		bridge_ends.append(a)
	# pass road arrival
	for rd in WorldData.get_roads():
		if String(rd["id"]) == "air_pass_switchbacks":
			var pts: PackedVector3Array = rd["points"]
			var e := pts[pts.size() - 1]
			plan.data["pass_end"] = e
			plan.reserve(e.x, e.z, 9.0)


# --- retaining walls -------------------------------------------------------------------------------

## Face radius of the retaining wall of boundary rb at every whole bearing (-180..180): where the
## terrain step has reached the lower tier (+0.5 m), never closer than rb + FACE_OUT. Where the
## generator blended the step into a slope (outside the landing arc, over the south court) the
## wall moves out to the foot of the slope, so no terrain shows in front of it.
var _faces: Dictionary = {}


func foot_radius(rb: float, b: float, y_low: float) -> float:
	var r := rb - 2.0
	while r < rb + 30.0:
		var p := L.xz(r, b)
		if ground(p.x, p.y) <= y_low + 0.4:
			return r
		r += 0.5
	return r


func _sample_faces(rb: float) -> void:
	# beside a stair the ramp's side slopes would push the face out at the gap end only: the chord
	# next to the gap then runs diagonally and its deep body swings across the stair (the 220 stair
	# to the courtyard was closed, the sanctum stairs narrowed to 0-2 m - wave 4 bug hunt). The
	# default face over the gap and the conservative +-2 degree window keeps those chords straight.
	var stair_b: Array[float] = []
	for r: Array in ramps:
		if absf(float(r[1]) - rb) < 1.0:
			stair_b.append(float(r[0]))
	var keep := RingLayout.half_angle(RAMP_HALF * 2.0, rb + FACE_OUT) + 3.0
	var raw := PackedFloat32Array()
	for k in 361:
		var b := -180.0 + k
		if stair_b.any(func(sb: float) -> bool: return absf(RingLayout.bdiff(b, sb)) < keep):
			raw.append(rb + FACE_OUT)
			continue
		var y_low := tier_y(rb + 30.0, b)
		var y_top := tier_y(rb - 8.0, b)
		var foot := foot_radius(rb, b, y_low)
		# a blended step is steep (its foot within 0.7 x its height); a gentler run is a ramp
		# (the stair covers it), where the wall keeps its default face
		if foot - rb > (y_top - y_low) * 0.7:
			foot = rb
		raw.append(maxf(rb + FACE_OUT, foot + 0.5))
	# conservative: the max over +-2 degrees (chords between samples never cut into the slope)
	var out := PackedFloat32Array()
	out.resize(361)
	for k in 361:
		var m := raw[k]
		for d in range(-2, 3):
			m = maxf(m, raw[posmod(k + d, 360)])
		out[k] = m
	_faces[rb] = out


## Face radius of boundary rb at bearing b (linear between the whole-degree samples).
func face_r(rb: float, b: float) -> float:
	if not _faces.has(rb):
		_sample_faces(rb)
	var arr: PackedFloat32Array = _faces[rb]
	var u := wrapf(b, -180.0, 180.0) + 180.0
	var k := int(floor(u))
	return lerpf(arr[k], arr[mini(k + 1, 360)], u - k)


## Wall chords along the boundary rb between bearings b0..b1 facing outward; the face follows
## face_r(), the body reaches back to rb - 3.2 m, heights come from the terrain.
func wall_arc(rb: float, b0: float, b1: float, opts: Dictionary = {}) -> void:
	var len_m := RingLayout.arc_len(b1 - b0, rb + FACE_OUT)
	if len_m < 1.5:
		return
	var n := maxi(int(ceil(len_m / CHORD)), 1)
	for i in n:
		var ba := lerpf(b0, b1, float(i) / n)
		var bb := lerpf(b0, b1, float(i + 1) / n)
		var bm := (ba + bb) * 0.5
		var ra := face_r(rb, ba)
		var rb2 := face_r(rb, bb)
		var a := L.xz(ra, ba)
		var b := L.xz(rb2, bb)
		var m := (a + b) * 0.5
		var y_low := tier_y(rb + 30.0, bm)
		var y_top := tier_y(rb - 8.0, bm)
		if y_top - y_low < 2.0:
			continue
		var d := b - a
		var nrm := Vector2(d.y, -d.x).normalized()
		if nrm.dot(m - L.center) < 0.0:
			nrm = -nrm
		var depth := snappedf(maxf(ra, rb2) - (rb - 3.2), 0.5)
		# no balustrade where a suspended bridge leaves the wall top
		var rail: bool = opts.get("rail", true) and not _under_bridge(m, 4.0)
		var spec := {"L": snappedf(a.distance_to(b) + 0.05, 0.1), "H": y_top - y_low, "bottom": -1.4, "depth": depth,
			"v": int(ContentHash.hash4(int(m.x * 10.0), int(m.y * 10.0), 5) % 4), "rail": rail}
		plan.add(&"tier_wall", Vector3(m.x, y_low, m.y), yaw_dir(nrm), spec, 2, SatCivic.wall_arch(spec), a.distance_to(b) * 0.5)


## Wall chords along a radial line at bearing be from r0 to r1 facing towards bearing be + side.
func wall_radial(be: float, side: float, r0: float, r1: float) -> void:
	var n := maxi(int(ceil((r1 - r0) / CHORD)), 1)
	var tangent := RingLayout.dir(be + 90.0 * side)
	# the foot of the step along the tangent (the max over the run keeps the face straight)
	var off := FACE_OUT
	for k in 7:
		var q := L.xz(lerpf(r0, r1, k / 6.0), be)
		var y_low := snappedf(ground(q.x + tangent.x * 30.0, q.y + tangent.y * 30.0), 0.5)
		var t := -2.0
		while t < 30.0 and ground(q.x + tangent.x * t, q.y + tangent.y * t) > y_low + 0.4:
			t += 0.5
		off = maxf(off, t + 0.5)
	for i in n:
		var ra := lerpf(r0, r1, float(i) / n)
		var rb2 := lerpf(r0, r1, float(i + 1) / n)
		var a := L.xz(ra, be) + tangent * off
		var b := L.xz(rb2, be) + tangent * off
		var m := (a + b) * 0.5
		var y_low := snappedf(ground(m.x + tangent.x * 30.0, m.y + tangent.y * 30.0), 0.5)
		var y_top := snappedf(ground(m.x - tangent.x * (off + 8.0), m.y - tangent.y * (off + 8.0)), 0.5)
		if y_top - y_low < 2.0:
			continue
		var spec := {"L": snappedf(a.distance_to(b) + 0.05, 0.1), "H": y_top - y_low, "bottom": -1.4, "depth": snappedf(off + 3.2, 0.5),
			"v": i % 4, "rail": true}
		plan.add(&"tier_wall", Vector3(m.x, y_low, m.y), yaw_dir(tangent), spec, 2, SatCivic.wall_arch(spec), a.distance_to(b) * 0.5)


func _walls() -> void:
	var ta: Variant = L.tier(&"terrace").get("arc")
	var b0 := -150.0 if ta == null else float(ta[0])
	var b1 := 150.0 if ta == null else float(ta[1])
	# sanctum edge all the way round
	for s: Array in spans(-180.0, 180.0, 46.0 + FACE_OUT, ramp_gaps(46.0)):
		wall_arc(46.0, s[0], s[1])
	# courtyard edge: 20 m over the terraces, 40 m over the open south court (split at the
	# terrace arc ends so no chord straddles the change of height)
	for part: Array in [[-180.0, b0], [b0, b1], [b1, 180.0]]:
		for s: Array in spans(float(part[0]), float(part[1]), 112.0 + FACE_OUT, ramp_gaps(112.0)):
			wall_arc(112.0, s[0], s[1])
	# terrace edge over the landing ring, and the two radial ends of the terrace arc
	for s: Array in spans(b0, b1, 162.0 + FACE_OUT, ramp_gaps(162.0)):
		wall_arc(162.0, s[0], s[1])
	wall_radial(b0, -1.0, 112.0 + FACE_OUT - 1.0, 162.0 + FACE_OUT)
	wall_radial(b1, 1.0, 112.0 + FACE_OUT - 1.0, 162.0 + FACE_OUT)


# --- stairs --------------------------------------------------------------------------------------

func _stairs() -> void:
	for r: Array in ramps:
		var b := float(r[0])
		var rb := float(r[1])
		var y0 := float(r[2])
		var y1 := float(r[3])
		var length := 34.0
		for rp in L.ramps:
			if absf(RingLayout.bdiff(float(rp["bearing"]), b)) < 0.5:
				length = float(rp.get("length", 34.0))
		var foot := p3(rb + length * 0.5, b, y0)
		var spec := {"H": y1 - y0, "R": length, "W": 12.0, "half": length * 0.5}
		plan.add(&"stair", foot, yaw_in(b), spec, 2, "sat_stair:%d:%d" % [int(y1 - y0), int(length)], 9.0)
		plan.data.get_or_add("stairs", []).append({"bearing": b, "r": rb, "foot": foot, "top": p3(rb - length * 0.5, b, y1)})
		# a gateway at the top of the stair (part of the stair: inside its reserved strip), the
		# flight path permitting
		var gp := p3(rb - length * 0.5 - 3.0, b, y1)
		if cam_ok(gp.x, gp.z, 5.5, y1 + 9.0, y1):
			plan.add(&"gateway", gp, yaw_in(b), {"span": 8.0, "height": 5.6, "roof": rb > 100.0, "bells": true}, 2,
					"sat_gate:8:%d" % int(rb > 100.0), 5.5)


# --- cliff edges -----------------------------------------------------------------------------------

## Radius of the landing ring's cliff edge at bearing b (first r beyond 195 m under y - 1.5 m).
func edge_radius(b: float, y: float) -> float:
	var r := 195.0
	while r < 260.0:
		var p := L.xz(r, b)
		if ground(p.x, p.y) < y - 1.5:
			return r
		r += 0.5
	return r


## Balustrade along a closed / open polyline of cliff-edge points (world, at ground height).
func rail_polyline(pts: PackedVector3Array, closed: bool, skip: Callable = Callable()) -> void:
	var n := pts.size()
	for i in (n if closed else n - 1):
		var a := pts[i]
		var b := pts[(i + 1) % n]
		var m := (a + b) * 0.5
		if skip.is_valid() and skip.call(m):
			continue
		var d := Vector2(b.x - a.x, b.z - a.z)
		var length := d.length()
		if length < 1.0:
			continue
		# -Z of the piece faces the drop: the outward normal of the polyline
		var nrm := Vector2(d.y, -d.x).normalized()
		var lq := snappedf(length + 0.05, 0.5)
		var v := i % 3
		plan.add(&"edge_rail", Vector3(m.x, minf(a.y, b.y), m.z), yaw_dir(nrm), {"L": lq, "v": v, "lamp": i % 7 == 3}, 1,
				"sat_rail:%d:%d:%d" % [int(lq * 10.0), v, int(i % 7 == 3)], length * 0.5)


func _cliff_edges() -> void:
	# landing ring + open south court: follow the measured edge 1.6 m inside it
	var pts := PackedVector3Array()
	var b := -180.0
	var pass_end: Vector3 = plan.data.get("pass_end", Vector3.INF)
	while b < 180.0 - 0.01:
		var er := edge_radius(b, 762.0) - 1.6
		var p := L.xz(er, b)
		pts.append(Vector3(p.x, ground(p.x, p.y), p.y))
		b += 2.4
	plan.data["edge_pts"] = pts
	# gaps: the pass road, the cantilevered pavilions, the cliff towers (their walls are the rail)
	var gaps: Array = []
	if pass_end.is_finite():
		gaps.append([pass_end, 9.0])
	for pb: float in SatDistricts.PAVILIONS:
		gaps.append([SatDistricts.pavilion_pos(self, pb), 4.6])
	for t: Array in SatDistricts.CLIFF_TOWERS:
		gaps.append([SatDistricts.cliff_tower_pos(self, t), float(t[1]) + 1.2])
	rail_polyline(pts, true, func(m: Vector3) -> bool:
		for g: Array in gaps:
			var q: Vector3 = g[0]
			if Vector2(m.x - q.x, m.z - q.z).length() < float(g[1]):
				return true
		return false)
	# pinnacles
	for p in pinnacles:
		var c: Vector3 = p["position"]
		var ring := PackedVector3Array()
		for k in 24:
			var a := TAU * k / 24.0
			var r := 12.0
			while r < 45.0 and ground(c.x + cos(a) * r, c.z + sin(a) * r) > c.y - 1.5:
				r += 0.5
			r -= 1.4
			ring.append(Vector3(c.x + cos(a) * r, ground(c.x + cos(a) * r, c.z + sin(a) * r), c.z + sin(a) * r))
		var ends := bridge_ends_on(c, 40.0)
		rail_polyline(ring, true, func(m: Vector3) -> bool:
			for e: Vector3 in ends:
				if Vector2(m.x - e.x, m.z - e.z).length() < 6.5:
					return true
			return false)


## Deck heights (relative to a.y) every metre along a suspended span: the BridgeBuilder sag
## curve between the cliff edges, resting on the ground beyond them, then slope-limited (raise
## only, 0.4 m per metre) so the change from rim to curve never kinks into an unwalkable step.
static func deck_profile(a: Vector3, b: Vector3, sag: float, e: Vector2) -> PackedFloat32Array:
	var length := Vector2(b.x - a.x, b.z - a.z).length()
	var n := maxi(int(ceil(length)), 2) + 1
	var prof := PackedFloat32Array()
	prof.resize(n)
	for i in n:
		prof[i] = BridgeBuilder.deck_height(Vector3.ZERO, b - a, sag, a, float(i) / (n - 1), e)
	var step := 0.4 * length / (n - 1)
	for i in range(1, n):
		prof[i] = maxf(prof[i], prof[i - 1] - step)
	for i in range(n - 2, -1, -1):
		prof[i] = maxf(prof[i], prof[i + 1] - step)
	return prof


## Deck height (relative to a.y) at t along a profile.
static func deck_y(prof: PackedFloat32Array, t: float) -> float:
	var u := clampf(t, 0.0, 1.0) * (prof.size() - 1)
	var k := mini(int(floor(u)), prof.size() - 2)
	return lerpf(prof[k], prof[k + 1], u - k)


## True when x/z lies within `margin` (+ half the deck) of a claimed bridge's span.
func _under_bridge(p: Vector2, margin: float) -> bool:
	for br in WorldData.get_bridges():
		if not CLAIMS.has(StringName(br["id"])):
			continue
		var a: Vector3 = br["a"]
		var b: Vector3 = br["b"]
		var q := Geometry2D.get_closest_point_to_segment(p, Vector2(a.x, a.z), Vector2(b.x, b.z))
		if q.distance_to(p) < float(br.get("width", 3.2)) * 0.5 + margin:
			return true
	return false


## Bridge deck anchors (both ends) within `r` of `c`.
func bridge_ends_on(c: Vector3, r: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for br in WorldData.get_bridges():
		if not CLAIMS.has(StringName(br["id"])):
			continue
		for k: String in ["a", "b"]:
			var e: Vector3 = br[k]
			if Vector2(e.x - c.x, e.z - c.z).length() < r:
				out.append(e)
	return out


# --- suspended bridges -----------------------------------------------------------------------------

func _bridges() -> void:
	for br in WorldData.get_bridges():
		if not CLAIMS.has(StringName(br["id"])):
			continue
		var a: Vector3 = br["a"]
		var b: Vector3 = br["b"]
		var width := float(br.get("width", 3.2))
		var sag := float(br.get("sag", 6.0))
		var e := BridgeBuilder.edges(Vector3.ZERO, b - a, a)
		var length := Vector2(b.x - a.x, b.z - a.z).length()
		# the deck stays level out to the face of the terrace wall (its top is the walkable edge)
		var t := 0.0
		while t < 0.45:
			var q := a.lerp(b, t)
			var pr := L.polar(q.x, q.z)
			if pr.x > face_r(162.0, pr.y) + 0.3:
				break
			t += 0.002
		e.x = maxf(e.x, t)
		var prof := deck_profile(a, b, sag, e)
		var n := maxi(int(ceil(length / BRIDGE_SEG)), 1)
		for k in n:
			var t0 := float(k) / n
			var t1 := float(k + 1) / n
			var tm := (t0 + t1) * 0.5
			var mid := a.lerp(b, tm)
			mid.y = deck_y(prof, tm) + a.y
			plan.add(&"sky_bridge", mid, 0.0, {"a": a, "b": b, "sag": sag, "width": width, "t0": t0, "t1": t1, "origin": mid, "profile": prof,
				"poles": true, "bridge": br["id"]}, 2, "", length / n * 0.5)
		# gates at both ends, facing along the span
		var dir := Vector2(b.x - a.x, b.z - a.z).normalized()
		for end: Array in [[a, -dir], [b, dir]]:
			var p: Vector3 = end[0]
			var out: Vector2 = end[1]
			var gp := p + Vector3(out.x, 0, out.y) * 2.5
			gp.y = p.y
			plan.add(&"gateway", gp, yaw_dir(-out), {"span": width + 1.6, "height": 4.4, "roof": true, "bells": true}, 2, "sat_gate:bridge", 3.5)
			plan.anchor(&"quest_giver" if end[0] == a else &"idle", gp + Vector3(out.x, 0, out.y) * 3.0 + Vector3(-out.y, 0, out.x) * 2.5,
					yaw_dir(-out), {"tags": ["bridge", String(br["id"])]})
		# a monk crossing the bridge
		var walk := PackedVector3Array()
		for k in 9:
			var tw := float(k) / 8.0
			var q := a.lerp(b, tw)
			q.y = deck_y(prof, tw) + a.y
			walk.append(q)
		plan.anchor(&"patrol", walk[0], yaw_dir(dir), {"points": walk, "loop": false, "tags": ["bridge", "monk_walk", String(br["id"])]})


# --- tutorial ------------------------------------------------------------------------------------

## Everything around the Airball Courts POI is tagged so the tutorial (which dresses its own
## training ground there) can leave it out (`skip_tags`).
func _tag_tutorial_site() -> void:
	var poi := WorldData.get_poi(&"at_airball_courts")
	if poi.is_empty():
		return
	var c: Vector3 = poi["position"]
	var axis := RingLayout.dir(L.polar(c.x, c.z).y)
	for pc in plan.pieces:
		if pc["kind"] in [&"tier_wall", &"stair", &"edge_rail", &"sky_bridge"]:
			continue
		var p: Vector3 = pc["pos"]
		var d := Vector2(p.x - c.x, p.z - c.z)
		# the arena: ring r 13 around the POI and the pavilion 19.5 m further out along the axis
		var along := d.dot(axis)
		var side := absf(d.dot(Vector2(-axis.y, axis.x)))
		if d.length() - float(pc["r"]) < 16.0 or (along > 0.0 and along < 30.0 and side - float(pc["r"]) < 10.0):
			(pc["spec"] as Dictionary)["tag"] = &"airball_court"
