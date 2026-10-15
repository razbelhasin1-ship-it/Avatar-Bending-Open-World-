class_name SnowTrails
extends Node
## Deformable snow: footprints, paw prints and landing craters stamped into a toroidal trail
## map around the focus, displacing the terrain (vertex) and shading it (fragment) wherever
## the snow layer is present.
##
## * Input: Events.footstep (oriented print sized by `size`, depth by `weight`; heavy
##   creatures with size >= 0.42 m leave paw prints) and Events.landed (crater + rim + scatter),
##   or `add_footprint()` / `add_crater()` directly.
## * Storage: every stamp is also kept in a CPU ring buffer, so prints persist (and refill
##   consistently) when the window scrolls away and back, and `get_sink_depth()` can tell
##   animation how deep a foot stands.
## * GPU: a SubViewport render target (RGBA8, R depth, G rim, B scatter) updated only on frames
##   with work; stamps max-blend through back-buffer copies, refill subtracts in 1/255 steps.
## * Refill: depth fraction recovers at `refill_rate` per second (weather multiplies it:
##   ~4 min for a full print in clear weather, under a minute in a blizzard).

signal stamped(kind: int, position: Vector3)

const STAMP_SHADER := preload("res://assets/shaders/world/snow_stamp.gdshader")
const REFILL_SHADER := preload("res://assets/shaders/world/snow_refill.gdshader")
## Depth encoded by R = 1 (metres).
const MAX_DEPTH := 0.5
## Raised rim encoded by G = 1 (metres).
const RIM_HEIGHT := 0.08
const KIND_FOOT := 0
const KIND_PAW := 1
const KIND_CRATER := 2
const CAPACITY := 4096
## Base refill speed: fraction of MAX_DEPTH per second (0.5 m in ~240 s).
const BASE_REFILL := 1.0 / 240.0
const REFILL_INTERVAL := 0.5

var resolution: int = 1024
var texel: float = 0.032
var window_size: float = 32.768
var window_center := Vector2.ZERO
## Weather multiplier for the refill speed (1 clear, 3.5 snowing, 9 blizzard).
var refill_multiplier: float = 1.0
var viewport: SubViewport
var puffs: BurstPool
var material: ShaderMaterial          # terrain material receiving the trail uniforms
var camera_position := Vector3.ZERO

# CPU stamp store (ring buffer of parallel arrays)
var _pos := PackedVector2Array()
var _y := PackedFloat32Array()
var _yaw := PackedFloat32Array()
var _size := PackedFloat32Array()
var _depth := PackedFloat32Array()     # depth fraction (0..1 of MAX_DEPTH) at creation
var _rim := PackedFloat32Array()
var _scatter := PackedFloat32Array()
var _kind := PackedInt32Array()
var _clock0 := PackedFloat32Array()    # refill clock at creation
var _count := 0
var _head := 0

var _refill_clock := 0.0               # integrated refill (depth fraction units)
var _refill_pending := 0.0
var _refill_timer := 0.0
var _queue: Array[int] = []            # stamp indices waiting to be drawn
var _clears: Array[Rect2] = []         # texture-space rects to zero
var _items: Array[RID] = []
var _items_frame := -1                 # Engine.get_frames_drawn() when _items were submitted
var _draw_index := 0
var _canvas: RID
var _stamp_mat: ShaderMaterial
var _refill_mat: ShaderMaterial
var _clear_mat: ShaderMaterial
var _needs_full_clear := true
var _gpu := true


