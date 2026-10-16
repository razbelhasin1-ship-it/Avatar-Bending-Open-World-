class_name SatDistricts
extends RefCounted
## Second half of the Air Temple layout (see SatPlanner): the Sanctum with the Great Spire, the
## sanctuary, the courtyard ring (monks' houses, halls, spires, gardens, statues, the airball
## court, the arrival plaza), the prayer terraces, the bison landing with its stables and the
## pass gate, the cliff-edge meditation pavilions and cliff towers, the open south court, the
## pinnacles, and the NPC anchors of all of them.

## Bearings of the cliff-edge meditation pavilions on the landing ring (the edge balustrade
## leaves a gap there).
const PAVILIONS := [70.0, 122.0, 160.0, -160.0, -122.0, -70.0]
## Courtyard spires among the houses: [bearing, r, shaft radius, height, roof_h, cupola].
const COURT_SPIRES := [[-62.0, 104.0, 5.2, 40.0, 15.0, true], [-104.0, 103.0, 4.6, 32.0, 13.0, false], [-170.0, 102.0, 4.4, 30.0, 12.0, false],
	[62.0, 104.0, 4.8, 36.0, 14.0, true], [92.0, 103.0, 4.2, 28.0, 11.5, true], [150.0, 102.0, 4.4, 32.0, 12.5, false],
	[-138.0, 100.0, 4.0, 26.0, 11.0, false], [-20.0, 104.0, 4.6, 34.0, 13.0, true]]
## Terrace spires: [bearing, r, shaft radius, height, roof_h, cupola].
const TERRACE_SPIRES := [[-120.0, 140.0, 5.6, 46.0, 17.0, true], [-52.0, 146.0, 4.6, 34.0, 13.5, false], [-12.0, 150.0, 4.0, 26.0, 11.0, false],
	[50.0, 146.0, 5.2, 40.0, 15.5, true], [84.0, 142.0, 4.4, 32.0, 12.5, false], [122.0, 145.0, 4.2, 30.0, 12.0, true],
	[-72.0, 136.0, 4.0, 28.0, 11.5, true], [12.0, 138.0, 3.8, 24.0, 10.5, false], [-140.0, 150.0, 3.8, 24.0, 10.5, false]]
## Cliff towers rising from below the landing edge: [bearing, shaft radius, height above the landing, roof_h].
const CLIFF_TOWERS := [[-142.0, 6.0, 52.0, 18.0], [142.0, 5.6, 44.0, 16.0], [-35.0, 5.0, 36.0, 14.0], [95.0, 5.2, 40.0, 15.0],
	[-84.0, 4.4, 30.0, 12.0], [-108.0, 5.0, 36.0, 14.0], [176.0, 6.4, 56.0, 19.0], [-174.0, 4.6, 32.0, 12.5], [58.0, 4.8, 34.0, 13.5],
	[-58.0, 4.2, 28.0, 11.5], [110.0, 4.4, 30.0, 12.0], [-150.0, 4.0, 26.0, 11.0]]

var P: SatPlanner
var L: RingLayout
var plan: SettlementPlan
var rng: RandomNumberGenerator


func _init(p: SatPlanner) -> void:
	P = p
	L = p.L
	plan = p.plan
	rng = ContentHash.rng(ContentHash.hash_name("sat_districts"))


func build() -> void:
	_sanctum()
	_sanctuary()
	_airball_court()
	_arrival_plaza()
	_courtyard_spires()
	_courtyard_houses()
	_courtyard_middle()
	_terraces()
	_landing()
	_pavilions()
	_cliff_towers()
	_lower_court()
	# monks' quarters and storehouses backed against the terrace wall (east and west of the
	# landing field) and against the courtyard wall over the open south court
	_ring_houses(162.0, -150.0, -66.0, ["landing"], 170.0)
	_ring_houses(162.0, 66.0, 150.0, ["landing"], 170.0)
	_ring_houses(112.0, -180.0, -154.0, ["lower_court"], 125.0)
	_ring_houses(112.0, 154.0, 180.0, ["lower_court"], 125.0)
	_pinnacles()
	_walks()


static func world(pos: Vector3, yaw: float, local: Vector3) -> Vector3:
	return pos + Basis(Vector3.UP, yaw) * local


