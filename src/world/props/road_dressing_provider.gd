class_name RoadDressingProvider
extends ContentProvider
## Dresses WorldData roads outside the settlements in 256 m cells (thread-safe kit geometry, one
## mesh per nation per cell, box collision, budgeted lights):
##   lanterns    every 28 m on alternating sides in the approach band around villages and cities
##               (styled per nation: EK post lanterns, FN red post lanterns, AN stone, WT ice)
##   fences      split-rail fences along both road edges wherever the roadside is farmland
##   signposts   at junctions (road ends meeting another road), one arrow board per branch
##   milestones  every 400 m of arc length along every road
## All positions derive from each road's arc length, so every cell builds the same items no matter
## when it loads; an item belongs to the cell that contains it.

const MILESTONE_EVERY := 400.0
const LANTERN_EVERY := 28.0
const LANTERN_BAND := 220.0
const FENCE_EVERY := 3.2
const JUNCTION_DIST := 26.0

var cfg: Dictionary = {}
## [{"id", "kind", "width", "pts": PackedVector3Array, "s": PackedFloat32Array}]
var _roads: Array = []
var _seg_cells: Dictionary = {}        # Vector2i -> [[road, seg], ...]
var _junctions: Array = []             # [{"pos": Vector3, "dirs": PackedVector3Array}]
var _settlements: Array = []           # [[Vector2 centre, radius, is_city]]


func _init() -> void:
	id = &"road_dressing"
	cell_size = 256.0
	priority = 6
	unload_margin = 60.0


func configure() -> bool:
	var c := PropSettings.current()
	var changed := not cfg.is_empty() and c.hash() != cfg.hash()
	cfg = c
	range_m = float(cfg["road_range"])
	NationPalette.prepare_materials()
	if _roads.is_empty():
		_index()
	return changed


func _index() -> void:
	var sets: Array = []
	for c in WorldData.get_cities():
		var ctr: Vector3 = c["center"]
		var rc: Variant = c.get("ring_center")
		var cc := Vector2(ctr.x, ctr.z) if not (rc is Vector2) else (rc as Vector2)
		sets.append([cc, float(c.get("radius", 300.0)) + 10.0, true])
	for v in WorldData.get_villages():
		var ctr: Vector3 = v["center"]
		sets.append([Vector2(ctr.x, ctr.z), float(v.get("radius", 60.0)) * 0.8, false])
	_settlements = sets
	var roads: Array = []
	var seg_cells := {}
	for r in WorldData.get_roads():
		var pts: PackedVector3Array = r["points"]
		if pts.size() < 2:
			continue
		var s := PackedFloat32Array([0.0])
		for i in range(1, pts.size()):
			s.append(s[i - 1] + Vector2(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z).length())
		var ri := roads.size()
		roads.append({"id": r["id"], "kind": r.get("kind", &"minor"), "width": float(r.get("width", 5.0)), "pts": pts, "s": s})
		for i in pts.size() - 1:
			var lo := Vector2(minf(pts[i].x, pts[i + 1].x), minf(pts[i].z, pts[i + 1].z)) - Vector2(8, 8)
			var hi := Vector2(maxf(pts[i].x, pts[i + 1].x), maxf(pts[i].z, pts[i + 1].z)) + Vector2(8, 8)
			var c0 := coord_of(lo.x, lo.y)
			var c1 := coord_of(hi.x, hi.y)
			for cz in range(c0.y, c1.y + 1):
				for cx in range(c0.x, c1.x + 1):
					var key := Vector2i(cx, cz)
					if not seg_cells.has(key):
						seg_cells[key] = []
					(seg_cells[key] as Array).append([ri, i])
	_roads = roads
	_seg_cells = seg_cells
	# junctions: a road end within JUNCTION_DIST of another road's polyline
	var js: Array = []
	for ri in roads.size():
		var rd: Dictionary = roads[ri]
		var pts: PackedVector3Array = rd["pts"]
		for end in [0, pts.size() - 1]:
			var p := pts[end]
			if in_settlement(Vector2(p.x, p.z), 0.0):
				continue
			for rj in roads.size():
				if rj == ri:
					continue
				var hit := _closest_on(roads[rj], Vector2(p.x, p.z))
				if hit[0] > JUNCTION_DIST:
					continue
				var dirs := PackedVector3Array()
				var inward: Vector3 = (pts[1] - pts[0]) if end == 0 else (pts[end - 1] - pts[end])
				dirs.append(Vector3(inward.x, 0, inward.z).normalized())
				var q: PackedVector3Array = roads[rj]["pts"]
				var si: int = hit[1]
				var along := Vector3(q[si + 1].x - q[si].x, 0, q[si + 1].z - q[si].z).normalized()
				if float(hit[2]) > 0.05 or si > 0:
					dirs.append(-along)
				if float(hit[2]) < 0.95 or si < q.size() - 2:
					dirs.append(along)
				if not _near_structure(Vector2(p.x, p.z), 24.0):
					js.append({"pos": Vector3(p.x, 0, p.z), "dirs": dirs})
				break
	_junctions = js


