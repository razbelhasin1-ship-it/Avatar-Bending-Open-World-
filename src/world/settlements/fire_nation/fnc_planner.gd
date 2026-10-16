class_name FncPlanner
extends FnRingPlanner
## Lays out the Fire Nation capital in its caldera (deterministic, main thread) from the WorldData
## ring layout: the Royal Palace on its tiered podium facing the Plaza of the Sun, the Palace
## Terrace (government halls, temples, gardens, the fire element's spawn plaza), the Noble
## Quarter (walled mansions, the Flame Kata Grounds, the dojo and a noble's house to enter), the
## dense Lower City with its markets, basalt retaining walls with flame merlons on the measured
## tier steps, grand stairs over the four ramps, the gatehouse fortress across the Dragon's
## Throat, braziers everywhere and the NPC anchors. The fire arrival flight crosses the palace:
## every tall piece is checked against it.

const ID := &"fire_nation_capital"
const RAMP_HALF := 10.5
## The tutorial's training ground stands on the Flame Kata Grounds: pieces there are tagged.
const KATA_TAG := &"flame_kata_grounds"
## The Dragon's Throat: the gatehouse radius on the gorge axis, the stair from the city floor
## (top) down to the gorge road (foot), the curtain chord length.
const GATE_R := 442.0
const STAIR_TOP_R := 407.0
const STAIR_FOOT_R := 427.0
const STAIR_LANDING := 6.0
const ROAD_ID := &"fn_capital_harbor"
const CURTAIN := 7.0
## The palace's grand stair at bearing 180: (top radius, foot radius).
const PALACE_STAIR := Vector2(53.0, 76.0)
## House bands: [tier, front radius, depth, facing_in, kinds, style].
const BANDS := [
	[&"palace_terrace", 64.0, 26.0, true, {&"fn_townhouse": 3, &"noble_house": 2}, FnStyle.NOBLE],
	[&"palace_terrace", 98.0, 26.0, true, {&"noble_house": 3, &"fn_townhouse": 2}, FnStyle.NOBLE],
	[&"palace_terrace", 130.0, 11.5, true, {&"fn_townhouse": 4, &"fn_house": 1}, FnStyle.NOBLE],
	[&"noble", 157.0, 28.0, true, {&"noble_house": 5, &"fn_townhouse": 2}, FnStyle.NOBLE],
	[&"noble", 213.0, 27.0, false, {&"noble_house": 4, &"fn_townhouse": 3}, FnStyle.NOBLE],
	[&"noble", 221.0, 28.0, true, {&"noble_house": 4, &"fn_townhouse": 3}, FnStyle.NOBLE],
	[&"lower_city", 276.0, 11.0, true, {&"fn_house": 6, &"fn_townhouse": 2}, FnStyle.LOWER],
	[&"lower_city", 300.0, 11.0, false, {&"fn_house": 6, &"fn_townhouse": 1}, FnStyle.LOWER],
	[&"lower_city", 308.0, 11.0, true, {&"fn_house": 6, &"fn_townhouse": 2}, FnStyle.LOWER],
	[&"lower_city", 332.0, 11.0, false, {&"fn_house": 6, &"fn_townhouse": 1}, FnStyle.LOWER],
	[&"lower_city", 340.0, 11.0, true, {&"fn_house": 6, &"fn_townhouse": 2}, FnStyle.LOWER],
	[&"lower_city", 364.0, 11.0, false, {&"fn_house": 7}, FnStyle.LOWER],
	[&"lower_city", 372.0, 12.0, true, {&"fn_house": 6, &"fn_townhouse": 1}, FnStyle.LOWER],
]
const STREETS := [[&"palace_terrace", 94.0], [&"palace_terrace", 127.0], [&"noble", 153.0], [&"noble", 217.0], [&"noble", 257.0],
	[&"lower_city", 272.0], [&"lower_city", 304.0], [&"lower_city", 336.0], [&"lower_city", 368.0]]

var th := {}
var kata := Vector3.INF