## Spire piece (archetype keyed by its dimensions); tries a lower variant before giving up when
## the arrival flight passes close. Returns the record or {}.
func spire(pos: Vector3, yaw: float, r: float, h: float, roof_h: float, cupola: bool, base: float = -1.5, v: int = -1) -> Dictionary:
	if v < 0:
		v = int(absf(pos.x * 0.37 + pos.z * 0.11)) % 3
	for scale: float in [1.0, 0.72, 0.5]:
		var hh := roundf(h * scale)
		var rh := roundf(roof_h * (0.6 + 0.4 * scale))
		var spec := {"r": snappedf(r, 0.2), "h": hh, "base": snappedf(base, 0.5), "roof_h": rh, "v": v, "cupola": cupola and scale > 0.6,
			"balcony": hh > 16.0}
		var top := pos.y + hh + 1.1 + rh * (1.3 if cupola else 1.0) + 2.0
		var arch := "sat_spire:%d:%d:%d:%d:%d:%d" % [int(spec["r"] * 10.0), int(hh), int(spec["base"] * 2.0), int(rh), v, int(spec["cupola"])]
		var rec := P.place(&"spire", pos, yaw, spec, 2, arch, r + 2.0, top, r * 1.5 + 1.0)
		if not rec.is_empty():
			return rec
	return {}


func _anchor(kind: StringName, pos: Vector3, yaw: float, tags: Array, extra: Dictionary = {}) -> void:
	var e := extra.duplicate()
	e["tags"] = tags
	plan.anchor(kind, pos, yaw, e)


# --- the sanctum -----------------------------------------------------------------------------------

func _sanctum() -> void:
	var c := P.p3(0.0, 0.0, P.tier_y(20.0, 90.0))
	# the Great Spire, checked against the flight with its real profile: hall wings, shaft +
	# balconies, the great cone (eave 15 m narrowing to the cupola) and the upper cone
	var prof := [[c.y, c.y + 15.0, 18.5], [c.y, c.y + 66.5, 10.8], [c.y + 66.5, c.y + 76.0, 17.4], [c.y + 76.0, c.y + 94.0, 11.5],
		[c.y + 94.0, c.y + 126.0, 8.5]]
	if P.cam_ok_profile(c.x, c.z, prof):
		plan.add(&"great_spire", c, 0.0, {"r": 9.0, "h": 64.0, "roof_h": 38.0}, 2, "", 18.0)
		plan.reserve(c.x, c.z, 19.0)
		plan.data["great_spire"] = c
	for k in 4:
		var yaw := k * PI * 0.5
		_anchor(&"idle", world(c, yaw, Vector3(3.5, 0.0, -20.0)), yaw, ["meditate", "sanctum"])
	_anchor(&"quest_giver", world(c, 0.0, Vector3(-2.0, 0.0, -20.5)), 0.0, ["abbot", "sanctum"])
	_anchor(&"trainer", world(c, PI, Vector3(-2.5, 0.0, -21.0)), PI, ["master", "sanctum", "airbending"])
	# secondary spires on the sanctum
	for s: Array in [[-58.0, 33.0, 5.4, 42.0, 16.0], [-122.0, 32.0, 5.0, 36.0, 14.0], [168.0, 33.0, 4.4, 30.0, 12.0], [78.0, 37.0, 4.2, 26.0, 11.0],
			[-178.0, 36.0, 3.6, 22.0, 9.5], [-8.0, 36.0, 3.8, 28.0, 11.0]]:
		spire(P.p3(float(s[1]), float(s[0]), c.y), SatPlanner.yaw_out(float(s[0])), float(s[2]), float(s[3]), float(s[4]), true)
	# prayer wheels, lanterns and flags around the podium
	for b: float in [-90.0, 0.0, 90.0, 180.0]:
		var p := P.p3(24.5, b + 47.0, c.y)
		P.place(&"prayer_wheels", p, SatPlanner.yaw_in(b + 47.0), {"n": 6}, 1, "sat_wheels:6", 3.6, p.y + 3.5)
	for k in 8:
		var b := 22.5 + 45.0 * k
		var p := P.p3(40.0, b, c.y)
		P.place(&"lantern", p, 0.0, {"v": k % 2, "light": k % 2 == 0}, 1, "sat_lantern:%d:%d" % [k % 2, int(k % 2 == 0)], 0.8, p.y + 2.2)


# --- the sanctuary ---------------------------------------------------------------------------------

