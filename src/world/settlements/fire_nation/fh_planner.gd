class_name FhPlanner
extends FnRingPlanner
## Lays out Crimson Harbor (deterministic, main thread) from the WorldData ring layout: the navy
## basin (r < 160) ringed by the basalt quay with stone piers and moored Fire Navy warships, a
## fleet at anchor, moles with watchtowers framing the harbour mouth, the dock tier (cranes, coal,
## cargo, warehouses), the Lantern Steps (houses, lantern strings), the Harbor Market (stalls),
## the Admiralty tier (the admiralty hall, officers' houses), the town wall with three gatehouses
## and grand stairs over the ramps. The ferry landing (worldscene FerryDock at the port quay) and
## the ferry's berth stay clear. Here the tiers rise outward: the retaining walls face the basin.

const ID := &"fire_harbor"
const PORT := &"port_crimson_harbor"
const DOCK_POI := &"fn_crimson_harbor"
const QUAY_FACE := 160.0
const RAMP_LEN := 40.0
## Piers into the basin (bearings) and which side their warship lies on (0 none).
const PIERS := [[214.0, -1], [234.0, -1], [254.0, -1], [274.0, -1], [294.0, -1], [314.0, -1], [334.0, 0]]
const PIER_L := 34.0
## Warships at anchor in the basin: [r, bearing, heading offset, length].
## (The ferry from Full Moon Bay crosses the basin's east half to its berth at bearing ~199.)
const FLEET := [[78.0, 250.0, 70.0, 60.0], [70.0, 300.0, -60.0, 56.0], [96.0, 345.0, 95.0, 52.0]]
## Moles: [bearing from, bearing to, radius] with a watchtower at the far end.
const MOLES := [[352.0, 24.0, 166.0], [188.0, 150.0, 166.0]]
const TOWN_WALL_R := 403.0
## House bands: [tier, front radius, depth, facing_in, kinds, style].
const BANDS := [
	[&"quay", 184.0, 12.0, true, {&"fn_warehouse": 1}, FnStyle.HARBOR],
	[&"quay", 206.0, 12.0, true, {&"fn_warehouse": 2, &"fn_townhouse": 1}, FnStyle.HARBOR],
	[&"lower", 233.0, 11.0, true, {&"fn_house": 5, &"fn_townhouse": 2}, FnStyle.LOWER],
	[&"lower", 255.0, 11.0, false, {&"fn_house": 6, &"fn_townhouse": 1}, FnStyle.LOWER],
	[&"lower", 262.0, 11.0, true, {&"fn_house": 5, &"fn_townhouse": 2}, FnStyle.LOWER],
	[&"middle", 293.0, 11.0, true, {&"fn_townhouse": 3, &"fn_house": 3}, FnStyle.LOWER],
	[&"middle", 316.0, 11.0, true, {&"fn_townhouse": 3, &"fn_house": 2}, FnStyle.LOWER],
	[&"upper", 345.0, 26.0, true, {&"noble_house": 3, &"fn_townhouse": 2}, FnStyle.NOBLE],
	[&"upper", 398.0, 21.0, false, {&"fn_townhouse": 3, &"fn_warehouse": 1}, FnStyle.NOBLE],
]
const STREETS := [[&"quay", 201.0], [&"lower", 229.5], [&"lower", 258.5], [&"lower", 280.0], [&"middle", 290.5], [&"middle", 332.0],
	[&"upper", 341.5], [&"upper", 374.0]]

var th := {}
var arcs := {}
## Ramp avenues: [[bearing, half width m], ...].
var ramp_axes: Array = []


