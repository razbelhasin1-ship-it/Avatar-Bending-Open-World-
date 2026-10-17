class_name NwtDistricts
extends RefCounted
## Second half of the Water Tribe layout (see NwtPlanner): the palace, Spirit Oasis, gates,
## enterable interiors, plazas, markets, the houses of every tier band, street furniture and
## the NPC anchors (homes, merchants, guards, patrols, trainer, healer, quest givers, idlers).

## House bands: [tier, front radius, max depth, kind weights {kind: weight}].
const BANDS := [
	[&"harbor", 316.0, 19.0, {&"warehouse": 3, &"block_house": 3, &"dome_home": 3, &"tower_house": 1}],
	[&"harbor", 347.0, 21.5, {&"dome_home": 4, &"block_house": 4, &"tower_house": 2}],
	[&"middle", 383.0, 29.0, {&"block_house": 4, &"dome_home": 3, &"tower_house": 2, &"wt_hall": 1}],
	[&"middle", 437.0, 29.0, {&"block_house": 4, &"dome_home": 3, &"tower_house": 3}],
	[&"upper", 481.0, 23.5, {&"block_house": 3, &"tower_house": 4, &"dome_home": 2, &"noble_house": 1}],
	[&"upper", 517.0, 40.0, {&"noble_house": 5, &"tower_house": 3, &"wt_hall": 1, &"block_house": 2}],
	[&"palace", 573.0, 24.0, {&"noble_house": 4, &"wt_hall": 3, &"tower_house": 3}],
	[&"palace", 612.0, 30.0, {&"noble_house": 5, &"wt_hall": 2, &"tower_house": 3}],
	[&"palace", 653.0, 44.0, {&"noble_house": 5, &"wt_hall": 2, &"tower_house": 3}],
]
## Promenades (walk along the parapet of each tier step) and ring streets: [tier, radius].
const PROMENADES := [[&"harbor", 307.0], [&"middle", 376.5], [&"upper", 474.0], [&"palace", 566.0]]
const STREETS := [[&"harbor", 341.5], [&"middle", 432.5], [&"upper", 511.0], [&"palace", 605.0]]
## Market rows: [tier, street radius, b0, b1].
const MARKETS := [[&"harbor", 341.5, -70.0, -49.0], [&"harbor", 341.5, 49.0, 70.0], [&"upper", 511.0, -44.0, -24.0], [&"middle", 432.5, 12.0, 24.0]]
const HOME_KINDS: Array[StringName] = [&"dome_home", &"block_house", &"tower_house", &"noble_house"]

var P: NwtPlanner
var L: RingLayout
var plan: SettlementPlan
var rng: RandomNumberGenerator


func _init(p: NwtPlanner) -> void:
	P = p
	L = p.L
	plan = p.plan
	rng = ContentHash.rng(ContentHash.hash_name("nwt_districts"))


func build() -> void:
	_landmarks()
	_plazas()
	_markets()
	_bands()
	_street_props()
	_patrols()


## World position of a piece-local point.
static func world(pos: Vector3, yaw: float, local: Vector3) -> Vector3:
	return pos + Basis(Vector3.UP, yaw) * local


func _arc_of(tier_id: StringName) -> Array:
	var t := L.tier(tier_id)
	var a: Variant = t.get("arc")
	return [-180.0, 180.0] if a == null else [float(a[0]), float(a[1])]


# --- landmarks -----------------------------------------------------------------------------------