func _sanctuary() -> void:
	var b := 180.0
	var pos := P.p3(74.0, b, P.tier_y(74.0, b))
	var yaw := SatPlanner.yaw_out(b)
	var mid := world(pos, yaw, Vector3(0, 0, 9.0))
	plan.reserve(mid.x, mid.z, 19.0)
	plan.add(&"sanctuary", pos, yaw, {}, 2, "", 22.0)
	# the forecourt: a paved plaza on the approach, kept clear out to the courtyard edge
	var fc := world(pos, yaw, Vector3(0, 0, -23.0))
	plan.reserve_line(Vector2(pos.x, pos.z), Vector2(fc.x, fc.z), 12.0)
	var fc2 := world(pos, yaw, Vector3(0, 0, -36.0))
	plan.reserve(fc2.x, fc2.z, 10.0)
	plan.add(&"court", fc, 0.0, {"r": 10.0, "swirl": true}, 1, "sat_court:100", 10.0)
	plan.data["sanctuary"] = pos
	_anchor(&"quest_giver", world(pos, yaw, Vector3(2.2, 1.4, -2.6)), yaw + PI, ["elder", "sanctuary", "door"])
	_anchor(&"idle", world(pos, yaw, Vector3(-4.0, 0.0, -10.0)), yaw + PI, ["pilgrim", "sanctuary"])
	# statues of monks flanking the approach, lanterns and gardens
	for sx: float in [-1.0, 1.0]:
		var sp := world(pos, yaw, Vector3(sx * 11.5, 0.0, -14.0))
		if P.cam_ok(sp.x, sp.z, 2.4, sp.y + 7.5, sp.y):
			plan.add(&"statue", sp, yaw, {"v": 0 if sx < 0.0 else 1}, 2, "sat_statue:%d" % (0 if sx < 0.0 else 1), 2.4)
		var gp := world(pos, yaw, Vector3(sx * 18.5, 0.0, -9.0))
		P.place(&"garden", gp, yaw, {"r": 3.6, "seed": int(sx + 2.0), "plants": "blossom"}, 1, "sat_garden_r:36:%d" % int(sx + 2.0), 3.8, gp.y + 7.0)


# --- airball court ---------------------------------------------------------------------------------

func _airball_court() -> void:
	var poi := WorldData.get_poi(&"at_airball_courts")
	if poi.is_empty():
		return
	var c: Vector3 = poi["position"]
	var b := L.polar(c.x, c.z).y
	var r := L.polar(c.x, c.z).x
	var pos := P.p3(r, b, P.tier_y(r, b))
	var yaw := SatPlanner.yaw_out(b) + PI * 0.5
	plan.reserve(pos.x, pos.z, 15.5)
	plan.add(&"airball_court", pos, yaw, {"w": 16.0, "l": 28.0}, 1, "", 16.0)
	_anchor(&"trainer", world(pos, yaw, Vector3(9.5, 0.1, 0.0)), yaw - PI * 0.5, ["airball", "coach"])
	for k in 4:
		var row := float(k >> 1)
		_anchor(&"child_play", world(pos, yaw, Vector3(lerpf(-5.0, 5.0, float(k & 1)), 0.15, lerpf(-8.0, 8.0, row))), yaw + PI * row, ["airball", "player"])
	for sz: float in [-1.0, 1.0]:
		_anchor(&"student", world(pos, yaw, Vector3(-9.6, 0.1, sz * 6.0)), yaw + PI * 0.5, ["airball", "spectator"])
		var bp := world(pos, yaw, Vector3(-10.4, 0.0, sz * 9.5))
		plan.add(&"bench", bp, yaw + PI * 0.5, {"v": 1}, 0, "sat_bench:1", 1.4)


# --- the arrival plaza -------------------------------------------------------------------------------

func _arrival_plaza() -> void:
	var sp: Vector3 = plan.data["spawn"]
	var pos := Vector3(sp.x, P.ground(sp.x, sp.z), sp.z)
	plan.add(&"court", pos, 0.0, {"r": 9.0, "swirl": true}, 1, "sat_court:90", 9.0)
	# a resting sky bison statue and flag lines frame the view north
	var b := L.polar(pos.x, pos.z).y
	for sx: float in [-1.0, 1.0]:
		var q := world(pos, SatPlanner.yaw_out(b), Vector3(sx * 13.0, 0.0, 2.0))
		P.place(&"lantern", q, 0.0, {"v": 1, "light": true}, 1, "sat_lantern:1:1", 0.8, q.y + 2.4)
	var st := world(pos, SatPlanner.yaw_out(b), Vector3(-15.0, 0.0, 7.0))
	P.place(&"statue", st, SatPlanner.yaw_out(b), {"v": 2}, 2, "sat_statue:2", 2.6, st.y + 6.0)
	_anchor(&"quest_giver", world(pos, SatPlanner.yaw_out(b), Vector3(-5.0, 0.0, -4.0)), SatPlanner.yaw_in(b), ["greeter", "arrival"])


# --- courtyard ---------------------------------------------------------------------------------------

func _courtyard_spires() -> void:
	for s: Array in COURT_SPIRES:
		var b := float(s[0])
		spire(P.p3(float(s[1]), b, P.tier_y(float(s[1]), b)), SatPlanner.yaw_in(b), float(s[2]), float(s[3]), float(s[4]), bool(s[5]))


