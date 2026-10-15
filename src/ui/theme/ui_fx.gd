class_name UiFx
extends RefCounted
## UI feedback helpers: Audio.play_ui sounds, focus/hover wiring and short, deliberate
## tweens (pop, fade, slide). Every interactive widget goes through `wire()` so mouse,
## keyboard and controller behave the same: hovering grabs focus, focus plays the
## hover tick and lifts the control, pressing plays the click.

const HOVER := &"ui_hover"
const CLICK := &"ui_click"
const CONFIRM := &"ui_confirm"
const BACK := &"ui_back"
const OPEN := &"ui_open"
const CLOSE := &"ui_close"
const ERROR := &"ui_error"
const SELECT_ELEMENT := &"ui_select_element"
const NOTIFY := &"ui_notify"

## Sounds requested through UiFx are recorded here (newest last) so tests can verify feedback.
static var history: Array[StringName] = []
static var _quiet_until := 0


static func sound(sound_name: StringName) -> void:
	if Time.get_ticks_msec() < _quiet_until and sound_name == HOVER:
		return
	history.append(sound_name)
	if history.size() > 64:
		history.pop_front()
	Audio.play_ui(sound_name)


## Suppresses hover ticks for a moment (programmatic focus when a menu opens).
static func quiet(msec: int = 120) -> void:
	_quiet_until = Time.get_ticks_msec() + msec


## Grabs focus without the hover tick.
static func focus_silently(c: Control) -> void:
	if c == null or not c.is_inside_tree() or not c.is_visible_in_tree():
		return
	quiet()
	c.grab_focus()


## Standard interaction wiring for buttons/rows. opts: {"lift": px (default 0),
## "pop": scale (default 1.0 = none), "press_sound": StringName (default CLICK)}.
static func wire(c: Control, opts: Dictionary = {}) -> void:
	if c.has_meta(&"ui_wired"):
		return
	c.set_meta(&"ui_wired", true)
	c.mouse_entered.connect(func() -> void:
		if c.focus_mode != Control.FOCUS_NONE and c.is_visible_in_tree() and not c.has_focus() and _can_focus(c):
			c.grab_focus())
	c.focus_entered.connect(func() -> void:
		sound(HOVER)
		var s: float = opts.get("pop", 1.0)
		if s != 1.0:
			pop(c, s))
	if c is BaseButton:
		var snd: StringName = opts.get("press_sound", CLICK)
		(c as BaseButton).pressed.connect(func() -> void: sound(snd))


static func _can_focus(c: Control) -> bool:
	if c is BaseButton and (c as BaseButton).disabled:
		return false
	return true


## Quick scale pop around the control's center.
static func pop(c: Control, peak: float = 1.05, time: float = 0.14) -> void:
	c.pivot_offset = c.size * 0.5
	var t := c.create_tween()
	t.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(c, "scale", Vector2.ONE * peak, time * 0.45)
	t.tween_property(c, "scale", Vector2.ONE, time * 0.55).set_trans(Tween.TRANS_SINE)


static func fade_in(c: CanvasItem, time: float = 0.25, delay: float = 0.0) -> Tween:
	c.modulate.a = 0.0
	var t := c.create_tween()
	t.tween_property(c, "modulate:a", 1.0, time).set_delay(delay).set_trans(Tween.TRANS_SINE)
	return t


static func fade_out(c: CanvasItem, time: float = 0.2) -> Tween:
	var t := c.create_tween()
	t.tween_property(c, "modulate:a", 0.0, time).set_trans(Tween.TRANS_SINE)
	return t


## Slides a control in from `offset` (relative px) while fading in.
static func slide_in(c: Control, offset: Vector2, time: float = 0.35, delay: float = 0.0) -> Tween:
	var target := c.position
	c.position = target + offset
	c.modulate.a = 0.0
	var t := c.create_tween().set_parallel(true)
	t.tween_property(c, "position", target, time).set_delay(delay).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	t.tween_property(c, "modulate:a", 1.0, time * 0.8).set_delay(delay)
	return t


## Horizontal shake for invalid input (disabled option, insufficient chi).
static func shake(c: Control, strength: float = 8.0, time: float = 0.3) -> void:
	var base := c.position
	var t := c.create_tween()
	var steps := 6
	for i in steps:
		var k := (1.0 - float(i) / steps) * strength * (1.0 if i % 2 == 0 else -1.0)
		t.tween_property(c, "position:x", base.x + k, time / steps)
	t.tween_property(c, "position:x", base.x, 0.04)
