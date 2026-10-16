class_name TerrainCollision
extends Node3D
## Streams HeightMapShape3D terrain collision around the focus and around requested points.
##
## Patches are PATCH_M x PATCH_M metres with 1 m sample spacing (PATCH_M + 1 samples per
## side, neighbours share their edge row). Samples sit on the heightmap texel grid (odd
## metres) and its midpoints, and are computed with exactly WorldData.get_height's bilinear
## formula, so collision equals WorldData at every sample; between samples the physics
## triangles deviate from the bilinear surface by at most 1/16 of the local cell twist
## (p99 ~2.5 cm on walkable ground). Height data is prepared on WorkerThreadPool tasks; the
## main thread only creates shapes (MAX_APPLY_PER_FRAME per frame). The patch under the focus
## is built synchronously if it is missing, so the focus can never stand on missing ground.
## Bodies are on Layers.WORLD.

signal patch_ready(key: Vector2i)
## Emitted when the safety net put a body that fell through the world back on the ground.
signal body_rescued(body: Node3D)

const PATCH_M := 64
const SAMPLES := PATCH_M + 1
## First patch origin: a texel centre (odd metre) at the world's west/north edge.
const ORIGIN := WorldConstants.WORLD_MIN + 1.0
const GRID := int(WorldConstants.WORLD_SIZE / PATCH_M)
const MAX_APPLY_PER_FRAME := 2
const MAX_JOBS := 3

## Radius (m) of collision kept around the focus.
var focus_radius: float = 150.0
var focus: Node3D = null
## Safety net: put the focus back on the ground if it falls below the terrain.
var safety_enabled: bool = true

var _active: Dictionary = {}       # Vector2i -> {body, frame}
var _pending: Dictionary = {}      # Vector2i -> true (queued or building)
var _queue: Array[Vector2i] = []
var _jobs: Dictionary = {}         # task id -> Vector2i
var _results: Array = []           # [Vector2i, PackedFloat32Array]
var _mutex := Mutex.new()
var _requests: Dictionary = {}     # id -> {pos, radius, expires}
var _next_request := 1
var _focus_pos := Vector3.INF
var _time := 0.0
var _holes_version := 0
var _stale: Dictionary = {}        # in-flight patch builds computed before a hole change


func _ready() -> void:
	process_physics_priority = -10


func _exit_tree() -> void:
	for id: int in _jobs.keys():
		WorkerThreadPool.wait_for_task_completion(id)
	_jobs.clear()


# --- public API --------------------------------------------------------------------------------

## Keeps collision within `radius` of `pos` until released (or for `lifetime_s` seconds if > 0).
## Returns a request id for `release_request`.
func request_around(pos: Vector3, radius: float, lifetime_s: float = 0.0) -> int:
	var id := _next_request
	_next_request += 1
	_requests[id] = {"pos": pos, "radius": maxf(radius, 1.0), "expires": _time + lifetime_s if lifetime_s > 0.0 else INF}
	_want_area(pos, radius, true)
	return id


## Moves an existing request (e.g. a companion following the player).
func move_request(id: int, pos: Vector3) -> void:
	if _requests.has(id):
		_requests[id]["pos"] = pos


func release_request(id: int) -> void:
	_requests.erase(id)


## True when collision covers `pos` and has been in the physics space for a physics frame.
func is_ready_at(pos: Vector3) -> bool:
	var key := patch_key(pos)
	return _active.has(key) and _settled(_active[key])


## Builds the patch containing `pos` right now on the main thread (spawns/teleports).
func ensure_now(pos: Vector3) -> void:
	var key := patch_key(pos)
	if _active.has(key) or not _valid_key(key):
		return
	_apply(key, build_heights(key))


## Number of live collision patches.
func patch_count() -> int:
	return _active.size()


## Patch containing a world position.
static func patch_key(pos: Vector3) -> Vector2i:
	return Vector2i(int(floor((pos.x - ORIGIN) / PATCH_M)), int(floor((pos.z - ORIGIN) / PATCH_M)))


## World x/z of a patch's first sample.
static func patch_origin(key: Vector2i) -> Vector2:
	return Vector2(ORIGIN + key.x * PATCH_M, ORIGIN + key.y * PATCH_M)


