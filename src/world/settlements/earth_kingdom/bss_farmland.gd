class_name BssFarmland
extends RefCounted
## The Agrarian Zone between Ba Sing Se's outer and inner walls (see BssPlanner): the fields are
## the terrain's farm plots and the ground cover's crops; this adds raised irrigation channels
## along every avenue with water wheels and footbridges, avenue trees, farm hamlets (farmhouses,
## granaries, haystacks, carts, orchards), windmills on the field edges, field huts and
## scarecrows, a fishing pier on Yuelan Lake, and the farmers' anchors.

const R0 := 400.0
const R1 := 676.0
## Irrigation channel offset from the avenue axis (clockwise side) and width.
const CANAL_OFF := 17.0
const CANAL_W := 3.0
const CANAL_SEG := 16.0

var P: BssPlanner
var L: RingLayout
var plan: SettlementPlan
var rng: RandomNumberGenerator
var cam: ArrivalClearance
var lakes: Array[Dictionary] = []


func _init(p: BssPlanner) -> void:
	P = p
	L = p.L
	plan = p.plan
	cam = p.cam
	rng = ContentHash.rng(ContentHash.hash_name("bss_farmland"))
	for lk in WorldData.get_lakes():
		var c: Vector3 = lk["center"]
		if Vector2(c.x - L.center.x, c.z - L.center.y).length() < 720.0:
			lakes.append(lk)


func build() -> void:
	_canals()
	_avenue_trees()
	_lake_pier()
	_hamlets()
	_windmills()
	_field_dressing()


func in_lake(x: float, z: float, margin: float) -> bool:
	for lk in lakes:
		var c: Vector3 = lk["center"]
		if Vector2(x - c.x, z - c.z).length() < float(lk["radius"]) + margin:
			return true
	return WorldData.get_water_height(x, z) > -INF


## True when x/z is plain farmland: inside the agrarian ring, off the avenues, out of lakes.
func is_field(x: float, z: float, margin: float) -> bool:
	var pr := L.polar(x, z)
	if pr.x < R0 + margin or pr.x > R1 - margin:
		return false
	if P.on_avenue(pr.y, pr.x, 13.0 + margin + CANAL_OFF):
		return false
	return not in_lake(x, z, margin + 4.0)


# --- irrigation ---------------------------------------------------------------------------------

func _canals() -> void:
	for b in P.avenues:
		var off := RingLayout.half_angle(2.0 * CANAL_OFF, 1.0)       # placeholder, recomputed per radius
		var r := R0 - 4.0
		var k := 0
		while r + CANAL_SEG <= R1 + 6.0:
			var rm := r + CANAL_SEG * 0.5
			off = RingLayout.half_angle(2.0 * CANAL_OFF, rm)
			var bb: float = b + off
			var a := L.xz(r, bb)
			var e := L.xz(r + CANAL_SEG, bb)
			var m := (a + e) * 0.5
			if in_lake(m.x, m.y, 3.0):
				r += CANAL_SEG
				continue
			var y := minf(P.ground(a.x, a.y), P.ground(e.x, e.y))
			var yaw := SettlementLayout.yaw_dir((e - a).normalized())
			plan.add(&"canal", Vector3(m.x, y, m.y), yaw, {"L": CANAL_SEG + 0.04, "W": CANAL_W}, 1, "ek_canal:%d" % int(CANAL_SEG), CANAL_SEG * 0.5)
			plan.reserve_line(a, e, CANAL_W * 0.5 + 1.0)
			if k % 6 == 3:
				plan.add(&"water_wheel", Vector3(m.x, y, m.y), yaw, {"v": k % 3}, 2, "ek_water_wheel:%d" % (k % 3), 4.0)
				plan.reserve(m.x + 0.0, m.y, 5.5)
				var mill := SettlementLayout.world(Vector3(m.x, y, m.y), yaw, Vector3(4.4, 0, -2.6))
				plan.anchor(&"worker", mill, yaw, {"tags": ["mill", "farm"]})
			elif k % 6 == 0:
				plan.add(&"footbridge", Vector3(m.x, y, m.y), yaw + PI * 0.5, {"span": 4.0, "width": 2.4, "hump": 1.4}, 1, "ek_footbridge:4", 4.0)
			r += CANAL_SEG
			k += 1


func _avenue_trees() -> void:
	var trees: Array = []
	for b in P.avenues:
		var r := R0 + 6.0
		while r < R1 - 4.0:
			# the canal side is the clockwise one: trees on the far kerb, one row
			var bb: float = b - RingLayout.half_angle(2.0 * 15.5, r)
			var p := P.p3(r, bb)
			if not in_lake(p.x, p.z, 4.0):
				trees.append(p)
			r += 22.0
	var by_cell := {}
	for p: Vector3 in trees:
		var k := plan.coord_of(p.x, p.z)
		if not by_cell.has(k):
			by_cell[k] = []
		(by_cell[k] as Array).append(p)
	for k: Vector2i in by_cell:
		var pts: Array = by_cell[k]
		plan.add(&"tree_row", pts[0], 0.0, {"points": pts, "species": &"oak"}, 0, "", 4.0)


