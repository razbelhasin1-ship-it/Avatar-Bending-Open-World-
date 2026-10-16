class_name WorldContent
extends Node3D
## Streams everything that stands on the terrain: vegetation, rocks, nature structures, POI
## buildings, road dressing — and whatever later modules plug in through ContentProvider
## (settlements, NPC / enemy camp / wildlife spawners).
##
##   var content := WorldContent.new()          # default providers: vegetation + nature/POIs
##   add_child(content)
##   content.setup(player, camera)              # focus drives streaming, camera = LOD reference
##   content.register_provider(MyProvider.new())
##   await content.wait_until_settled(5.0)     # optional (loading screens, teleports)
##
## How it works: every provider has a square grid. Cells within the provider's range of the focus
## (and of the focus position predicted `predict_seconds` ahead) are queued nearest-first by
## priority, built by `ContentProvider.build_cell` on WorkerThreadPool (at most `max_jobs` at
## once; pure data: transforms, mesh arrays) and instantiated on the main thread in steps inside
## `frame_budget_usec` per frame. Cells leaving range + margin are released; their
## MultiMeshInstance3D / MeshInstance3D nodes go back to pools. Pooled near-focus collision lives
## in `colliders`. Budgets follow Settings (detail, vegetation, view distance) and are re-applied
## on Events.graphics_settings_changed. Full reference: docs/modules/worldcontent.md.

## A cell finished instantiating.
signal cell_ready(provider_id: StringName, coord: Vector2i)
signal cell_released(provider_id: StringName, coord: Vector2i)
## All cells in range are built (emitted on the transition busy -> settled).
signal settled

## Register the standard vegetation + nature/POI providers in _ready (set false before adding
## to the tree for an empty framework, e.g. in tests or custom dev scenes).
var use_default_providers: bool = true
var focus: Node3D = null
var camera: Camera3D = null
## Main-thread time budget per frame for instantiation and releases (µs).
var frame_budget_usec: int = 2500
## Worker tasks in flight.
var max_jobs: int = 3
## Seconds between wanted-cell scans (also when the focus moved > 8 m).
var update_interval: float = 0.15
## Look-ahead along the focus velocity for prefetching (s).
var predict_seconds: float = 1.2
## Pooled near-focus collision for scattered content.
var colliders: ContentColliders

var _providers: Array[ContentProvider] = []
var _cells: Dictionary = {}            # provider id -> {Vector2i: ContentCell}
var _queue: Array[ContentCell] = []    # QUEUED
var _jobs: Array[ContentCell] = []     # BUILDING on workers
var _built: Array[ContentCell] = []    # BUILT, waiting for the main thread
var _current: ContentCell = null       # INSTANTIATING
var _release: Array[ContentCell] = []
var _mmi_pool: Array[MultiMeshInstance3D] = []
var _mesh_pool: Array[MeshInstance3D] = []
var _exclusion_list: Array[Dictionary] = []
var _exclusions := ContentExclusions.new()
var _next_exclusion := 1
var _focus_pos := Vector3.INF
var _scan_pos := Vector3.INF
var _focus_vel := Vector3.ZERO
var _timer := 0.0
var _was_settled := true
var _stats := {}
var _defaults_registered := false

const POOL_LIMIT := 384


func _init() -> void:
	reset_stats()


func _ready() -> void:
	WorldData.load_world()
	add_to_group(&"world_content")
	colliders = ContentColliders.new()
	colliders.name = "Colliders"
	add_child(colliders)
	_apply_settings()
	Events.graphics_settings_changed.connect(_on_graphics_changed)
	if use_default_providers and not _defaults_registered:
		_defaults_registered = true
		WorldContentDefaults.register_all(self)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for n in _mmi_pool:
			if is_instance_valid(n):
				n.free()
		for n in _mesh_pool:
			if is_instance_valid(n):
				n.free()
		_mmi_pool.clear()
		_mesh_pool.clear()


func _exit_tree() -> void:
	for cell in _jobs:
		if cell.task_id >= 0:
			WorkerThreadPool.wait_for_task_completion(cell.task_id)
			cell.task_id = -1
	_jobs.clear()


# --- Public API --------------------------------------------------------------------------------

## Focus (player/mount/camera) drives streaming; camera is the LOD reference (defaults to the
## viewport camera). Either may be null.
func setup(p_focus: Node3D, p_camera: Camera3D = null) -> void:
	focus = p_focus
	camera = p_camera
	_scan_pos = Vector3.INF