func _ready() -> void:
	var detail := Settings.detail_level()
	resolution = 2048 if detail >= 3 else (1024 if detail >= 1 else 512)
	window_size = resolution * texel
	for arr in [_pos, _y, _yaw, _size, _depth, _rim, _scatter, _clock0]:
		arr.resize(CAPACITY)
	_kind.resize(CAPACITY)
	_gpu = DisplayServer.get_name() != "headless"
	viewport = SubViewport.new()
	viewport.name = "TrailMap"
	viewport.size = Vector2i(resolution, resolution)
	viewport.disable_3d = true
	viewport.transparent_bg = true
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)
	_canvas = viewport.find_world_2d().canvas
	_stamp_mat = ShaderMaterial.new()
	_stamp_mat.shader = STAMP_SHADER
	_refill_mat = ShaderMaterial.new()
	_refill_mat.shader = REFILL_SHADER
	_clear_mat = ShaderMaterial.new()
	_clear_mat.shader = REFILL_SHADER
	_clear_mat.set_shader_parameter(&"mode", 1)
	puffs = BurstPool.new()
	puffs.name = "SnowPuffs"
	add_child(puffs)
	puffs.setup(10, 26, 1.3, _puff_process(), BurstPool.soft_quad(0.16, Color(0.97, 0.98, 1.0, 0.9), 0.3))
	Events.footstep.connect(_on_footstep)
	Events.landed.connect(_on_landed)


func _exit_tree() -> void:
	_free_items()


## Terrain material that samples the trail map (uniforms are kept up to date).
func bind_material(m: ShaderMaterial) -> void:
	material = m
	material.set_shader_parameter(&"trail_map", viewport.get_texture())
	material.set_shader_parameter(&"trail_texel", texel)
	material.set_shader_parameter(&"trail_max_depth", MAX_DEPTH)
	material.set_shader_parameter(&"trail_rim_height", RIM_HEIGHT)
	_update_window_uniform()


# --- stamping API --------------------------------------------------------------------------------

## Snow present (and deep enough to print) at a point.
static func has_snow(pos: Vector3, surface: StringName = &"") -> bool:
	if surface == &"ice" or surface == &"water":
		return false
	if surface == &"snow":
		return true
	return WorldData.get_snow_depth(pos.x, pos.z) > 0.03 and WorldData.get_splat(pos.x, pos.z).r > 0.3


## Adds a foot/paw print. `size` = foot length (m), `weight` 0..1+ (heavy creatures > 1),
## `speed` m/s (running prints are slightly longer and kick snow forward). Returns false when
## there is no snow.
func add_footprint(pos: Vector3, yaw: float, size: float, weight: float, speed: float = 0.0, surface: StringName = &"") -> bool:
	if not has_snow(pos, surface):
		return false
	var snow_depth := maxf(WorldData.get_snow_depth(pos.x, pos.z), 0.06)
	var depth_m := clampf(0.035 + 0.09 * weight * sqrt(maxf(size, 0.05) / 0.28), 0.02, 0.4)
	depth_m = minf(depth_m, snow_depth * 0.9)
	var running := speed > 4.0
	var kind := KIND_PAW if size >= 0.42 else KIND_FOOT
	var stretch := 1.12 if running else 1.0
	_store(Vector2(pos.x, pos.z), pos.y, yaw, size * stretch, depth_m / MAX_DEPTH,
			clampf(0.45 + weight * 0.3, 0.3, 1.0), 0.8 if running else 0.15, kind)
	if pos.distance_to(camera_position) < 70.0:
		var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
		puffs.fire(pos + Vector3.UP * 0.05, clampf(size * 2.4 * (1.4 if running else 0.8) * (0.7 + weight * 0.4), 0.3, 2.5),
				(Vector3.UP + fwd * (0.9 if running else 0.3)).normalized())
	stamped.emit(kind, pos)
	return true