func build() -> SettlementPlan:
	plan = SettlementPlan.new(ID, &"fire_nation")
	if not WorldData.has_world_data():
		return plan
	L = RingLayout.from_city(ID)
	if not L.is_valid():
		return plan
	rng = ContentHash.rng(ContentHash.hash_name("fh_plan"))
	cam = ArrivalClearance.for_element(ElementDefs.Element.FIRE)
	plan.display_name = String(L.record.get("name", "Crimson Harbor"))
	plan.center = Vector3(L.center.x, 0.0, L.center.y)
	plan.radius = 420.0
	plan.cell_size = 128.0
	plan.y_range = Vector2(-10.0, 70.0)
	plan.data["claims"] = [DOCK_POI]
	for t in L.tiers:
		th[StringName(t["id"])] = float(t["height"])
		var arc: Variant = t.get("arc")
		arcs[StringName(t["id"])] = Vector2(wrapf(float(arc[0]), 0.0, 360.0), wrapf(float(arc[1]), 0.0, 360.0)) if arc is Array else Vector2(0.0, 360.0)
	_axes()
	_districts()
	_reserve()
	_quay_wall()
	_steps()
	_piers_and_ships()
	_moles()
	_docks()
	_admiralty()
	_market()
	for b: Array in BANDS:
		var arc: Vector2 = arcs[b[0]]
		band(b[0], h(b[0]), float(b[1]), float(b[2]), bool(b[3]), b[4], int(b[5]), arc.x + 1.0, arc.y - 1.0, Callable(),
				Vector2(0.2, 0.9) if int(b[5]) != FnStyle.NOBLE else Vector2(0.8, 2.0))
	courtyard_trees()
	_lanterns()
	_town_wall()
	_patrols()
	return plan


func h(tier_id: StringName) -> float:
	return float(th.get(tier_id, 3.0))


func _axes() -> void:
	# one stair per terrain ramp: the two ramps at the main gate road run side by side
	for rp: Dictionary in L.ramps:
		var b := wrapf(float(rp["bearing"]), 0.0, 360.0)
		ramp_axes.append([b, float(rp.get("width", 12.0)) * 0.5 + 1.0])
		avenues.append(wrapf(b, -180.0, 180.0))


## Spans of the ring at radius r inside the bearing arc [b0, b1] (0..360), cut by the gaps.
func arc_spans(r: float, gaps: Array, arc: Vector2) -> Array:
	var out := []
	for sp: Array in ring_spans(r, gaps):
		for shift: float in [-360.0, 0.0, 360.0]:
			var a := maxf(float(sp[0]) + shift, arc.x)
			var b := minf(float(sp[1]) + shift, arc.y)
			if b > a + 0.5:
				out.append([a, b])
	return out


func _ramp_gaps(extra: float = 0.0) -> Array:
	var out := []
	for a: Array in ramp_axes:
		out.append([a[0], float(a[1]) + extra])
	return out


# --- districts + keep-outs -----------------------------------------------------------------------

func _districts() -> void:
	for t: Array in [[&"quay", "Quayside", 192.0], [&"lower", "Lantern Steps", 256.0], [&"middle", "Harbor Market", 313.0], [&"upper", "Admiralty Tier", 370.0]]:
		var arc: Vector2 = arcs[t[0]]
		var n := maxi(int(RingLayout.arc_len(arc.y - arc.x, float(t[2])) / 110.0), 1)
		for k in n:
			var b := lerpf(arc.x, arc.y, (k + 0.5) / n)
			plan.add_district(StringName("fh_%s" % t[0]), String(t[1]), p3(float(t[2]), b, h(t[0])), maxf(RingLayout.arc_len(arc.y - arc.x, float(t[2])) / n * 0.62, 50.0))
	plan.add_district(&"fh_basin", "Crimson Harbor", Vector3(L.center.x, 0.0, L.center.y), 150.0)


func _reserve() -> void:
	for a: Array in ramp_axes:
		plan.reserve_line(L.xz(160.0, float(a[0])), L.xz(410.0, float(a[0])), float(a[1]) + 1.0)
	# the gate passages through the upper tier to the town wall
	for g: Dictionary in L.record.get("gates", []):
		var b := wrapf(float(g.get("bearing", 0.0)), 0.0, 360.0)
		var c := p3(TOWN_WALL_R, b, NAN)
		plan.reserve(c.x, c.z, 16.0)
		plan.reserve_line(L.xz(TOWN_WALL_R - 34.0, b), L.xz(TOWN_WALL_R + 20.0, b), 8.0)
	for p: Dictionary in WorldData.get_ports():
		if StringName(p.get("id", "")) == PORT:
			var q: Vector3 = p["quay"]
			var berth: Vector3 = p.get("berth", q)
			plan.reserve(q.x, q.z, 13.0)
			plan.reserve_line(Vector2(q.x, q.z), Vector2(berth.x, berth.z), 14.0)
			plan.data["ferry_quay"] = q
			plan.data["ferry_berth"] = berth
			plan.anchor(&"quest_giver", q + Vector3(4.0, 0, 4.0).rotated(Vector3.UP, float(p.get("yaw", 0.0))), 0.0, {"tags": ["harbor_master", "ferry"]})


