class_name BssDistricts
extends RefCounted
## Second half of the Ba Sing Se layout (see BssPlanner): the royal palace complex, the spawn
## overlook, the Upper Ring mansions and gardens, the Middle Ring courtyard houses, teahouses,
## plazas and parks, the dense Lower Ring rows with their markets, the enterable tea shop and
## earthbending hall, the avenue lanterns and the NPC anchors.

## House bands: [ring, front radius, depth, facing_in, kind weights].
const LOWER_BANDS := [
	[277.0, 12.0, true], [302.0, 12.0, false], [310.0, 12.0, true], [335.0, 12.0, false], [342.0, 12.0, true], [366.0, 11.0, false],
]
const LOWER_KINDS := {&"row_house": 9, &"tenement": 2, &"shack": 1}
const MIDDLE_BANDS := [[163.0, 22.0, true], [207.0, 21.0, false], [216.0, 22.0, true], [252.0, 13.0, false]]
const MIDDLE_KINDS := {&"town_house": 5, &"court_house": 4, &"teahouse": 1}
const UPPER_BANDS := [[98.0, 30.0, false], [108.0, 30.0, true]]
## Ring streets: [tier, radius] (lamp posts, benches, patrols).
const STREETS := [[&"lower_ring", 272.0], [&"lower_ring", 306.0], [&"lower_ring", 338.5], [&"lower_ring", 369.0],
	[&"middle_ring", 159.5], [&"middle_ring", 211.5], [&"middle_ring", 257.0], [&"upper_ring", 103.0], [&"upper_ring", 142.0]]
## Middle Ring parks: [bearing, radius, width, depth].
const PARKS := [[45.0, 185.0, 46.0, 40.0], [135.0, 185.0, 46.0, 40.0], [205.0, 228.0, 40.0, 30.0], [318.0, 185.0, 46.0, 40.0]]
## Radial lanes of the Lower / Middle Ring (every n degrees, offset).
const LOWER_LANES := 9.0
const MIDDLE_LANES := 15.0

var P: BssPlanner
var L: RingLayout
var plan: SettlementPlan
var rng: RandomNumberGenerator
var cam: ArrivalClearance


func _init(p: BssPlanner) -> void:
	P = p
	L = p.L
	plan = p.plan
	cam = p.cam
	rng = ContentHash.rng(ContentHash.hash_name("bss_districts"))


func build() -> void:
	_palace()
	_spawn_overlook()
	_interiors()
	_plazas_and_parks()
	_lanes()
	_markets()
	_upper_ring()
	for b: Array in MIDDLE_BANDS:
		_band(&"middle_ring", float(b[0]), float(b[1]), bool(b[2]), MIDDLE_KINDS, EkStyle.MIDDLE)
	for b: Array in LOWER_BANDS:
		_band(&"lower_ring", float(b[0]), float(b[1]), bool(b[2]), LOWER_KINDS, EkStyle.LOWER)
	_street_props()
	_avenue_lamps()
	_patrols()


func world(pos: Vector3, yaw: float, local: Vector3) -> Vector3:
	return SettlementLayout.world(pos, yaw, local)


func y_of(tier: StringName) -> float:
	return P.h(tier)


# --- palace ------------------------------------------------------------------------------------------

