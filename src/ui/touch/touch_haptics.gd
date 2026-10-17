class_name TouchHaptics
extends RefCounted
## Vibration feedback for touch play (Input.vibrate_handheld: Android, iOS, and mobile
## browsers through navigator.vibrate). Driven by the combat events, gated by the
## touch.haptics setting, throttled so rapid combos never buzz continuously.
##
##   Events.hit_landed  -> player hits: light 16 ms, heavy 34 ms; parry 30 ms
##   Events.player_damaged -> 42 ms (stronger for heavy hits)
##   on_button()        -> 7 ms tick when a touch button is pressed

## Minimum spacing between two pulses (ms); a stronger pulse may cut in earlier.
const MIN_GAP_MS := 70

var enabled := true
## Called as vibrate.call(duration_ms: int, amplitude: float); tests inject a recorder.
var vibrate: Callable = Callable(Input, &"vibrate_handheld")
## Millisecond clock (tests inject a fake one).
var clock: Callable = Callable(Time, &"get_ticks_msec")
## Last pulses [duration_ms, amplitude] (capped; tests and debugging).
var history: Array = []

var _last_ms := -100000
var _last_amp := 0.0


## Events.hit_landed handler.
func on_hit_landed(hit: HitInfo, target: Node, result: int) -> void:
	if hit == null:
		return
	var target_is_player := target != null and is_instance_valid(target) and target.is_in_group(&"player")
	if target_is_player:
		match result:
			Combat.Result.DEFLECTED: pulse(30, 0.55)
			Combat.Result.BLOCKED: pulse(22, 0.4)
		return
	if hit.team != Combat.Team.PLAYER:
		return
	if result == Combat.Result.HIT or result == Combat.Result.KILLED:
		var heavy := hit.is_heavy or int(hit.reaction) >= int(HitInfo.Reaction.KNOCKBACK)
		pulse(34 if heavy else 16, 0.7 if heavy else 0.35)


## Events.player_damaged handler.
func on_player_damaged(_amount: float, hit: HitInfo) -> void:
	if hit != null and hit.has_meta(&"dot"):
		pulse(14, 0.2)   # burn tick: a faint buzz, not a blow
		return
	var heavy := hit != null and (hit.is_heavy or int(hit.reaction) >= int(HitInfo.Reaction.KNOCKBACK))
	pulse(60 if heavy else 42, 0.85 if heavy else 0.6)


func on_button() -> void:
	pulse(7, 0.18)


## Vibrates for `ms` at `amplitude` (0..1) unless throttled or disabled. Returns true if sent.
func pulse(ms: int, amplitude: float) -> bool:
	if not enabled:
		return false
	var now := int(clock.call())
	if now - _last_ms < MIN_GAP_MS and amplitude <= _last_amp:
		return false
	_last_ms = now
	_last_amp = amplitude
	history.append([ms, amplitude])
	if history.size() > 32:
		history.remove_at(0)
	if vibrate.is_valid():
		vibrate.call(ms, clampf(amplitude, 0.0, 1.0))
	return true