func set_focus(node: Node3D) -> void:
	focus = node
	_scan_pos = Vector3.INF


## Adds a provider (configures it, then streams its cells). Ids must be unique.
func register_provider(p: ContentProvider) -> void:
	if get_provider(p.id) != null:
		push_warning("WorldContent: provider '%s' already registered" % p.id)
		return
	p.content = self
	p.configure()
	_providers.append(p)
	_providers.sort_custom(func(a: ContentProvider, b: ContentProvider) -> bool: return a.priority > b.priority)
	_cells[p.id] = {}
	_scan_pos = Vector3.INF


## Removes a provider and releases all its cells.
func unregister_provider(provider_id: StringName) -> void:
	var p := get_provider(provider_id)
	if p == null:
		return
	_release_provider_cells(p, true)
	_providers.erase(p)
	_cells.erase(provider_id)


func get_provider(provider_id: StringName) -> ContentProvider:
	for p in _providers:
		if p.id == provider_id:
			return p
	return null


func get_providers() -> Array[ContentProvider]:
	return _providers.duplicate()


## Rebuilds the cells of one provider (or all with &"") — e.g. after its data changed.
func refresh(provider_id: StringName = &"") -> void:
	for p in _providers:
		if provider_id == &"" or p.id == provider_id:
			p.generation += 1
			_release_provider_cells(p, false)
	_scan_pos = Vector3.INF


## Rebuilds cells (of scatter providers by default: all) intersecting a world rectangle.
func refresh_area(rect: Rect2, provider_ids: Array = []) -> void:
	for p in _providers:
		if not provider_ids.is_empty() and not provider_ids.has(p.id):
			continue
		var dict: Dictionary = _cells[p.id]
		for coord: Vector2i in dict.keys():
			var cell: ContentCell = dict[coord]
			if cell.rect.intersects(rect):
				_drop_cell(cell)
	_scan_pos = Vector3.INF


## The cell of a provider at a coordinate (null if not loaded/queued).
func get_cell(provider_id: StringName, coord: Vector2i) -> ContentCell:
	var dict: Dictionary = _cells.get(provider_id, {})
	return dict.get(coord)


## All cells of a provider (any state).
func get_cells(provider_id: StringName) -> Array[ContentCell]:
	var out: Array[ContentCell] = []
	for c: ContentCell in (_cells.get(provider_id, {}) as Dictionary).values():
		out.append(c)
	return out


## Current focus position (Vector3.INF before the first update).
func focus_position() -> Vector3:
	return _focus_pos


## Position of the LOD reference camera (the camera given to setup(), else the viewport's),
## falling back to the focus.
func camera_position() -> Vector3:
	var c: Camera3D = camera if camera and is_instance_valid(camera) else (get_viewport().get_camera_3d() if is_inside_tree() else null)
	if c and c.is_inside_tree():
		return c.global_position
	return _focus_pos


## True when no cell in range is queued, building or instantiating.
func is_settled() -> bool:
	return _queue.is_empty() and _jobs.is_empty() and _built.is_empty() and _current == null and _release.is_empty()


## Waits (frames) until settled or `timeout` seconds (wall clock) passed. Returns success.
func wait_until_settled(timeout: float = 10.0) -> bool:
	var t0 := Time.get_ticks_msec()
	_scan_pos = Vector3.INF
	await get_tree().process_frame
	while not is_settled():
		if Time.get_ticks_msec() - t0 > int(timeout * 1000.0):
			return false
		await get_tree().process_frame
	return true


## Synchronously loads everything in range of `pos` (or the focus) — loading screens, teleports,
## tests. Builds run in parallel on workers; the main thread blocks until done or `max_ms`.
func load_now(pos: Vector3 = Vector3.INF, max_ms: int = 30000) -> bool:
	if pos.is_finite():
		_focus_pos = pos
	else:
		_update_focus(0.0)
	if not _focus_pos.is_finite():
		return false
	var t0 := Time.get_ticks_msec()
	_scan(_focus_pos)
	while not is_settled():
		_start_jobs(8)
		while not _jobs.is_empty():
			var cell: ContentCell = _jobs.pop_front()
			WorkerThreadPool.wait_for_task_completion(cell.task_id)
			cell.task_id = -1
			_finish_build(cell)
		_build_inline(1 << 30)
		_main_work(Time.get_ticks_usec(), 1 << 30)
		if Time.get_ticks_msec() - t0 > max_ms:
			return false
	colliders.update(_focus_pos, 1.0)
	return true


