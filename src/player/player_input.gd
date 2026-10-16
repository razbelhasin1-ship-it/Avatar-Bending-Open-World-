class_name PlayerInput
extends Node
## Gameplay input for the player, read ONLY through InputMap actions so the
## touch overlay (Input.action_press) and rebinding work everywhere.
##
## Call poll(delta) once per physics tick before gameplay reads it.
## * move_vector: camera-relative world direction (length 0..1, analog aware)
## * sprinting: hold or toggle (Settings controls.toggle_sprint)
## * presses of combat actions are buffered for BUFFER_TIME seconds of game
##   time: consume(action) returns true once if it was pressed recently, so a
##   press during recovery fires on the first cancellable frame.

const BUFFER_TIME := 0.2
const BUFFERED: Array[StringName] = [&"attack_light", &"attack_heavy", &"block", &"dodge", &"jump",
		&"ability_1", &"ability_2", &"ability_3", &"ability_4", &"ability_special", &"interact", &"lock_on", &"mount", &"companion_call"]

## When false every query reads as idle (cinematics, death, menus).
var enabled := true
## Node whose basis defines "forward" for the move vector (usually the camera).
var view: Node3D = null
## Raw stick/keys (x right, y back), 0..1 magnitude.
var move_input := Vector2.ZERO
## Camera-relative world move direction (y = 0), length = stick magnitude.
var move_vector := Vector3.ZERO
var sprinting := false
## Game-time clock (sum of physics deltas).
var clock := 0.0

## Virtual mode: actions come from `virtual` (action -> strength) instead of the
## Input singleton. Used by tests, fuzzing and scripted/AI control; the
## gameplay code above this layer cannot tell the difference.
var virtual_mode := false
var virtual: Dictionary = {}

var _pressed_at: Dictionary = {}
var _released_now: Dictionary = {}
var _held_since: Dictionary = {}
var _sprint_toggled := false
var _idle_time := 0.0
var _virtual_prev: Dictionary = {}
var _real_prev: Dictionary = {}


func poll(delta: float) -> void:
	clock += delta
	_released_now.clear()
	if not enabled:
		move_input = Vector2.ZERO
		move_vector = Vector3.ZERO
		sprinting = false
		_sprint_toggled = false
		_held_since.clear()
		_pressed_at.clear()
		_virtual_prev = virtual.duplicate()
		return
	move_input = Vector2(_strength(&"move_right") - _strength(&"move_left"), _strength(&"move_back") - _strength(&"move_forward"))
	if move_input.length() > 1.0:
		move_input = move_input.normalized()
	move_vector = _to_world(move_input)
	for a: StringName in BUFFERED:
		if not virtual_mode and not InputMap.has_action(a):
			continue
		var jp := false
		var jr := false
		if virtual_mode:
			jp = _just_pressed(a)
			jr = _just_released(a)
		else:
			# Edge detection against the previous tick: a press made between
			# physics ticks (touch overlay, scripted input) counts exactly once.
			# is_action_just_pressed() only adds taps pressed AND released
			# between two ticks.
			var now := Input.is_action_pressed(a)
			var before := bool(_real_prev.get(a, false))
			jp = (now and not before) or (not now and not before and Input.is_action_just_pressed(a))
			jr = not now and before
			_real_prev[a] = now
		if jp:
			_pressed_at[a] = clock
			_held_since[a] = clock
		elif jr:
			_released_now[a] = true
			_held_since.erase(a)
		elif not _pressed(a) and _held_since.has(a):
			# Missed release (focus loss): never leave a hold stuck.
			_released_now[a] = true
			_held_since.erase(a)
	_update_sprint(delta)
	_virtual_prev = virtual.duplicate()


func _strength(a: StringName) -> float:
	if virtual_mode:
		return float(virtual.get(a, 0.0))
	return Input.get_action_strength(a) if InputMap.has_action(a) else 0.0


func _pressed(a: StringName) -> bool:
	if virtual_mode:
		return float(virtual.get(a, 0.0)) > 0.0
	return Input.is_action_pressed(a)


func _just_pressed(a: StringName) -> bool:
	if virtual_mode:
		return _pressed(a) and float(_virtual_prev.get(a, 0.0)) <= 0.0
	return Input.is_action_just_pressed(a)


func _just_released(a: StringName) -> bool:
	if virtual_mode:
		return not _pressed(a) and float(_virtual_prev.get(a, 0.0)) > 0.0
	return Input.is_action_just_released(a)


## Virtual mode helpers.
func press(action: StringName, strength: float = 1.0) -> void:
	virtual[action] = strength


func release(action: StringName) -> void:
	virtual.erase(action)


func release_all() -> void:
	virtual.clear()


func _update_sprint(delta: float) -> void:
	var toggle := bool(Settings.get_value("controls", "toggle_sprint", false))
	if toggle:
		if _just_pressed(&"sprint"):
			_sprint_toggled = not _sprint_toggled
		if move_input.length() < 0.1:
			_idle_time += delta
			if _idle_time > 0.3:
				_sprint_toggled = false
		else:
			_idle_time = 0.0
		sprinting = _sprint_toggled
	else:
		sprinting = _pressed(&"sprint")


func _to_world(v: Vector2) -> Vector3:
	if v.length_squared() < 0.0001:
		return Vector3.ZERO
	var fwd := Vector3.FORWARD
	if view != null and is_instance_valid(view):
		fwd = -view.global_basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 1e-5:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	return right * v.x - fwd * v.y


## True (once) if `action` was pressed within the buffer window. Clears it.
func consume(action: StringName) -> bool:
	if not peek(action):
		return false
	_pressed_at.erase(action)
	return true


## True if `action` was pressed within the buffer window (does not clear it).
func peek(action: StringName) -> bool:
	if not enabled or not _pressed_at.has(action):
		return false
	if clock - float(_pressed_at[action]) > BUFFER_TIME:
		_pressed_at.erase(action)
		return false
	return true


## Seconds since the buffered press of `action` (INF if none).
func press_age(action: StringName) -> float:
	return clock - float(_pressed_at[action]) if _pressed_at.has(action) else INF


func clear(action: StringName) -> void:
	_pressed_at.erase(action)


func clear_all() -> void:
	_pressed_at.clear()


func is_held(action: StringName) -> bool:
	if not enabled:
		return false
	if virtual_mode:
		return _pressed(action)
	return InputMap.has_action(action) and Input.is_action_pressed(action)


## True on the tick `action` was released.
func just_released(action: StringName) -> bool:
	return _released_now.has(action)


## How long `action` has been held (0 if not held).
func held_time(action: StringName) -> float:
	if not is_held(action) or not _held_since.has(action):
		return 0.0
	return clock - float(_held_since[action])


func has_move() -> bool:
	return move_vector.length_squared() > 0.0025