func _landmarks() -> void:
	var palace: Dictionary = L.record.get("palace", {})
	if not palace.is_empty():
		var pp: Vector3 = palace["position"]
		var b := L.polar(pp.x, pp.z).y
		var yaw := NwtPlanner.yaw_in(b)
		var top := float(palace.get("height", pp.y))
		var pos := Vector3(pp.x, top, pp.z)
		plan.add(&"palace", pos, yaw, {"r": float(palace["radius"]), "drop": top - P.h(&"palace")}, 2, "", float(palace["radius"]) + 10.0)
		for sx: float in [-1.0, 1.0]:
			plan.anchor(&"guard_post", world(pos, yaw, Vector3(sx * 9.5, 0.0, -float(palace["radius"]) + 3.0)), yaw + PI, {"tags": ["palace"]})
			plan.anchor(&"guard_post", world(pos, yaw, Vector3(sx * 6.0, 0.0, -24.0)), yaw + PI, {"tags": ["palace", "door"]})
		plan.anchor(&"quest_giver", world(pos, yaw, Vector3(0, 0, -float(palace["radius"]) + 8.0)), yaw + PI, {"tags": ["chief", "palace"]})
		var ring := PackedVector3Array()
		for k in 13:
			var a := TAU * k / 12.0
			ring.append(Vector3(pp.x + cos(a) * (float(palace["radius"]) - 4.0), top, pp.z + sin(a) * (float(palace["radius"]) - 4.0)))
		plan.anchor(&"patrol", ring[0], 0.0, {"points": ring, "loop": true, "tags": ["palace"]})
	var oasis: Dictionary = L.record.get("spirit_oasis", {})
	if not oasis.is_empty():
		var op: Vector3 = oasis["position"]
		var toward := Vector2(L.center.x, L.center.y) - Vector2(op.x, op.z)
		var pal: Vector3 = palace.get("position", op)
		var to_pal := Vector2(pal.x - op.x, pal.z - op.z)
		var gate_dir := (to_pal.normalized() + toward.normalized() * 0.6).normalized()
		var yaw := NwtPlanner.yaw_dir(gate_dir)
		var pos := Vector3(op.x, float(oasis.get("position").y), op.z)
		plan.add(&"oasis", pos, yaw, {"r": float(oasis["radius"]) - 3.0, "pond": float(oasis["pond_radius"]), "level": float(oasis["pond_level"])},
				2, "", float(oasis["radius"]))
		plan.anchor(&"quest_giver", world(pos, yaw, Vector3(0, 0, -float(oasis["radius"]) - 1.0)), yaw + PI, {"tags": ["oasis", "princess"]})
		for k in 3:
			var a := TAU * (k + 0.3) / 3.0
			var q := pos + Vector3(cos(a), 0, sin(a)) * (float(oasis["pond_radius"]) + 2.4)
			plan.anchor(&"idle", q, NwtPlanner.yaw_dir(Vector2(op.x - q.x, op.z - q.z)), {"tags": ["meditate", "oasis"]})
	# land gates at the ends of the middle tier
	for g in L.record.get("gates", []):
		var gp: Vector3 = g["position"]
		var pr := L.polar(gp.x, gp.z)
		var side := signf(pr.y)
		var tang := Vector2(cos(deg_to_rad(pr.y)), sin(deg_to_rad(pr.y))) * side
		var yaw := NwtPlanner.yaw_dir(tang)
		var y := P.h(&"middle")
		plan.add(&"land_gate", Vector3(gp.x, y, gp.z), yaw, {"W": 14.0, "h": 10.0, "depth": 10.0}, 2, "land_gate", 20.0)
		plan.reserve(gp.x, gp.z, 16.0)
		var mt := L.tier(&"middle")
		var r0 := float(mt["r_inner"]) + 1.0
		var r1 := float(mt["r_outer"]) - 3.0
		var gr := pr.x
		for seg in [[r0, gr - 16.0], [gr + 16.0, r1]]:
			if float(seg[1]) - float(seg[0]) < 2.0:
				continue
			P.wall_line(L.xz(float(seg[0]), pr.y), L.xz(float(seg[1]), pr.y), tang, y, y + 9.0, {"style": &"end", "depth": 3.0, "chord": 13.0})
		for sx: float in [-1.0, 1.0]:
			plan.anchor(&"guard_post", Vector3(gp.x, y, gp.z) + Vector3(tang.x, 0, tang.y) * 9.0 * sx + Basis(Vector3.UP, yaw) * Vector3(4.0, 0, 0),
					yaw if sx > 0.0 else yaw + PI, {"tags": ["gate", String(g.get("id", ""))]})
	# enterable interiors. Anchor facings are relative to the building and follow the anchor
	# contract (a -Z-forward model): 0 faces the entrance (local -Z), PI faces the back wall.
	# The healer and the master stand at the back facing the room, students face the master,
	# idlers by a side wall face the middle of the room, the resident by the door faces the fire.
	_interior(&"healer_hut", &"upper", -16.0, 536.0, 11.0, [[&"healer", Vector3(0, 0.3, 2.4), 0.0], [&"idle", Vector3(3.8, 0.3, 0.0), PI * 0.5]])
	_interior(&"training_hall", &"upper", 31.0, 534.0, 15.0, [[&"trainer", Vector3(0, 0.8, 6.0), 0.0],
		[&"student", Vector3(-2.5, 0.3, -1.0), PI], [&"student", Vector3(2.5, 0.3, -1.0), PI], [&"student", Vector3(0.0, 0.3, -3.2), PI]])
	_interior(&"family_home", &"middle", -42.0, 449.0, 7.5, [[&"home", Vector3(0, 0.3, -1.5), PI], [&"idle", Vector3(-2.6, 0.3, -0.4), -PI * 0.5]])
	# council halls
	for b in [-62.0, 64.0]:
		var pos := P.p3(531.0, b, P.h(&"upper"))
		if plan.is_free(pos.x, pos.z, 10.0):
			plan.reserve(pos.x, pos.z, 10.0)
			plan.add(&"wt_hall", pos, NwtPlanner.yaw_in(b), {"v": 0, "w": 14.0, "d": 11.0}, 2, "wt_hall:big", 10.0)
			plan.anchor(&"quest_giver", world(pos, NwtPlanner.yaw_in(b), Vector3(0, 0.6, -8.0)), NwtPlanner.yaw_in(b) + PI, {"tags": ["council"]})