## Adds a landing crater; `impact` = vertical speed at touchdown (m/s).
func add_crater(pos: Vector3, impact: float, surface: StringName = &"") -> bool:
	if not has_snow(pos, surface):
		return false
	var snow_depth := maxf(WorldData.get_snow_depth(pos.x, pos.z), 0.08)
	var radius := clampf(0.35 + absf(impact) * 0.07, 0.4, 1.6)
	var depth_m := minf(clampf(0.05 + absf(impact) * 0.022, 0.05, 0.45), snow_depth * 0.95)
	_store(Vector2(pos.x, pos.z), pos.y, 0.0, radius, depth_m / MAX_DEPTH, 1.0, 1.0, KIND_CRATER)
	if pos.distance_to(camera_position) < 90.0:
		puffs.fire(pos + Vector3.UP * 0.1, clampf(radius * 2.0, 0.6, 3.5), Vector3.UP)
		puffs.fire(pos + Vector3.UP * 0.1, clampf(radius * 1.4, 0.5, 3.0), Vector3.UP)
	stamped.emit(KIND_CRATER, pos)
	return true


func _on_footstep(actor: Node3D, position: Vector3, yaw: float, size: float, weight: float, surface: StringName) -> void:
	var speed := 0.0
	if actor is CharacterBody3D:
		speed = Vector2((actor as CharacterBody3D).velocity.x, (actor as CharacterBody3D).velocity.z).length()
	elif actor is RigidBody3D:
		speed = Vector2((actor as RigidBody3D).linear_velocity.x, (actor as RigidBody3D).linear_velocity.z).length()
	add_footprint(position, yaw, size, weight, speed, surface)


func _on_landed(_actor: Node3D, position: Vector3, impact: float, surface: StringName) -> void:
	if absf(impact) >= 3.0:
		add_crater(position, impact, surface)


func _store(p: Vector2, y: float, yaw: float, size: float, depth: float, rim: float, scatter: float, kind: int) -> void:
	var i := _head
	_head = (_head + 1) % CAPACITY
	_count = mini(_count + 1, CAPACITY)
	_pos[i] = p
	_y[i] = y
	_yaw[i] = yaw
	_size[i] = size
	_depth[i] = clampf(depth, 0.0, 1.0)
	_rim[i] = rim
	_scatter[i] = scatter
	_kind[i] = kind
	_clock0[i] = _refill_clock
	if _in_window(p, _extent(i)):
		_queue.append(i)


## Half-size (m) of the stamp's bounding square: the stamp shader draws a print of length
## `size` across 0.56 of the square, and a crater of radius `size` at 0.55 of the half-size.
func _extent(i: int) -> float:
	return _size[i] * (1.85 if _kind[i] == KIND_CRATER else 0.9)


func _in_window(p: Vector2, ext: float) -> bool:
	var h := window_size * 0.5 + ext
	return absf(p.x - window_center.x) < h and absf(p.y - window_center.y) < h


## Remaining depth fraction (0..1 of MAX_DEPTH) of stamp i after refill.
func _current_depth(i: int) -> float:
	return maxf(_depth[i] - (_refill_clock - _clock0[i]), 0.0)


## How far (m) the snow surface is pressed down at x/z by trails (for feet/body sinking).
func get_sink_depth(pos: Vector3) -> float:
	var best := 0.0
	var p := Vector2(pos.x, pos.z)
	for k in _count:
		var i := (_head - 1 - k + CAPACITY) % CAPACITY
		var r := _size[i] * (0.55 if _kind[i] != KIND_CRATER else 1.0)
		if absf(_pos[i].x - p.x) > r or absf(_pos[i].y - p.y) > r:
			continue
		var d := _current_depth(i)
		if d <= 0.0:
			continue
		var rel := p - _pos[i]
		var f := 1.0
		if _kind[i] == KIND_CRATER:
			var rr := rel.length() / _size[i]
			f = clampf(1.0 - rr * rr, 0.0, 1.0)
		else:
			# foot frame: forward = (-sin yaw, -cos yaw)
			var fwd := Vector2(-sin(_yaw[i]), -cos(_yaw[i]))
			var side := Vector2(-fwd.y, fwd.x)
			var along := rel.dot(fwd) / (_size[i] * 0.5)
			var across := rel.dot(side) / (_size[i] * 0.22)
			f = 1.0 if along * along + across * across <= 1.0 else 0.0
		best = maxf(best, d * f * MAX_DEPTH)
	return best