## True near a POI structure (gates, shrines...) that already marks the spot.
static func _near_structure(p: Vector2, r: float) -> bool:
	for poi in WorldData.get_pois():
		var q: Vector3 = poi["position"]
		if p.distance_to(Vector2(q.x, q.z)) < r + PoiStructures.footprint(poi):
			return true
	return false


## [distance, segment index, t] of the closest point of a road polyline to p.
static func _closest_on(rd: Dictionary, p: Vector2) -> Array:
	var pts: PackedVector3Array = rd["pts"]
	var best := [INF, 0, 0.0]
	for i in pts.size() - 1:
		var a := Vector2(pts[i].x, pts[i].z)
		var b := Vector2(pts[i + 1].x, pts[i + 1].z)
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var d := p.distance_to(a + ab * t)
		if d < float(best[0]):
			best = [d, i, t]
	return best


## True inside a city or village footprint (+ margin).
func in_settlement(p: Vector2, margin: float) -> bool:
	for s: Array in _settlements:
		if p.distance_to(s[0]) < float(s[1]) + margin:
			return true
	return false


## Distance outside the nearest settlement edge (0 inside).
func _settlement_gap(p: Vector2) -> float:
	var best := INF
	for s: Array in _settlements:
		best = minf(best, maxf(p.distance_to(s[0]) - float(s[1]), 0.0))
	return best


func wants_cell(coord: Vector2i) -> bool:
	return _seg_cells.has(coord)