func _palace() -> void:
	var c := Vector3(L.center.x, y_of(&"palace"), L.center.y)
	var yaw := BssPlanner.yaw_out(180.0)      # the palace faces south (local -Z = south)
	var at := func(lx: float, lz: float, y: float = 0.0) -> Vector3: return world(c, yaw, Vector3(lx, y, lz))
	var top := c.y + 4.0
	plan.add(&"palace_podium", at.call(0.0, 8.0), yaw, {"w": 60.0, "d": 44.0, "h": 4.0}, 2, "", 34.0)
	plan.reserve(at.call(0.0, 8.0).x, at.call(0.0, 8.0).z, 36.0)
	var hall: Vector3 = at.call(0.0, 15.0, 4.0)
	plan.add(&"throne_hall", hall, yaw, {"w": 36.0, "d": 20.0}, 2, "", 24.0)
	for sx: float in [-1.0, 1.0]:
		var sp: Vector3 = at.call(sx * 21.0, -5.0, 4.0)
		plan.add(&"palace_hall", sp, yaw, {"w": 14.0, "d": 10.0, "v": int(sx > 0.0)}, 2, "palace_hall:14:10:%d" % int(sx > 0.0), 10.0)
	var gate: Vector3 = at.call(0.0, -44.0)
	if cam.ok(gate.x, gate.z, 14.0, gate.y + 20.0):
		plan.add(&"palace_gate", gate, yaw, {"w": 26.0, "d": 10.0}, 2, "palace_gate:26", 15.0)
	plan.reserve(gate.x, gate.z, 15.0)
	var court: Vector3 = at.call(0.0, -33.0)
	plan.add(&"plaza", court, yaw, {"r": 7.0, "v": 1}, 1, "ek_plaza:7:1", 7.0)
	for sx: float in [-1.0, 1.0]:
		var pg: Vector3 = at.call(sx * 37.0, 22.0)
		var ph := EkPalace.pagoda_height(5)
		if cam.ok(pg.x, pg.z, 8.0, pg.y + ph):
			plan.add(&"pagoda", pg, yaw, {"tiers": 5, "w": 9.0}, 2, "pagoda:5:9", 8.0)
			plan.reserve(pg.x, pg.z, 9.0)
		var gd: Vector3 = at.call(sx * 36.0, -18.0)
		plan.add(&"garden", gd, yaw, {"w": 20.0, "d": 22.0, "v": int(sx > 0.0) + 2, "plants": 2}, 1, "", 14.0)
		plan.reserve(gd.x, gd.z, 12.0)
		plan.anchor(&"gardener", world(gd, yaw, Vector3(4.0, 0, 6.0)), yaw, {"tags": ["palace", "garden"]})
		for k in 3:
			var bp: Vector3 = at.call(sx * (6.0 + k * 3.0), -38.0 + k * 0.5)
			plan.add(&"lamp_post", bp, yaw, {"v": 1, "light": k == 0}, 1, "ek_lamp:1:%d" % int(k == 0), 0.8)
	# guards, the king, patrol around the podium
	plan.anchor(&"quest_giver", at.call(0.0, 2.0, 4.0 + 1.6), yaw, {"tags": ["earth_king", "palace", "throne_hall"]})
	for sx: float in [-1.0, 1.0]:
		plan.anchor(&"guard_post", at.call(sx * 5.0, -48.0), yaw, {"tags": ["palace", "gate"]})
		plan.anchor(&"guard_post", at.call(sx * 8.5, -28.0), yaw, {"tags": ["palace", "stair"]})
		plan.anchor(&"guard_post", at.call(sx * 7.0, 3.0, 4.0), yaw, {"tags": ["palace", "throne_hall"]})
		plan.anchor(&"idle", at.call(sx * 21.0, -12.5, 4.0), yaw, {"tags": ["palace", "courtier"]})
	var ring := PackedVector3Array()
	for k in 13:
		var a := TAU * k / 12.0
		ring.append(at.call(cos(a) * 33.0, 8.0 + sin(a) * 26.0))
	plan.anchor(&"patrol", ring[0], 0.0, {"points": ring, "loop": true, "tags": ["palace"]})
	plan.data["palace"] = {"center": c, "yaw": yaw, "top": top}


# --- spawn overlook ------------------------------------------------------------------------------

func _spawn_overlook() -> void:
	if not plan.data.has("spawn"):
		return
	var sp: Vector3 = plan.data["spawn"]
	var yaw := float(plan.data.get("spawn_yaw", 0.0))
	var c := Vector3(sp.x, y_of(&"upper_ring"), sp.z)
	plan.add(&"plaza", c, yaw, {"r": 12.0, "v": 2}, 1, "ek_plaza:12:2", 12.0)
	plan.reserve(c.x, c.z, 13.0)
	# braziers over the player's shoulders, lanterns + benches at the rim (nothing ahead)
	for sx: float in [-1.0, 1.0]:
		plan.add(&"lamp_post", world(c, yaw, Vector3(sx * 6.0, 0, 3.5)), yaw, {"v": 0, "light": true}, 1, "ek_lamp:0:1", 0.8)
		plan.add(&"bench", world(c, yaw, Vector3(sx * 8.5, 0, -2.0)), yaw + sx * PI * 0.5, {"v": 0}, 0, "ek_bench:0", 1.2)
		plan.anchor(&"idle", world(c, yaw, Vector3(sx * 8.5, 0, -2.0)), yaw, {"tags": ["overlook", "bench"]})
		plan.add(&"banner_pole", world(c, yaw, Vector3(sx * 10.5, 0, 6.0)), yaw, {"v": 1}, 2, "ek_banner_pole:1", 0.8)
	plan.anchor(&"quest_giver", world(c, yaw, Vector3(3.0, 0, 6.5)), yaw + PI, {"tags": ["overlook", "guide"]})
	plan.add_district(&"bss_overlook", "The Overlook", c, 16.0)
	plan.districts.push_front(plan.districts.pop_back())


