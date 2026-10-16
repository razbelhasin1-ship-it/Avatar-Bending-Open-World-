class_name RingLayout
extends RefCounted
## Polar helpers for the WorldData ring-layout cities (docs/modules/worlddata.md "Cities"):
## concentric tiers around `center` with bearing arcs, radial ramps across every tier step.
## Bearings are degrees from north (-Z), clockwise; direction of bearing b = (sin b, -cos b).
## Thread-safe (reads WorldData only).
##
##   var L := RingLayout.from_city(&"northern_water_tribe")
##   L.point(400.0, 30.0)          # world position on the ground at r = 400 m, bearing 30
##   L.polar(x, z)                 # Vector2(r, bearing)
##   L.tier_at(x, z)               # the tier record there ({} outside every tier)
##   L.ramp_at(bearing, r, 2.0)    # the ramp record crossing a step there ({} if none)

var id: StringName = &""
var record: Dictionary = {}
var center := Vector2.ZERO
## Tier records sorted by r_inner: {id, name, r_inner, r_outer, height, arc: [b0, b1] | null}
var tiers: Array[Dictionary] = []
## Ramp records: {bearing, width, length}
var ramps: Array[Dictionary] = []


static func from_city(city_id: StringName) -> RingLayout:
	var L := RingLayout.new()
	L.id = city_id
	L.record = WorldData.get_city(city_id)
	if L.record.is_empty():
		return L
	var rc: Variant = L.record.get("ring_center")
	if rc is Vector2:
		L.center = rc
	else:
		var c: Vector3 = L.record.get("center", Vector3.ZERO)
		L.center = Vector2(c.x, c.z)
	for t: Dictionary in L.record.get("tiers", []):
		L.tiers.append(t)
	L.tiers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["r_inner"]) < float(b["r_inner"]))
	for r: Dictionary in L.record.get("ramps", []):
		L.ramps.append(r)
	return L


func is_valid() -> bool:
	return not tiers.is_empty()


## Unit direction (x, z) of a bearing in degrees.
static func dir(bearing: float) -> Vector2:
	var b := deg_to_rad(bearing)
	return Vector2(sin(b), -cos(b))


## Yaw (radians, Basis(UP, yaw) applied to a -Z-forward model) that faces along a bearing.
static func yaw_of(bearing: float) -> float:
	return -deg_to_rad(bearing)


## Yaw facing from p towards q (x/z).
static func yaw_towards(p: Vector3, q: Vector3) -> float:
	var d := Vector2(q.x - p.x, q.z - p.z)
	return atan2(-d.x, -d.y)


## Wraps a bearing into [-180, 180).
static func wrap(bearing: float) -> float:
	return wrapf(bearing, -180.0, 180.0)


## Signed smallest difference a - b in degrees.
static func bdiff(a: float, b: float) -> float:
	return wrapf(a - b, -180.0, 180.0)


## x/z of polar coordinates.
func xz(r: float, bearing: float) -> Vector2:
	return center + dir(bearing) * r


## World point at polar coordinates; y = terrain height (or `y` when finite).
func point(r: float, bearing: float, y: float = NAN) -> Vector3:
	var p := xz(r, bearing)
	return Vector3(p.x, WorldData.get_height(p.x, p.y) if is_nan(y) else y, p.y)


## Vector2(r, bearing) of a world x/z.
func polar(x: float, z: float) -> Vector2:
	var d := Vector2(x, z) - center
	return Vector2(d.length(), rad_to_deg(atan2(d.x, -d.y)))


static func in_arc(bearing: float, arc: Variant, margin: float = 0.0) -> bool:
	if arc == null or not (arc is Array) or (arc as Array).size() < 2:
		return true
	var a0 := float(arc[0]) - margin
	var a1 := float(arc[1]) + margin
	var b := bearing
	# arcs are given as an increasing pair in [-180, 360]; test b and b +/- 360
	for k in [0.0, 360.0, -360.0]:
		if b + k >= a0 and b + k <= a1:
			return true
	return false


func tier(tier_id: StringName) -> Dictionary:
	for t in tiers:
		if StringName(t["id"]) == tier_id:
			return t
	return {}


## The tier containing x/z (by radius and arc), {} outside.
func tier_at(x: float, z: float) -> Dictionary:
	var pr := polar(x, z)
	for t in tiers:
		if pr.x >= float(t["r_inner"]) and pr.x < float(t["r_outer"]) and in_arc(pr.y, t.get("arc")):
			return t
	return {}


## Ramp record whose strip contains (bearing, r): within width/2 + margin metres sideways.
func ramp_at(bearing: float, r: float, margin: float = 0.0) -> Dictionary:
	for rp in ramps:
		var side := absf(bdiff(bearing, float(rp["bearing"]))) * PI / 180.0 * r
		if side <= float(rp["width"]) * 0.5 + margin:
			return rp
	return {}


## Angular half width (degrees) of a strip `width` metres wide at radius r.
static func half_angle(width: float, r: float) -> float:
	return rad_to_deg(width * 0.5 / maxf(r, 1.0))


## Arc length in metres of `deg` degrees at radius r.
static func arc_len(deg: float, r: float) -> float:
	return absf(deg) * PI / 180.0 * r