func _interior(kind: StringName, tier: StringName, b: float, r: float, rad: float, anchors: Array) -> void:
	var pos := P.p3(r, b, P.h(tier))
	var yaw := NwtPlanner.yaw_in(b)
	plan.reserve(pos.x, pos.z, rad)
	plan.add(kind, pos, yaw, {}, 2, "%s:0" % kind, rad)
	for a: Array in anchors:
		plan.anchor(a[0], world(pos, yaw, a[1]), yaw + float(a[2]), {"tags": ["interior", String(kind)], "building": kind, "interior": true})
	plan.anchor(&"quest_giver" if kind != &"family_home" else &"home", world(pos, yaw, Vector3(1.6, 0, -rad - 1.5)), yaw + PI, {"tags": [String(kind), "door"]})
	plan.data.get_or_add("interiors", []).append({"kind": kind, "position": pos, "yaw": yaw})


# --- plazas ---------------------------------------------------------------------------------------

func _plazas() -> void:
	var spots: Array = []
	for s: Dictionary in plan.data.get("stairs", []):
		var b := float(s["bearing"])
		var rb := float(s["r"])
		spots.append([P.p3(rb - 35.0, b, (s["foot"] as Vector3).y), b, 9.0])
		if rb < 560.0:
			spots.append([P.p3(rb + 35.0, b, (s["top"] as Vector3).y), b, 9.0])
	if plan.data.has("spawn"):
		# the water element's spawn plaza: framed around the player (local -Z = the spawn's facing)
		var sp: Vector3 = plan.data["spawn"]
		spots.append([Vector3(sp.x, P.h(&"upper"), sp.z), L.polar(sp.x, sp.z).y, 12.0, float(plan.data.get("spawn_yaw", 0.0))])
	for s: Array in spots:
		var c: Vector3 = s[0]
		var b: float = s[1]
		var r: float = s[2]
		var spawn := s.size() > 3
		if P._in_other_canal(Vector2(c.x, c.z), &"", 4.0):
			continue
		var yaw: float = s[3] if spawn else NwtPlanner.yaw_in(b)
		plan.add(&"plaza", c, yaw, {"r": r}, 1, "plaza:%d" % int(r), r)
		plan.reserve(c.x, c.z, r + 1.0)
		var v := int(absf(b) * 7.0 + r) % 5
		if spawn:
			# keep the spawn point and the ways out clear: two braziers behind the player's shoulders
			for sx: float in [-1.0, 1.0]:
				plan.add(&"brazier", NwtDistricts.world(c, yaw, Vector3(sx * 5.0, 0, 3.0)), yaw, {"v": 0}, 1, "brazier:0", 1.0)
		else:
			var centre_kind: StringName = &"sculpture" if int(absf(b)) % 2 == 0 else &"brazier"
			plan.add(centre_kind, c, yaw, {"v": v}, 1, "%s:%d" % [centre_kind, v], 2.0)
		for k in 4:
			var a := TAU * (k + 0.5) / 4.0
			var q := NwtDistricts.world(c, yaw, Vector3(cos(a), 0, sin(a)) * (r - 1.2))
			plan.add(&"lamp_post", q, 0.0, {"v": k % 2, "light": k % 2 == 0}, 1, "lamp_post:%d:%d" % [k % 2, int(k % 2 == 0)], 0.6)
		for sx: float in [-1.0, 1.0]:
			var q := NwtDistricts.world(c, yaw, Vector3(sx * (r * 0.6), 0, r * 0.45))
			plan.add(&"bench", q, yaw + PI, {"v": 0}, 0, "bench:0", 1.2)
			plan.anchor(&"idle", q, yaw + PI, {"tags": ["bench", "plaza"]})
			var bp := NwtDistricts.world(c, yaw, Vector3(sx * (r + 1.4), 0, -r * 0.2))
			plan.add(&"banner_pole", bp, yaw, {"v": int(absf(b)) % 3}, 2, "banner_pole:%d" % (int(absf(b)) % 3), 0.8)
		plan.anchor(&"child_play", NwtDistricts.world(c, yaw, Vector3(2.5, 0, 3.5)), 0.0, {"tags": ["plaza"]})