# --- interiors --------------------------------------------------------------------------------------

func _interiors() -> void:
	_interior(&"tea_shop", &"lower_ring", 261.0, 310.2, true, 9.5, [[&"quest_giver", Vector3(-1.0, 0.6, 3.2), PI, ["tea_master"]],
		[&"worker", Vector3(5.4, 0.6, 3.6), PI, ["tea_shop", "cook"]], [&"idle", Vector3(-3.6, 0.6, -1.2), 0.0, ["tea_shop", "customer"]],
		[&"idle", Vector3(0.6, 0.6, -1.6), PI, ["tea_shop", "customer"]], [&"idle", Vector3(3.8, 0.6, 2.4), PI * 0.5, ["tea_shop", "customer"]]])
	_interior(&"training_hall", &"middle_ring", 296.0, 216.5, true, 15.0, [[&"trainer", Vector3(0, 1.4, 6.4), PI, ["earthbending", "master"]],
		[&"student", Vector3(-3.0, 0.7, -1.0), 0.0, ["earthbending"]], [&"student", Vector3(0.0, 0.7, -2.5), 0.0, ["earthbending"]],
		[&"student", Vector3(3.0, 0.7, -1.0), 0.0, ["earthbending"]]])


func _interior(kind: StringName, tier: StringName, b: float, r: float, facing_in: bool, rad: float, anchors: Array) -> void:
	var y := y_of(tier)
	var d := EkPlaces.TEA_D if kind == &"tea_shop" else EkPlaces.HALL_D
	var rc := r + d * 0.5 if facing_in else r - d * 0.5
	var pos := P.p3(rc, b, y)
	var yaw := BssPlanner.yaw_in(b) if facing_in else BssPlanner.yaw_out(b)
	plan.reserve(pos.x, pos.z, rad)
	plan.add(kind, pos, yaw, {}, 2, "%s:0" % kind, rad)
	for a: Array in anchors:
		plan.anchor(a[0], world(pos, yaw, a[1]), yaw + float(a[2]), {"tags": (a[3] as Array) + ["interior", String(kind)], "building": kind, "interior": true})
	plan.anchor(&"home" if kind == &"tea_shop" else &"quest_giver", world(pos, yaw, Vector3(2.4, 0, -d * 0.5 - 2.4)), yaw + PI, {"tags": [String(kind), "door"]})
	plan.data.get_or_add("interiors", []).append({"kind": kind, "position": pos, "yaw": yaw, "d": d})


# --- plazas, parks, lanes ------------------------------------------------------------------------

