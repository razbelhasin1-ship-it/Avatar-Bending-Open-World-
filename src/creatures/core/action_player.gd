class_name ActionPlayer
extends RefCounted
## Plays CreatureActions with cross-fading, timed events and hold/loop semantics.
## Owned by CreatureRig, which forwards `event_fired` / `finished` to its signals.

signal event_fired(action_name: StringName, event: StringName)
signal finished(action_name: StringName)

## Current (main) action or null.
var current: CreatureAction = null
## Actions blending out.
var fading: Array[CreatureAction] = []


func play(a: CreatureAction) -> void:
	if current != null:
		if a.cut_previous:
			finished.emit(current.name)
		else:
			_begin_stop(current)
	current = a
	a.t = 0.0
	a.weight = 0.0 if a.blend_in > 0.0 else 1.0
	a.stopping = false
	a._next_event = 0


## Stops the current action (blends out over its blend_out).
func stop() -> void:
	if current != null:
		_begin_stop(current)
		current = null


## Stops the current action only if it is an idle behaviour.
func stop_idle() -> void:
	if current != null and current.is_idle:
		stop()


func is_playing(action_name: StringName = &"") -> bool:
	if current == null:
		return false
	return action_name == &"" or current.name == action_name


## All actions contributing this frame (current + fading).
func active() -> Array[CreatureAction]:
	var out: Array[CreatureAction] = fading.duplicate()
	if current != null:
		out.append(current)
	return out


func update(delta: float) -> void:
	if current != null:
		var a := current
		a.t += delta
		a.weight = minf(1.0, a.weight + delta / maxf(a.blend_in, 1e-3))
		_fire_events(a)
		if a.t >= a.duration:
			if a.loop:
				a.t = fmod(a.t, maxf(a.duration, 1e-3))
				a._next_event = 0
			elif a.hold:
				a.t = a.duration
			else:
				_begin_stop(a)
				current = null
	for i in range(fading.size() - 1, -1, -1):
		var f := fading[i]
		f.stop_t += delta
		if not f.hold:
			f.t = minf(f.t + delta, f.duration)
		f.weight = maxf(0.0, f.weight - delta / maxf(f.blend_out, 1e-3))
		if f.weight <= 0.0:
			fading.remove_at(i)
			finished.emit(f.name)


func clear() -> void:
	if current != null:
		finished.emit(current.name)
	for f in fading:
		finished.emit(f.name)
	current = null
	fading.clear()


func _begin_stop(a: CreatureAction) -> void:
	a.stopping = true
	a.stop_t = 0.0
	if a.weight <= 0.0:
		finished.emit(a.name)
		return
	fading.append(a)


func _fire_events(a: CreatureAction) -> void:
	while a._next_event < a.events.size() and a.t >= float(a.events[a._next_event][0]):
		event_fired.emit(a.name, a.events[a._next_event][1])
		a._next_event += 1
