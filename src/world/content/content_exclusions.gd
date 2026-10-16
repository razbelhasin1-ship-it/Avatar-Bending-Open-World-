class_name ContentExclusions
extends RefCounted
## Immutable set of keep-out areas (settlements, POI structures, bridges, caves) that scatter
## providers (vegetation, rocks, clutter) must avoid. WorldContent replaces the whole object when
## an area is added or removed, and every cell build captures the snapshot that was current when
## it was queued, so worker threads never see a set that changes under them.
##
## Each area is a circle or capsule in x/z with a `mask` of tags it blocks (bit flags below).

const TAG_TREES := 1
const TAG_GRASS := 2
const TAG_ROCKS := 4
const TAG_PROPS := 8
const TAG_ALL := 0xff

const BUCKET := 256.0

## Each entry: {"id", "a": Vector2, "b": Vector2, "radius", "mask", "soft", "inner"} (soft = metres
## of falloff where density thins out instead of stopping hard; inner > 0 makes it a ring: only
## distances between inner and radius are blocked, e.g. a city wall with farmland inside).
var areas: Array[Dictionary] = []
var _buckets: Dictionary = {}       # Vector2i -> Array[int] indices


func _init(p_areas: Array[Dictionary] = []) -> void:
	areas = p_areas
	for i in areas.size():
		var e := areas[i]
		var a: Vector2 = e["a"]
		var b: Vector2 = e["b"]
		var r: float = float(e["radius"]) + float(e.get("soft", 0.0))
		var lo := Vector2(minf(a.x, b.x) - r, minf(a.y, b.y) - r)
		var hi := Vector2(maxf(a.x, b.x) + r, maxf(a.y, b.y) + r)
		for j in range(int(floor(lo.y / BUCKET)), int(floor(hi.y / BUCKET)) + 1):
			for k in range(int(floor(lo.x / BUCKET)), int(floor(hi.x / BUCKET)) + 1):
				var key := Vector2i(k, j)
				if not _buckets.has(key):
					_buckets[key] = []
				(_buckets[key] as Array).append(i)


## Density multiplier 0..1 at x/z for scatter with `tag` (0 = fully excluded).
func factor(x: float, z: float, tag: int) -> float:
	var key := Vector2i(int(floor(x / BUCKET)), int(floor(z / BUCKET)))
	if not _buckets.has(key):
		return 1.0
	var p := Vector2(x, z)
	var f := 1.0
	for i: int in _buckets[key]:
		var e := areas[i]
		if int(e["mask"]) & tag == 0:
			continue
		var dc := _seg_dist(p, e["a"], e["b"])
		var d := dc - float(e["radius"])
		var inner := float(e.get("inner", 0.0))
		if inner > 0.0:
			d = maxf(d, inner - dc)
		if d <= 0.0:
			return 0.0
		var soft := float(e.get("soft", 0.0))
		if d < soft:
			f = minf(f, d / soft)
	return f


## True if x/z is inside a hard area for `tag`.
func blocked(x: float, z: float, tag: int) -> bool:
	return factor(x, z, tag) <= 0.0


## Whether any area for `tag` touches the rectangle (cheap early-out for whole cells).
func touches(rect: Rect2, tag: int) -> bool:
	var k0 := Vector2i(int(floor(rect.position.x / BUCKET)), int(floor(rect.position.y / BUCKET)))
	var k1 := Vector2i(int(floor(rect.end.x / BUCKET)), int(floor(rect.end.y / BUCKET)))
	for j in range(k0.y, k1.y + 1):
		for i in range(k0.x, k1.x + 1):
			var key := Vector2i(i, j)
			if not _buckets.has(key):
				continue
			for idx: int in _buckets[key]:
				if int(areas[idx]["mask"]) & tag != 0:
					return true
	return false


func size() -> int:
	return areas.size()


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 1e-8:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)