# --- Exclusion zones (scatter providers avoid them) --------------------------------------------

## Keep-out circle at x/z for content tagged in `mask` (ContentExclusions.TAG_*). `soft` metres of
## density falloff outside the radius. Cells already built are not changed: call refresh_area for that.
func add_exclusion(center: Vector3, radius: float, mask: int = ContentExclusions.TAG_ALL, soft: float = 0.0) -> int:
	var c := Vector2(center.x, center.z)
	return add_exclusion_capsule(c, c, radius, mask, soft)


## Keep-out capsule between a and b (x/z) — roads, bridges, walls.
func add_exclusion_capsule(a: Vector2, b: Vector2, radius: float, mask: int = ContentExclusions.TAG_ALL, soft: float = 0.0) -> int:
	var id := _next_exclusion
	_next_exclusion += 1
	_exclusion_list.append({"id": id, "a": a, "b": b, "radius": radius, "mask": mask, "soft": soft})
	_exclusions = ContentExclusions.new(_exclusion_list.duplicate())
	return id


## Keep-out ring (between inner and outer radius around center) — city walls around farmland.
func add_exclusion_ring(center: Vector3, inner: float, outer: float, mask: int = ContentExclusions.TAG_ALL, soft: float = 0.0) -> int:
	var id := _next_exclusion
	_next_exclusion += 1
	var c := Vector2(center.x, center.z)
	_exclusion_list.append({"id": id, "a": c, "b": c, "radius": outer, "inner": inner, "mask": mask, "soft": soft})
	_exclusions = ContentExclusions.new(_exclusion_list.duplicate())
	return id


func remove_exclusion(id: int) -> void:
	for i in _exclusion_list.size():
		if int(_exclusion_list[i]["id"]) == id:
			_exclusion_list.remove_at(i)
			_exclusions = ContentExclusions.new(_exclusion_list.duplicate())
			return


## Current exclusion snapshot (immutable; safe to read from any thread).
func get_exclusions() -> ContentExclusions:
	return _exclusions


# --- Statistics --------------------------------------------------------------------------------

func reset_stats() -> void:
	_stats = {"main_usec_last": 0, "main_usec_max": 0, "main_usec_sum": 0, "frames": 0, "cells_built": 0,
		"build_usec_sum": 0, "build_usec_max": 0, "cells_released": 0, "steps": 0, "step_usec_max": 0, "step_max_info": "",
		"scan_usec_max": 0, "update_usec_max": 0, "update_max_info": ""}


## {"providers": {id: {cells, active, queued, building, instances}}, "queue", "jobs",
##  "main_usec_last/max/avg", "build_ms_avg/max", "cells_built", "cells_released",
##  "colliders_active", "instances", "multimesh_nodes", "mesh_nodes"}
func get_stats() -> Dictionary:
	var per := {}
	var total_inst := 0
	var mm_nodes := 0
	var mesh_nodes := 0
	for p in _providers:
		var s := {"cells": 0, "active": 0, "queued": 0, "building": 0, "instances": 0}
		for cell: ContentCell in (_cells[p.id] as Dictionary).values():
			s["cells"] += 1
			match cell.state:
				ContentCell.State.ACTIVE:
					s["active"] += 1
					s["instances"] += cell.instance_count
					for n in cell.pooled:
						if n is MultiMeshInstance3D:
							mm_nodes += 1
						elif n is MeshInstance3D:
							mesh_nodes += 1
				ContentCell.State.QUEUED:
					s["queued"] += 1
				ContentCell.State.BUILDING:
					s["building"] += 1
		total_inst += s["instances"]
		per[p.id] = s
	var frames: int = maxi(int(_stats["frames"]), 1)
	var built: int = maxi(int(_stats["cells_built"]), 1)
	return {"providers": per, "queue": _queue.size(), "jobs": _jobs.size(), "built_waiting": _built.size(),
		"main_usec_last": _stats["main_usec_last"], "main_usec_max": _stats["main_usec_max"],
		"main_usec_avg": float(_stats["main_usec_sum"]) / frames, "build_ms_avg": float(_stats["build_usec_sum"]) / built / 1000.0,
		"build_ms_max": float(_stats["build_usec_max"]) / 1000.0, "cells_built": _stats["cells_built"],
		"cells_released": _stats["cells_released"], "colliders_active": colliders.active_count() if colliders else 0,
		"instances": total_inst, "multimesh_nodes": mm_nodes, "mesh_nodes": mesh_nodes, "settled": is_settled(),
		"step_usec_max": _stats["step_usec_max"], "step_max_info": _stats["step_max_info"], "scan_usec_max": _stats["scan_usec_max"],
		"update_usec_max": _stats["update_usec_max"], "update_max_info": _stats["update_max_info"]}