## Number of stored stamps (diagnostics/tests).
func stamp_count() -> int:
	return _count


# --- per-frame -----------------------------------------------------------------------------------

func update(focus_pos: Vector3, delta: float) -> void:
	var rate := BASE_REFILL * refill_multiplier
	_refill_clock += rate * delta
	_refill_pending += rate * delta
	_refill_timer -= delta
	var p := Vector2(focus_pos.x, focus_pos.z)
	if p.distance_to(window_center) > window_size * 0.125 or _needs_full_clear:
		_move_window(p)
	# items are freed only once a frame has drawn them: several updates within one frame
	# (tools, tests, time skips) append instead of dropping queued GPU work
	if Engine.get_frames_drawn() != _items_frame:
		_free_items()
	if not _gpu:
		_queue.clear()
		_clears.clear()
		_refill_pending = 0.0
		return
	var draw_index := _draw_index
	var work := false
	if _needs_full_clear:
		_clears = [Rect2(0, 0, resolution, resolution)]
		_needs_full_clear = false
	for r in _clears:
		_add_item(r, Color(0, 0, 0, 0), _clear_mat, false, draw_index)
		draw_index += 1
		work = true
	_clears.clear()
	if _refill_timer <= 0.0 and _refill_pending * 255.0 >= 1.0:
		_refill_timer = REFILL_INTERVAL
		var steps := floorf(_refill_pending * 255.0)
		_refill_pending -= steps / 255.0
		var v := steps / 255.0
		_add_item(Rect2(0, 0, resolution, resolution), Color(v, v, minf(v * 2.0, 1.0), 0.0), _refill_mat, true, draw_index)
		draw_index += 1
		work = true
	var budget := 48
	while not _queue.is_empty() and budget > 0:
		var i: int = _queue.pop_front()
		budget -= 1
		_draw_stamp(i, draw_index)
		draw_index += 1
		work = true
	_draw_index = draw_index
	if work:
		_items_frame = Engine.get_frames_drawn()
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _move_window(p: Vector2) -> void:
	var nc := Vector2(roundf(p.x / texel) * texel, roundf(p.y / texel) * texel)
	var oc := window_center
	var h := window_size * 0.5
	var fresh := _needs_full_clear or absf(nc.x - oc.x) >= window_size or absf(nc.y - oc.y) >= window_size
	window_center = nc
	if fresh:
		_needs_full_clear = true
		_clears.clear()
	else:
		# world strips that entered the window
		var strips: Array[Rect2] = []
		if nc.x > oc.x:
			strips.append(Rect2(oc.x + h, nc.y - h, nc.x - oc.x, window_size))
		elif nc.x < oc.x:
			strips.append(Rect2(nc.x - h, nc.y - h, oc.x - nc.x, window_size))
		if nc.y > oc.y:
			strips.append(Rect2(nc.x - h, oc.y + h, window_size, nc.y - oc.y))
		elif nc.y < oc.y:
			strips.append(Rect2(nc.x - h, nc.y - h, window_size, oc.y - nc.y))
		for s in strips:
			for r in _texture_rects(s):
				_clears.append(r)
		_restamp(strips)
	if fresh:
		_queue.clear()
		_restamp([])
	_update_window_uniform()


## Queues stored prints for redrawing: all prints in the window (`strips` empty) or only those
## touching the given world rects (max-blending makes redraws of untouched parts harmless).
func _restamp(strips: Array[Rect2]) -> void:
	for k in _count:
		var i := (_head - _count + k + CAPACITY) % CAPACITY
		if _current_depth(i) <= 0.0 and _scatter[i] <= 0.0:
			continue
		var ext := _extent(i)
		if not _in_window(_pos[i], ext):
			continue
		if strips.is_empty():
			_queue.append(i)
			continue
		var box := Rect2(_pos[i] - Vector2(ext, ext), Vector2(ext, ext) * 2.0)
		for st in strips:
			if st.intersects(box):
				_queue.append(i)
				break