func build() -> SettlementPlan:
	plan = SettlementPlan.new(ID, &"fire_nation")
	if not WorldData.has_world_data():
		return plan
	L = RingLayout.from_city(ID)
	if not L.is_valid():
		return plan
	rng = ContentHash.rng(ContentHash.hash_name("fnc_plan"))
	cam = ArrivalClearance.for_element(ElementDefs.Element.FIRE)
	plan.display_name = String(L.record.get("name", "Fire Nation Capital"))
	plan.center = Vector3(L.center.x, 0.0, L.center.y)
	plan.radius = 470.0
	plan.cell_size = 128.0
	plan.y_range = Vector2(0.0, 64.0)
	for t in L.tiers:
		th[StringName(t["id"])] = float(t["height"])
	for rp: Dictionary in L.ramps:
		avenues.append(wrapf(float(rp["bearing"]), -180.0, 180.0))
	_districts()
	_reserve()
	_tier_steps()
	_palace()
	_terrace()
	_noble()
	_lower_city()
	for b: Array in BANDS:
		band(b[0], h(b[0]), float(b[1]), float(b[2]), bool(b[3]), b[4], int(b[5]), 0.0, 360.0, Callable(),
				Vector2(0.1, 0.6) if int(b[5]) == FnStyle.LOWER else Vector2(0.6, 1.8))
	courtyard_trees()
	for st: Array in STREETS:
		street_lights(st[0], h(st[0]), float(st[1]), 26.0 if st[0] != &"lower_city" else 30.0, 3 if st[0] != &"lower_city" else 4)
	_gorge_gate()
	_patrols()
	return plan


func h(tier_id: StringName) -> float:
	return float(th.get(tier_id, 112.0))


# --- districts + keep-outs -----------------------------------------------------------------------

func _districts() -> void:
	plan.add_district(&"fnc_palace", "Royal Palace", Vector3(L.center.x, h(&"palace"), L.center.y), 56.0)
	for t: Array in [[&"palace_terrace", "Palace Terrace", 100.0], [&"noble", "Noble Quarter", 205.0], [&"lower_city", "Lower City", 335.0]]:
		var n := maxi(int(TAU * float(t[2]) / 120.0), 1)
		for k in n:
			plan.add_district(StringName("fnc_%s" % t[0]), String(t[1]), p3(float(t[2]), 360.0 * (k + 0.5) / n, h(t[0])), maxf(TAU * float(t[2]) / n * 0.62, 60.0))


func _reserve() -> void:
	for b in avenues:
		plan.reserve_line(L.xz(28.0, b), L.xz(400.0, b), RAMP_HALF + 1.0)
	var sp := WorldData.get_spawn(ElementDefs.Element.FIRE)
	if L.tier_at(sp.origin.x, sp.origin.z).size() > 0:
		plan.data["spawn"] = sp.origin
		var f := -sp.basis.z
		plan.data["spawn_yaw"] = SettlementLayout.yaw_dir(Vector2(f.x, f.z))
		plan.reserve(sp.origin.x, sp.origin.z, 14.0)
	var poi := WorldData.get_poi(&"fn_plaza_of_the_sun")
	if not poi.is_empty():
		var pp: Vector3 = poi["position"]
		plan.reserve(pp.x, pp.z, 27.0)
		plan.data["sun_plaza"] = pp
	var kp := WorldData.get_poi(&"fn_flame_kata_grounds")
	if not kp.is_empty():
		kata = kp["position"]
		plan.reserve(kata.x, kata.z, 24.0)


# --- tier steps ----------------------------------------------------------------------------------