# --- Yuelan Lake --------------------------------------------------------------------------------

func _lake_pier() -> void:
	for lk in lakes:
		var c: Vector3 = lk["center"]
		var lvl := float(lk.get("level", c.y))
		# the shore point closest to the city centre
		var to_city := (L.center - Vector2(c.x, c.z)).normalized()
		var shore := Vector2.ZERO
		var found := false
		for k in 40:
			var q := Vector2(c.x, c.z) + to_city * (float(lk["radius"]) * (0.3 + k * 0.025))
			if WorldData.get_water_height(q.x, q.y) == -INF:
				shore = q
				found = true
				break
		if not found:
			continue
		var yaw := SettlementLayout.yaw_dir(-to_city)
		var base := Vector3(shore.x, lvl + 0.6, shore.y)
		plan.add(&"lake_pier", base, yaw, {"L": 18.0, "W": 2.6}, 1, "ek_lake_pier:18", 9.0)
		plan.reserve_line(shore, shore - to_city * 20.0, 3.0)
		var tip := SettlementLayout.world(base, yaw, Vector3(0, 0, -16.0))
		plan.anchor(&"fisher", tip, yaw, {"tags": ["lake", "pier"]})
		for sx: float in [-1.0, 1.0]:
			var bp := SettlementLayout.world(Vector3(base.x, lvl, base.z), yaw, Vector3(sx * 2.8, 0, -9.0 - sx * 3.0))
			plan.add(&"rowboat", bp, yaw + sx * 0.2, {"v": int(sx > 0.0)}, 1, "ek_rowboat:%d" % int(sx > 0.0), 2.5)
			plan.anchor(&"boat", bp, yaw, {"tags": ["lake"]})
		plan.add_district(&"bss_yuelan_lake", String(lk.get("name", "Yuelan Lake")), c, float(lk["radius"]) + 10.0)


# --- hamlets ------------------------------------------------------------------------------------

func _hamlets() -> void:
	var centres: Array[Vector2] = []
	var tries := 0
	while centres.size() < 30 and tries < 900:
		tries += 1
		var r := rng.randf_range(R0 + 30.0, R1 - 30.0)
		var b := rng.randf_range(-180.0, 180.0)
		var c := L.xz(r, b)
		if not is_field(c.x, c.y, 24.0):
			continue
		var ok := true
		for o in centres:
			if o.distance_to(c) < 95.0:
				ok = false
				break
		if ok and plan.is_free(c.x, c.y, 22.0):
			centres.append(c)
	for i in centres.size():
		_hamlet(centres[i], i)


func _hamlet(c: Vector2, idx: int) -> void:
	var hrng := ContentHash.rng(ContentHash.hash4(int(c.x), int(c.y), 41))
	var n := 2 + hrng.randi() % 3
	var face := PI + hrng.randf_range(-0.35, 0.35)       # farmhouses face south
	var placed := 0
	var plants: Array = []
	for k in n:
		var a := TAU * k / n + hrng.randf() * 0.6
		var rr := 0.0 if k == 0 else hrng.randf_range(20.0, 26.0)
		var q := c + Vector2(cos(a), sin(a)) * rr
		var v := hrng.randi() % 6
		var fp := EkHomes.footprint(&"farmhouse", v)
		var yaw := face + hrng.randf_range(-0.2, 0.2)
		var lo := SettlementLayout.ground_range(q.x, q.y, maxf(fp.x, fp.y) * 0.5).x
		var pos := Vector3(q.x, lo, q.y)
		if not is_field(q.x, q.y, 8.0) or not SettlementLayout.fits(plan, pos, yaw, fp + Vector2(2, 2)):
			continue
		SettlementLayout.reserve_rect(plan, pos, yaw, fp + Vector2(2, 2))
		plan.add(&"farmhouse", pos, yaw, {"v": v, "style": EkStyle.FARM}, 2, "ek_farmhouse:%d" % v, maxf(fp.x, fp.y) * 0.5)
		plan.anchor(&"home", SettlementLayout.world(pos, yaw, Vector3(-fp.x * 0.15, 0, -fp.y * 0.5 - 1.0)), yaw + PI, {"tags": ["farm", "agrarian"],
			"building": &"farmhouse", "capacity": 3 + v % 3})
		plan.anchor(&"worker", SettlementLayout.world(pos, yaw, Vector3(fp.x * 0.3, 0, -fp.y * 0.5 - 5.0)), yaw, {"tags": ["farmer", "field"]})
		# trees behind the house
		for t in 2:
			plants.append([&"oak" if (t + v) % 3 != 0 else &"maple", SettlementLayout.world(pos, yaw, Vector3((t - 0.5) * fp.x * 0.8, 0, fp.y * 0.5 + 3.5)),
				hrng.randf_range(0.8, 1.1)])
		placed += 1
	if placed == 0:
		return
	# granary, haystacks, a scarecrow in the fields
	var gp := c + Vector2(hrng.randf_range(-1, 1), hrng.randf_range(-1, 1)).normalized() * 14.0
	if is_field(gp.x, gp.y, 4.0) and plan.is_free(gp.x, gp.y, 3.5):
		plan.reserve(gp.x, gp.y, 3.5)
		plan.add(&"granary", Vector3(gp.x, P.ground(gp.x, gp.y), gp.y), face, {"v": idx % 3}, 2, "ek_granary:%d" % (idx % 3), 3.0)
	for k in 2 + hrng.randi() % 3:
		var a := hrng.randf() * TAU
		var hp := c + Vector2(cos(a), sin(a)) * hrng.randf_range(28.0, 40.0)
		if is_field(hp.x, hp.y, 2.0) and plan.is_free(hp.x, hp.y, 2.0):
			plan.reserve(hp.x, hp.y, 2.0)
			plan.add(&"haystack", Vector3(hp.x, P.ground(hp.x, hp.y), hp.y), a, {"v": k % 2}, 1, "ek_haystack:%d" % (k % 2), 1.8)
	if plants.size() > 0:
		plan.add(&"orchard", Vector3(c.x, P.ground(c.x, c.y), c.y), 0.0, {"plants": plants}, 0, "", 20.0)
	if idx % 4 == 0:
		plan.anchor(&"quest_giver", Vector3(c.x, P.ground(c.x, c.y), c.y) + Vector3(3.0, 0, -3.0), face, {"tags": ["farm_elder", "agrarian"]})
	if idx % 3 == 1:
		plan.anchor(&"child_play", Vector3(c.x, P.ground(c.x, c.y), c.y) + Vector3(-5.0, 0, -8.0), 0.0, {"tags": ["farm"]})
	plan.add_district(StringName("bss_hamlet_%d" % idx), "Farmstead", Vector3(c.x, P.ground(c.x, c.y), c.y), 40.0)
	plan.districts.push_front(plan.districts.pop_back())


