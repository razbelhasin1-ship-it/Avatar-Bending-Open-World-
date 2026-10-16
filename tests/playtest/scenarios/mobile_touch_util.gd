extends RefCounted
## Simulated multi-touch for the mobile_* playtests: real InputEventScreenTouch /
## ScreenDrag events through Input.parse_input_event (window coordinates, so they travel
## the same path as a phone's: stretch transform, GUI touch focus, mouse emulation).
## Not a scenario itself (no run()).

var p: Playtest
var _pos: Dictionary = {}


func _init(pt: Playtest) -> void:
	p = pt


## Window (screen) position of a point given in `ci`'s local coordinates.
func to_screen(ci: CanvasItem, local: Vector2) -> Vector2:
	var vp := ci.get_viewport()
	return vp.get_screen_transform() * (ci.get_global_transform_with_canvas() * local)


func overlay_point(ov: Control, local: Vector2) -> Vector2:
	return to_screen(ov, local)


func button_center(ov: TouchOverlay, id: StringName) -> Vector2:
	var b: TouchButton = ov.buttons[id]
	return to_screen(ov, b.get_center())


func down(index: int, screen_pos: Vector2) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = screen_pos
	ev.pressed = true
	_pos[index] = screen_pos
	Input.parse_input_event(ev)


func move(index: int, screen_pos: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = screen_pos
	var prev: Vector2 = _pos.get(index, screen_pos)
	ev.relative = screen_pos - prev
	ev.screen_relative = ev.relative
	_pos[index] = screen_pos
	Input.parse_input_event(ev)


func up(index: int) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = _pos.get(index, Vector2.ZERO)
	ev.pressed = false
	_pos.erase(index)
	Input.parse_input_event(ev)


## Finger down, glide to `to` in `steps` drag events (one per rendered frame).
func drag(index: int, from: Vector2, to: Vector2, steps: int = 6, lift: bool = true) -> void:
	down(index, from)
	await p.frames(1)
	for i in steps:
		move(index, from.lerp(to, float(i + 1) / steps))
		await p.frames(1)
	if lift:
		up(index)
		await p.frames(1)


## Tap on a touch button (down, `hold` seconds of game time, up).
func tap_button(ov: TouchOverlay, id: StringName, index: int = 3, hold: float = 0.08) -> void:
	var at := button_center(ov, id)
	down(index, at)
	await p.frames(1)
	await p.wait_game(hold)
	up(index)
	await p.frames(1)


func release_all_fingers() -> void:
	for i: int in _pos.keys():
		up(i)