func _courtyard_houses() -> void:
	# monks' houses on the outer band, facing the courtyard; halls where the band is widest
	var rf := 96.5
	var b := -180.0
	var n := 0
	while b < 180.0:
		var kind: StringName = &"dormitory"
		var v := rng.randi() % 6
		if n % 7 == 3:
			kind = &"hall"
			v = (n / 7) % 2
		var fp := SatPlaces.footprint(kind, v)
		var bc := b + RingLayout.half_angle(fp.x, rf)
		var rc := rf + fp.y * 0.5
		var yaw := SatPlanner.yaw_in(bc)
		var pos := P.p3(rc, bc, P.tier_y(rc, bc))
		var top := pos.y + (16.0 if kind == &"hall" else 15.0)
		if _fits(pos, yaw, fp) and P.cam_ok(pos.x, pos.z, maxf(fp.x, fp.y) * 0.5, top, pos.y) and rc + fp.y * 0.5 < 112.5:
			_reserve_rect(pos, yaw, fp)
			plan.add(kind, pos, yaw, {"v": v}, 2, "sat_%s:%d" % [kind, v], maxf(fp.x, fp.y) * 0.5)
			var door := world(pos, yaw, Vector3(0, 0.3, -fp.y * 0.5 - 1.2))
			if kind == &"dormitory":
				_anchor(&"home", door, yaw + PI, ["courtyard", "dormitory"], {"building": kind, "capacity": 4 + v % 4})
			else:
				_anchor(&"idle", door, yaw + PI, ["courtyard", "hall"], {"building": kind})
				_anchor(&"quest_giver", world(pos, yaw, Vector3(3.0, 0.6, -fp.y * 0.5 - 2.0)), yaw + PI, ["librarian" if n % 2 else "cook", "hall"])
			b += RingLayout.half_angle((fp.x + rng.randf_range(2.5, 5.0)) * 2.0, rf)
			n += 1
		else:
			b += RingLayout.half_angle(4.0, rf)


## Buildings in [b0, b1] backed against the retaining wall of boundary `rb` (its measured face),
## facing outward (the view). Dormitories, halls (storehouses / dining halls) and an orchard
## bed now and then.
func _ring_houses(rb: float, b0: float, b1: float, tags: Array, r_ref: float) -> void:
	var b := b0 + RingLayout.half_angle(3.0, r_ref)
	var n := 0
	while b < b1:
		var kind: StringName = &"dormitory"
		var v := rng.randi() % 6
		if n % 5 == 2:
			kind = &"hall"
			v = n % 2
		var fp := SatPlaces.footprint(kind, v)
		var back := maxf(P.face_r(rb, b), P.face_r(rb, b + RingLayout.half_angle(fp.x * 2.0, r_ref))) + 0.6
		var rc := back + fp.y * 0.5
		var bc := b + RingLayout.half_angle(fp.x, rc)
		if bc + RingLayout.half_angle(fp.x, rc) > b1:
			break
		var yaw := SatPlanner.yaw_out(bc)
		var pos := P.p3(rc, bc, P.tier_y(rc, bc))
		var top := pos.y + 16.0
		if rng.randf() < 0.85 and _fits(pos, yaw, fp) and P.cam_ok(pos.x, pos.z, maxf(fp.x, fp.y) * 0.5, top, pos.y):
			_reserve_rect(pos, yaw, fp)
			plan.add(kind, pos, yaw, {"v": v}, 2, "sat_%s:%d" % [kind, v], maxf(fp.x, fp.y) * 0.5)
			var door := world(pos, yaw, Vector3(0, 0.3, -fp.y * 0.5 - 1.2))
			if kind == &"dormitory":
				_anchor(&"home", door, yaw + PI, tags + ["dormitory"], {"building": kind, "capacity": 3 + v % 4})
			else:
				_anchor(&"worker", door, yaw + PI, tags + ["storehouse"], {"building": kind})
			b = bc + RingLayout.half_angle(fp.x + rng.randf_range(3.0, 7.0) * 2.0, rc)
			n += 1
		else:
			# an orchard bed in the gap
			var gp := P.p3(back + 3.0, b + RingLayout.half_angle(6.0, back), P.tier_y(back + 3.0, b))
			if rng.randf() < 0.5:
				P.place(&"garden", gp, SatPlanner.yaw_out(b), {"w": 9.0, "d": 4.0, "seed": n * 13 + int(b), "plants": "blossom"}, 1,
						"sat_garden:90:40:%d" % (n % 4), 4.8, gp.y + 8.0)
			b += RingLayout.half_angle(12.0, r_ref)
			n += 1


