class_name CreatureAction
extends RefCounted
## One playing action (roar, sit, dig_in, takeoff...). Species scripts create them in
## `make_action()` and pose them in `action_pose()` from `t` (seconds), `weight`
## (0..1 blend) and `progress()`. Timed `events` are emitted through
## CreatureRig.action_event when `t` crosses them.

var name: StringName
## Length in seconds. For `hold` actions: length of the intro, after which the end pose
## is held until CreatureRig.stop_action() (or locomotion when `cancel_on_move`).
var duration := 1.0
var hold := false
var loop := false
var blend_in := 0.2
## Blend-out time used when finishing or stopping.
var blend_out := 0.3
var cancel_on_move := false
## Locomotion is suppressed while playing (the creature plants its feet).
var roots := false
## [[time_seconds, &"event"], ...] sorted by time.
var events: Array = []
var opts: Dictionary = {}
## Idle behaviour (any explicit play_action replaces it immediately).
var is_idle := false

# Runtime state (managed by ActionPlayer).
var t := 0.0
var weight := 0.0
var stopping := false
var stop_t := 0.0
var _next_event := 0


func _init(action_name: StringName = &"", dur: float = 1.0) -> void:
	name = action_name
	duration = dur


## 0..1 progress through `duration`.
func progress() -> float:
	return clampf(t / maxf(duration, 1e-4), 0.0, 1.0)


## Smooth 0->1->0 envelope over the action with `a` attack and `r` release fractions.
func envelope(a: float = 0.2, r: float = 0.25) -> float:
	var p := progress()
	if hold:
		return smoothstep(0.0, maxf(a, 1e-3), p)
	return smoothstep(0.0, maxf(a, 1e-3), p) * (1.0 - smoothstep(1.0 - r, 1.0, p))


## Smooth bump between two progress values.
func window(from_p: float, to_p: float, edge: float = 0.1) -> float:
	var p := progress()
	return smoothstep(from_p, from_p + edge, p) * (1.0 - smoothstep(to_p - edge, to_p, p))


func add_event(time: float, event: StringName) -> CreatureAction:
	events.append([time, event])
	events.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	return self