func _tier_steps() -> void:
	var steps := [[&"palace_terrace", &"palace", 40.0, 72.0, &"palace"], [&"noble", &"palace_terrace", 128.0, 165.0, &"crenel"],
		[&"lower_city", &"noble", 248.0, 285.0, &"crenel"]]
	for st: Array in steps:
		var lo: StringName = st[0]
		var hi: StringName = st[1]
		var nominal := float(L.tier(hi).get("r_outer", 60.0))
		var gaps := avenue_gaps(RAMP_HALF)
		if hi == &"palace":
			gaps.append([180.0, 11.5])
		var faces := step_wall(ring_spans(nominal, gaps), h(lo), h(hi), float(st[2]), float(st[3]), nominal, 12.0,
				{&"balustrade": 1.2, &"palace": 3.4}.get(st[4], 2.4), st[4], 0)
		plan.data[StringName("%s_faces" % hi)] = faces
		for b in avenues:
			var rp := L.ramp_at(b, nominal)
			var length := float(rp.get("length", 50.0))
			var foot := p3(nominal + length * 0.5, b, h(lo))
			# the palace ramps run on into the palace tier as gentle terrain slopes: the stair
			# covers the step itself, from the face to the foot
			var top_r := nominal - length * 0.5 if hi != &"palace" else nominal + 0.5
			var top := p3(top_r, b, h(hi) if hi != &"palace" else NAN)
			var run := nominal + length * 0.5 - top_r
			plan.add(&"fn_stair", foot, yaw_in(b), {"H": snappedf(top.y - h(lo), 0.05), "R": run, "W": 21.0, "half": length * 0.5 if hi != &"palace" else run},
					2, "", run * 0.55)
			plan.data.get_or_add("stairs", []).append({"bearing": b, "foot": foot, "top": top})
			for sx: float in [-1.0, 1.0]:
				var gr := top_r - 3.0
				var gp := p3(gr, b + sx * RingLayout.half_angle(2.0 * 9.0, gr), NAN)
				plan.anchor(&"guard_post", gp, yaw_out(b), {"tags": ["stair", String(hi)]})
			if hi != &"palace":
				var arch_at := p3(nominal - length * 0.5 - 6.5, b, h(hi))
				if cam.ok(arch_at.x, arch_at.z, 10.0, arch_at.y + 11.0):
					plan.add(&"fn_gate", arch_at, yaw_in(b), {"span": 12.0, "height": 8.0}, 2, "fn_gate:12:8", 9.0)


# --- the Royal Palace -----------------------------------------------------------------------------