func _fits(pos: Vector3, yaw: float, fp: Vector2) -> bool:
	var bs := Basis(Vector3.UP, yaw)
	var hx := fp.x * 0.5
	var hz := fp.y * 0.5
	for q: Vector3 in [Vector3.ZERO, Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(hx, 0, hz), Vector3(-hx, 0, hz),
			Vector3(0, 0, -hz), Vector3(0, 0, hz), Vector3(-hx, 0, 0), Vector3(hx, 0, 0)]:
		var w := pos + bs * q
		if not plan.is_free(w.x, w.z, 0.8 if q != Vector3.ZERO else minf(hx, hz) * 0.8):
			return false
		if absf(P.ground(w.x, w.z) - pos.y) > 0.8:
			return false
	return true


func _reserve_rect(pos: Vector3, yaw: float, fp: Vector2) -> void:
	var bs := Basis(Vector3.UP, yaw)
	var r := minf(fp.x, fp.y) * 0.5
	var n := maxi(int(ceil(maxf(fp.x, fp.y) / maxf(minf(fp.x, fp.y), 1.0))), 1)
	for k in n:
		var t := (float(k) + 0.5) / n - 0.5
		var q := Vector3(t * fp.x, 0, 0) if fp.x >= fp.y else Vector3(0, 0, t * fp.y)
		var w := pos + bs * q
		plan.reserve(w.x, w.z, r * 1.08)


func _courtyard_middle() -> void:
	# round blossom gardens, statues, chimes and prayer flags in the open middle band
	var k := 0
	for b: float in [-150.0, -118.0, -80.0, -48.0, 48.0, 78.0, 152.0, -8.0]:
		var r := 70.0 + (k % 2) * 6.0
		var gp := P.p3(r, b, P.tier_y(r, b))
		var rec := P.place(&"garden", gp, 0.0, {"r": 4.4, "seed": k, "plants": "blossom"}, 1, "sat_garden_r:44:%d" % k, 4.6, gp.y + 8.0)
		if not rec.is_empty():
			_anchor(&"gardener", gp + Vector3(5.2, 0, 0), PI * 0.5, ["garden", "courtyard"])
			for s: float in [-1.0, 1.0]:
				var bp := P.p3(r, b + s * RingLayout.half_angle(14.0, r), gp.y)
				P.place(&"bench", bp, SatPlanner.yaw_in(b + s * 6.0) + PI * 0.5, {"v": k % 2}, 0, "sat_bench:%d" % (k % 2), 1.6, bp.y + 1.0)
		k += 1
	# chime posts and lanterns on the ring path between the middle band and the houses
	var b := -175.0
	var i := 0
	while b < 175.0:
		var p := P.p3(89.0, b, P.tier_y(89.0, b))
		if i % 3 == 1:
			P.place(&"chime_post", p, SatPlanner.yaw_in(b), {"v": i % 2}, 1, "sat_chime:%d" % (i % 2), 1.0, p.y + 4.6)
		else:
			P.place(&"lantern", p, 0.0, {"v": i % 2, "light": i % 4 == 0}, 1, "sat_lantern:%d:%d" % [i % 2, int(i % 4 == 0)], 0.8, p.y + 2.4)
		b += 9.5
		i += 1
	# prayer-flag lines radiating towards the sanctum wall
	for fb: float in [-135.0, -95.0, -40.0, 40.0, 100.0, 132.0]:
		var p := P.p3(56.0, fb, P.tier_y(56.0, fb))
		P.place(&"flag_line", p, SatPlanner.yaw_in(fb) + PI * 0.5, {"L": 12.0, "h": 5.0}, 1, "sat_flags:120:50", 6.2, p.y + 5.4)
	# rectangular beds along the foot of the sanctum wall
	for gb: float in [-100.0, -60.0, 60.0, 100.0]:
		var p := P.p3(52.5, gb, P.tier_y(52.5, gb))
		var rec := P.place(&"garden", p, SatPlanner.yaw_in(gb), {"w": 9.0, "d": 3.4, "seed": int(gb), "plants": "mixed"}, 1,
				"sat_garden:90:34:%d" % int(gb), 4.6, p.y + 6.0)
		if not rec.is_empty():
			_anchor(&"gardener", world(p, SatPlanner.yaw_in(gb), Vector3(0, 0, 2.6)), SatPlanner.yaw_in(gb), ["garden", "sanctum_wall"])
	# a gong by the sanctuary stair
	var gp := P.p3(88.0, 168.0, P.tier_y(88.0, 168.0))
	P.place(&"gong", gp, SatPlanner.yaw_in(168.0), {}, 1, "sat_gong", 2.2, gp.y + 4.8)


# --- terraces --------------------------------------------------------------------------------------