# --- the basin quay, tier steps, stairs ----------------------------------------------------------

## Basalt quay chords on the measured basin edge (top at the quay level, the water face -Z).
func _quay_wall() -> void:
	var arc: Vector2 = arcs[&"quay"]
	var y := h(&"quay")
	var n := int(ceil(RingLayout.arc_len(arc.y - arc.x, QUAY_FACE) / 12.0))
	var prev := Vector2.INF
	for k in n + 1:
		var b := lerpf(arc.x, arc.y, float(k) / n)
		var r := SettlementLayout.face_r(L, b, QUAY_FACE + 14.0, QUAY_FACE - 14.0, y - 1.0)
		var pt := L.xz(r, b)
		if prev.is_finite():
			var m := (prev + pt) * 0.5
			var mb := L.polar(m.x, m.y).y
			plan.add(&"fn_quay", Vector3(m.x, y, m.y), yaw_in(mb), {"L": snappedf(prev.distance_to(pt) + 0.1, 0.1), "H": y + 9.5, "D": 6.0}, 2, "", 7.0)
			plan.reserve(m.x, m.y, 3.0)
		prev = pt


func _steps() -> void:
	var steps := [[&"quay", &"lower", 225.0], [&"lower", &"middle", 285.0], [&"middle", &"upper", 340.0]]
	for st: Array in steps:
		var lo: StringName = st[0]
		var hi: StringName = st[1]
		var nominal := float(st[2])
		var arc: Vector2 = arcs[hi]
		# walls face the basin: the lower side is inward
		var faces := step_wall(arc_spans(nominal, _ramp_gaps(0.5), arc), h(lo), h(hi), nominal + 16.0, nominal - 16.0, nominal, 12.0, 2.4, &"crenel", 0)
		plan.data[StringName("%s_faces" % hi)] = faces
		for a: Array in _stair_axes(nominal):
			var b := float(a[0])
			if b < arc.x or b > arc.y:
				continue
			var W := float(a[1]) * 2.0 + 3.0
			var foot := p3(nominal - RAMP_LEN * 0.5, b, h(lo))
			plan.add(&"fn_stair", foot, yaw_out(b), {"H": h(hi) - h(lo), "R": RAMP_LEN, "W": W, "half": RAMP_LEN * 0.5}, 2, "", 22.0)
			plan.data.get_or_add("stairs", []).append({"bearing": b, "foot": foot, "top": p3(nominal + RAMP_LEN * 0.5, b, h(hi))})
			for sx: float in [-1.0, 1.0]:
				var gr := nominal + RAMP_LEN * 0.5 + 3.0
				plan.anchor(&"guard_post", p3(gr, b + sx * RingLayout.half_angle(W + 2.0, gr), h(hi)), yaw_in(b), {"tags": ["stair", String(hi)]})


## The stairs of a step at radius r: one per ramp, or one wide stair where two ramps overlap there
## (the twin ramps of the main gate road run together near the quay).
func _stair_axes(r: float) -> Array:
	var axes := ramp_axes.duplicate()
	axes.sort_custom(func(p: Array, q: Array) -> bool: return float(p[0]) < float(q[0]))
	var out := []
	var i := 0
	while i < axes.size():
		var a: Array = axes[i]
		if i + 1 < axes.size():
			var nb: Array = axes[i + 1]
			var sep := RingLayout.arc_len(float(nb[0]) - float(a[0]), r)
			if sep < float(a[1]) + float(nb[1]) - 1.0:
				out.append([(float(a[0]) + float(nb[0])) * 0.5, sep * 0.5 + float(a[1])])
				i += 2
				continue
		out.append(a)
		i += 1
	return out