func _plazas_and_parks() -> void:
	# plazas where the avenues cross the main ring streets
	for b in P.avenues:
		for pr: Array in [[&"middle_ring", 211.5, 13.0], [&"lower_ring", 306.0, 12.0]]:
			var c := P.p3(float(pr[1]), b, y_of(pr[0]))
			var r := float(pr[2])
			var v := int(absf(b) / 30.0) % 2
			plan.add(&"plaza", c, BssPlanner.yaw_in(b), {"r": r, "v": v}, 1, "ek_plaza:%d:%d" % [int(r), v], r)
			plan.reserve(c.x, c.z, r + 1.0)
			plan.anchor(&"child_play", world(c, BssPlanner.yaw_in(b), Vector3(r * 0.5, 0, r * 0.4)), 0.0, {"tags": ["plaza", String(pr[0])]})
			for sx: float in [-1.0, 1.0]:
				var q := world(c, BssPlanner.yaw_in(b), Vector3(sx * (r + 2.0), 0, 0))
				plan.add(&"banner_pole", q, BssPlanner.yaw_in(b), {"v": int(absf(b)) % 3}, 2, "ek_banner_pole:%d" % (int(absf(b)) % 3), 0.8)
				plan.anchor(&"idle", world(c, BssPlanner.yaw_in(b), Vector3(sx * r * 0.7, 0, -r * 0.5)), BssPlanner.yaw_in(b), {"tags": ["plaza"]})
			if v == 1:
				plan.add(&"statue", world(c, BssPlanner.yaw_in(b), Vector3(0, 0, r * 0.62)), BssPlanner.yaw_out(b), {"v": int(absf(b)) % 2}, 2,
						"ek_statue:%d" % (int(absf(b)) % 2), 2.0)
	for pk: Array in PARKS:
		var c := P.p3(float(pk[1]), float(pk[0]), y_of(&"middle_ring"))
		var yaw := BssPlanner.yaw_in(float(pk[0]))
		var spec := {"w": float(pk[2]), "d": float(pk[3]), "v": int(float(pk[0]) / 45.0), "plants": 3}
		if not SettlementLayout.fits(plan, c, yaw, Vector2(spec["w"], spec["d"])):
			continue
		SettlementLayout.reserve_rect(plan, c, yaw, Vector2(spec["w"], spec["d"]), 1.0)
		plan.add(&"garden", c, yaw, spec, 1, "", maxf(spec["w"], spec["d"]) * 0.5)
		plan.anchor(&"gardener", world(c, yaw, Vector3(-6.0, 0, 8.0)), yaw, {"tags": ["park"]})
		for k in 3:
			plan.anchor(&"idle", world(c, yaw, Vector3(lerpf(-12.0, 12.0, k / 2.0), 0, -float(pk[3]) * 0.42)), yaw + PI, {"tags": ["park", "bench" if k != 1 else "stroll"]})
		plan.add_district(&"bss_park", "Middle Ring Gardens", c, maxf(spec["w"], spec["d"]) * 0.5)


## Radial lanes between the house rows (kept free) and a well / notice board at some crossings.
func _lanes() -> void:
	var lane := func(r0: float, r1: float, step: float, offset: float, width: float, tier: StringName) -> void:
		var b := offset
		while b < 360.0 + offset - 0.1:
			var bb := wrapf(b, -180.0, 180.0)
			if not P.on_avenue(bb, (r0 + r1) * 0.5, 22.0):
				plan.reserve_line(L.xz(r0, bb), L.xz(r1, bb), width * 0.5)
			b += step
	lane.call(276.0, 368.0, LOWER_LANES, 4.5, 4.4, &"lower_ring")
	lane.call(162.0, 254.0, MIDDLE_LANES, 7.5, 6.0, &"middle_ring")
	# wells and notice boards at Lower Ring lane mouths
	var b2 := 4.5
	var k := 0
	while b2 < 364.0:
		var bb := wrapf(b2, -180.0, 180.0)
		if not P.on_avenue(bb, 306.0, 26.0) and k % 3 == 0:
			var wp := P.p3(306.0, bb + RingLayout.half_angle(10.0, 306.0), y_of(&"lower_ring"))
			if plan.is_free(wp.x, wp.z, 1.4):
				plan.reserve(wp.x, wp.z, 1.4)
				if k % 2 == 0:
					plan.add(&"well", wp, BssPlanner.yaw_in(bb), {"v": 0}, 1, "ek_well", 1.2)
					plan.anchor(&"worker", world(wp, BssPlanner.yaw_in(bb), Vector3(0, 0, -1.6)), BssPlanner.yaw_in(bb) + PI, {"tags": ["well", "water"]})
				else:
					plan.add(&"noticeboard", wp, BssPlanner.yaw_in(bb), {"v": 0}, 0, "ek_noticeboard", 1.2)
					plan.anchor(&"quest_giver", world(wp, BssPlanner.yaw_in(bb), Vector3(0, 0, -1.4)), BssPlanner.yaw_in(bb) + PI, {"tags": ["noticeboard", "lower_ring"]})
		b2 += LOWER_LANES
		k += 1


# --- markets --------------------------------------------------------------------------------------