func build_cell(cell: ContentCell) -> void:
	var p := CellPayload.new()
	var kits := {}             # nation -> BuildingKit
	var rect := cell.rect
	var root := cell.origin()
	for e: Array in _seg_cells.get(cell.coord, []):
		var rd: Dictionary = _roads[e[0]]
		var i: int = e[1]
		var pts: PackedVector3Array = rd["pts"]
		var s: PackedFloat32Array = rd["s"]
		var a := pts[i]
		var b := pts[i + 1]
		var s0 := s[i]
		var s1 := s[i + 1]
		var seg_len := maxf(s1 - s0, 0.001)
		var dir := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
		var side := dir.cross(Vector3.UP).normalized()
		var half := float(rd["width"]) * 0.5
		var length: float = s[s.size() - 1]
		# milestones
		var k := int(ceil(s0 / MILESTONE_EVERY))
		while k * MILESTONE_EVERY < s1:
			var at := k * MILESTONE_EVERY
			k += 1
			if at < 120.0 or at > length - 120.0:
				continue
			var c := _grounded(a.lerp(b, (at - s0) / seg_len) + side * (half + 1.3))
			if rect.has_point(Vector2(c.x, c.z)) and not in_settlement(Vector2(c.x, c.z), 20.0) and _placeable(c, 0.0):
				_milestone(_kit(kits, c, cell), c - root, dir)
		# lanterns in the approach band of settlements
		k = int(ceil(s0 / LANTERN_EVERY))
		while k * LANTERN_EVERY < s1:
			var at := k * LANTERN_EVERY
			var sgn := 1.0 if k % 2 == 0 else -1.0
			k += 1
			var c := _grounded(a.lerp(b, (at - s0) / seg_len) + side * sgn * (half + 1.0))
			var c2 := Vector2(c.x, c.z)
			if not rect.has_point(c2):
				continue
			var gap := _settlement_gap(c2)
			if gap <= 0.0 or gap > LANTERN_BAND or not _placeable(c, 0.0):
				continue
			_lantern(_kit(kits, c, cell), c - root, k % 4 < 2)
		# farmland fences on both edges
		k = int(ceil(s0 / FENCE_EVERY))
		while k * FENCE_EVERY < s1:
			var at := k * FENCE_EVERY
			k += 1
			for sgn: float in [-1.0, 1.0]:
				var c := _grounded(a.lerp(b, (at - s0) / seg_len) + side * sgn * (half + 1.4))
				if not rect.has_point(Vector2(c.x, c.z)) or not _is_fence(c):
					continue
				var prev_s := at - FENCE_EVERY
				var prev := _point_at(rd, prev_s, sgn * (half + 1.4))
				var kit := _kit(kits, c, cell)
				_fence_post(kit, c - root, prev - root if prev.is_finite() and _is_fence(prev) else Vector3.INF)
	# signposts
	for j: Dictionary in _junctions:
		var jp: Vector3 = j["pos"]
		var dirs: PackedVector3Array = j["dirs"]
		var off := Vector3.ZERO
		for d in dirs:
			off -= d
		off = (off.normalized() if off.length() > 0.1 else dirs[0].cross(Vector3.UP)) * 6.5
		var c := jp + off
		if rect.has_point(Vector2(c.x, c.z)):
			c.y = WorldData.get_height(c.x, c.z)
			_signpost(_kit(kits, c, cell), c - root, dirs)
	for n: StringName in kits:
		var res := (kits[n] as BuildingKit).build()
		res.add_to_payload(p, Transform3D.IDENTITY, {"vis_end": range_m + 40.0, "margin": 10.0,
				"shadow": cfg["shadows"], "tag": StringName("road_%s" % n)})
	cell.payload = p


## Point at arc length `at` along a road, offset sideways (terrain height).
static func _point_at(rd: Dictionary, at: float, offset: float) -> Vector3:
	var s: PackedFloat32Array = rd["s"]
	var pts: PackedVector3Array = rd["pts"]
	if at < 0.0 or at > s[s.size() - 1]:
		return Vector3.INF
	var i := s.bsearch(at, true) - 1
	i = clampi(i, 0, pts.size() - 2)
	var t := (at - s[i]) / maxf(s[i + 1] - s[i], 0.001)
	var dir := Vector3(pts[i + 1].x - pts[i].x, 0, pts[i + 1].z - pts[i].z).normalized()
	var c := pts[i].lerp(pts[i + 1], t) + dir.cross(Vector3.UP).normalized() * offset
	c.y = WorldData.get_height(c.x, c.z)
	return c


## Dry, not too steep, not on another road.
func _placeable(c: Vector3, _r: float) -> bool:
	if WorldData.get_road(c.x, c.z) > 0.35:
		return false
	var h := WorldData.get_height(c.x, c.z)
	if h < 0.3 or WorldData.get_water_height(c.x, c.z) > h - 0.2:
		return false
	return WorldData.get_slope_deg(c.x, c.z) < 32.0


func _is_fence(c: Vector3) -> bool:
	if WorldData.get_biome(c.x, c.z) != WorldData.Biome.FARMLAND and WorldData.get_ground_hints(c.x, c.z).b < 0.35:
		return false
	return not in_settlement(Vector2(c.x, c.z), 15.0) and _placeable(c, 0.0)