# --- the navy basin ----------------------------------------------------------------------------

func _piers_and_ships() -> void:
	var y := h(&"quay")
	var ships := 0
	for pr: Array in PIERS:
		var b := float(pr[0])
		var r := SettlementLayout.face_r(L, b, QUAY_FACE + 14.0, QUAY_FACE - 14.0, y - 1.0)
		var root := p3(r, b, y)
		var fq: Vector3 = plan.data.get("ferry_quay", Vector3.INF)
		if fq.is_finite() and Vector2(fq.x, fq.z).distance_to(Vector2(root.x, root.z)) < 30.0:
			continue
		var yaw := yaw_in(b)
		plan.add(&"fn_pier", root, yaw, {"L": PIER_L, "W": 7.0, "depth": 9.0 + y}, 2, "fn_pier:%d" % int(PIER_L), PIER_L * 0.5)
		plan.reserve_line(L.xz(r, b), L.xz(r - PIER_L, b), 4.5)
		var tip := SettlementLayout.world(root, yaw, Vector3(0, 0, -PIER_L + 2.0))
		plan.anchor(&"worker", tip, yaw + PI, {"tags": ["dock", "pier"]})
		plan.anchor(&"idle", SettlementLayout.world(root, yaw, Vector3(2.0, 0, -6.0)), yaw, {"tags": ["sailor", "pier"]})
		var side := int(pr[1])
		if side != 0:
			var L_ship := 56.0 if ships % 3 != 2 else 50.0
			var pos := SettlementLayout.world(Vector3(root.x, 0.0, root.z), yaw, Vector3(side * 10.5, 0.0, -L_ship * 0.5 - 2.5))
			plan.add(&"warship", pos, yaw, {"L": L_ship, "v": ships % 4, "cold": ships % 2 == 1}, 2, "warship:%d:%d" % [int(L_ship), ships % 4], L_ship * 0.5)
			plan.anchor(&"guard_post", pos + Vector3(0, 3.2, 0), yaw, {"tags": ["warship", "deck", "navy"]})
			plan.data.get_or_add("ships", []).append(pos)
			ships += 1
	for f: Array in FLEET:
		var b := float(f[1])
		var pos := p3(float(f[0]), b, 0.0)
		var yaw := yaw_in(b) + deg_to_rad(float(f[2]))
		var L_ship := float(f[3])
		plan.add(&"warship", pos, yaw, {"L": L_ship, "v": ships % 4, "cold": ships % 3 != 0}, 2, "warship:%d:%d" % [int(L_ship), ships % 4], L_ship * 0.5)
		plan.data.get_or_add("ships", []).append(pos)
		ships += 1


## Basalt moles over the shoals at both ends of the quay, a watchtower at each head.
func _moles() -> void:
	var y := h(&"quay")
	for m: Array in MOLES:
		var b0 := float(m[0])
		var b1 := float(m[1])
		if b1 < b0 - 180.0:
			b1 += 360.0
		var r := float(m[2])
		var n := int(ceil(RingLayout.arc_len(absf(b1 - b0), r) / 12.0))
		var dir := signf(b1 - b0)
		for k in n:
			var a := L.xz(r, lerpf(b0, b1, float(k) / n))
			var e := L.xz(r, lerpf(b0, b1, float(k + 1) / n))
			var mid := (a + e) * 0.5
			var mb := L.polar(mid.x, mid.y).y
			# the sea face towards the basin, 8 m wide on the shoal
			plan.add(&"fn_quay", Vector3(mid.x, y, mid.y), yaw_in(mb), {"L": snappedf(a.distance_to(e) + 0.1, 0.1), "H": y + 9.5, "D": 8.0}, 2, "", 7.0)
		var head := p3(r + 4.0, b1 + dir * 1.0, y)
		plan.add(&"watchtower", head, yaw_in(b1), {"h": 18.0}, 2, "watchtower:18", 4.0)
		plan.anchor(&"guard_post", SettlementLayout.world(head, yaw_in(b1), Vector3(0, 0, -4.5)), yaw_in(b1), {"tags": ["mole", "watchtower"]})
		plan.anchor(&"fisher", p3(r + 4.0, lerpf(b0, b1, 0.6), y), yaw_in(lerpf(b0, b1, 0.6)), {"tags": ["mole", "fishing"]})


