class_name TouchStick
extends Control
## Floating virtual stick (left thumb). The base appears where the thumb lands inside the
## stick zone; the knob follows the thumb up to the ring. Pushing to (or past) the ring's
## edge sprints when touch.auto_sprint is on; dragging far past it drags the base along so
## direction changes stay instant. When idle a faint ring rests at `rest_center` as a hint.
##
## Pure maths lives in static helpers (`stick_vector`, `follow_base`) so the behaviour is
## unit-tested without a display.

## Ring radius (design px, scaled by touch.button_scale).
var radius := 118.0
## Normalised dead zone of the knob travel.
var deadzone := 0.1
## Thumb distance (in radii) that turns sprint on / off (hysteresis).
var sprint_on := 1.0
var sprint_off := 0.84
## Beyond this many radii the base is dragged after the thumb.
var follow_limit := 1.45
var auto_sprint := true
var accent := UiTheme.GOLD
var opacity := 0.7
## Where the idle hint ring is drawn (parent coordinates).
var rest_center := Vector2(260, 800)

## Touch index driving the stick (-1 = idle).
var touch_index := -1
var base := Vector2.ZERO
var thumb := Vector2.ZERO
## Output: x right, y down (back), length 0..1.
var vector := Vector2.ZERO
var sprinting := false

var _fade := 0.0


func _init() -> void:
	name = "Stick"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func is_active() -> bool:
	return touch_index >= 0


## Thumb down at `p` (parent coordinates). The base is kept inside `bounds` so the
## ring never leaves the screen.
func begin(index: int, p: Vector2, bounds: Rect2) -> void:
	touch_index = index
	var r := radius
	base = Vector2(clampf(p.x, bounds.position.x + r, maxf(bounds.position.x + r, bounds.end.x - r)),
			clampf(p.y, bounds.position.y + r, maxf(bounds.position.y + r, bounds.end.y - r)))
	thumb = p
	_update()


func move(p: Vector2) -> void:
	if touch_index < 0:
		return
	thumb = p
	base = follow_base(base, thumb, radius * follow_limit)
	_update()


func end() -> void:
	touch_index = -1
	vector = Vector2.ZERO
	sprinting = false
	queue_redraw()


func _update() -> void:
	vector = stick_vector(base, thumb, radius, deadzone)
	var dist := base.distance_to(thumb) / maxf(radius, 1.0)
	if auto_sprint:
		if sprinting:
			sprinting = dist >= sprint_off
		else:
			sprinting = dist >= sprint_on
	else:
		sprinting = false
	queue_redraw()


## Normalised stick output for a thumb at `thumb` over a base at `base`: length 0..1,
## dead zone removed and re-scaled so travel just outside it starts at ~0.
static func stick_vector(p_base: Vector2, p_thumb: Vector2, p_radius: float, p_deadzone: float) -> Vector2:
	var off := (p_thumb - p_base) / maxf(p_radius, 1.0)
	var l := off.length()
	if l <= p_deadzone:
		return Vector2.ZERO
	var m := clampf((l - p_deadzone) / (1.0 - p_deadzone), 0.0, 1.0)
	return off / l * m


## Base dragged toward the thumb so it never trails by more than `max_dist`.
static func follow_base(p_base: Vector2, p_thumb: Vector2, max_dist: float) -> Vector2:
	var d := p_thumb - p_base
	if d.length() <= max_dist:
		return p_base
	return p_thumb - d.normalized() * max_dist


func _process(delta: float) -> void:
	var want := 1.0 if is_active() else 0.0
	if not is_equal_approx(_fade, want):
		_fade = move_toward(_fade, want, delta * (10.0 if want > 0.5 else 4.0))
		queue_redraw()
	elif sprinting:
		queue_redraw()


func _draw() -> void:
	# Idle: a quiet hint at the rest spot. Active: full strength where the thumb landed
	# (and it fades back out from there).
	var a := lerpf(opacity * 0.6, 1.0, _fade)
	var c := base if is_active() or _fade > 0.01 else rest_center
	var r := radius
	# Base: lacquer disc, dark rim, gold hairline, inner guide ring, cardinal ticks.
	draw_circle(c, r, Color(UiTheme.INK, 0.4 * a), true, -1.0, true)
	draw_arc(c, r + 1.5, 0.0, TAU, 72, Color(0, 0, 0, 0.3 * a), 2.0, true)
	draw_arc(c, r, 0.0, TAU, 72, Color(UiTheme.GOLD, 0.7 * a), 2.5, true)
	draw_arc(c, r * 0.5, 0.0, TAU, 48, Color(UiTheme.GOLD, 0.14 * a), 1.2, true)
	for i in 4:
		var ang := i * PI * 0.5
		var d := Vector2(cos(ang), sin(ang))
		draw_line(c + d * (r - 14.0), c + d * (r - 4.0), Color(UiTheme.PARCHMENT, 0.35 * a), 2.0, true)
	var knob_c := c
	if is_active():
		var off := thumb - base
		if off.length() > r:
			off = off.normalized() * r
		knob_c = base + off
		# Direction arc on the ring.
		if vector.length() > 0.05:
			var ang := vector.angle()
			var span := 0.35 + 0.45 * vector.length()
			var col := accent if not sprinting else accent.lightened(0.3)
			draw_arc(c, r + 1.0, ang - span, ang + span, 24, Color(col, 0.85 * a), 6.0 if sprinting else 4.0, true)
		if sprinting:
			var t := Time.get_ticks_msec() * 0.001
			var pulse := 0.5 + 0.5 * sin(t * 10.0)
			draw_arc(c, r + 10.0 + 4.0 * pulse, 0.0, TAU, 72, Color(accent, 0.35 * a), 3.0, true)
	var kr := r * 0.42
	draw_circle(knob_c, kr, Color(UiTheme.INK_3, 0.85 * a), true, -1.0, true)
	draw_arc(knob_c, kr, 0.0, TAU, 48, Color(accent if is_active() else UiTheme.GOLD, 0.9 * a), 3.0, true)
	draw_arc(knob_c + Vector2(0, -kr * 0.18), kr * 0.6, PI * 1.15, PI * 1.85, 24, Color(1, 1, 1, 0.1 * a), kr * 0.2, true)
