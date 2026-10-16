class_name TouchActions
extends RefCounted
## Presses InputMap actions on behalf of the touch overlay, exactly like a keyboard or
## controller would, so gameplay keeps reading input ONLY through actions.
##
## * Several sources (fingers / widgets) can hold the same action: it stays pressed until
##   the last source lets go (e.g. the stick and a button never fight over `sprint`).
## * Minimum hold: a tap shorter than MIN_HOLD_FRAMES physics ticks is released on a later
##   tick (flush()), so PlayerInput's per-tick edge detection always sees the press.
## * Menu-type actions (EVENT_ACTIONS: pause, map, journal, skills) are consumed by
##   `_unhandled_input` listeners, so they are delivered as InputEventAction events
##   through Input.parse_input_event (which also updates the action state).
## * Analog actions (move_*) carry a strength (0..1); 0 releases.
##
##   var acts := TouchActions.new()
##   acts.press(&"attack_light", &"strike")       # finger down on Strike
##   acts.release(&"attack_light", &"strike")     # finger up (deferred if too short)
##   acts.flush()                                  # every physics tick
##   acts.release_all()                            # pause, focus loss, overlay hidden

## Physics ticks an action stays pressed at least (PlayerInput polls once per tick).
const MIN_HOLD_FRAMES := 2
## Actions delivered as InputEventAction events instead of Input.action_press.
const EVENT_ACTIONS: Array[StringName] = [&"pause", &"open_map", &"open_journal", &"open_skills", &"ui_cancel"]

## action -> {source: strength}
var _sources: Dictionary = {}
## action -> physics frame of the press edge
var _pressed_frame: Dictionary = {}
## actions waiting for their minimum hold before being released
var _pending_release: Dictionary = {}
## Physics frame provider (tests inject a fake clock).
var frame_source: Callable = Callable(Engine, &"get_physics_frames")
## Log of press edges (action names) for tests and debugging; capped.
var history: Array[StringName] = []


## Holds `action` for `source` with `strength` (0..1). Re-pressing updates the strength.
func press(action: StringName, source: StringName = &"", strength: float = 1.0) -> void:
	if not InputMap.has_action(action):
		return
	if strength <= 0.0:
		release(action, source)
		return
	var src: Dictionary = _sources.get(action, {})
	var was_held := not src.is_empty()
	src[source] = clampf(strength, 0.0, 1.0)
	_sources[action] = src
	_pending_release.erase(action)
	var s := _strength(action)
	if action in EVENT_ACTIONS:
		if not was_held:
			_emit_event(action, true, s)
	else:
		Input.action_press(action, s)
	if not was_held:
		_pressed_frame[action] = int(frame_source.call())
		history.append(action)
		if history.size() > 64:
			history.remove_at(0)


## Analog convenience: press with `strength`, or release when it is ~0.
func set_strength(action: StringName, source: StringName, strength: float) -> void:
	if strength <= 0.001:
		release(action, source)
	else:
		press(action, source, strength)


## Releases `source`'s hold of `action` (the action stays down while other sources hold it).
func release(action: StringName, source: StringName = &"") -> void:
	if not _sources.has(action):
		return
	var src: Dictionary = _sources[action]
	src.erase(source)
	if not src.is_empty():
		if not action in EVENT_ACTIONS:
			Input.action_press(action, _strength(action))
		return
	_sources.erase(action)
	var held_for := int(frame_source.call()) - int(_pressed_frame.get(action, -1000))
	# Event listeners see the press event itself, so menu actions release at once
	# (and never wait for a physics tick that a paused tree would not run).
	if held_for < MIN_HOLD_FRAMES and not action in EVENT_ACTIONS:
		_pending_release[action] = true
		return
	_do_release(action)


## Instant press + release (deferred by the minimum hold), for one-shot buttons.
func tap(action: StringName, source: StringName = &"tap") -> void:
	press(action, source)
	release(action, source)


## Completes deferred releases whose minimum hold has passed. Call every physics tick.
func flush() -> void:
	if _pending_release.is_empty():
		return
	var now := int(frame_source.call())
	for action: StringName in _pending_release.keys():
		if now - int(_pressed_frame.get(action, -1000)) >= MIN_HOLD_FRAMES:
			_pending_release.erase(action)
			_do_release(action)


## Releases everything immediately (pause, focus loss, overlay hidden, scene exit).
func release_all() -> void:
	var all: Array = _sources.keys()
	for a: StringName in _pending_release.keys():
		if not all.has(a):
			all.append(a)
	_sources.clear()
	_pending_release.clear()
	for action: StringName in all:
		_do_release(action)


## True while any source holds `action` (or its release is still pending).
func is_held(action: StringName) -> bool:
	return _sources.has(action) or _pending_release.has(action)


## Sources currently holding `action`.
func sources_of(action: StringName) -> Array:
	return (_sources.get(action, {}) as Dictionary).keys()


func held_actions() -> Array:
	var out: Array = _sources.keys()
	for a: StringName in _pending_release.keys():
		if not out.has(a):
			out.append(a)
	return out


func _strength(action: StringName) -> float:
	var best := 0.0
	for v: float in (_sources.get(action, {}) as Dictionary).values():
		best = maxf(best, v)
	return best


func _do_release(action: StringName) -> void:
	_pressed_frame.erase(action)
	if action in EVENT_ACTIONS:
		_emit_event(action, false, 0.0)
	elif InputMap.has_action(action):
		Input.action_release(action)


static func _emit_event(action: StringName, pressed: bool, strength: float) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	ev.strength = strength
	Input.parse_input_event(ev)
