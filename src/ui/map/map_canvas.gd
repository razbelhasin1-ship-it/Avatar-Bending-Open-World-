class_name MapCanvas
extends Control
## The interactive world map surface: the parchment map texture (explored / unexplored via
## map_fog.gdshader) under a MapOverlay (lettering, places, routes, markers), with zoom and
## pan for every input:
##   mouse  - wheel zooms at the pointer, drag pans, hover highlights, click selects,
##            double-click activates (fast travel)
##   touch  - one-finger drag pans, two-finger pinch zooms (also trackpad magnify / pan
##            gestures), tap selects
##   keys / controller - WASD / arrows / left stick pan under a centre reticle that snaps
##            to nearby places, +/- or RT / LT zoom (driven by the page every frame)
## The view: `zoom` 1 = the whole world fits the height; `center` = map uv at the centre.

signal hovered(place: Dictionary)
signal clicked(place: Dictionary)
signal activated(place: Dictionary)

const MIN_ZOOM := 1.0
const MAX_ZOOM := 7.0
const PICK_PX := 30.0
const PICK_TOUCH_PX := 46.0
const FOG_SHADER := preload("res://src/ui/map/map_fog.gdshader")
const NOISE := preload("res://assets/textures/world/clouds.png")

var zoom := 1.0
var center := Vector2(0.5, 0.5)
## Smoothed targets (the view eases toward them).
var target_zoom := 1.0
var target_center := Vector2(0.5, 0.5)
## Reticle mode (keyboard / controller): hover = the place nearest the reticle.
var cursor_mode := false:
	set(v):
		if v and not cursor_mode and not _cursor_in_view():
			cursor_uv = center
		cursor_mode = v
## The reticle's map position (it leaves the view centre where the view is clamped at the
## map's edges, so every place can be reached).
var cursor_uv := Vector2(0.5, 0.5)
## Set by the page while the stick / keys are actively panning (magnetism waits).
var panning := false
var hover: Dictionary = {}
var selected: Dictionary = {}
var overlay: MapOverlay
var paper: Control

var _tex: Texture2D
var _reveal_tex: ImageTexture
var _mat: ShaderMaterial
var _touches: Dictionary = {}       # index -> position
var _pinch_d := 0.0
var _drag_from := Vector2.ZERO
var _dragging := false
var _press_pos := Vector2.ZERO
var _press_time := 0
var _mouse_down := false
var _touch_moved := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	clip_contents = true


func _ready() -> void:
	_tex = WorldData.get_map_texture()
	paper = Control.new()
	paper.name = "Paper"
	paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = FOG_SHADER
	_mat.set_shader_parameter(&"noise_tex", NOISE)
	paper.material = _mat
	paper.draw.connect(_draw_paper)
	add_child(paper)
	overlay = MapOverlay.new()
	overlay.name = "Overlay"
	overlay.canvas = self
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	resized.connect(func() -> void:
		_clamp_view()
		redraw())
	refresh_reveal()


## Re-reads the explored mask (MapModel.reveal_image).
func refresh_reveal() -> void:
	var img := MapModel.reveal_image()
	if _reveal_tex == null:
		_reveal_tex = ImageTexture.create_from_image(img)
	else:
		_reveal_tex.update(img)
	_mat.set_shader_parameter(&"reveal_tex", _reveal_tex)
	paper.queue_redraw()


func redraw() -> void:
	if paper:
		paper.queue_redraw()
	if overlay:
		overlay.queue_redraw()


# --- view maths --------------------------------------------------------------------------------

## Map size in local px at the current zoom (zoom 1 fits the height).
func map_px() -> float:
	return maxf(minf(size.x, size.y), 64.0) * zoom


func uv_to_local(uv: Vector2) -> Vector2:
	return size * 0.5 + (uv - center) * map_px()


func local_to_uv(p: Vector2) -> Vector2:
	return center + (p - size * 0.5) / map_px()


func world_to_local(pos: Vector3) -> Vector2:
	return uv_to_local(MapModel.world_to_uv(pos))


func local_to_world(p: Vector2) -> Vector3:
	return MapModel.uv_to_world(local_to_uv(p))


## Metres per local pixel at the current zoom.
func metres_per_px() -> float:
	return 8192.0 / map_px()