# --- markets --------------------------------------------------------------------------------------

func _markets() -> void:
	for m: Array in MARKETS:
		var tier: StringName = m[0]
		var rs: float = m[1]
		var y := P.h(tier)
		var b := float(m[2])
		var b1 := float(m[3])
		var n := 0
		while b < b1:
			for side: float in [-1.0, 1.0]:
				var r: float = rs + side * 3.8
				var p := P.p3(r, b, y)
				if not plan.is_free(p.x, p.z, 1.9):
					continue
				var yaw := NwtPlanner.yaw_in(b) if side > 0.0 else NwtPlanner.yaw_out(b)
				var v := (n + int(side > 0.0)) % 4
				plan.add(&"stall", p, yaw, {"v": v}, 1, "stall:%d" % v, 1.9)
				plan.reserve(p.x, p.z, 1.9)
				plan.anchor(&"market_stall", world(p, yaw, Vector3(0, 0, 0.5)), yaw, {"tags": [String(tier)], "goods": ["fish", "pottery", "furs", "trinkets"][v]})
				if n % 3 == 1:
					var cp := world(p, yaw, Vector3(2.4, 0, 0.6))
					plan.add(&"crates", cp, yaw, {"v": n % 4}, 0, "crates:%d" % (n % 4), 1.2)
			n += 1
			b += RingLayout.half_angle(8.6, rs)
		var mid := P.p3(rs, (float(m[2]) + float(m[3])) * 0.5, y)
		plan.anchor(&"quest_giver", mid, NwtPlanner.yaw_in((float(m[2]) + float(m[3])) * 0.5), {"tags": ["market", String(tier)]})
		for k in 3:
			plan.anchor(&"idle", P.p3(rs, lerpf(float(m[2]), float(m[3]), (k + 0.5) / 3.0), y), 0.0, {"tags": ["market", "shopper"]})
	# fish racks along the quay promenade
	for b in [-96.0, -78.0, -40.0, 36.0, 52.0, 80.0, 96.0]:
		var p := P.p3(311.0, b, P.h(&"harbor"))
		if plan.is_free(p.x, p.z, 2.6):
			plan.reserve(p.x, p.z, 2.6)
			plan.add(&"fish_rack", p, NwtPlanner.yaw_in(b + 90.0), {"v": int(absf(b)) % 2}, 1, "fish_rack:%d" % (int(absf(b)) % 2), 2.6)
			plan.anchor(&"fisher", world(p, NwtPlanner.yaw_in(b + 90.0), Vector3(0, 0, -1.5)), NwtPlanner.yaw_in(b + 90.0) + PI, {"tags": ["fish_rack"]})


# --- houses ---------------------------------------------------------------------------------------