# --- Main loop -----------------------------------------------------------------------------------

func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_update_focus(delta)
	if not _focus_pos.is_finite():
		return
	_timer -= delta
	if _timer <= 0.0 or not _scan_pos.is_finite() or _scan_pos.distance_to(_focus_pos) > 8.0:
		_timer = update_interval
		var ts := Time.get_ticks_usec()
		_scan(_focus_pos)
		_stats["scan_usec_max"] = maxi(int(_stats["scan_usec_max"]), Time.get_ticks_usec() - ts)
	_poll_jobs()
	_start_jobs(max_jobs)
	_main_work(t0, frame_budget_usec)
	_build_inline(frame_budget_usec - (Time.get_ticks_usec() - t0))
	colliders.update(_focus_pos, delta)
	var used := Time.get_ticks_usec() - t0
	_stats["main_usec_last"] = used
	_stats["main_usec_max"] = maxi(int(_stats["main_usec_max"]), used)
	_stats["main_usec_sum"] = int(_stats["main_usec_sum"]) + used
	_stats["frames"] = int(_stats["frames"]) + 1
	var now_settled := is_settled()
	if now_settled and not _was_settled:
		settled.emit()
	_was_settled = now_settled


func _update_focus(delta: float) -> void:
	var node: Node3D = focus
	if node == null or not is_instance_valid(node):
		node = camera if camera and is_instance_valid(camera) else get_viewport().get_camera_3d() if is_inside_tree() else null
	if node == null or not node.is_inside_tree():
		return
	var p := node.global_position
	if _focus_pos.is_finite() and delta > 0.0:
		var v := (p - _focus_pos) / delta
		if v.length() > 400.0:     # teleport: no prediction
			v = Vector3.ZERO
		_focus_vel = _focus_vel.lerp(v, clampf(delta * 4.0, 0.0, 1.0))
	_focus_pos = p


## Decides which cells every provider wants, queues new ones, releases far ones.
func _scan(fp: Vector3) -> void:
	_scan_pos = fp
	var ahead := fp + Vector3(_focus_vel.x, 0.0, _focus_vel.z) * predict_seconds
	var bounds := WorldData.get_bounds()
	var excl := _exclusions
	for p in _providers:
		p.tick()
		var dict: Dictionary = _cells[p.id]
		if not p.enabled:
			if not dict.is_empty():
				_release_provider_cells(p, false)
			continue
		var r := p.range_m
		# existing cells: distance, release beyond range + margin
		for coord: Vector2i in dict.keys():
			var cell: ContentCell = dict[coord]
			cell.distance = _cell_distance(p, cell.rect, cell.ground_y, fp)
			var d_ahead := _cell_distance(p, cell.rect, cell.ground_y, ahead)
			if minf(cell.distance, d_ahead) > r + p.unload_margin or cell.generation != p.generation:
				_drop_cell(cell)
			elif cell.state == ContentCell.State.ACTIVE:
				var tu := Time.get_ticks_usec()
				p.update_cell(cell, cell.distance)
				var du := Time.get_ticks_usec() - tu
				if du > int(_stats["update_usec_max"]):
					_stats["update_usec_max"] = du
					_stats["update_max_info"] = String(p.id)
		# new cells around the focus and the predicted point
		for centre in ([fp, ahead] if ahead.distance_to(fp) > p.cell_size * 0.25 else [fp]):
			var c0 := p.coord_of(centre.x - r, centre.z - r)
			var c1 := p.coord_of(centre.x + r, centre.z + r)
			for j in range(c0.y, c1.y + 1):
				for i in range(c0.x, c1.x + 1):
					var coord := Vector2i(i, j)
					if dict.has(coord):
						continue
					var rect := p.rect_of(coord)
					if not rect.intersects(bounds):
						continue
					var gy := 0.0
					if p.use_height:
						var c := rect.get_center()
						gy = maxf(WorldData.get_height(c.x, c.y), 0.0)
					var d := _cell_distance(p, rect, gy, centre)
					if d > r or not p.wants_cell(coord):
						continue
					var cell := ContentCell.new(p, coord)
					cell.ground_y = gy
					cell.generation = p.generation
					cell.exclusions = excl
					cell.distance = _cell_distance(p, rect, gy, fp)
					dict[coord] = cell
					_queue.append(cell)
		if p.max_cells > 0 and dict.size() > p.max_cells:
			var all: Array = dict.values()
			all.sort_custom(func(a: ContentCell, b: ContentCell) -> bool: return a.distance > b.distance)
			for k in dict.size() - p.max_cells:
				_drop_cell(all[k])
	_queue.sort_custom(_cell_before)
	_built.sort_custom(_cell_before)