func _kit(kits: Dictionary, c: Vector3, cell: ContentCell) -> BuildingKit:
	var nation := NationPalette.nation_for_region(WorldData.get_region(c.x, c.z))
	if not kits.has(nation):
		kits[nation] = BuildingKit.new(NationPalette.get_palette(nation), 0, cell.seed ^ ContentHash.hash_name(String(nation)))
	return kits[nation]


static func _grounded(c: Vector3) -> Vector3:
	return Vector3(c.x, WorldData.get_height(c.x, c.z), c.z)


func _milestone(kit: BuildingKit, c: Vector3, dir: Vector3) -> void:
	kit.push(Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.z)), c))
	kit.box(Vector3(0, 0.05, 0), Vector3(0.75, 0.2, 0.55), &"stone_dark", false)
	kit.box(Vector3(0, 0.5, 0), Vector3(0.5, 0.8, 0.32), &"stone", true)
	kit.g().cylinder(Vector3(-0.25, 0.9, 0), Vector3(0.25, 0.9, 0), 0.16, 0.16, 8, kit.col(&"stone"), 2)
	kit.box(Vector3(0, 0.62, 0), Vector3(0.52, 0.06, 0.34), &"trim", false)
	kit.pop()


func _lantern(kit: BuildingKit, c: Vector3, light: bool) -> void:
	var style: StringName
	match kit.palette.nation:
		&"water_tribe": style = &"ice"
		&"air_nomads": style = &"stone"
		_: style = &"post"
	kit.lantern(Vector3(c.x, c.y, c.z), {"style": style, "height": 2.2 if style == &"post" else 1.4, "light": light, "range": 10.0, "energy": 1.4})


func _fence_post(kit: BuildingKit, c: Vector3, prev: Vector3) -> void:
	kit.g().cylinder(c - Vector3(0, 0.2, 0), c + Vector3(0, 1.15, 0), 0.07, 0.06, 5, kit.col(&"wood_dark"), 1)
	if not prev.is_finite():
		return
	for h in [0.5, 0.95]:
		kit.beam(prev + Vector3(0, h, 0), c + Vector3(0, h, 0), 0.06, 0.08, &"wood")
	var mid := (prev + c) * 0.5 + Vector3(0, 0.6, 0)
	var d := c - prev
	kit.collide_box(mid, Vector3(0.15, 1.2, Vector2(d.x, d.z).length()), Basis(Vector3.UP, atan2(d.x, d.z)))


func _signpost(kit: BuildingKit, c: Vector3, dirs: PackedVector3Array) -> void:
	kit.g().cylinder(c - Vector3(0, 0.3, 0), c + Vector3(0, 3.0, 0), 0.1, 0.09, 6, kit.col(&"wood_dark"), 1)
	kit.collide_box(c + Vector3(0, 1.4, 0), Vector3(0.3, 2.8, 0.3))
	kit.push(Transform3D(Basis(), c + Vector3(0, 3.0, 0)))
	kit.box(Vector3(0, 0.08, 0), Vector3(0.5, 0.08, 0.5), &"roof", false)
	kit.g().cone(Vector3(0, 0.12, 0), Vector3(0, 0.38, 0), 0.36, 4, kit.col(&"roof"))
	kit.pop()
	for i in dirs.size():
		var d := dirs[i]
		var yaw := atan2(d.x, d.z)
		kit.push(Transform3D(Basis(Vector3.UP, yaw), c + Vector3(0, 2.55 - i * 0.38, 0)))
		kit.box(Vector3(0, 0, 0.75), Vector3(0.06, 0.26, 1.2), &"wood", false)
		kit.g().flat_tri(Vector3(0.035, 0.18, 1.35), Vector3(0.035, 0.0, 1.6), Vector3(0.035, -0.18, 1.35), kit.col(&"wood"))
		kit.g().flat_tri(Vector3(-0.035, -0.18, 1.35), Vector3(-0.035, 0.0, 1.6), Vector3(-0.035, 0.18, 1.35), kit.col(&"wood"))
		kit.box(Vector3(0, 0, 0.7), Vector3(0.075, 0.08, 0.8), &"cloth", false)
		kit.pop()