func _bands() -> void:
	for band: Array in BANDS:
		var tier: StringName = band[0]
		var rf: float = band[1]
		var depth: float = band[2]
		var weights: Dictionary = band[3]
		var arc := _arc_of(tier)
		var y := P.h(tier)
		var b := float(arc[0]) + RingLayout.half_angle(6.0, rf)
		var b_end := float(arc[1]) - RingLayout.half_angle(6.0, rf)
		var since_alley := 0
		while b < b_end:
			var kind := _pick(weights)
			var v := rng.randi() % 8
			var fp := _footprint(kind, v)
			if fp.y > depth:
				kind = &"dome_home" if depth >= 9.0 else &"block_house"
				v = rng.randi() % 4
				fp = _footprint(kind, v)
				if fp.y > depth:
					b += RingLayout.half_angle(4.0, rf)
					continue
			var bc := b + RingLayout.half_angle(fp.x, rf)
			var rc := rf + fp.y * 0.5 + rng.randf_range(0.0, minf(2.0, depth - fp.y))
			var yaw := NwtPlanner.yaw_in(bc)
			var pos := P.p3(rc, bc, y)
			if _fits(pos, yaw, fp):
				var rad := maxf(fp.x, fp.y) * 0.5
				_reserve_rect(pos, yaw, fp)
				var arch := "%s:%d" % [kind, v]
				var spec := {"v": v}
				if kind == &"wt_hall":
					spec = {"v": v, "w": fp.x - 2.0, "d": fp.y - 2.0}
					arch = "wt_hall:%d" % v
				plan.add(kind, pos, yaw, spec, 2, arch, rad)
				if HOME_KINDS.has(kind):
					plan.anchor(&"home", world(pos, yaw, Vector3(0, 0, -fp.y * 0.5 - 1.0)), yaw + PI,
							{"tags": [String(tier)], "building": kind, "capacity": 2 + v % 3})
				elif kind == &"warehouse":
					plan.anchor(&"worker", world(pos, yaw, Vector3(fp.x * 0.24, 0, -fp.y * 0.5 - 1.5)), yaw + PI, {"tags": ["harbor"]})
				since_alley += 1
				var gap := rng.randf_range(0.8, 2.2)
				if since_alley >= 3 + rng.randi() % 3:
					gap = rng.randf_range(3.5, 5.0)
					since_alley = 0
				b += RingLayout.half_angle((fp.x + gap) * 2.0, rf)
			else:
				b += RingLayout.half_angle(5.0, rf)


func _pick(weights: Dictionary) -> StringName:
	var total := 0.0
	for k in weights:
		total += float(weights[k])
	var x := rng.randf() * total
	for k: StringName in weights:
		x -= float(weights[k])
		if x <= 0.0:
			return k
	return weights.keys()[0]


func _footprint(kind: StringName, v: int) -> Vector2:
	if kind == &"wt_hall":
		return Vector2(14.0 + (v % 3) * 1.5, 11.5 + (v % 2) * 1.0) + Vector2(2.0, 2.0)
	return NwtHomes.footprint(kind, v)


## True when the rotated footprint rectangle is free (centre + corners + edge midpoints).
func _fits(pos: Vector3, yaw: float, fp: Vector2) -> bool:
	var bs := Basis(Vector3.UP, yaw)
	var hx := fp.x * 0.5
	var hz := fp.y * 0.5
	for q: Vector3 in [Vector3.ZERO, Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(hx, 0, hz), Vector3(-hx, 0, hz),
			Vector3(0, 0, -hz), Vector3(0, 0, hz), Vector3(-hx, 0, 0), Vector3(hx, 0, 0)]:
		var w := pos + bs * q
		if not plan.is_free(w.x, w.z, 0.6 if q != Vector3.ZERO else minf(hx, hz) * 0.8):
			return false
		if L.tier_at(w.x, w.z).is_empty():
			return false
	return true


func _reserve_rect(pos: Vector3, yaw: float, fp: Vector2) -> void:
	var bs := Basis(Vector3.UP, yaw)
	var r := minf(fp.x, fp.y) * 0.5
	var n := maxi(int(ceil(maxf(fp.x, fp.y) / maxf(minf(fp.x, fp.y), 1.0))), 1)
	var long_x := fp.x >= fp.y
	for k in n:
		var t := (float(k) + 0.5) / n - 0.5
		var q := Vector3(t * fp.x, 0, 0) if long_x else Vector3(0, 0, t * fp.y)
		var w := pos + bs * q
		plan.reserve(w.x, w.z, r * 1.05)


# --- street furniture -----------------------------------------------------------------------------