# --- the dock tier -------------------------------------------------------------------------------

func _docks() -> void:
	var y := h(&"quay")
	var arc: Vector2 = arcs[&"quay"]
	var b := arc.x + 3.0
	var k := 0
	while b < arc.y - 3.0:
		var crane_at := p3(QUAY_FACE + 6.5, b, y)
		if plan.is_free(crane_at.x, crane_at.z, 3.0):
			plan.reserve(crane_at.x, crane_at.z, 3.0)
			plan.add(&"crane", crane_at, yaw_in(b), {"v": k % 3}, 2, "crane:%d" % (k % 3), 8.0)
			plan.anchor(&"worker", SettlementLayout.world(crane_at, yaw_in(b), Vector3(2.6, 0, 1.0)), yaw_in(b), {"tags": ["dock", "crane"]})
		# coal heaps and cargo between the cranes
		for t: Array in [[175.0, &"coal_pile", 4.0, 13.0, 0], [171.5, &"crates", 1.6, 6.0, 1], [178.0, &"cart", 1.8, 20.0, 2], [172.0, &"crates", 1.6, 19.0, 0]]:
			var bb := b + RingLayout.half_angle(float(t[3]), float(t[0]))
			var p := p3(float(t[0]), bb, y)
			if k % 3 == int(t[4]) and plan.is_free(p.x, p.z, float(t[2])):
				plan.reserve(p.x, p.z, float(t[2]))
				plan.add(t[1], p, yaw_in(bb) + (k % 4) * 0.4, {"v": k % 3}, 1, "%s:%d" % [t[1], k % 3], float(t[2]))
		b += RingLayout.half_angle(2.0 * 13.0, QUAY_FACE + 6.5)
		k += 1


# --- the Admiralty and the Harbor Market ---------------------------------------------------------

func _admiralty() -> void:
	var y := h(&"upper")
	var b := 255.0                      # between the ramp avenues at 240 and 270
	var c := p3(362.0, b, y)
	var yaw := yaw_in(b)
	plan.reserve(c.x, c.z, 19.0)
	plan.add(&"fn_hall", c, yaw, {"w": 30.0, "d": 16.0, "v": 0}, 2, "fn_hall:30:16:0", 17.0)
	plan.add_district(&"fh_admiralty", "The Admiralty", c, 34.0)
	plan.districts.push_front(plan.districts.pop_back())
	plan.anchor(&"quest_giver", SettlementLayout.world(c, yaw, Vector3(0, 1.0, -6.0)), yaw + PI, {"tags": ["admiral", "navy", "admiralty"]})
	for sx: float in [-1.0, 1.0]:
		plan.anchor(&"guard_post", SettlementLayout.world(c, yaw, Vector3(sx * 6.0, 0, -12.5)), yaw + PI, {"tags": ["admiralty", "door"]})
		var fp := SettlementLayout.world(c, yaw, Vector3(sx * 12.0, 0, -13.0))
		plan.add(&"flame_pillar", fp, yaw, {"h": 5.0}, 2, "flame_pillar:5", 2.0)
		plan.reserve(fp.x, fp.z, 2.0)
	# the parade ground between the hall and the parapet over the harbour
	var pg := SettlementLayout.world(c, yaw, Vector3(0, 0, -14.0))
	plan.add(&"fn_plaza", pg, yaw + PI, {"r": 6.0, "v": 1}, 1, "fn_plaza:6:1", 6.0)
	for k in 6:
		plan.anchor(&"student", SettlementLayout.world(c, yaw, Vector3(-5.0 + k * 2.0, 0, -17.5)), yaw + PI, {"tags": ["navy", "drill"]})
	# the harbour watchtower behind the hall
	var wt := SettlementLayout.world(c, yaw, Vector3(18.0, 0, 6.0))
	if plan.is_free(wt.x, wt.z, 3.5):
		plan.add(&"watchtower", wt, yaw, {"h": 22.0}, 2, "watchtower:22", 4.0)
		plan.reserve(wt.x, wt.z, 3.5)