func _clamp_center(c: Vector2, z: float) -> Vector2:
	var mp := maxf(minf(size.x, size.y), 64.0) * z
	var half := size * 0.5 / mp
	var out := c
	for i in 2:
		if half[i] >= 0.5:
			out[i] = 0.5
		else:
			out[i] = clampf(c[i], half[i], 1.0 - half[i])
	return out


func _clamp_view() -> void:
	target_zoom = clampf(target_zoom, MIN_ZOOM, MAX_ZOOM)
	target_center = _clamp_center(target_center, target_zoom)
	zoom = clampf(zoom, MIN_ZOOM, MAX_ZOOM)
	center = _clamp_center(center, zoom)


## Jumps (or eases) to look at a world position.
func focus_on(pos: Vector3, z: float = -1.0, instant: bool = false) -> void:
	if z > 0.0:
		target_zoom = clampf(z, MIN_ZOOM, MAX_ZOOM)
	cursor_uv = MapModel.world_to_uv(pos).clamp(Vector2.ZERO, Vector2.ONE)
	target_center = _clamp_center(cursor_uv, target_zoom)
	if instant:
		zoom = target_zoom
		center = target_center
		redraw()


## Zooms by `factor` keeping the map point under `local_pos` fixed.
func zoom_at(local_pos: Vector2, factor: float) -> void:
	var before := target_center + (local_pos - size * 0.5) / (maxf(minf(size.x, size.y), 64.0) * target_zoom)
	target_zoom = clampf(target_zoom * factor, MIN_ZOOM, MAX_ZOOM)
	var mp := maxf(minf(size.x, size.y), 64.0) * target_zoom
	target_center = _clamp_center(before - (local_pos - size * 0.5) / mp, target_zoom)


## Pans by a local-pixel delta (positive = the map moves with the finger).
func pan_px(delta: Vector2) -> void:
	var mp := maxf(minf(size.x, size.y), 64.0) * target_zoom
	target_center = _clamp_center(target_center - delta / mp, target_zoom)
	# direct manipulation follows the finger exactly
	center = _clamp_center(center - delta / map_px(), zoom)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	var k := 1.0 - exp(-delta * 14.0)
	var moved := false
	if absf(zoom - target_zoom) > 0.0005:
		zoom = lerpf(zoom, target_zoom, k)
		moved = true
	if center.distance_squared_to(target_center) > 1e-10:
		center = center.lerp(target_center, k)
		moved = true
	if moved:
		center = _clamp_center(center, zoom)
		redraw()
	if cursor_mode:
		_update_cursor_hover()
		# magnetism: an idle reticle settles onto the place it is over
		if not panning and not hover.is_empty() and hover.has("position"):
			var huv := MapModel.world_to_uv(hover["position"])
			if huv.distance_to(cursor_uv) > 1e-5:
				cursor_uv = cursor_uv.lerp(huv, 1.0 - exp(-delta * 9.0))
				target_center = _clamp_center(cursor_uv, target_zoom)


## Moves the reticle by a local-pixel delta (the view follows, clamped at the map edges).
func move_cursor(delta_px: Vector2) -> void:
	cursor_mode = true
	cursor_uv = (cursor_uv + delta_px / map_px()).clamp(Vector2.ZERO, Vector2.ONE)
	target_center = _clamp_center(cursor_uv, target_zoom)


func _cursor_in_view() -> bool:
	return Rect2(Vector2.ZERO, size).grow(1.0).has_point(uv_to_local(cursor_uv)) if size.x > 16.0 else false


func cursor_local() -> Vector2:
	return uv_to_local(cursor_uv) if cursor_mode else size * 0.5


# --- picking -----------------------------------------------------------------------------------

## The place (or quest marker) under a local position, {} if none.
func pick(p: Vector2, radius: float = -1.0) -> Dictionary:
	var r := radius if radius > 0.0 else (PICK_TOUCH_PX if UiInput.device == &"touch" else PICK_PX)
	var best: Dictionary = {}
	var best_d := r
	for e in overlay.pickables():
		var d := (e["screen"] as Vector2).distance_to(p)
		if d < best_d:
			best_d = d
			best = e
	return best


func _update_cursor_hover() -> void:
	var h := pick(uv_to_local(cursor_uv), 64.0)
	if h.get("id", &"") != hover.get("id", &"") or h.get("kind", &"") != hover.get("kind", &""):
		hover = h
		hovered.emit(h)
		overlay.queue_redraw()