func _street_props() -> void:
	for pr: Array in PROMENADES:
		var tier: StringName = pr[0]
		var r: float = pr[1]
		var arc := _arc_of(tier)
		var y := P.h(tier)
		var step := RingLayout.half_angle(48.0, r)
		var b := float(arc[0]) + step * 0.5
		var k := 0
		while b < float(arc[1]) - 2.0:
			var p := P.p3(r - 2.2, b, y)
			if plan.is_free(p.x, p.z, 1.0):
				plan.reserve(p.x, p.z, 1.0)
				if k % 4 == 3:
					plan.add(&"brazier", p, 0.0, {"v": k % 2}, 1, "brazier:%d" % (k % 2), 1.0)
				else:
					plan.add(&"lamp_post", p, 0.0, {"v": k % 2, "light": k % 2 == 0}, 1, "lamp_post:%d:%d" % [k % 2, int(k % 2 == 0)], 0.6)
				if k % 3 == 1:
					var bp := P.p3(r - 1.6, b + step * 0.5, y)
					if plan.is_free(bp.x, bp.z, 1.3):
						plan.reserve(bp.x, bp.z, 1.3)
						plan.add(&"bench", bp, NwtPlanner.yaw_in(b + step * 0.5) + PI, {"v": 1}, 0, "bench:1", 1.2)
						plan.anchor(&"idle", bp, NwtPlanner.yaw_in(b + step * 0.5), {"tags": ["bench", "view"]})
				if k % 5 == 2:
					var sp := P.p3(r + 1.0, b + step * 0.5, y)
					if plan.is_free(sp.x, sp.z, 1.8):
						plan.reserve(sp.x, sp.z, 1.8)
						var v := k % 5
						plan.add(&"sculpture", sp, NwtPlanner.yaw_in(b), {"v": v}, 1, "sculpture:%d" % v, 1.8)
			b += step
			k += 1
	for st: Array in STREETS:
		var tier: StringName = st[0]
		var r: float = st[1]
		var arc := _arc_of(tier)
		var y := P.h(tier)
		var step := RingLayout.half_angle(64.0, r)
		var b := float(arc[0]) + step
		var k := 0
		while b < float(arc[1]) - 2.0:
			var side := 1.0 if k % 2 == 0 else -1.0
			var p := P.p3(r + side * 4.0, b, y)
			if plan.is_free(p.x, p.z, 0.9):
				plan.reserve(p.x, p.z, 0.9)
				plan.add(&"lamp_post", p, 0.0, {"v": k % 2, "light": k % 3 == 0}, 1, "lamp_post:%d:%d" % [k % 2, int(k % 3 == 0)], 0.6)
			if k % 4 == 1:
				var bp := P.p3(r - side * 4.2, b + step * 0.4, y)
				if plan.is_free(bp.x, bp.z, 1.0):
					plan.reserve(bp.x, bp.z, 1.0)
					plan.add(&"banner_pole", bp, NwtPlanner.yaw_in(b), {"v": k % 3}, 2, "banner_pole:%d" % (k % 3), 0.8)
			if k % 3 == 2 and tier == &"harbor":
				var cp := P.p3(r - side * 3.6, b - step * 0.3, y)
				if plan.is_free(cp.x, cp.z, 1.4):
					plan.reserve(cp.x, cp.z, 1.4)
					plan.add(&"crates", cp, rng.randf() * TAU, {"v": k % 4}, 0, "crates:%d" % (k % 4), 1.4)
			b += step
			k += 1


# --- patrols --------------------------------------------------------------------------------------

func _patrols() -> void:
	for pr: Array in PROMENADES:
		var tier: StringName = pr[0]
		var arc := _arc_of(tier)
		var pts := PackedVector3Array()
		var n := maxi(int((float(arc[1]) - float(arc[0])) / 6.0), 2)
		for k in n + 1:
			var b := lerpf(float(arc[0]) + 3.0, float(arc[1]) - 3.0, float(k) / n)
			pts.append(P.p3(float(pr[1]) + 2.0, b, P.h(tier)))
		plan.anchor(&"patrol", pts[0], 0.0, {"points": pts, "loop": false, "tags": [String(tier), "promenade"]})
	var harbor_master: Vector3 = plan.data.get("ferry_quay", Vector3.INF)
	if harbor_master.is_finite():
		plan.anchor(&"quest_giver", harbor_master + Vector3(4.0, 0.0, 3.0), 0.0, {"tags": ["harbor_master", "ferry"]})
