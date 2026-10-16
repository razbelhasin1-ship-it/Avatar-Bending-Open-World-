class_name TerrainHoles
extends RefCounted
## Registry of holes in the terrain *collision* (cave mouths, tunnel entrances). The terrain has
## no holes visually (structures are built in front of the cliffs), but walking into a cave means
## passing through the heightfield there: TerrainCollision punches NaN samples (Jolt treats them
## as holes) inside every registered capsule when it builds a patch, and rebuilds live patches
## when `version` changes. Thread-safe: the hole list is an immutable snapshot replaced on change.
##
##   var id := TerrainHoles.add_capsule(Vector2(x0, z0), Vector2(x1, z1), 3.5)
##   TerrainHoles.remove(id)

static var version: int = 0
static var _holes: Array = []        # [[id, a: Vector2, b: Vector2, radius], ...] (immutable)
static var _next := 1
static var _mutex := Mutex.new()


## Adds a capsule hole (x/z segment + radius in metres). Returns its id.
static func add_capsule(a: Vector2, b: Vector2, radius: float) -> int:
	_mutex.lock()
	var id := _next
	_next += 1
	var copy := _holes.duplicate()
	copy.append([id, a, b, radius])
	_holes = copy
	version += 1
	_mutex.unlock()
	return id


static func remove(id: int) -> void:
	_mutex.lock()
	var copy: Array = []
	for h: Array in _holes:
		if int(h[0]) != id:
			copy.append(h)
	if copy.size() != _holes.size():
		_holes = copy
		version += 1
	_mutex.unlock()


static func clear() -> void:
	_mutex.lock()
	if not _holes.is_empty():
		_holes = []
		version += 1
	_mutex.unlock()


static func count() -> int:
	return _holes.size()


## True if a hole covers x/z.
static func contains(x: float, z: float) -> bool:
	var p := Vector2(x, z)
	for h: Array in _holes:
		if ContentExclusions._seg_dist(p, h[1], h[2]) <= float(h[3]):
			return true
	return false


## True if any hole touches the rectangle.
static func touches(rect: Rect2) -> bool:
	for h: Array in _holes:
		var a: Vector2 = h[1]
		var b: Vector2 = h[2]
		var r := float(h[3])
		var hb := Rect2(Vector2(minf(a.x, b.x) - r, minf(a.y, b.y) - r), Vector2(absf(a.x - b.x) + r * 2.0, absf(a.y - b.y) + r * 2.0))
		if hb.intersects(rect):
			return true
	return false


## Sets every sample of a row-major height grid (samples x samples at 1 m spacing from origin)
## that lies inside a hole to NAN. Called by TerrainCollision.build_heights (any thread).
static func punch(origin: Vector2, samples: int, heights: PackedFloat32Array, spacing: float = 1.0) -> void:
	var holes := _holes
	if holes.is_empty():
		return
	var rect := Rect2(origin, Vector2(samples - 1, samples - 1) * spacing)
	for h: Array in holes:
		var a: Vector2 = h[1]
		var b: Vector2 = h[2]
		var r := float(h[3])
		var lo := Vector2(minf(a.x, b.x) - r, minf(a.y, b.y) - r)
		var hi := Vector2(maxf(a.x, b.x) + r, maxf(a.y, b.y) + r)
		if not Rect2(lo, hi - lo).intersects(rect):
			continue
		var i0 := clampi(int(floor((lo.x - origin.x) / spacing)), 0, samples - 1)
		var i1 := clampi(int(ceil((hi.x - origin.x) / spacing)), 0, samples - 1)
		var j0 := clampi(int(floor((lo.y - origin.y) / spacing)), 0, samples - 1)
		var j1 := clampi(int(ceil((hi.y - origin.y) / spacing)), 0, samples - 1)
		for j in range(j0, j1 + 1):
			for i in range(i0, i1 + 1):
				var p := origin + Vector2(i, j) * spacing
				if ContentExclusions._seg_dist(p, a, b) <= r:
					heights[j * samples + i] = NAN
