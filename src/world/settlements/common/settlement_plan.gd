class_name SettlementPlan
extends RefCounted
## The deterministic layout of one settlement: what stands where (pieces), the NPC anchor data
## exported to the NPC/quest modules, keep-out areas, and a cell index for streaming.
## Built once by a planner on the main thread from WorldData (NwtPlanner, SatPlanner); read-only
## afterwards, so worker threads can read it while building cells.
##
## Piece record (Dictionary):
##   kind  StringName   recipe of the settlement's SettlementBuilder
##   pos   Vector3      world anchor (ground point), the recipe's local origin
##   yaw   float        rotation about +Y (0 = front faces -Z)
##   spec  Dictionary   recipe parameters
##   lod   int          coarsest LOD that still draws it: 0 = near detail only, 1 = + simplified
##                      mid-distance version, 2 = + far silhouette
##   arch  String       archetype key ("" = unique, built in place). Pieces with the same key
##                      share one cached build (KitCache) and are merged with their transform.
##   r     float        footprint radius (occupancy, culling)
##   id    StringName   optional unique id
##
## Anchor record: see docs/modules/settlements.md ("NPC anchors").

var id: StringName = &""
var display_name := ""
var nation: StringName = &"neutral"
## World x/z centre and radius (for "is this position in the settlement").
var center := Vector3.ZERO
var radius := 0.0
var pieces: Array[Dictionary] = []
var anchors: Array[Dictionary] = []
## Named districts {id, name, center: Vector3, radius} for district_at() / NPC flavour.
var districts: Array[Dictionary] = []
## Cell size of the near provider grid (the far provider uses 4 x this).
var cell_size := 128.0
## Every LOD of a cell shares one AABB (LOD hand-over is measured to the AABB centre): y.y is
## the headroom above the highest piece anchor of the cell (towers, spires).
var y_range := Vector2(0.0, 60.0)
## Extra per-settlement data the builder may need (layout, records...).
var data: Dictionary = {}

var _by_cell: Dictionary = {}          # Vector2i -> PackedInt32Array
var _cell_y: Dictionary = {}           # Vector2i -> Vector2(min, max) piece anchor y
var _occ: Dictionary = {}              # Vector2i (8 m bucket) -> Array[Vector3(x, z, r)]
const OCC := 8.0


func _init(p_id: StringName = &"", p_nation: StringName = &"neutral") -> void:
	id = p_id
	nation = p_nation


## Adds a piece. Returns the record (callers may add keys).
func add(kind: StringName, pos: Vector3, yaw: float = 0.0, spec: Dictionary = {}, lod: int = 1, arch: String = "",
		r: float = 0.0) -> Dictionary:
	var rec := {"kind": kind, "pos": pos, "yaw": yaw, "spec": spec, "lod": lod, "arch": arch, "r": r}
	pieces.append(rec)
	return rec


## Adds an NPC anchor: kind (home, market_stall, guard_post, patrol, trainer, quest_giver, healer,
## idle, fisher, monk, bison_stall, ...), position, facing yaw, extra keys (merged).
func anchor(kind: StringName, pos: Vector3, yaw: float = 0.0, extra: Dictionary = {}) -> Dictionary:
	var rec := {"id": StringName("%s_%s_%d" % [id, kind, anchors.size()]), "settlement": id, "kind": kind,
		"position": pos, "yaw": yaw, "district": district_at(pos), "tags": []}
	rec.merge(extra, true)
	anchors.append(rec)
	return rec


func add_district(d_id: StringName, d_name: String, c: Vector3, r: float) -> void:
	districts.append({"id": d_id, "name": d_name, "center": c, "radius": r})


## The district id containing pos (nearest centre within its radius), &"" otherwise.
func district_at(pos: Vector3) -> StringName:
	var best := INF
	var out: StringName = &""
	for d in districts:
		var c: Vector3 = d["center"]
		var dd := Vector2(pos.x - c.x, pos.z - c.z).length()
		if dd <= float(d["radius"]) and dd < best:
			best = dd
			out = d["id"]
	return out


# --- occupancy (planners avoid overlapping pieces) -------------------------------------------

