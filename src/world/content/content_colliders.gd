class_name ContentColliders
extends Node3D
## Pooled near-focus collision for scattered content (tree trunks, boulders, ice chunks, driftwood).
##
## Cells register descriptor groups ({type, transform (world), size}); only descriptors within
## `radius` of the focus (or of extra request points: companions, NPC groups) get a physics body.
## Bodies are PhysicsServer3D static bodies (no nodes) recycled through a free list, shapes are
## shared per quantised size, and `body_attach_object_instance_id` points at this node, so a ray or
## shape query that hits a tree reports `collider == <ContentColliders>` (group &"world_content").
## Thousands of trees therefore cost a few hundred bodies at most.
##
## Groups are bucketed (16 m) by `bucketize()` — WorldContent does that on the worker thread that
## built the cell — so registering a cell with thousands of trees costs only a few hundred
## dictionary operations on the main thread.

const BUCKET := 16.0

## Activation radius around the focus (m); bodies are released beyond radius + hysteresis.
var radius: float = 48.0
var hysteresis: float = 8.0
## Hard cap on simultaneously active bodies (nearest win).
var max_bodies: int = 600
var collision_layer: int = Layers.WORLD
## Seconds between activation scans (also rescans when the focus moved > 3 m).
var interval: float = 0.2

var _groups: Dictionary = {}         # gid -> {"list": Array[Dictionary], "buckets": {Vector2i: PackedInt32Array}}
var _bucket_groups: Dictionary = {}  # Vector2i -> Array[int] gids
var _active: Dictionary = {}         # key (gid << 24 | index) -> RID body
var _free: Array[RID] = []
var _shapes: Dictionary = {}         # key -> RID
var _requests: Dictionary = {}       # id -> Vector3
var _next_group := 1
var _next_request := 1
var _entry_count := 0
var _timer := 0.0
var _last_scan := Vector3.INF


func _ready() -> void:
	add_to_group(&"world_content")


func _exit_tree() -> void:
	for k: int in _active:
		PhysicsServer3D.free_rid(_active[k])
	_active.clear()
	for b in _free:
		PhysicsServer3D.free_rid(b)
	_free.clear()
	for k: String in _shapes:
		PhysicsServer3D.free_rid(_shapes[k])
	_shapes.clear()


## Thread-safe: bucket index of a descriptor list ({Vector2i: PackedInt32Array of indices}).
static func bucketize(list: Array[Dictionary]) -> Dictionary:
	var out := {}
	for i in list.size():
		var o: Vector3 = (list[i]["transform"] as Transform3D).origin
		var key := Vector2i(int(floor(o.x / BUCKET)), int(floor(o.z / BUCKET)))
		if not out.has(key):
			out[key] = PackedInt32Array()
		var arr: PackedInt32Array = out[key]
		arr.append(i)
		out[key] = arr
	return out


## Registers descriptors ({"type", "transform", "size"}) as one group; returns the group id.
## Pass `buckets` from bucketize() when it was computed off the main thread.
func add_group(list: Array[Dictionary], buckets: Dictionary = {}) -> int:
	var gid := _next_group
	_next_group += 1
	if buckets.is_empty() and not list.is_empty():
		buckets = bucketize(list)
	_groups[gid] = {"list": list, "buckets": buckets}
	for key: Vector2i in buckets:
		if not _bucket_groups.has(key):
			_bucket_groups[key] = []
		(_bucket_groups[key] as Array).append(gid)
	_entry_count += list.size()
	_last_scan = Vector3.INF
	return gid


func remove_group(gid: int) -> void:
	if not _groups.has(gid):
		return
	var g: Dictionary = _groups[gid]
	var list: Array = g["list"]
	for i in list.size():
		_deactivate((gid << 24) | i)
	for key: Vector2i in g["buckets"]:
		if _bucket_groups.has(key):
			(_bucket_groups[key] as Array).erase(gid)
			if (_bucket_groups[key] as Array).is_empty():
				_bucket_groups.erase(key)
	_entry_count -= list.size()
	_groups.erase(gid)


## Keeps collision around an extra point (companion, NPC group); returns a request id.
func request_point(pos: Vector3) -> int:
	var id := _next_request
	_next_request += 1
	_requests[id] = pos
	_last_scan = Vector3.INF
	return id


func move_request(id: int, pos: Vector3) -> void:
	if _requests.has(id):
		_requests[id] = pos


func release_request(id: int) -> void:
	_requests.erase(id)


func active_count() -> int:
	return _active.size()