func _set_hover(h: Dictionary) -> void:
	if h.get("id", &"") == hover.get("id", &"") and h.get("kind", &"") == hover.get("kind", &""):
		return
	hover = h
	hovered.emit(h)
	overlay.queue_redraw()


func select(p: Dictionary) -> void:
	selected = p
	overlay.queue_redraw()


# --- pointer + touch input -----------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_touch(event as InputEventScreenTouch)
		accept_event()
		return
	if event is InputEventScreenDrag:
		_touch_drag(event as InputEventScreenDrag)
		accept_event()
		return
	if event is InputEventMagnifyGesture:
		var mg := event as InputEventMagnifyGesture
		zoom_at(mg.position, mg.factor)
		accept_event()
		return
	if event is InputEventPanGesture:
		pan_px(-(event as InputEventPanGesture).delta * 12.0)
		accept_event()
		return
	# Mouse emulated from touch is ignored: the touch events above carry the gesture.
	if event is InputEventMouse and (event as InputEventMouse).device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					zoom_at(mb.position, 1.0 + 0.16 * maxf(mb.factor, 1.0))
				accept_event()
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					zoom_at(mb.position, 1.0 / (1.0 + 0.16 * maxf(mb.factor, 1.0)))
				accept_event()
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				if mb.pressed:
					_mouse_down = true
					_dragging = false
					_press_pos = mb.position
					_drag_from = mb.position
					if mb.double_click and mb.button_index == MOUSE_BUTTON_LEFT:
						var p := pick(mb.position)
						if not p.is_empty():
							activated.emit(p)
				else:
					if _mouse_down and not _dragging and mb.button_index == MOUSE_BUTTON_LEFT:
						clicked.emit(pick(mb.position))
					_mouse_down = false
					_dragging = false
				accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		cursor_mode = false
		if _mouse_down:
			if not _dragging and mm.position.distance_to(_press_pos) > 7.0:
				_dragging = true
			if _dragging:
				pan_px(mm.position - _drag_from)
				_drag_from = mm.position
		else:
			_set_hover(pick(mm.position))
		accept_event()


func _touch(t: InputEventScreenTouch) -> void:
	cursor_mode = false
	if t.pressed:
		_touches[t.index] = t.position
		if _touches.size() == 1:
			_press_pos = t.position
			_press_time = Time.get_ticks_msec()
			_touch_moved = false
		elif _touches.size() == 2:
			_pinch_d = _pinch_span()
			_touch_moved = true
	else:
		var was_tap := _touches.size() == 1 and not _touch_moved and Time.get_ticks_msec() - _press_time < 450
		_touches.erase(t.index)
		if was_tap:
			var p := pick(t.position)
			_set_hover(p)
			clicked.emit(p)
		if _touches.size() == 2:
			_pinch_d = _pinch_span()


func _touch_drag(d: InputEventScreenDrag) -> void:
	if not _touches.has(d.index):
		_touches[d.index] = d.position
	var prev: Vector2 = _touches[d.index]
	_touches[d.index] = d.position
	if _touches.size() == 1:
		if d.position.distance_to(_press_pos) > 12.0:
			_touch_moved = true
		if _touch_moved:
			pan_px(d.position - prev)
	elif _touches.size() >= 2:
		var span := _pinch_span()
		var mid := _pinch_mid()
		if _pinch_d > 1.0 and span > 1.0:
			zoom_at(mid, span / _pinch_d)
			zoom = target_zoom
			center = target_center
		_pinch_d = span
		pan_px((d.position - prev) * 0.5)


func _pinch_span() -> float:
	var pts := _touches.values()
	return (pts[0] as Vector2).distance_to(pts[1]) if pts.size() >= 2 else 0.0


func _pinch_mid() -> Vector2:
	var pts := _touches.values()
	return ((pts[0] as Vector2) + (pts[1] as Vector2)) * 0.5 if pts.size() >= 2 else size * 0.5


# --- drawing --------------------------------------------------------------------------------------

func _draw() -> void:
	# paper behind the map image (visible beside it at low zoom)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.80, 0.86, 0.85))


func _draw_paper() -> void:
	if _tex == null:
		return
	var tl := uv_to_local(Vector2.ZERO)
	var mp := map_px()
	paper.draw_texture_rect(_tex, Rect2(tl, Vector2(mp, mp)), false)