## The Royal Palace on its tier (r < 55): the terrain ramps of the palace step climb into the tier
## from r 30 at bearings 0 / 57 / 120 / 240, so the halls and the garden only go where they fit
## between them; the podium's skirt hides the ramp under its corners. Axis: the Plaza of the Sun,
## the grand stair (bearing 180), the gate pavilion, the courtyard of flame pillars, the podium
## stair, the throne hall.
func _palace() -> void:
	var c := Vector3(L.center.x, h(&"palace"), L.center.y)
	var yaw := yaw_out(180.0)          # the palace faces south, over the Plaza of the Sun
	var at := func(lx: float, lz: float, y: float = 0.0) -> Vector3: return SettlementLayout.world(c, yaw, Vector3(lx, y, lz))
	var lh := 3.0
	var top := 3 * lh
	var pod: Vector3 = at.call(0.0, 2.0)
	plan.add(&"fn_podium", pod, yaw, {"w": 56.0, "d": 46.0, "levels": 3, "lh": lh, "bottom": -3.0}, 2, "", 36.0)
	SettlementLayout.reserve_rect(plan, pod, yaw, Vector2(56.0, 46.0))
	var hall: Vector3 = at.call(0.0, 7.0, top)
	plan.add(&"fn_throne_hall", hall, yaw, {"w": 34.0, "d": 22.0, "plinth": top}, 2, "", 22.0)
	# side halls on the palace tier flanking the podium, facing the axis
	for sx: float in [-1.0, 1.0]:
		var hb := 180.0 + sx * 91.5             # local +X is bearing 270, -X bearing 90 (between the ramps)
		var sp := p3(45.0, hb, h(&"palace"))
		var syaw := yaw_in(hb)
		if SettlementLayout.fits(plan, sp, syaw, Vector2(18.0, 12.0)) and cam.ok(sp.x, sp.z, 10.0, sp.y + 15.0):
			SettlementLayout.reserve_rect(plan, sp, syaw, Vector2(18.0, 12.0))
			plan.add(&"fn_hall", sp, syaw, {"w": 18.0, "d": 12.0, "v": int(sx > 0.0)}, 2, "fn_hall:18:12:%d" % int(sx > 0.0), 10.0)
			plan.anchor(&"idle", SettlementLayout.world(sp, syaw, Vector3(3.0, 0, -9.0)), syaw + PI, {"tags": ["palace", "courtier"]})
		for k in 2:
			var fp: Vector3 = at.call(sx * 14.0, -33.0 - k * 8.0)
			plan.add(&"flame_pillar", fp, yaw, {"h": 6.0, "embers": int(k == 0)}, 2, "flame_pillar:6", 2.0)
			plan.reserve(fp.x, fp.z, 2.0)
		plan.anchor(&"guard_post", at.call(sx * 7.0, -30.0), yaw, {"tags": ["palace", "stair"]})
		plan.anchor(&"guard_post", at.call(sx * 8.0, -6.0, top), yaw, {"tags": ["palace", "throne_hall"]})
	# the royal garden with the turtle-duck pond, where it fits between the ramps behind the hall
	for b: float in [300.0, 315.0, 290.0]:
		var gpos := p3(46.5, b, h(&"palace"))
		var gyaw := yaw_in(b)
		if SettlementLayout.fits(plan, gpos, gyaw, Vector2(16.0, 8.0)):
			SettlementLayout.reserve_rect(plan, gpos, gyaw, Vector2(16.0, 8.0))
			plan.add(&"fn_garden", gpos, gyaw, {"w": 16.0, "d": 8.0, "v": 1, "plants": 1}, 1, "", 9.0)
			plan.anchor(&"gardener", SettlementLayout.world(gpos, gyaw, Vector3(-5.0, 0, 3.0)), gyaw, {"tags": ["palace", "garden", "turtle_ducks"]})
			plan.data["royal_garden"] = gpos
			break
	# the gate pavilion over the grand stair down to the Plaza of the Sun
	var gate: Vector3 = at.call(0.0, -49.0)
	plan.add(&"fn_palace_gate", gate, yaw, {"w": 30.0, "d": 9.0}, 2, "fn_palace_gate:30", 16.0)
	plan.reserve(gate.x, gate.z, 15.0)
	var foot := p3(PALACE_STAIR.y, 180.0, h(&"palace_terrace"))
	plan.add(&"fn_stair", foot, yaw_in(180.0), {"H": h(&"palace") - h(&"palace_terrace"), "R": PALACE_STAIR.y - PALACE_STAIR.x, "W": 22.0,
		"half": PALACE_STAIR.y - PALACE_STAIR.x}, 2, "", 14.0)
	plan.reserve_line(L.xz(PALACE_STAIR.x, 180.0), L.xz(PALACE_STAIR.y + 2.0, 180.0), 11.0)
	plan.data.get_or_add("stairs", []).append({"bearing": 180.0, "foot": foot, "top": p3(PALACE_STAIR.x, 180.0, h(&"palace"))})
	for sx: float in [-1.0, 1.0]:
		plan.anchor(&"guard_post", at.call(sx * 5.5, -55.5), yaw, {"tags": ["palace", "gate"]})
	plan.add(&"fn_plaza", at.call(0.0, -37.0), yaw + PI, {"r": 6.0, "v": 2}, 1, "fn_plaza:6:2", 6.0)
	plan.anchor(&"quest_giver", at.call(0.0, 0.0, top + 1.2), yaw, {"tags": ["fire_lord", "palace", "throne_hall"]})
	var ring := PackedVector3Array()
	for k in 13:
		var a := TAU * k / 12.0
		ring.append(at.call(cos(a) * 46.0, -2.0 + sin(a) * 40.0))
	plan.anchor(&"patrol", ring[0], 0.0, {"points": ring, "loop": true, "tags": ["palace"]})
	plan.data["palace"] = {"center": c, "yaw": yaw, "courtyard": at.call(0.0, -37.0), "throne_hall": hall}


# --- Palace Terrace ------------------------------------------------------------------------------