## Stalls lining every avenue between the inner gate and the Lower Ring plaza, and along the main
## ring street of the Lower Ring next to every avenue.
func _markets() -> void:
	var y := y_of(&"lower_ring")
	var n := 0
	for b in P.avenues:
		# along the avenue (both kerbs), r 320 .. 362
		var r := 322.0
		while r < 362.0:
			for side: float in [-1.0, 1.0]:
				var bb: float = b + side * RingLayout.half_angle(2.0 * 10.6, r)
				var p := P.p3(r, bb, y)
				var yaw := BssPlanner.yaw_in(bb + 90.0 * side)
				_stall(p, yaw, n, "avenue")
				n += 1
			r += 4.2
		# along the ring street near the avenue
		for side: float in [-1.0, 1.0]:
			for k in 6:
				var bb: float = b + side * (RingLayout.half_angle(2.0 * 15.0, 306.0) + k * RingLayout.half_angle(2.0 * 4.0, 306.0))
				for rs: float in [-1.0, 1.0]:
					var p := P.p3(306.0 + rs * 2.9, bb, y)
					_stall(p, BssPlanner.yaw_in(bb) if rs > 0.0 else BssPlanner.yaw_out(bb), n, "ring")
					n += 1
		plan.anchor(&"quest_giver", P.p3(340.0, b + RingLayout.half_angle(2.0 * 8.0, 340.0), y), BssPlanner.yaw_in(b), {"tags": ["market", "merchant_guild"]})
		plan.add_district(StringName("bss_market_%d" % int(wrapf(b, 0.0, 360.0))), "Lower Ring Market", P.p3(338.0, b, y), 30.0)
		plan.districts.push_front(plan.districts.pop_back())


func _stall(p: Vector3, yaw: float, n: int, tag: String) -> void:
	if not plan.is_free(p.x, p.z, 1.7):
		# the avenue strip itself is reserved: stalls stand on its kerbs (checked against houses only)
		if tag != "avenue":
			return
	var v := n % 6
	plan.add(&"stall", p, yaw, {"v": v}, 1, "ek_stall:%d" % v, 1.7)
	plan.reserve(p.x, p.z, 1.6)
	plan.anchor(&"market_stall", world(p, yaw, Vector3(0, 0, 0.8)), yaw, {"tags": ["lower_ring", tag], "goods": EkProps.GOODS[v]})
	if n % 4 == 1:
		plan.add(&"crates", world(p, yaw, Vector3(2.2, 0, 0.6)), yaw, {"v": n % 3}, 0, "ek_crates:%d" % (n % 3), 1.2)
	if n % 5 == 2:
		plan.anchor(&"idle", world(p, yaw, Vector3(0, 0, -1.8)), yaw + PI, {"tags": ["market", "shopper"]})


# --- Upper Ring ---------------------------------------------------------------------------------

func _upper_ring() -> void:
	var y := y_of(&"upper_ring")
	# a formal garden down the arrival corridor and gardens between the mansions
	for gb: Array in [[245.0, 120.0], [65.0, 84.0], [150.0, 122.0], [330.0, 84.0], [20.0, 122.0]]:
		var b := float(gb[0])
		var r := float(gb[1])
		var c := P.p3(r, b, y)
		var yaw := BssPlanner.yaw_in(b)
		var spec := {"w": 34.0, "d": 24.0, "v": int(b / 60.0), "plants": 1 if b == 245.0 else 2}
		if not plan.is_free(c.x, c.z, 8.0):
			continue
		SettlementLayout.reserve_rect(plan, c, yaw, Vector2(34.0, 24.0), 1.0)
		plan.add(&"garden", c, yaw, spec, 1, "", 17.0)
		plan.anchor(&"gardener", world(c, yaw, Vector3(5.0, 0, 5.0)), yaw, {"tags": ["upper_ring", "garden"]})
		plan.anchor(&"idle", world(c, yaw, Vector3(-8.0, 0, -9.0)), yaw + PI, {"tags": ["upper_ring", "garden", "noble"]})
	for b: Array in UPPER_BANDS:
		_band(&"upper_ring", float(b[0]), float(b[1]), bool(b[2]), {&"mansion": 1}, EkStyle.UPPER)
	# the grand ring avenue: trees between lamp posts
	var r := 103.0
	var step := RingLayout.half_angle(2.0 * 14.0, r)
	var bb := 0.0
	var k := 0
	var trees: Array = []
	while bb < 360.0:
		var b := wrapf(bb, -180.0, 180.0)
		if not P.on_avenue(b, r, 16.0):
			for side: float in [-1.0, 1.0]:
				var p := P.p3(r + side * 3.6, b, y)
				if k % 2 == 0:
					trees.append(p)
				elif plan.is_free(p.x, p.z, 0.8):
					plan.add(&"lamp_post", p, BssPlanner.yaw_in(b), {"v": 0, "light": k % 4 == 1}, 1, "ek_lamp:0:%d" % int(k % 4 == 1), 0.8)
		bb += step
		k += 1
	plan.data["avenue_trees"] = trees
	_tree_rows(trees, &"cypress", y)