func _terraces() -> void:
	for s: Array in TERRACE_SPIRES:
		var b := float(s[0])
		spire(P.p3(float(s[1]), b, P.tier_y(float(s[1]), b)), SatPlanner.yaw_out(b), float(s[2]), float(s[3]), float(s[4]), bool(s[5]))
	# houses facing the view, backs against the courtyard wall
	var rf := 129.5
	var b := -146.0
	while b < 146.0:
		var v := rng.randi() % 6
		var fp := SatPlaces.footprint(&"dormitory", v)
		var bc := b + RingLayout.half_angle(fp.x, rf)
		var rc := rf - fp.y * 0.5
		var yaw := SatPlanner.yaw_out(bc)
		var pos := P.p3(rc, bc, P.tier_y(rc, bc))
		if rng.randf() < 0.8 and _fits(pos, yaw, fp) and P.cam_ok(pos.x, pos.z, maxf(fp.x, fp.y) * 0.5, pos.y + 15.0, pos.y):
			_reserve_rect(pos, yaw, fp)
			plan.add(&"dormitory", pos, yaw, {"v": v}, 2, "sat_dormitory:%d" % v, maxf(fp.x, fp.y) * 0.5)
			_anchor(&"home", world(pos, yaw, Vector3(0, 0.3, -fp.y * 0.5 - 1.2)), yaw + PI, ["terrace", "dormitory"], {"building": &"dormitory", "capacity": 3 + v % 3})
			b += RingLayout.half_angle((fp.x + rng.randf_range(4.0, 9.0)) * 2.0, rf)
		else:
			b += RingLayout.half_angle(6.0, rf)
	# gardens, flag lines along the outer edge, chimes, benches facing the view
	var k := 0
	b = -140.0
	while b <= 140.0:
		var r := 152.0
		var p := P.p3(r, b, P.tier_y(r, b))
		match k % 4:
			0:
				var rec := P.place(&"garden", p, SatPlanner.yaw_out(b), {"w": 8.0, "d": 4.4, "seed": 100 + k, "plants": "blossom"}, 1,
						"sat_garden:80:44:%d" % (k % 5), 4.8, p.y + 8.0)
				if not rec.is_empty():
					_anchor(&"gardener", world(p, SatPlanner.yaw_out(b), Vector3(0, 0, 3.2)), SatPlanner.yaw_out(b), ["garden", "terrace"])
			1:
				P.place(&"flag_line", p, SatPlanner.yaw_out(b) + PI * 0.5, {"L": 13.0, "h": 4.6}, 1, "sat_flags:130:46", 6.8, p.y + 5.0)
			2:
				if P.place(&"bench", p, SatPlanner.yaw_in(b), {"v": 0}, 0, "sat_bench:0", 1.6, p.y + 1.0).size() > 0:
					_anchor(&"idle", p, SatPlanner.yaw_out(b), ["meditate", "view", "terrace"])
			3:
				P.place(&"chime_post", p, SatPlanner.yaw_out(b), {"v": k % 2}, 1, "sat_chime:%d" % (k % 2), 1.0, p.y + 4.6)
		b += 11.0
		k += 1
	# Glider's Leap: a cantilevered platform at the vista
	var leap := WorldData.get_poi(&"at_gliders_leap")
	if not leap.is_empty():
		var lp: Vector3 = leap["position"]
		var lb := L.polar(lp.x, lp.z).y
		var pos := P.p3(158.5, lb, P.tier_y(150.0, lb))
		if P.place(&"pavilion", pos, SatPlanner.yaw_out(lb), {"r": 3.4, "cantilever": true, "v": 1}, 2, "sat_pavilion:34:1:1", 5.0, pos.y + 9.0).size() > 0:
			_anchor(&"idle", world(pos, SatPlanner.yaw_out(lb), Vector3(0, 0.4, -2.0)), SatPlanner.yaw_out(lb), ["gliders_leap", "glider"])


# --- the landing ------------------------------------------------------------------------------------