func _terrace() -> void:
	var y := h(&"palace_terrace")
	# the Plaza of the Sun
	if plan.data.has("sun_plaza"):
		var pp: Vector3 = plan.data["sun_plaza"]
		var c := Vector3(pp.x, y, pp.z)
		var yaw := yaw_in(L.polar(pp.x, pp.z).y)
		if cam.ok(c.x, c.z, 6.0, y + 16.0):
			plan.add(&"sun_monument", c, yaw, {"r": 24.0}, 2, "", 24.0)
		else:
			plan.add(&"fn_plaza", c, yaw, {"r": 24.0, "v": 0}, 1, "fn_plaza:24:0", 24.0)
		plan.add_district(&"fnc_plaza_of_the_sun", "Plaza of the Sun", c, 28.0)
		plan.districts.push_front(plan.districts.pop_back())
		plan.anchor(&"quest_giver", SettlementLayout.world(c, yaw, Vector3(0, 0, -20.0)), yaw + PI, {"tags": ["herald", "plaza_of_the_sun"]})
		for k in 6:
			var a := TAU * k / 6.0
			plan.anchor(&"idle", c + Vector3(cos(a), 0, sin(a)) * 21.0, a, {"tags": ["plaza_of_the_sun"]})
		plan.anchor(&"child_play", c + Vector3(14.0, 0, 6.0), 0.0, {"tags": ["plaza_of_the_sun"]})
	# the fire element's spawn plaza (braziers over the player's shoulders, nothing ahead)
	if plan.data.has("spawn"):
		var sp: Vector3 = plan.data["spawn"]
		var syaw := float(plan.data.get("spawn_yaw", 0.0))
		var c := Vector3(sp.x, y, sp.z)
		plan.add(&"fn_plaza", c, syaw, {"r": 11.0, "v": 2}, 1, "fn_plaza:11:2", 11.0)
		for sx: float in [-1.0, 1.0]:
			var bp := SettlementLayout.world(c, syaw, Vector3(sx * 6.5, 0, 4.5))
			if cam.ok(bp.x, bp.z, 1.0, y + 3.2, 3.0, 2.0):
				plan.add(&"fn_brazier", bp, syaw, {"v": 1}, 1, "fn_brazier:1", 1.2)
			plan.add(&"fn_lamp", SettlementLayout.world(c, syaw, Vector3(sx * 9.0, 0, -4.0)), syaw, {"v": 1, "light": sx > 0.0}, 1, "fn_lamp:1:%d" % int(sx > 0.0), 0.7)
		plan.anchor(&"quest_giver", SettlementLayout.world(c, syaw, Vector3(3.5, 0, 6.0)), syaw + PI, {"tags": ["spawn", "guide"]})
		plan.add_district(&"fnc_spawn_plaza", "Palace Terrace", c, 14.0)
		plan.districts.push_front(plan.districts.pop_back())
	# temples and gardens between the halls
	for t: Array in [[300.0, 112.0, &"fn_temple"], [20.0, 112.0, &"fn_garden"], [150.0, 112.0, &"fn_temple"], [225.0, 76.0, &"fn_garden"]]:
		var b := float(t[0])
		var c := p3(float(t[1]), b, y)
		var yaw := yaw_in(b)
		var fp := Vector2(22.0, 20.0)
		if not SettlementLayout.fits(plan, c, yaw, fp) or not cam.ok(c.x, c.z, 12.0, y + 14.0):
			continue
		SettlementLayout.reserve_rect(plan, c, yaw, fp)
		if t[2] == &"fn_temple":
			plan.add(&"fn_temple", c, yaw, {"w": 11.0, "d": 9.0}, 2, "fn_temple:11:9", 12.0)
			plan.anchor(&"quest_giver", SettlementLayout.world(c, yaw, Vector3(0, 0, -11.0)), yaw + PI, {"tags": ["sage", "temple"]})
		else:
			plan.add(&"fn_garden", c, yaw, {"w": 22.0, "d": 20.0, "v": int(b) % 2, "plants": 2}, 1, "", 12.0)
			plan.anchor(&"gardener", SettlementLayout.world(c, yaw, Vector3(4.0, 0, 4.0)), yaw, {"tags": ["garden", "palace_terrace"]})


# --- Noble Quarter -------------------------------------------------------------------------------