static func _cell_before(a: ContentCell, b: ContentCell) -> bool:
	if a.provider.priority != b.provider.priority:
		return a.provider.priority > b.provider.priority
	return a.distance < b.distance


func _cell_distance(p: ContentProvider, rect: Rect2, ground_y: float, pos: Vector3) -> float:
	var cx := clampf(pos.x, rect.position.x, rect.end.x)
	var cz := clampf(pos.z, rect.position.y, rect.end.y)
	var dx := pos.x - cx
	var dz := pos.z - cz
	var dy := maxf(pos.y - ground_y, 0.0) if p.use_height else 0.0
	return sqrt(dx * dx + dz * dz + dy * dy)


func _start_jobs(limit: int) -> void:
	var i := 0
	while _jobs.size() < limit and i < _queue.size():
		var cell := _queue[i]
		if not cell.provider.threaded:
			i += 1
			continue
		_queue.remove_at(i)
		cell.state = ContentCell.State.BUILDING
		cell.task_id = WorkerThreadPool.add_task(_run_build.bind(cell), false, "WorldContent %s %s" % [cell.provider.id, cell.coord])
		_jobs.append(cell)


func _run_build(cell: ContentCell) -> void:
	var t0 := Time.get_ticks_usec()
	cell.provider.build_cell(cell)
	var p := cell.payload as CellPayload
	if p and not p.colliders.is_empty() and p.collider_buckets.is_empty():
		p.collider_buckets = ContentColliders.bucketize(p.colliders)
	cell.build_usec = Time.get_ticks_usec() - t0


## Main-thread builds for providers with threaded = false.
func _build_inline(budget_left: int) -> void:
	if budget_left <= 0:
		return
	var t0 := Time.get_ticks_usec()
	var i := 0
	while i < _queue.size() and Time.get_ticks_usec() - t0 < budget_left:
		var cell := _queue[i]
		if cell.provider.threaded:
			i += 1
			continue
		_queue.remove_at(i)
		_run_build(cell)
		_finish_build(cell)


func _poll_jobs() -> void:
	var i := 0
	while i < _jobs.size():
		var cell := _jobs[i]
		if WorkerThreadPool.is_task_completed(cell.task_id):
			WorkerThreadPool.wait_for_task_completion(cell.task_id)
			cell.task_id = -1
			_jobs.remove_at(i)
			_finish_build(cell)
		else:
			i += 1


func _finish_build(cell: ContentCell) -> void:
	_stats["cells_built"] = int(_stats["cells_built"]) + 1
	_stats["build_usec_sum"] = int(_stats["build_usec_sum"]) + cell.build_usec
	_stats["build_usec_max"] = maxi(int(_stats["build_usec_max"]), cell.build_usec)
	if cell.state == ContentCell.State.RELEASED or cell.generation != cell.provider.generation:
		cell.payload = null
		return
	cell.state = ContentCell.State.BUILT
	var at := _built.bsearch_custom(cell, _cell_before)
	_built.insert(at, cell)


## Releases and instantiation steps inside the budget. Always makes progress (one step minimum).
func _main_work(t0: int, budget: int) -> void:
	while not _release.is_empty() and Time.get_ticks_usec() - t0 < budget:
		_release_now(_release.pop_back())
	var steps := 0
	while true:
		if _current == null:
			if _built.is_empty():
				break
			_current = _built.pop_front()
			_begin_instantiate(_current)
		var ts := Time.get_ticks_usec()
		var done := _current.provider.instantiate_step(_current)
		var dt := Time.get_ticks_usec() - ts
		if dt > int(_stats["step_usec_max"]):
			_stats["step_usec_max"] = dt
			_stats["step_max_info"] = "%s step %d" % [_current.provider.id, _current.step]
		_current.step += 1
		steps += 1
		if done:
			_current.state = ContentCell.State.ACTIVE
			_current.provider.update_cell(_current, _current.distance)
			cell_ready.emit(_current.provider.id, _current.coord)
			_current = null
		if Time.get_ticks_usec() - t0 >= budget:
			break
	_stats["steps"] = int(_stats["steps"]) + steps