func _landing() -> void:
	var y := 762.0
	# bison landing circle
	var lc := P.p3(192.0, -6.0, y)
	plan.reserve(lc.x, lc.z, 15.0)
	plan.add(&"court", lc, 0.0, {"r": 15.0, "swirl": true}, 1, "sat_court:150", 15.0)
	for k in 4:
		var a := TAU * k / 4.0 + 0.4
		_anchor(&"bison_landing", lc + Vector3(cos(a) * 8.0, 0, sin(a) * 8.0), -a, ["bison", "landing"])
	# stables against the terrace wall, open fronts towards the landing field
	var s := 0
	for b: float in [8.0, 44.0]:
		var D := 12.0
		var Lh := 30.0
		var r := 162.0 + SatPlanner.FACE_OUT + 0.6 + D * 0.5
		var pos := P.p3(r, b, y)
		var yaw := SatPlanner.yaw_out(b)
		if not P.cam_ok(pos.x, pos.z, Lh * 0.5, y + 16.0, y):
			continue
		_reserve_rect(pos, yaw, Vector2(Lh, D))
		plan.add(&"stable", pos, yaw, {"L": Lh, "D": D}, 2, "sat_stable:%d" % int(Lh), Lh * 0.5)
		var bays := maxi(int(Lh / 9.0), 2)
		for i in bays:
			var x := lerpf(-Lh * 0.5, Lh * 0.5, (i + 0.5) / bays)
			_anchor(&"bison_stall", world(pos, yaw, Vector3(x, 0.1, 0.0)), yaw + PI, ["bison", "stable"], {"building": &"stable"})
		_anchor(&"quest_giver" if s == 0 else &"worker", world(pos, yaw, Vector3(Lh * 0.5 - 3.0, 0.1, -D * 0.5 - 2.0)), yaw + PI,
				["stable_keeper" if s == 0 else "stable_hand", "stable"])
		var hp := world(pos, yaw, Vector3(-Lh * 0.5 - 4.5, 0.0, -2.0))
		P.place(&"hay", hp, yaw, {"v": s}, 1, "sat_hay:%d" % s, 2.8, y + 2.0)
		s += 1
	# the pass gate where the Pass of a Thousand Steps arrives
	var pe: Vector3 = plan.data.get("pass_end", Vector3.INF)
	if pe.is_finite():
		var pb := L.polar(pe.x, pe.z)
		var gp := P.p3(pb.x - 4.0, pb.y, y)
		plan.add(&"gateway", gp, SatPlanner.yaw_out(pb.y), {"span": 8.0, "height": 6.6, "roof": true, "bells": true}, 2, "sat_gate:pass", 6.0)
		for sx: float in [-1.0, 1.0]:
			var lp := world(gp, SatPlanner.yaw_out(pb.y), Vector3(sx * 7.0, 0.0, 3.0))
			P.place(&"lantern", lp, 0.0, {"v": 1, "light": true}, 1, "sat_lantern:1:1", 0.8, y + 2.4)
		_anchor(&"quest_giver", world(gp, SatPlanner.yaw_out(pb.y), Vector3(3.0, 0.0, 3.5)), SatPlanner.yaw_out(pb.y), ["gatekeeper", "pass"])
		_anchor(&"idle", world(gp, SatPlanner.yaw_out(pb.y), Vector3(-3.0, 0.0, 4.5)), SatPlanner.yaw_out(pb.y), ["pilgrim", "pass"])
	# flag lines and lanterns around the landing field
	for b: float in [-48.0, -26.0, 26.0, 62.0]:
		var p := P.p3(200.0, b, y)
		P.place(&"flag_line", p, SatPlanner.yaw_out(b) + PI * 0.5, {"L": 14.0, "h": 5.2}, 1, "sat_flags:140:52", 7.2, y + 5.6)


func _pavilions() -> void:
	for b: float in PAVILIONS:
		var pos := pavilion_pos(P, b)
		var rec := P.place(&"pavilion", pos, SatPlanner.yaw_out(b), {"r": 3.6, "cantilever": true, "v": int(absf(b)) % 3}, 2,
				"sat_pavilion:36:%d:1" % (int(absf(b)) % 3), 5.0, pos.y + 9.5)
		if not rec.is_empty():
			_anchor(&"idle", world(pos, SatPlanner.yaw_out(b), Vector3(0, 0.4, -2.2)), SatPlanner.yaw_out(b), ["meditate", "pavilion", "cliff"])


## World position of a cliff tower (on the edge, half over the drop) and of a pavilion.
static func cliff_tower_pos(P2: SatPlanner, t: Array) -> Vector3:
	var b := float(t[0])
	return P2.p3(P2.edge_radius(b, 762.0) + float(t[1]) - 0.8, b, 762.0)


static func pavilion_pos(P2: SatPlanner, b: float) -> Vector3:
	var pos := P2.p3(P2.edge_radius(b, 762.0) - 3.4, b, 762.0)
	pos.y = P2.ground(pos.x, pos.z)
	return pos


func _cliff_towers() -> void:
	for t: Array in CLIFF_TOWERS:
		var b := float(t[0])
		var pos := cliff_tower_pos(P, t)
		# its masonry foot reaches down the cliff below; the door faces the landing
		var below := P.ground(pos.x + RingLayout.dir(b).x * float(t[1]), pos.z + RingLayout.dir(b).y * float(t[1]))
		var base := clampf(below - pos.y - 3.0, -60.0, -3.0)
		spire(pos, SatPlanner.yaw_in(b), float(t[1]), float(t[2]), float(t[3]), true, snappedf(base, 0.5))