func _noble() -> void:
	var y := h(&"noble")
	if kata.is_finite():
		var c := Vector3(kata.x, y, kata.z)
		var b := L.polar(kata.x, kata.z).y
		var yaw := yaw_in(b)
		plan.add(&"kata_grounds", c, yaw, {"w": 40.0, "d": 34.0, "tag": KATA_TAG}, 1, "", 22.0)
		plan.add_district(&"fnc_kata_grounds", "Flame Kata Grounds", c, 24.0)
		plan.districts.push_front(plan.districts.pop_back())
		plan.anchor(&"trainer", SettlementLayout.world(c, yaw, Vector3(0, 0.8, 14.0)), yaw + PI, {"tags": ["firebending", "master", "kata_grounds"]})
		for k in 4:
			plan.anchor(&"student", SettlementLayout.world(c, yaw, Vector3(-6.0 + k * 4.0, 0.1, 2.0)), yaw, {"tags": ["firebending", "kata_grounds"]})
		plan.data["kata"] = {"position": c, "yaw": yaw}
	# the dojo and a noble's house (enterable)
	_interior(&"fn_dojo", 44.0, 221.0, FnPlaces.DOJO_D, 14.0, [[&"trainer", Vector3(0, 1.5, 5.6), PI, ["firebending", "dojo_master"]],
		[&"student", Vector3(-3.0, 0.9, -1.0), 0.0, ["firebending"]], [&"student", Vector3(3.0, 0.9, -1.0), 0.0, ["firebending"]]])
	_interior(&"noble_interior", 102.0, 157.0, FnPlaces.NOBLE_D, 11.0, [[&"quest_giver", Vector3(0, 1.2, 1.4), PI, ["noble", "host"]],
		[&"idle", Vector3(-2.0, 1.2, 0.6), PI * 0.5, ["noble", "guest"]], [&"worker", Vector3(3.6, 1.1, -2.0), 0.0, ["servant"]]])
	for t: Array in [[250.0, 186.0], [330.0, 237.0]]:
		var b := float(t[0])
		var c := p3(float(t[1]), b, y)
		var yaw := yaw_in(b)
		if SettlementLayout.fits(plan, c, yaw, Vector2(26.0, 22.0)):
			SettlementLayout.reserve_rect(plan, c, yaw, Vector2(26.0, 22.0))
			plan.add(&"fn_garden", c, yaw, {"w": 26.0, "d": 22.0, "v": int(b) % 2, "plants": 3}, 1, "", 14.0)
			plan.anchor(&"idle", SettlementLayout.world(c, yaw, Vector3(-6.0, 0, -8.0)), yaw + PI, {"tags": ["noble", "garden"]})


func _interior(kind: StringName, b: float, rf: float, d: float, rad: float, anchors: Array) -> void:
	var y := h(&"noble")
	var pos := p3(rf + d * 0.5 + 1.0, b, y)
	var yaw := yaw_in(b)
	plan.reserve(pos.x, pos.z, rad)
	plan.add(kind, pos, yaw, {}, 2, "%s:0" % kind, rad)
	for a: Array in anchors:
		plan.anchor(a[0], SettlementLayout.world(pos, yaw, a[1]), yaw + float(a[2]), {"tags": (a[3] as Array) + ["interior", String(kind)], "building": kind,
			"interior": true})
	plan.anchor(&"guard_post" if kind == &"fn_dojo" else &"home", SettlementLayout.world(pos, yaw, Vector3(2.6, 0, -d * 0.5 - 3.4)), yaw + PI,
			{"tags": [String(kind), "door"]})
	plan.data.get_or_add("interiors", []).append({"kind": kind, "position": pos, "yaw": yaw, "d": d})


# --- Lower City ----------------------------------------------------------------------------------

func _lower_city() -> void:
	var y := h(&"lower_city")
	# markets along the ramp avenues between r 290 and 390
	var n := 0
	for b in avenues:
		var r := 292.0
		while r < 392.0:
			for side: float in [-1.0, 1.0]:
				var bb: float = b + side * RingLayout.half_angle(2.0 * 9.4, r)
				var p := p3(r, bb, y)
				var yaw := yaw_in(bb + 90.0 * side)
				if absf(r - 304.0) > 5.0 and absf(r - 336.0) > 5.0 and absf(r - 368.0) > 5.0:
					var v := n % 5
					plan.add(&"fn_stall", p, yaw, {"v": v}, 1, "fn_stall:%d" % v, 1.7)
					plan.anchor(&"market_stall", SettlementLayout.world(p, yaw, Vector3(0, 0, 0.8)), yaw, {"tags": ["lower_city", "market"],
						"goods": ["spices", "fireworks", "fish", "silk", "fire_flakes"][v]})
					n += 1
			r += 4.4
		plan.anchor(&"quest_giver", p3(350.0, b + RingLayout.half_angle(2.0 * 6.0, 350.0), y), yaw_in(b), {"tags": ["market", "merchant"]})
		plan.add_district(StringName("fnc_market_%d" % int(wrapf(b, 0.0, 360.0))), "Lower City Market", p3(340.0, b, y), 40.0)
		plan.districts.push_front(plan.districts.pop_back())
	# plazas with a dragon statue / great brazier where the ring streets cross the avenues
	for b in avenues:
		for r: float in [304.0, 368.0]:
			var c := p3(r, b, y)
			var v := int(r > 340.0)
			plan.add(&"fn_plaza", c, yaw_in(b), {"r": 9.0, "v": v}, 1, "fn_plaza:9:%d" % v, 9.0)
			plan.reserve(c.x, c.z, 10.0)
			plan.anchor(&"child_play", c + Vector3(4.0, 0, 3.0), 0.0, {"tags": ["lower_city", "plaza"]})
	# radial lanes through the house rows
	var bl := 6.0
	while bl < 366.0:
		var bb := wrapf(bl, -180.0, 180.0)
		if not on_avenue(bb, 330.0, 20.0):
			plan.reserve_line(L.xz(274.0, bb), L.xz(386.0, bb), 2.3)
		bl += 10.0