func _begin_instantiate(cell: ContentCell) -> void:
	cell.state = ContentCell.State.INSTANTIATING
	cell.step = 0
	var root := Node3D.new()
	root.name = "%s_%d_%d" % [cell.provider.id, cell.coord.x, cell.coord.y]
	root.position = cell.origin()
	add_child(root)
	cell.root = root


## Removes a cell from its provider map and schedules its teardown.
func _drop_cell(cell: ContentCell) -> void:
	var dict: Dictionary = _cells.get(cell.provider.id, {})
	if dict.get(cell.coord) == cell:
		dict.erase(cell.coord)
	match cell.state:
		ContentCell.State.QUEUED:
			_queue.erase(cell)
			cell.state = ContentCell.State.RELEASED
		ContentCell.State.BUILDING:
			cell.state = ContentCell.State.RELEASED     # discarded when the job finishes
		ContentCell.State.BUILT:
			_built.erase(cell)
			cell.state = ContentCell.State.RELEASED
			cell.payload = null
		ContentCell.State.INSTANTIATING, ContentCell.State.ACTIVE:
			if cell == _current:
				_current = null
			cell.state = ContentCell.State.RELEASED
			_release.append(cell)


func _release_provider_cells(p: ContentProvider, immediate: bool) -> void:
	var dict: Dictionary = _cells.get(p.id, {})
	for coord: Vector2i in dict.keys():
		_drop_cell(dict[coord])
	if immediate:
		while not _release.is_empty():
			_release_now(_release.pop_back())


func _release_now(cell: ContentCell) -> void:
	cell.provider.release_cell(cell)
	for id in cell.loops:
		Audio.stop_loop(id, 0.5)
	cell.loops.clear()
	if cell.user.has("collider_group"):
		colliders.remove_group(int(cell.user["collider_group"]))
		cell.user.erase("collider_group")
	for n in cell.pooled:
		if not is_instance_valid(n):
			continue
		var node := n as Node
		if node.get_parent():
			node.get_parent().remove_child(node)
		if n is MultiMeshInstance3D and _mmi_pool.size() < POOL_LIMIT:
			_mmi_pool.append(n)
		elif n is MeshInstance3D and _mesh_pool.size() < POOL_LIMIT:
			(n as MeshInstance3D).mesh = null
			_mesh_pool.append(n)
		else:
			node.queue_free()
	cell.pooled.clear()
	if cell.root and is_instance_valid(cell.root):
		cell.root.queue_free()
	cell.root = null
	cell.payload = null
	_stats["cells_released"] = int(_stats["cells_released"]) + 1
	cell_released.emit(cell.provider.id, cell.coord)


# --- Default payload instantiation ---------------------------------------------------------------

## One step of turning a CellPayload into nodes (ContentProvider.instantiate_step default).
func instantiate_payload_step(cell: ContentCell) -> bool:
	var p := cell.payload as CellPayload
	if p == null:
		return true
	var i := cell.step
	var n_mm := p.multimeshes.size()
	var n_m := p.meshes.size()
	var n_s := 1 if not p.static_bodies.is_empty() else 0
	if i < n_mm:
		spawn_multimesh(cell, p.multimeshes[i])
	elif i < n_mm + n_m:
		spawn_mesh(cell, p.meshes[i - n_mm])
	elif i < n_mm + n_m + n_s:
		spawn_static_bodies(cell, p.static_bodies)
	elif i < n_mm + n_m + n_s + p.calls.size():
		var c: Callable = p.calls[i - n_mm - n_m - n_s]
		if c.is_valid():
			c.call(cell)
	else:
		if not p.colliders.is_empty():
			cell.user["collider_group"] = colliders.add_group(p.colliders, p.collider_buckets)
		cell.instance_count = p.instance_count
		return true
	return false