## Rows of street trees as tree_row pieces (one per near cell: their plants are extras).
func _tree_rows(points: Array, species: StringName, _y: float) -> void:
	var by_cell := {}
	for p: Vector3 in points:
		var k := plan.coord_of(p.x, p.z)
		if not by_cell.has(k):
			by_cell[k] = []
		(by_cell[k] as Array).append(p)
	for k: Vector2i in by_cell:
		var pts: Array = by_cell[k]
		var c := Vector3.ZERO
		for p: Vector3 in pts:
			c += p
		c /= pts.size()
		plan.add(&"tree_row", c, 0.0, {"points": pts, "species": species}, 0, "", 4.0)


# --- house bands -------------------------------------------------------------------------------------

## A row of buildings along a ring street: fronts at radius rf facing the street (inward when
## facing_in), up to `depth` deep, gaps where lanes / plazas / avenues are reserved.
func _band(tier: StringName, rf: float, depth: float, facing_in: bool, kinds: Dictionary, style: int) -> void:
	var y := y_of(tier)
	var inside := func(w: Vector3) -> bool:
		var t := L.tier_at(w.x, w.z)
		return not t.is_empty() and StringName(t["id"]) == tier and absf(P.ground(w.x, w.z) - y) < 0.9
	var b := 0.0
	var since := 0
	while b < 360.0:
		var kind: StringName = SettlementLayout.pick(kinds, rng)
		var v := rng.randi() % 12
		var fp := EkHomes.footprint(kind, v)
		if fp.y > depth:
			kind = &"row_house" if style <= EkStyle.LOWER else &"town_house"
			fp = EkHomes.footprint(kind, v)
			if fp.y > depth:
				v = 0
				fp = EkHomes.footprint(kind, v)
		var bc := b + RingLayout.half_angle(fp.x, rf)
		var rc := rf + fp.y * 0.5 if facing_in else rf - fp.y * 0.5
		var bw := wrapf(bc, -180.0, 180.0)
		var yaw := BssPlanner.yaw_in(bw) if facing_in else BssPlanner.yaw_out(bw)
		var pos := P.p3(rc, bw, y)
		var hgt := EkHomes.height(kind, v)
		if SettlementLayout.fits(plan, pos, yaw, fp, inside) and cam.ok(pos.x, pos.z, maxf(fp.x, fp.y) * 0.5, y + hgt):
			SettlementLayout.reserve_rect(plan, pos, yaw, fp)
			var arch := "ek_%s:%d:%d" % [kind, v, style]
			var spec := {"v": v, "style": style}
			if kind == &"teahouse":
				spec = {"v": v % 2, "style": style}
				arch = "ek_teahouse:%d:%d" % [v % 2, style]
			plan.add(kind, pos, yaw, spec, 2, arch, maxf(fp.x, fp.y) * 0.5)
			var door := world(pos, yaw, Vector3(0, 0, -fp.y * 0.5 - 1.2))
			match kind:
				&"teahouse":
					plan.anchor(&"worker", door, yaw + PI, {"tags": [String(tier), "teahouse"], "building": kind})
					plan.anchor(&"idle", world(pos, yaw, Vector3(-fp.x * 0.3, 0.5, -fp.y * 0.12)), yaw, {"tags": [String(tier), "teahouse", "customer"]})
				&"row_house":
					var shop: bool = v % 4 == 0 and style == EkStyle.LOWER
					plan.anchor(&"market_stall" if shop else &"home", door, yaw + PI, {"tags": [String(tier)] + (["shop"] as Array if shop else []),
						"building": kind, "capacity": 2 + v % 4, "goods": EkProps.GOODS[v % EkProps.GOODS.size()] if shop else ""})
				_:
					plan.anchor(&"home", door, yaw + PI, {"tags": [String(tier)], "building": kind, "capacity": {&"tenement": 9, &"shack": 2,
						&"town_house": 4, &"court_house": 7, &"mansion": 12}.get(kind, 3)})
			since += 1
			var gap := rng.randf_range(0.05, 0.4) if style == EkStyle.LOWER else rng.randf_range(0.6, 2.0)
			if since >= 4 + rng.randi() % 3:
				gap = rng.randf_range(1.6, 3.0)
				since = 0
			b += RingLayout.half_angle((fp.x + gap) * 2.0, rf)
		else:
			b += RingLayout.half_angle(2.0 * 2.5, rf)


# --- street furniture ----------------------------------------------------------------------------