# --- the Dragon's Throat gatehouse -----------------------------------------------------------

## The gatehouse across the Dragon's Throat on the road to Crimson Harbor (GATE_R from the centre,
## where the gorge floor is ~20 m below the city), curtain walls climbing the gorge sides, and a
## grand stair from the Lower City down into the gorge (the road starts ~11 m below the caldera
## floor at the gorge mouth).
func _gorge_gate() -> void:
	var gorge: Dictionary = L.record.get("gorge", {})
	var gates: Array = L.record.get("gates", [])
	if gates.is_empty():
		return
	var b := float((gates[0] as Dictionary).get("bearing", 57.04))
	var dir := RingLayout.dir(b)
	var dir3 := Vector3(dir.x, 0, dir.y)
	var perp := Vector2(-dir.y, dir.x)
	var yaw := yaw_out(b)
	var c := p3(GATE_R, b)
	c.y = ground(c.x, c.z)
	var H := 20.0
	var top := c.y + H
	var spec := {"W": 12.0, "Wt": 10.0, "D": 16.0, "H": H, "Ho": 11.0, "bottom": -4.0}
	plan.add(&"gate_fort", c, yaw, spec, 2, "", 24.0)
	plan.reserve(c.x, c.z, 18.0)
	# curtain walls stepping up the gorge sides
	var hw := float(spec["W"]) * 0.5 + float(spec["Wt"])
	for side: float in [-1.0, 1.0]:
		var s := hw - 0.5
		var k := 0
		while s < 46.0:
			var a := Vector2(c.x, c.z) + perp * side * s
			var e := Vector2(c.x, c.z) + perp * side * (s + CURTAIN)
			var m := (a + e) * 0.5
			var lo := minf(ground(a.x, a.y), ground(e.x, e.y))
			var hi := maxf(ground(a.x, a.y), ground(e.x, e.y))
			var ctop := maxf(top - 1.5, hi + 3.5)
			var base := snappedf(lo - 1.0, 0.5)
			plan.add(&"fn_curtain", Vector3(m.x, base, m.y), yaw, {"L": CURTAIN + 0.2, "H": snappedf(ctop - base, 0.5), "T": 4.0, "bottom": -3.0, "v": k % 2},
					2, "", CURTAIN * 0.5)
			s += CURTAIN
			k += 1
	# the stair from the Lower City down to the gorge road: a landing over the crumbling lip of the
	# caldera floor (slightly above it), then the flight down, above the gorge's steep walls
	var top_p := p3(STAIR_TOP_R, b, h(&"lower_city") + 0.15)
	# the foot on the road (it bends off the gorge axis there), the flight aimed at the top
	var foot := _road_at(ROAD_ID, STAIR_FOOT_R)
	if not foot.is_finite():
		foot = p3(STAIR_FOOT_R, b)
	foot.y = ground(foot.x, foot.z)
	var run := Vector2(top_p.x - foot.x, top_p.z - foot.z).length()
	var syaw := SettlementLayout.yaw_dir(Vector2(top_p.x - foot.x, top_p.z - foot.z).normalized())
	plan.add(&"fn_stair", foot, syaw, {"H": snappedf(top_p.y - foot.y, 0.05), "R": run, "W": 14.0, "half": run, "landing": STAIR_LANDING},
			2, "", 14.0)
	plan.reserve_line(L.xz(STAIR_TOP_R - STAIR_LANDING - 4.0, b), L.xz(GATE_R + 30.0, b), 8.0)
	top_p = p3(STAIR_TOP_R - STAIR_LANDING + 1.0, b, h(&"lower_city"))
	var arch_at := p3(STAIR_TOP_R - STAIR_LANDING - 2.5, b, h(&"lower_city"))
	if cam.ok(arch_at.x, arch_at.z, 9.0, arch_at.y + 11.0):
		plan.add(&"fn_gate", arch_at, yaw_in(b), {"span": 12.0, "height": 8.0}, 2, "fn_gate:12:8", 9.0)
	var inside := _road_at(ROAD_ID, GATE_R - 9.0)
	var outside := _road_at(ROAD_ID, GATE_R + 13.0)
	plan.data["gorge_gate"] = {"position": c, "yaw": yaw, "outside": outside if outside.is_finite() else c + dir3 * 13.0,
		"inside": inside if inside.is_finite() else c - dir3 * 9.0, "stair_top": top_p, "stair_foot": foot}
	plan.add_district(&"fnc_gorge_gate", String(gorge.get("name", "The Dragon's Throat")), c, 48.0)
	plan.districts.push_front(plan.districts.pop_back())
	plan.data.get_or_add("exclusions", []).append([Vector3(c.x, 0, c.z), 56.0, ContentExclusions.TAG_TREES | ContentExclusions.TAG_ROCKS | ContentExclusions.TAG_PROPS])
	var mid := (foot + top_p) * 0.5
	plan.data["exclusions"].append([Vector3(mid.x, 0, mid.z), 16.0, ContentExclusions.TAG_TREES | ContentExclusions.TAG_ROCKS | ContentExclusions.TAG_PROPS])
	for sx: float in [-1.0, 1.0]:
		var o := SettlementLayout.world(c, yaw, Vector3(sx * 8.0, 0, -12.0))
		plan.anchor(&"guard_post", Vector3(o.x, ground(o.x, o.z), o.z), yaw, {"tags": ["gorge_gate", "outside"]})
		var i := SettlementLayout.world(c, yaw, Vector3(sx * 4.5, 0, 12.0))
		plan.anchor(&"guard_post", Vector3(i.x, ground(i.x, i.z), i.z), yaw + PI, {"tags": ["gorge_gate", "inside"]})
		plan.anchor(&"guard_post", SettlementLayout.world(c, yaw, Vector3(sx * (hw - float(spec["Wt"]) * 0.5), H + 6.0, 0)), yaw, {"tags": ["gorge_gate", "tower"]})
		plan.anchor(&"guard_post", SettlementLayout.world(top_p, yaw_in(b), Vector3(sx * 8.5, 0, -4.0)), yaw_out(b), {"tags": ["gorge_gate", "stair"]})
	var q := SettlementLayout.world(c, yaw, Vector3(5.0, 0, 15.0))
	plan.anchor(&"quest_giver", Vector3(q.x, ground(q.x, q.z), q.z), yaw + PI, {"tags": ["gatekeeper", "gorge"]})


## Where a WorldData road first crosses radius r from the city centre (INF if it does not).
func _road_at(road_id: StringName, r: float) -> Vector3:
	for rd in WorldData.get_roads():
		if StringName(rd.get("id", "")) != road_id:
			continue
		var pts: PackedVector3Array = rd.get("points", PackedVector3Array())
		for i in pts.size() - 1:
			var ra := L.polar(pts[i].x, pts[i].z).x
			var rb := L.polar(pts[i + 1].x, pts[i + 1].z).x
			if (ra - r) * (rb - r) <= 0.0 and absf(rb - ra) > 0.001:
				return pts[i].lerp(pts[i + 1], (r - ra) / (rb - ra))
	return Vector3.INF


func _patrols() -> void:
	for st: Array in [[&"palace_terrace", 134.0], [&"noble", 217.0], [&"lower_city", 336.0]]:
		var pts := PackedVector3Array()
		for k in 25:
			pts.append(p3(float(st[1]), k * 15.0, h(st[0])))
		plan.anchor(&"patrol", pts[0], 0.0, {"points": pts, "loop": true, "tags": ["fire_capital", String(st[0])]})