func _market() -> void:
	var y := h(&"middle")
	var arc: Vector2 = arcs[&"middle"]
	var n := 0
	for r: float in [307.5, 312.5]:
		var b := arc.x + 4.0
		while b < arc.y - 4.0:
			var p := p3(r, b, y)
			if not on_avenue(wrapf(b, -180.0, 180.0), r, 16.0) and plan.is_free(p.x, p.z, 1.8):
				plan.reserve(p.x, p.z, 1.8)
				var yaw := yaw_in(b) if r > 310.0 else yaw_out(b)
				var v := n % 5
				plan.add(&"fn_stall", p, yaw, {"v": v}, 1, "fn_stall:%d" % v, 1.7)
				if n % 2 == 0:
					plan.anchor(&"market_stall", SettlementLayout.world(p, yaw, Vector3(0, 0, 0.8)), yaw, {"tags": ["harbor_market", "market"],
						"goods": ["fish", "spices", "fireworks", "rope", "silk"][v]})
				n += 1
			b += RingLayout.half_angle(2.0 * (4.0 if n % 6 != 5 else 12.0), r)
	plan.anchor(&"quest_giver", p3(310.0, 255.0, y), yaw_in(255.0), {"tags": ["merchant", "harbor_market"]})


## Lantern strings across the Lantern Steps' streets, lamps and braziers along the ring streets.
func _lanterns() -> void:
	var y := h(&"lower")
	var arc: Vector2 = arcs[&"lower"]
	for r: float in [258.5, 229.5]:
		var b := arc.x + 3.0
		var k := 0
		while b < arc.y - 3.0:
			var p := p3(r, b, y)
			if plan.is_free(p.x, p.z, 1.0):
				plan.add(&"lantern_string", p, yaw_out(b) + PI * 0.5, {"L": 6.2 if r > 240.0 else 5.8, "h": 4.8, "n": 5, "light": k % 3 == 0}, 1,
						"lantern_string:%d:%d" % [int(r > 240.0), int(k % 3 == 0)], 3.5)
				k += 1
			b += RingLayout.half_angle(2.0 * 11.0, r)
	for st: Array in STREETS:
		var arc2: Vector2 = arcs[st[0]]
		_ring_lights(st[0], float(st[1]), arc2, 4 if st[0] != &"upper" else 3)


func _ring_lights(tier: StringName, r: float, arc: Vector2, brazier_every: int) -> void:
	var y := h(tier)
	var b := arc.x + 2.0
	var k := 0
	while b < arc.y - 2.0:
		var side := 1.0 if k % 2 == 0 else -1.0
		var p := p3(r + side * 2.2, b, y)
		if plan.is_free(p.x, p.z, 0.8) and not on_avenue(wrapf(b, -180.0, 180.0), r, 10.0):
			plan.reserve(p.x, p.z, 0.8)
			if k % brazier_every == brazier_every - 1:
				plan.add(&"fn_brazier", p, 0.0, {"v": 0}, 1, "fn_brazier:0", 0.9)
			else:
				plan.add(&"fn_lamp", p, yaw_in(b), {"v": k % 2, "light": k % 3 == 0}, 1, "fn_lamp:%d:%d" % [k % 2, int(k % 3 == 0)], 0.7)
		b += RingLayout.half_angle(2.0 * 24.0, r)
		k += 1


# --- the town wall and its gatehouses ------------------------------------------------------------

