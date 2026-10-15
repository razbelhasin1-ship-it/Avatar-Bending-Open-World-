class_name AudioFader
extends RefCounted
## A non-positional player with a smoothly moving gain (equal-power curve).
## Used by MusicDirector and AmbienceMixer instead of tweens so fades can be
## retargeted at any time without fighting each other.

const SILENT_DB := -80.0

var player: AudioStreamPlayer
## What this fader is currently playing (track / ambience name).
var key: StringName = &""
var gain := 0.0
var target := 0.0
var rate := 1.0
## Static level of the content (from the caller's volume_db).
var base_db := 0.0
## Seconds spent silent (used to stop or forget paused tracks).
var idle := 0.0


func _init(p: AudioStreamPlayer) -> void:
	player = p


## Real (unscaled, wall-clock) seconds since `last_usec`; updates it in place via
## the returned pair [dt, now]. Audio fades and timers must not stall during
## hitstop (Engine.time_scale) or crawl when the frame rate drops.
static func real_delta(last_usec: int) -> Array:
	var now := Time.get_ticks_usec()
	var dt := 0.0 if last_usec <= 0 else float(now - last_usec) / 1000000.0
	return [clampf(dt, 0.0, 2.0), now]


## Starts a fade towards `to` (0..1) lasting `seconds` (0 = immediate).
func fade_to(to: float, seconds: float) -> void:
	target = clampf(to, 0.0, 1.0)
	if seconds <= 0.0:
		gain = target
		rate = 1.0
	else:
		rate = maxf(absf(target - gain), 0.05) / seconds


## Advances the fade and applies the volume. `extra_db` = ducking etc.
func step(delta: float, extra_db: float = 0.0) -> void:
	gain = move_toward(gain, target, rate * delta)
	var amp := sin(gain * PI * 0.5)
	player.volume_db = (linear_to_db(amp) if amp > 0.0001 else SILENT_DB) + base_db + extra_db
	if is_silent():
		idle += delta
	else:
		idle = 0.0


func is_silent() -> bool:
	return gain <= 0.0001 and target <= 0.0


func is_active() -> bool:
	return player.playing and not player.stream_paused and not is_silent()