## Splits a world rect into texture-space rects (toroidal wrap).
func _texture_rects(world: Rect2) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var x0 := fposmod(world.position.x, window_size) / texel
	var y0 := fposmod(world.position.y, window_size) / texel
	var w := world.size.x / texel
	var hh := world.size.y / texel
	var n := float(resolution)
	for ox in [0.0, -n]:
		for oy in [0.0, -n]:
			var r := Rect2(x0 + ox, y0 + oy, w, hh).intersection(Rect2(0, 0, n, n))
			if r.size.x > 0.0 and r.size.y > 0.0:
				out.append(r.grow(1.0))
	return out


func _update_window_uniform() -> void:
	if material:
		material.set_shader_parameter(&"trail_window", Vector4(window_center.x, window_center.y, window_size, 1.0))


func _draw_stamp(i: int, draw_index: int) -> void:
	var depth := _current_depth(i)
	var rim := _rim[i] * (depth / maxf(_depth[i], 0.001))
	var scatter := _scatter[i] * clampf(1.0 - (_refill_clock - _clock0[i]) * 2.0, 0.0, 1.0)
	if depth <= 0.0 and scatter <= 0.0:
		return
	var size_px := _extent(i) * 2.0 / texel
	var cx := fposmod(_pos[i].x, window_size) / texel
	var cy := fposmod(_pos[i].y, window_size) / texel
	var color := Color(depth, rim, scatter, float(_kind[i]) / 4.0)
	var angle := PI - _yaw[i]
	var n := float(resolution)
	var half := size_px * 0.5
	for ox in [0.0, n, -n]:
		for oy in [0.0, n, -n]:
			var c := Vector2(cx + ox, cy + oy)
			if c.x + half * 1.42 < 0.0 or c.y + half * 1.42 < 0.0 or c.x - half * 1.42 > n or c.y - half * 1.42 > n:
				continue
			var item := RenderingServer.canvas_item_create()
			RenderingServer.canvas_item_set_parent(item, _canvas)
			RenderingServer.canvas_item_set_draw_index(item, draw_index)
			RenderingServer.canvas_item_set_material(item, _stamp_mat.get_rid())
			var bb := Rect2(c - Vector2(half, half) * 1.42, Vector2(half, half) * 2.84)
			RenderingServer.canvas_item_set_copy_to_backbuffer(item, true, bb)
			RenderingServer.canvas_item_add_set_transform(item, Transform2D(angle, c))
			RenderingServer.canvas_item_add_rect(item, Rect2(-half, -half, size_px, size_px), color)
			_items.append(item)


func _add_item(rect: Rect2, color: Color, mat: ShaderMaterial, backbuffer: bool, draw_index: int) -> void:
	var item := RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(item, _canvas)
	RenderingServer.canvas_item_set_draw_index(item, draw_index)
	RenderingServer.canvas_item_set_material(item, mat.get_rid())
	if backbuffer:
		RenderingServer.canvas_item_set_copy_to_backbuffer(item, true, rect)
	RenderingServer.canvas_item_add_rect(item, rect, color)
	_items.append(item)


func _free_items() -> void:
	for item in _items:
		RenderingServer.free_rid(item)
	_items.clear()
	_draw_index = 0


func _puff_process() -> ParticleProcessMaterial:
	var p := ParticleProcessMaterial.new()
	p.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.12
	p.direction = Vector3(0, 1, 0)
	p.spread = 55.0
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 1.6
	p.gravity = Vector3(0, -2.2, 0)
	p.damping_min = 1.5
	p.damping_max = 3.0
	p.scale_min = 0.6
	p.scale_max = 1.5
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.5))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1, 1.3))
	var ct := CurveTexture.new()
	ct.curve = curve
	p.scale_curve = ct
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.85))
	g.set_color(1, Color(1, 1, 1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	p.color_ramp = gt
	return p