func entry_count() -> int:
	return _entry_count


## Activates/deactivates bodies around `focus_pos` (called by WorldContent every frame).
func update(focus_pos: Vector3, delta: float) -> void:
	if not focus_pos.is_finite() or not is_inside_tree():
		return
	_timer -= delta
	if _timer > 0.0 and _last_scan.is_finite() and _last_scan.distance_to(focus_pos) < 3.0:
		return
	_timer = interval
	_last_scan = focus_pos
	var points: Array[Vector3] = [focus_pos]
	for id: int in _requests:
		points.append(_requests[id])
	var want: Dictionary = {}
	for p in points:
		_collect(p, radius + hysteresis, want)
	for k: int in _active.keys():
		if not want.has(k):
			_deactivate(k)
	var cand: Array = []
	for k: int in want:
		if not _active.has(k) and float(want[k]) <= radius:
			cand.append([want[k], k])
	if _active.size() + cand.size() > max_bodies:
		cand.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for c: Array in cand:
		if _active.size() >= max_bodies:
			break
		_activate(c[1])


func _collect(p: Vector3, r: float, into: Dictionary) -> void:
	var k0 := Vector2i(int(floor((p.x - r) / BUCKET)), int(floor((p.z - r) / BUCKET)))
	var k1 := Vector2i(int(floor((p.x + r) / BUCKET)), int(floor((p.z + r) / BUCKET)))
	var r2 := r * r
	for j in range(k0.y, k1.y + 1):
		for i in range(k0.x, k1.x + 1):
			var key := Vector2i(i, j)
			if not _bucket_groups.has(key):
				continue
			for gid: int in _bucket_groups[key]:
				var g: Dictionary = _groups[gid]
				var list: Array = g["list"]
				for idx in (g["buckets"][key] as PackedInt32Array):
					var o: Vector3 = (list[idx]["transform"] as Transform3D).origin
					var d2 := Vector2(o.x - p.x, o.z - p.z).length_squared()
					if d2 <= r2:
						var k := (gid << 24) | idx
						var d := sqrt(d2)
						if not into.has(k) or into[k] > d:
							into[k] = d


func _activate(k: int) -> void:
	var e: Dictionary = (_groups[k >> 24]["list"] as Array)[k & 0xffffff]
	var shape := _shape_for(e["type"], e["size"])
	if not shape.is_valid():
		return
	var body: RID
	if _free.is_empty():
		body = PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_attach_object_instance_id(body, get_instance_id())
		PhysicsServer3D.body_set_collision_mask(body, 0)
	else:
		body = _free.pop_back()
	PhysicsServer3D.body_set_collision_layer(body, collision_layer)
	PhysicsServer3D.body_clear_shapes(body)
	PhysicsServer3D.body_add_shape(body, shape)
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM, e["transform"])
	PhysicsServer3D.body_set_space(body, get_world_3d().space)
	_active[k] = body


func _deactivate(k: int) -> void:
	if not _active.has(k):
		return
	var body: RID = _active[k]
	_active.erase(k)
	PhysicsServer3D.body_set_space(body, RID())
	PhysicsServer3D.body_clear_shapes(body)
	_free.append(body)


func _shape_for(type: StringName, size: Vector3) -> RID:
	var q := Vector3(snappedf(size.x, 0.05), snappedf(size.y, 0.05), snappedf(size.z, 0.05))
	var key := "%s|%s" % [type, q]
	if _shapes.has(key):
		return _shapes[key]
	var rid := RID()
	match type:
		&"cylinder":
			rid = PhysicsServer3D.cylinder_shape_create()
			PhysicsServer3D.shape_set_data(rid, {"radius": maxf(q.x, 0.05), "height": maxf(q.y, 0.1)})
		&"capsule":
			rid = PhysicsServer3D.capsule_shape_create()
			PhysicsServer3D.shape_set_data(rid, {"radius": maxf(q.x, 0.05), "height": maxf(q.y, q.x * 2.0 + 0.01)})
		&"sphere":
			rid = PhysicsServer3D.sphere_shape_create()
			PhysicsServer3D.shape_set_data(rid, maxf(q.x, 0.05))
		&"box":
			rid = PhysicsServer3D.box_shape_create()
			PhysicsServer3D.shape_set_data(rid, Vector3(maxf(q.x, 0.05), maxf(q.y, 0.05), maxf(q.z, 0.05)) * 0.5)
		_:
			return RID()
	_shapes[key] = rid
	return rid