func _town_wall() -> void:
	var y := h(&"upper")
	var arc: Vector2 = arcs[&"upper"]
	var gates: Array = L.record.get("gates", [])
	var gaps := []
	for g: Dictionary in gates:
		var b := wrapf(float(g.get("bearing", 0.0)), 0.0, 360.0)
		var main := StringName(g.get("id", "")) == &"gate"
		var W := 12.0 if main else 9.0
		var Wt := 8.0 if main else 6.5
		gaps.append([b, W * 0.5 + Wt])
		var c := p3(TOWN_WALL_R, b, NAN)
		var spec := {"W": W, "Wt": Wt, "D": 12.0, "H": 13.0 if main else 10.0, "Ho": 8.5 if main else 7.0, "bottom": -3.0}
		plan.add(&"gate_fort", c, yaw_out(b), spec, 2, "", 16.0)
		# where the road outside runs higher than the tier, a short stair up into the passage
		# (a landing over the steep lip, slightly above the passage floor)
		var foot := p3(TOWN_WALL_R - 11.0, b, NAN)
		var pass_y := ground(c.x, c.z) + 0.15
		if pass_y - foot.y > 0.75:
			plan.add(&"fn_stair", foot, yaw_out(b), {"H": snappedf(pass_y - foot.y, 0.05), "R": 7.0, "W": W - 1.0, "half": 7.0, "landing": 5.0},
					2, "", 7.0)
		# and where the road outside climbs steeply away from the passage, a flight up to it
		var high := -INF
		for rr: float in [TOWN_WALL_R + 8.0, TOWN_WALL_R + 10.0, TOWN_WALL_R + 12.0, TOWN_WALL_R + 14.0]:
			high = maxf(high, p3(rr, b, NAN).y)
		if high - pass_y > 1.0:
			var ofoot := p3(TOWN_WALL_R + 3.0, b, pass_y)
			plan.add(&"fn_stair", ofoot, yaw_in(b) + PI, {"H": snappedf(high + 0.25 - pass_y, 0.05), "R": 7.0, "W": W - 1.0, "half": 7.0, "landing": 4.0},
					2, "", 7.0)
		plan.data.get_or_add("gates", []).append({"id": g.get("id", &""), "position": c, "yaw": yaw_out(b),
			"outside": p3(TOWN_WALL_R + 18.0, b, NAN), "inside": p3(TOWN_WALL_R - 18.0, b, NAN)})
		for sx: float in [-1.0, 1.0]:
			var gp := SettlementLayout.world(c, yaw_out(b), Vector3(sx * (W * 0.5 + 2.0), 0, -8.5))
			plan.anchor(&"guard_post", Vector3(gp.x, ground(gp.x, gp.z), gp.z), yaw_out(b), {"tags": ["harbor_gate", String(g.get("id", ""))]})
	for sp: Array in arc_spans(TOWN_WALL_R, gaps, Vector2(arc.x + 1.5, arc.y - 1.5)):
		var n := int(ceil(RingLayout.arc_len(float(sp[1]) - float(sp[0]), TOWN_WALL_R) / 10.0))
		for k in n:
			var a := L.xz(TOWN_WALL_R, lerpf(float(sp[0]), float(sp[1]), float(k) / n))
			var e := L.xz(TOWN_WALL_R, lerpf(float(sp[0]), float(sp[1]), float(k + 1) / n))
			var m := (a + e) * 0.5
			var base := minf(ground(a.x, a.y), ground(e.x, e.y))
			var top := maxf(y + 8.0, maxf(ground(a.x, a.y), ground(e.x, e.y)) + 4.0)
			plan.add(&"fn_curtain", Vector3(m.x, base, m.y), yaw_out(L.polar(m.x, m.y).y), {"L": snappedf(a.distance_to(e) + 0.15, 0.1),
				"H": snappedf(top - base, 0.5), "T": 3.5, "bottom": -3.0, "v": k % 2}, 2, "", 5.5)
			plan.reserve(m.x, m.y, 3.0)


func _patrols() -> void:
	for st: Array in [[&"quay", 170.0], [&"lower", 258.5], [&"upper", 374.0]]:
		var arc: Vector2 = arcs[st[0]]
		var pts := PackedVector3Array()
		for k in 13:
			pts.append(p3(float(st[1]), lerpf(arc.x + 3.0, arc.y - 3.0, k / 12.0), h(st[0])))
		plan.anchor(&"patrol", pts[0], 0.0, {"points": pts, "loop": false, "tags": ["crimson_harbor", String(st[0])]})