func _lower_court() -> void:
	var y := 762.0
	var c := P.p3(176.0, 180.0, y)
	plan.reserve(c.x, c.z, 12.0)
	plan.add(&"court", c, 0.0, {"r": 11.0, "swirl": true}, 1, "sat_court:110", 11.0)
	var st := P.p3(150.0, 180.0, y)
	P.place(&"statue", st, SatPlanner.yaw_out(180.0), {"v": 0}, 2, "sat_statue:0", 2.6, y + 7.5)
	_anchor(&"idle", P.p3(146.0, 176.0, y), SatPlanner.yaw_out(180.0), ["pilgrim", "statue"])
	for b: float in [158.0, -158.0, 168.0, -168.0]:
		var r := 140.0 if absf(b) > 160.0 else 196.0
		var p := P.p3(r, b, y)
		var rec := P.place(&"garden", p, 0.0, {"r": 4.0, "seed": int(b), "plants": "blossom"}, 1, "sat_garden_r:40:%d" % int(absf(b)), 4.2, y + 8.0)
		if not rec.is_empty():
			_anchor(&"gardener", p + Vector3(4.8, 0, 0), PI * 0.5, ["garden", "lower_court"])
	for b: float in [-172.0, 172.0]:
		var p := P.p3(192.0, b, y)
		P.place(&"flag_line", p, SatPlanner.yaw_out(b) + PI * 0.5, {"L": 12.0, "h": 4.8}, 1, "sat_flags:120:48", 6.2, y + 5.2)


func _pinnacles() -> void:
	for pn in P.pinnacles:
		var c: Vector3 = pn["position"]
		var west := String(pn["id"]).begins_with("west")
		var to_temple := Vector2(L.center.x - c.x, L.center.y - c.z).normalized()
		var out := -to_temple
		var yaw_view := SatPlanner.yaw_dir(out)
		# a meditation pavilion in the middle, a spire on the far side, chimes around
		var pv := c + Vector3(out.x, 0, out.y) * 2.0
		pv.y = P.ground(pv.x, pv.z)
		if P.place(&"pavilion", pv, yaw_view, {"r": 4.2, "cantilever": false, "v": 2}, 2, "sat_pavilion:42:2:0", 5.0, pv.y + 10.0).size() > 0:
			_anchor(&"idle", world(pv, yaw_view, Vector3(0, 0.4, 0)), yaw_view, ["meditate", "pinnacle", String(pn["id"])])
			if west:
				_anchor(&"trainer", world(pv, yaw_view, Vector3(0, 0.4, 2.6)), yaw_view, ["meditation_master", "pinnacle"])
		var sp := c + Vector3(out.x, 0, out.y) * 14.0 + Vector3(-out.y, 0, out.x) * (6.0 if west else -6.0)
		sp.y = P.ground(sp.x, sp.z)
		spire(sp, yaw_view, 3.4, 18.0 if west else 22.0, 9.0, not west)
		for k in 4:
			var a := TAU * k / 4.0 + 0.6
			var q := c + Vector3(cos(a), 0, sin(a)) * 11.0
			q.y = P.ground(q.x, q.z)
			P.place(&"chime_post" if (k % 2 == 0 or not west) else &"lantern", q, 0.0, {"v": k % 2, "light": k == 1}, 1,
					"sat_chime:%d" % (k % 2) if (k % 2 == 0 or not west) else "sat_lantern:%d:%d" % [k % 2, int(k == 1)], 1.0, q.y + 4.6)
		if west:
			plan.data["meditation_ledge"] = pv


# --- walks -------------------------------------------------------------------------------------------

func _walks() -> void:
	var ring := PackedVector3Array()
	for k in 25:
		var b := -180.0 + 15.0 * k
		ring.append(P.p3(84.0, b, P.tier_y(84.0, b)))
	_anchor(&"patrol", ring[0], 0.0, ["courtyard", "monk_walk"], {"points": ring, "loop": true})
	var terr := PackedVector3Array()
	var b := -144.0
	while b <= 144.0:
		terr.append(P.p3(146.0, b, P.tier_y(146.0, b)))
		b += 12.0
	_anchor(&"patrol", terr[0], 0.0, ["terrace", "monk_walk"], {"points": terr, "loop": false})
	var landing := PackedVector3Array()
	b = -60.0
	while b <= 60.0:
		landing.append(P.p3(196.0, b, 762.0))
		b += 10.0
	_anchor(&"patrol", landing[0], 0.0, ["landing", "monk_walk"], {"points": landing, "loop": false})