## Heights of a patch, row-major [j * SAMPLES + i] at (origin + i, origin + j) metres.
## Thread-safe (reads WorldData's immutable heightmap only).
static func build_heights(key: Vector2i) -> PackedFloat32Array:
	var o := patch_origin(key)
	var out := PackedFloat32Array()
	out.resize(SAMPLES * SAMPLES)
	if not WorldData.has_world_data() or WorldData.height_override.is_valid():
		for k in out.size():
			out[k] = WorldData.get_height(o.x + (k % SAMPLES), o.y + int(k / SAMPLES))
		TerrainHoles.punch(o, SAMPLES, out)
		return out
	# texel-aligned 2 m block (exact stored heights), then exact bilinear midpoints
	var n := PATCH_M / 2 + 1
	var tex := WorldData.get_height_block(o.x, o.y, n, n, 2.0)
	for j in SAMPLES:
		var j0 := j >> 1
		var j1 := mini(j0 + 1, n - 1)
		var fz := 0.5 if (j & 1) == 1 else 0.0
		for i in SAMPLES:
			var i0 := i >> 1
			var i1 := mini(i0 + 1, n - 1)
			var fx := 0.5 if (i & 1) == 1 else 0.0
			var h00 := tex[j0 * n + i0]
			var h10 := tex[j0 * n + i1]
			var h01 := tex[j1 * n + i0]
			var h11 := tex[j1 * n + i1]
			var a := h00 + (h10 - h00) * fx
			var b := h01 + (h11 - h01) * fx
			out[j * SAMPLES + i] = a + (b - a) * fz
	# cave mouths (worldcontent): NaN samples are holes in the Jolt heightfield
	TerrainHoles.punch(o, SAMPLES, out)
	return out


# --- streaming ---------------------------------------------------------------------------------

func update(focus_pos: Vector3, delta: float) -> void:
	_time += delta
	_focus_pos = focus_pos
	if TerrainHoles.version != _holes_version:
		_holes_version = TerrainHoles.version
		_rebuild_holed_patches()
	# guarantee ground under the focus
	if focus_pos.is_finite():
		ensure_now(focus_pos)
	var wanted := {}
	if focus_pos.is_finite():
		_collect(focus_pos, focus_radius, wanted)
	for id: int in _requests.keys():
		var r: Dictionary = _requests[id]
		if float(r["expires"]) < _time:
			_requests.erase(id)
			continue
		_collect(r["pos"], float(r["radius"]), wanted)
	# queue missing patches, nearest first
	var missing: Array[Vector2i] = []
	for key: Vector2i in wanted:
		if not _active.has(key) and not _pending.has(key):
			missing.append(key)
	if not missing.is_empty():
		var fp := Vector2(focus_pos.x, focus_pos.z) if focus_pos.is_finite() else Vector2.ZERO
		missing.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return (patch_origin(a) + Vector2(32, 32)).distance_squared_to(fp) < (patch_origin(b) + Vector2(32, 32)).distance_squared_to(fp))
		for key in missing:
			_pending[key] = true
			_queue.append(key)
	_start_jobs()
	_apply_results()
	# unload patches nobody wants any more (with a margin against thrashing)
	var margin := {}
	if focus_pos.is_finite():
		_collect(focus_pos, focus_radius + PATCH_M, margin)
	for id: int in _requests:
		_collect(_requests[id]["pos"], float(_requests[id]["radius"]) + PATCH_M, margin)
	for key: Vector2i in _active.keys():
		if not margin.has(key):
			(_active[key]["body"] as Node).queue_free()
			_active.erase(key)


## Drops live patches touched by terrain holes (they are rebuilt with the holes punched).
func _rebuild_holed_patches() -> void:
	for key: Vector2i in _active.keys():
		var o := patch_origin(key)
		if TerrainHoles.touches(Rect2(o, Vector2(PATCH_M, PATCH_M))):
			(_active[key]["body"] as Node).queue_free()
			_active.erase(key)
	for key: Vector2i in _pending.keys():
		if TerrainHoles.touches(Rect2(patch_origin(key), Vector2(PATCH_M, PATCH_M))):
			_stale[key] = true


