class_name DayNightCycle
extends Node
## World clock and celestial geometry.
##
## `hour` runs 0..24 at `time_scale` game hours per real second (default 1 game hour per
## 2 real minutes). It is mirrored into GameState.time_of_day every frame (so saves persist it)
## and Events.time_of_day_changed fires every EMIT_STEP game hours and on every explicit set.
## Sun path: rises due east (+X) at 06:00, culminates due south (+Z, north is -Z) at noon at
## `max_elevation_deg`, sets due west at 18:00. The moon runs opposite, 1.5 h behind.

signal hour_changed(hour: float)

const DEFAULT_TIME_SCALE := 1.0 / 120.0
const EMIT_STEP := 0.25

var hour: float = 9.0
## Game hours per real second (0 freezes time).
var time_scale: float = DEFAULT_TIME_SCALE
var paused: bool = false
## Peak sun elevation (degrees); the sky controller blends it by region.
var max_elevation_deg: float = 55.0
## Moon phase 0..1 (0.5 full); advances one cycle per 8 game days.
var moon_phase: float = 0.42
var _last_slot: int = -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


## Advances the clock by `delta` real seconds.
func advance(delta: float) -> void:
	if paused or time_scale == 0.0:
		return
	var dh := delta * time_scale
	moon_phase = fposmod(moon_phase + dh / (24.0 * 8.0), 1.0)
	_apply_hour(hour + dh, false)


## Sets the time of day (hours, wrapped to 0..24) and notifies listeners immediately.
func set_hour(h: float) -> void:
	_apply_hour(h, true)


func _apply_hour(h: float, force: bool) -> void:
	hour = fposmod(h, 24.0)
	GameState.time_of_day = hour
	var slot := int(floor(hour / EMIT_STEP))
	if force or slot != _last_slot:
		_last_slot = slot
		hour_changed.emit(hour)
		Events.time_of_day_changed.emit(hour)


## Unit vector towards the sun.
func sun_direction() -> Vector3:
	return sun_direction_at(hour, max_elevation_deg)


## Unit vector towards the moon.
func moon_direction() -> Vector3:
	return sun_direction_at(hour + 13.5, max_elevation_deg * 0.85)


## Sun elevation above the horizon in degrees (negative at night).
func sun_elevation_deg() -> float:
	return rad_to_deg(asin(clampf(sun_direction().y, -1.0, 1.0)))


## Direction towards the sun at `h` hours for a path culminating at `max_elev` degrees.
static func sun_direction_at(h: float, max_elev: float) -> Vector3:
	var ha := (h - 12.0) / 24.0 * TAU
	var e := deg_to_rad(max_elev)
	# circle through east (06:00), up-south (noon), west (18:00)
	var up_south := Vector3(0.0, sin(e), cos(e))
	return (up_south * cos(ha) + Vector3(-1.0, 0.0, 0.0) * sin(ha)).normalized()


## 0 at night .. 1 in full daylight (smooth across dawn/dusk).
func daylight() -> float:
	return smoothstep(-6.0, 8.0, sun_elevation_deg())