func _street_props() -> void:
	for st: Array in STREETS:
		var tier: StringName = st[0]
		var r: float = st[1]
		var y := y_of(tier)
		var spacing := 30.0 if tier == &"lower_ring" else 26.0
		var step := RingLayout.half_angle(2.0 * spacing, r)
		var b := 1.0
		var k := 0
		while b < 361.0:
			var bb := wrapf(b, -180.0, 180.0)
			var side := 1.0 if k % 2 == 0 else -1.0
			var p := P.p3(r + side * 2.6, bb, y)
			if plan.is_free(p.x, p.z, 0.7) and not P.on_avenue(bb, r, 14.0):
				plan.reserve(p.x, p.z, 0.7)
				var v := 0 if tier != &"upper_ring" else 1
				plan.add(&"lamp_post", p, BssPlanner.yaw_in(bb), {"v": v, "light": k % 3 == 0}, 1, "ek_lamp:%d:%d" % [v, int(k % 3 == 0)], 0.7)
				if k % 4 == 2:
					var bp := P.p3(r - side * 2.4, bb + step * 0.5, y)
					if plan.is_free(bp.x, bp.z, 1.1):
						plan.reserve(bp.x, bp.z, 1.1)
						plan.add(&"bench", bp, BssPlanner.yaw_in(bb + 90.0), {"v": k % 2}, 0, "ek_bench:%d" % (k % 2), 1.1)
						plan.anchor(&"idle", bp, BssPlanner.yaw_in(bb + 90.0) + PI, {"tags": [String(tier), "bench"]})
				elif k % 5 == 3 and tier != &"lower_ring":
					var pp := P.p3(r - side * 2.6, bb, y)
					if plan.is_free(pp.x, pp.z, 1.0):
						plan.reserve(pp.x, pp.z, 1.0)
						plan.add(&"planter", pp, 0.0, {"v": k % 2}, 0, "ek_planter:%d" % (k % 2), 1.0)
				elif k % 6 == 5 and tier == &"lower_ring":
					var cp := P.p3(r - side * 2.6, bb, y)
					if plan.is_free(cp.x, cp.z, 1.2):
						plan.reserve(cp.x, cp.z, 1.2)
						plan.add(&"crates", cp, rng.randf() * TAU, {"v": k % 3}, 0, "ek_crates:%d" % (k % 3), 1.2)
			b += step
			k += 1


## Lamp posts on both kerbs of every avenue from the palace podium to the outer gate.
func _avenue_lamps() -> void:
	for b in P.avenues:
		var r := 70.0
		var k := 0
		while r < 690.0:
			var y := P.ground(L.xz(r, b).x, L.xz(r, b).y)
			var skip := (r > 116.0 and r < 186.0) or (r > 318.0 and r < 396.0) or absf(r - 211.5) < 15.0 or absf(r - 306.0) < 14.0
			if not skip:
				for side: float in [-1.0, 1.0]:
					var bb: float = b + side * RingLayout.half_angle(2.0 * 11.6, r)
					var p := P.p3(r, bb, y)
					var v := 0 if r > 380.0 else (1 if r < 150.0 else 0)
					plan.add(&"lamp_post", p, BssPlanner.yaw_in(b), {"v": v, "light": k % 2 == 0}, 1, "ek_lamp:%d:%d" % [v, int(k % 2 == 0)], 0.7)
			r += 24.0 if r < 380.0 else 32.0
			k += 1


# --- patrols ---------------------------------------------------------------------------------------

func _patrols() -> void:
	for st: Array in [[&"upper_ring", 142.0], [&"middle_ring", 257.0], [&"lower_ring", 306.0], [&"lower_ring", 369.0]]:
		var pts := PackedVector3Array()
		for k in 37:
			pts.append(P.p3(float(st[1]), k * 10.0, y_of(st[0])))
		plan.anchor(&"patrol", pts[0], 0.0, {"points": pts, "loop": true, "tags": [String(st[0]), "ring_street"]})
	# stair guards
	for s: Dictionary in plan.data.get("stairs", []):
		var top: Vector3 = s["top"]
		var b := float(s["bearing"])
		for sx: float in [-1.0, 1.0]:
			plan.anchor(&"guard_post", P.p3(L.polar(top.x, top.z).x - 3.0, b + sx * RingLayout.half_angle(2.0 * 9.0, 120.0), top.y), BssPlanner.yaw_out(b),
					{"tags": ["upper_gate", "stair"]})