## Marks a circle as used.
func reserve(x: float, z: float, r: float) -> void:
	var c0 := Vector2i(int(floor((x - r) / OCC)), int(floor((z - r) / OCC)))
	var c1 := Vector2i(int(floor((x + r) / OCC)), int(floor((z + r) / OCC)))
	for j in range(c0.y, c1.y + 1):
		for i in range(c0.x, c1.x + 1):
			var k := Vector2i(i, j)
			if not _occ.has(k):
				_occ[k] = []
			(_occ[k] as Array).append(Vector3(x, z, r))


## Marks a capsule (segment a-b, radius r) as used (sampled as circles).
func reserve_line(a: Vector2, b: Vector2, r: float) -> void:
	var n := maxi(int(a.distance_to(b) / maxf(r, 1.0)), 1)
	for k in n + 1:
		var p := a.lerp(b, float(k) / n)
		reserve(p.x, p.y, r)


## True when a circle overlaps nothing reserved.
func is_free(x: float, z: float, r: float) -> bool:
	var c0 := Vector2i(int(floor((x - r) / OCC)), int(floor((z - r) / OCC)))
	var c1 := Vector2i(int(floor((x + r) / OCC)), int(floor((z + r) / OCC)))
	for j in range(c0.y, c1.y + 1):
		for i in range(c0.x, c1.x + 1):
			for o: Vector3 in _occ.get(Vector2i(i, j), []):
				var dx := o.x - x
				var dz := o.y - z
				var rr := o.z + r
				if dx * dx + dz * dz < rr * rr:
					return false
	return true


## Adds a piece only if its footprint is free (then reserves it). Returns the record or {}.
func place(kind: StringName, pos: Vector3, yaw: float, spec: Dictionary, lod: int, arch: String, r: float) -> Dictionary:
	if not is_free(pos.x, pos.z, r):
		return {}
	reserve(pos.x, pos.z, r)
	return add(kind, pos, yaw, spec, lod, arch, r)


# --- cell index --------------------------------------------------------------------------------

func coord_of(x: float, z: float, size: float = cell_size) -> Vector2i:
	return Vector2i(int(floor(x / size)), int(floor(z / size)))


## Builds the cell index (call once after planning).
func index() -> void:
	_by_cell.clear()
	_cell_y.clear()
	for i in pieces.size():
		var p: Vector3 = pieces[i]["pos"]
		var k := coord_of(p.x, p.z)
		if not _by_cell.has(k):
			_by_cell[k] = PackedInt32Array()
			_cell_y[k] = Vector2(p.y, p.y)
		# packed arrays are values: append to the local copy and store it back
		var arr: PackedInt32Array = _by_cell[k]
		arr.append(i)
		_by_cell[k] = arr
		var y: Vector2 = _cell_y[k]
		_cell_y[k] = Vector2(minf(y.x, p.y), maxf(y.y, p.y))


func has_cell(coord: Vector2i) -> bool:
	return _by_cell.has(coord)


## Piece indices in a near-grid cell.
func cell_pieces(coord: Vector2i) -> PackedInt32Array:
	return _by_cell.get(coord, PackedInt32Array())


## Near-grid cells inside a far cell of `factor` x the size.
func sub_cells(far_coord: Vector2i, factor: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for j in factor:
		for i in factor:
			var k := Vector2i(far_coord.x * factor + i, far_coord.y * factor + j)
			if _by_cell.has(k):
				out.append(k)
	return out


func cells() -> Array:
	return _by_cell.keys()


## AABB shared by every LOD mesh of a near-grid cell, relative to `origin`: the cell square,
## from 30 m under its lowest piece anchor to `y_range.y` m over its highest.
func cell_aabb(coord: Vector2i, origin: Vector3) -> AABB:
	var y: Vector2 = _cell_y.get(coord, Vector2.ZERO)
	var lo := Vector3(coord.x * cell_size, y.x - 30.0, coord.y * cell_size) - origin
	return AABB(lo, Vector3(cell_size, y.y - y.x + 30.0 + y_range.y, cell_size))


func get_anchors(kind: StringName = &"") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for a in anchors:
		if kind == &"" or a["kind"] == kind:
			out.append(a)
	return out


## Pieces of a kind (tests / tools).
func pieces_of(kind: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p in pieces:
		if p["kind"] == kind:
			out.append(p)
	return out


func contains(pos: Vector3, margin: float = 0.0) -> bool:
	return Vector2(pos.x - center.x, pos.z - center.z).length() <= radius + margin