## Creates (or recycles) a MultiMeshInstance3D under the cell root from a payload entry.
func spawn_multimesh(cell: ContentCell, d: Dictionary) -> MultiMeshInstance3D:
	var mmi: MultiMeshInstance3D = _mmi_pool.pop_back() if not _mmi_pool.is_empty() else MultiMeshInstance3D.new()
	var mm: MultiMesh = mmi.multimesh
	if mm == null:
		mm = MultiMesh.new()
		mmi.multimesh = mm
	mm.instance_count = 0
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = false
	mm.use_custom_data = bool(d.get("custom", true))
	mm.mesh = d["mesh"]
	mm.instance_count = int(d["count"])
	mm.visible_instance_count = -1
	var aabb: AABB = d["aabb"]
	mm.custom_aabb = aabb
	mm.buffer = d["buffer"]
	mmi.material_override = d.get("material")
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if d.get("shadow", false) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.set_meta(&"casts", bool(d.get("shadow", false)))
	mmi.visible = true
	_apply_vis(mmi, d)
	mmi.layers = int(d.get("layers", 1))
	mmi.transform = Transform3D.IDENTITY
	if String(d.get("tag", &"")) != "":
		mmi.name = String(d["tag"])
	cell.root.add_child(mmi, true)
	cell.pooled.append(mmi)
	return mmi


## Creates a MeshInstance3D with an ArrayMesh from payload surfaces.
func spawn_mesh(cell: ContentCell, d: Dictionary) -> MeshInstance3D:
	var mi: MeshInstance3D = _mesh_pool.pop_back() if not _mesh_pool.is_empty() else MeshInstance3D.new()
	var mesh := ArrayMesh.new()
	for s: Array in d["surfaces"]:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, s[0])
		if s[1]:
			mesh.surface_set_material(mesh.get_surface_count() - 1, s[1])
	mi.mesh = mesh
	mi.material_override = null
	mi.transform = d.get("transform", Transform3D.IDENTITY)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if d.get("shadow", true) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.layers = int(d.get("layers", 1))
	_apply_vis(mi, d)
	if String(d.get("tag", &"")) != "":
		mi.name = String(d["tag"])
	cell.root.add_child(mi, true)
	cell.pooled.append(mi)
	return mi


static func _apply_vis(gi: GeometryInstance3D, d: Dictionary) -> void:
	gi.visibility_range_begin = float(d.get("vis_begin", 0.0))
	gi.visibility_range_end = float(d.get("vis_end", 0.0))
	var m := float(d.get("margin", 0.0))
	gi.visibility_range_begin_margin = m if gi.visibility_range_begin > 0.0 else 0.0
	gi.visibility_range_end_margin = m if gi.visibility_range_end > 0.0 else 0.0
	gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED


## Always-on static collision for a cell (trimesh faces and boxes, relative to the root).
func spawn_static_bodies(cell: ContentCell, list: Array[Dictionary]) -> void:
	for d in list:
		var body := StaticBody3D.new()
		body.collision_layer = int(d.get("layer", Layers.WORLD))
		body.collision_mask = 0
		if d.has("faces"):
			var shape := ConcavePolygonShape3D.new()
			shape.set_faces(d["faces"])
			shape.backface_collision = true
			var cs := CollisionShape3D.new()
			cs.shape = shape
			body.add_child(cs)
		if d.has("boxes"):
			for b: Array in d["boxes"]:
				var cs := CollisionShape3D.new()
				var bs := BoxShape3D.new()
				bs.size = b[1]
				cs.shape = bs
				cs.transform = b[0]
				body.add_child(cs)
		cell.root.add_child(body)


# --- Settings ------------------------------------------------------------------------------------

func _on_graphics_changed() -> void:
	_apply_settings()
	for p in _providers:
		if p.configure():
			p.generation += 1
	_scan_pos = Vector3.INF


func _apply_settings() -> void:
	var mobile := Settings.is_mobile_device() or Settings.detail_level() == 0
	frame_budget_usec = 1600 if mobile else 2500
	max_jobs = clampi(OS.get_processor_count() - 2, 1, 2 if mobile else 3)
	# Web builds ship without threads: WorkerThreadPool tasks then run on the main thread,
	# so start one cell build per frame at most (mobile module, src/platform).
	if not PlatformInfo.has_threads():
		max_jobs = 1
	if colliders:
		colliders.radius = 36.0 if mobile else 48.0
		colliders.max_bodies = 320 if mobile else 600
