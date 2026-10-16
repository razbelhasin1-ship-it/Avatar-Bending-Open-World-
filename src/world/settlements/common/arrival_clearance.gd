class_name ArrivalClearance
extends RefCounted
## The new-game arrival flight of an element (the same cubic Bezier as
## ArrivalCinematic._build_curve, sampled every 1/120 of the path) and clearance queries, so
## planners keep their tall pieces out of the camera's way. Thread-safe after construction.
##
##   var cam := ArrivalClearance.for_element(ElementDefs.Element.EARTH)
##   if cam.ok(x, z, radius, top_y):          # 6 m sideways or 6 m below the camera
##       plan.add(...)

## Camera path (world), 121 samples, empty without arrival data.
var path := PackedVector3Array()
var _box := AABB()


static func for_element(element: int) -> ArrivalClearance:
	var c := ArrivalClearance.new()
	var cam := WorldData.get_arrival_camera(element)
	if cam.is_empty():
		return c
	var p0: Vector3 = (cam["start"] as Transform3D).origin
	var p3: Vector3 = (cam["end"] as Transform3D).origin
	var span := p3 - p0
	var flat := Vector3(span.x, 0.0, span.z)
	var c1 := p0 + flat * 0.42 + Vector3.UP * maxf(0.0, -span.y) * 0.04
	var c2 := p3 - flat.normalized() * minf(flat.length() * 0.22, 120.0) + Vector3.UP * minf(absf(span.y) * 0.18, 40.0)
	for i in 121:
		var e := float(i) / 120.0
		var u := 1.0 - e
		c.path.append(p0 * (u * u * u) + c1 * (3.0 * u * u * e) + c2 * (3.0 * u * e * e) + p3 * (e * e * e))
	c._box = AABB(c.path[0], Vector3.ZERO)
	for q in c.path:
		c._box = c._box.expand(q)
	return c


## True when a piece (footprint radius `rad` at x/z, rising to world height `top`) stays clear of
## the flight: `side` m sideways or `below` m under every camera sample.
func ok(x: float, z: float, rad: float, top: float, side: float = 6.0, below: float = 6.0) -> bool:
	if path.is_empty():
		return true
	var reach := rad + side
	if x < _box.position.x - reach or x > _box.end.x + reach or z < _box.position.z - reach or z > _box.end.z + reach:
		return true
	for p in path:
		if p.y < top + below and Vector2(p.x - x, p.z - z).length() < reach:
			return false
	return true


## Lowest camera height over a disc (INF when the flight never passes over it).
func lowest_over(x: float, z: float, rad: float) -> float:
	var best := INF
	for p in path:
		if Vector2(p.x - x, p.z - z).length() < rad:
			best = minf(best, p.y)
	return best