func _collect(pos: Vector3, radius: float, into: Dictionary) -> void:
	var k0 := patch_key(pos - Vector3(radius, 0, radius))
	var k1 := patch_key(pos + Vector3(radius, 0, radius))
	var p := Vector2(pos.x, pos.z)
	for j in range(k0.y, k1.y + 1):
		for i in range(k0.x, k1.x + 1):
			var key := Vector2i(i, j)
			if not _valid_key(key):
				continue
			var o := patch_origin(key)
			var closest := Vector2(clampf(p.x, o.x, o.x + PATCH_M), clampf(p.y, o.y, o.y + PATCH_M))
			if closest.distance_to(p) <= radius:
				into[key] = true


func _want_area(pos: Vector3, radius: float, _priority: bool) -> void:
	var w := {}
	_collect(pos, radius, w)
	for key: Vector2i in w:
		if not _active.has(key) and not _pending.has(key):
			_pending[key] = true
			_queue.push_front(key)


static func _valid_key(key: Vector2i) -> bool:
	return key.x >= 0 and key.y >= 0 and key.x < GRID and key.y < GRID


func _start_jobs() -> void:
	while _jobs.size() < MAX_JOBS and not _queue.is_empty():
		var key: Vector2i = _queue.pop_front()
		if _active.has(key):
			_pending.erase(key)
			continue
		var id := WorkerThreadPool.add_task(_job.bind(key), false, "TerrainCollision patch")
		_jobs[id] = key
	for id: int in _jobs.keys():
		if WorkerThreadPool.is_task_completed(id):
			WorkerThreadPool.wait_for_task_completion(id)
			_jobs.erase(id)


func _job(key: Vector2i) -> void:
	var data := build_heights(key)
	_mutex.lock()
	_results.append([key, data])
	_mutex.unlock()


func _apply_results() -> void:
	_mutex.lock()
	var batch: Array = []
	while not _results.is_empty() and batch.size() < MAX_APPLY_PER_FRAME:
		batch.append(_results.pop_front())
	_mutex.unlock()
	for r: Array in batch:
		var key: Vector2i = r[0]
		_pending.erase(key)
		if _stale.has(key):
			_stale.erase(key)
			continue
		if not _active.has(key):
			_apply(key, r[1])


func _apply(key: Vector2i, heights: PackedFloat32Array) -> void:
	_pending.erase(key)
	var shape := HeightMapShape3D.new()
	shape.map_width = SAMPLES
	shape.map_depth = SAMPLES
	shape.map_data = heights
	var cs := CollisionShape3D.new()
	cs.shape = shape
	var body := StaticBody3D.new()
	body.name = "Patch_%d_%d" % [key.x, key.y]
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	var o := patch_origin(key)
	body.position = Vector3(o.x + PATCH_M * 0.5, 0.0, o.y + PATCH_M * 0.5)
	body.add_child(cs)
	add_child(body)
	_active[key] = {"body": body, "frame": Engine.get_physics_frames()}
	patch_ready.emit(key)


func _settled(entry: Dictionary) -> bool:
	return Engine.get_physics_frames() > int(entry["frame"])


# --- safety net ---------------------------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	if not safety_enabled or focus == null or not is_instance_valid(focus):
		return
	if not (focus is CharacterBody3D or focus is RigidBody3D):
		return
	var p := focus.global_position
	var ground := WorldData.get_height(p.x, p.z)
	if p.y > ground - 1.5:
		return
	# caves and other geometry below the terrain surface are fine: only rescue when nothing
	# solid is under the body
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.5, p + Vector3.DOWN * 60.0, Layers.SOLID)
	if focus is CollisionObject3D:
		q.exclude = [(focus as CollisionObject3D).get_rid()]
	if not space.intersect_ray(q).is_empty():
		return
	ensure_now(p)
	focus.global_position = Vector3(p.x, ground + 0.6, p.z)
	if focus is CharacterBody3D:
		(focus as CharacterBody3D).velocity.y = 0.0
	elif focus is RigidBody3D:
		(focus as RigidBody3D).linear_velocity.y = 0.0
	body_rescued.emit(focus)