func _windmills() -> void:
	var placed := 0
	var tries := 0
	var spots: Array[Vector2] = []
	while placed < 18 and tries < 600:
		tries += 1
		var r := rng.randf_range(R0 + 20.0, R1 - 20.0)
		var b := rng.randf_range(-180.0, 180.0)
		var p := L.xz(r, b)
		if not is_field(p.x, p.y, 6.0) or not plan.is_free(p.x, p.y, 6.0):
			continue
		var ok := true
		for s in spots:
			if s.distance_to(p) < 110.0:
				ok = false
		if not ok:
			continue
		var y := SettlementLayout.ground_range(p.x, p.y, 2.5).x
		if not cam.ok(p.x, p.y, 8.0, y + 19.0):
			continue
		spots.append(p)
		plan.reserve(p.x, p.y, 6.0)
		# sails face the prevailing wind (from the west)
		var yaw := deg_to_rad(90.0) + rng.randf_range(-0.3, 0.3)
		plan.add(&"windmill", Vector3(p.x, y, p.y), yaw, {"v": placed % 3}, 2, "ek_windmill:%d" % (placed % 3), 4.0)
		plan.anchor(&"worker", SettlementLayout.world(Vector3(p.x, y, p.y), yaw, Vector3(1.2, 0, -3.4)), yaw + PI, {"tags": ["miller", "windmill"]})
		placed += 1


func _field_dressing() -> void:
	var n := 0
	var tries := 0
	while n < 60 and tries < 800:
		tries += 1
		var r := rng.randf_range(R0 + 10.0, R1 - 10.0)
		var b := rng.randf_range(-180.0, 180.0)
		var p := L.xz(r, b)
		# on the farm plot grid corners (TerrainPatterns.PLOT_SIZE) so huts sit on field edges
		p = Vector2(roundf(p.x / TerrainPatterns.PLOT_SIZE.x) * TerrainPatterns.PLOT_SIZE.x, roundf(p.y / TerrainPatterns.PLOT_SIZE.y) * TerrainPatterns.PLOT_SIZE.y)
		if not is_field(p.x, p.y, 3.0) or not plan.is_free(p.x, p.y, 3.0):
			continue
		plan.reserve(p.x, p.y, 3.0)
		var y := P.ground(p.x, p.y)
		var kind: StringName = [&"field_hut", &"scarecrow", &"scarecrow", &"cart"][n % 4]
		var yaw := rng.randf() * TAU
		match kind:
			&"field_hut":
				plan.add(&"field_hut", Vector3(p.x, y, p.y), yaw, {"v": n % 3}, 1, "ek_field_hut:%d" % (n % 3), 2.0)
				plan.anchor(&"worker", Vector3(p.x, y, p.y) + Vector3(0.6, 0, 0.4), yaw, {"tags": ["farmer", "rest"]})
			&"scarecrow":
				plan.add(&"scarecrow", Vector3(p.x + 9.0, P.ground(p.x + 9.0, p.y + 6.0), p.y + 6.0), yaw, {"v": n % 5}, 0, "ek_scarecrow:%d" % (n % 5), 1.0)
			&"cart":
				plan.add(&"cart", Vector3(p.x, y, p.y), yaw, {"v": 0}, 0, "ek_cart", 1.6)
		n += 1
