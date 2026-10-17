class_name WorldRecords
extends RefCounted
## Parsed world.json: settlements, roads, water bodies, POIs, spawns and cameras.
##
## JSON vectors are converted once at load: [x, y, z] / [x, z] under position-like keys become
## Vector3 / Vector2, lists of points become PackedVector3Array / PackedVector2Array, and ids,
## types, kinds and regions become StringName.

const VEC_KEYS := ["position", "center", "quay", "berth", "a", "b", "top", "bottom", "entrance",
		"inner_gate", "outside", "inner", "outer", "look_at", "ring_center", "gate"]
const NAME_KEYS := ["id", "type", "kind", "region", "settlement", "from", "to", "tier", "pool", "surface"]
const BUCKET := 512.0

var meta: Dictionary = {}
var cities: Array[Dictionary] = []
var villages: Array[Dictionary] = []
var roads: Array[Dictionary] = []
var ports: Array[Dictionary] = []
var ferries: Array[Dictionary] = []
var lakes: Array[Dictionary] = []
var canals: Array[Dictionary] = []
var waterfalls: Array[Dictionary] = []
var bridges: Array[Dictionary] = []
var arches: Array[Dictionary] = []
var pois: Array[Dictionary] = []
var spawns: Dictionary = {}
var cameras: Dictionary = {}

var _poi_by_id: Dictionary = {}
var _city_by_id: Dictionary = {}
## bucket key (Vector2i) -> Array of {"kind": &"lake"|&"canal", "index": int}
var _water_buckets: Dictionary = {}


## Parses world.json. Returns "" or an error message.
func load_file(path: String) -> String:
	if not FileAccess.file_exists(path):
		return "missing %s" % path
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return "cannot parse %s" % path
	var d: Dictionary = parsed
	meta = {"version": d.get("version", 0), "seed": d.get("seed", 0), "world": d.get("world", {}),
			"heightmap": d.get("heightmap", {}), "maps": d.get("maps", {}), "regions": d.get("regions", [])}
	cities = _list(d.get("cities", []))
	villages = _list(d.get("villages", []))
	roads = _list(d.get("roads", []))
	ports = _list(d.get("ports", []))
	ferries = _list(d.get("ferries", []))
	lakes = _list(d.get("lakes", []))
	canals = _list(d.get("canals", []))
	waterfalls = _list(d.get("waterfalls", []))
	bridges = _list(d.get("bridges", []))
	arches = _list(d.get("arches", []))
	pois = _list(d.get("pois", []))
	spawns = _convert(d.get("spawns", {}), "")
	cameras = _convert(d.get("arrival_cameras", {}), "")
	for p in pois:
		_poi_by_id[p["id"]] = p
	for c in cities:
		_city_by_id[c["id"]] = c
	for v in villages:
		_city_by_id[v["id"]] = v
	_build_water_index()
	return ""


func get_poi(poi_id: StringName) -> Dictionary:
	return _poi_by_id.get(poi_id, {})


func get_city(city_id: StringName) -> Dictionary:
	return _city_by_id.get(city_id, {})


## Lakes and canals whose bounds touch the bucket containing (x, z).
func water_candidates(x: float, z: float) -> Array:
	return _water_buckets.get(Vector2i(floori(x / BUCKET), floori(z / BUCKET)), [])


# --- conversion ---------------------------------------------------------------------------

func _list(a: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if a is Array:
		for e: Variant in a:
			if e is Dictionary:
				out.append(_convert(e, ""))
	return out


func _convert(v: Variant, key: String) -> Variant:
	if v is Dictionary:
		var out := {}
		for k: String in v:
			out[k] = _convert(v[k], k)
		return out
	if v is Array:
		var arr: Array = v
		if VEC_KEYS.has(key) and _is_numbers(arr):
			if arr.size() == 3:
				return Vector3(arr[0], arr[1], arr[2])
			if arr.size() == 2:
				return Vector2(arr[0], arr[1])
		if not arr.is_empty() and arr[0] is Array and _is_numbers(arr[0]):
			if (arr[0] as Array).size() == 3:
				var p3 := PackedVector3Array()
				for e: Array in arr:
					p3.append(Vector3(e[0], e[1], e[2]))
				return p3
			if (arr[0] as Array).size() == 2:
				var p2 := PackedVector2Array()
				for e: Array in arr:
					p2.append(Vector2(e[0], e[1]))
				return p2
		var out_a: Array = []
		for e: Variant in arr:
			out_a.append(_convert(e, ""))
		return out_a
	if v is String and NAME_KEYS.has(key):
		return StringName(v)
	return v


static func _is_numbers(a: Array) -> bool:
	if a.is_empty():
		return false
	for e: Variant in a:
		if not (e is float or e is int):
			return false
	return true


## The outline of a lake's drawn water surface: its polygon grown outwards (8 % + 3 m) so the
## banks hide the edge (WaterSystem.build_inland_water draws exactly this). Gameplay water
## (WorldData.get_water_height) is tested against the same outline, so a body is never
## "swimming" where no water is drawn (wave 4 bug hunt, docs/qa/bughunt_world.md).
static func lake_surface_polygon(lk: Dictionary) -> PackedVector2Array:
	var c: Vector3 = lk.get("center", Vector3.ZERO)
	var cc := Vector2(c.x, c.z)
	var out := PackedVector2Array()
	for p: Vector2 in (lk.get("polygon", PackedVector2Array()) as PackedVector2Array):
		out.append(cc + (p - cc) * 1.08 + (p - cc).normalized() * 3.0)
	return out


func _build_water_index() -> void:
	_water_buckets.clear()
	for i in lakes.size():
		var lk := lakes[i]
		var c: Vector3 = lk["center"]
		# Cached drawn-water outline + its bounding radius (get_water_height's fast reject).
		var surf := lake_surface_polygon(lk)
		var reach := 0.0
		for p in surf:
			reach = maxf(reach, p.distance_to(Vector2(c.x, c.z)))
		lk["surface_polygon"] = surf
		lk["surface_radius"] = reach
		var br := maxf(float(lk["radius"]), reach)
		_add_bucket_range(Rect2(c.x - br, c.z - br, br * 2.0, br * 2.0),
				{"kind": &"lake", "index": i})
	for i in canals.size():
		var pts: PackedVector2Array = canals[i]["points"]
		var r := Rect2(pts[0], Vector2.ZERO)
		for p in pts:
			r = r.expand(p)
		r = r.grow(float(canals[i]["width"]))
		_add_bucket_range(r, {"kind": &"canal", "index": i})


func _add_bucket_range(r: Rect2, entry: Dictionary) -> void:
	for bx in range(floori(r.position.x / BUCKET), floori(r.end.x / BUCKET) + 1):
		for bz in range(floori(r.position.y / BUCKET), floori(r.end.y / BUCKET) + 1):
			var key := Vector2i(bx, bz)
			if not _water_buckets.has(key):
				_water_buckets[key] = []
			(_water_buckets[key] as Array).append(entry)


# --- geometry helpers ---------------------------------------------------------------------

## Distance from p to a polyline and the closest point on it.
static func polyline_closest(p: Vector2, pts: PackedVector2Array) -> Dictionary:
	var best := INF
	var best_p := pts[0] if not pts.is_empty() else p
	for k in pts.size() - 1:
		var q := Geometry2D.get_closest_point_to_segment(p, pts[k], pts[k + 1])
		var d := q.distance_to(p)
		if d < best:
			best = d
			best_p = q
	return {"distance": best, "point": best_p}
