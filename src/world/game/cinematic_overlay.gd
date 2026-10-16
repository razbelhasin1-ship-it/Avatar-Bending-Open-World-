class_name CinematicOverlay
extends CanvasLayer
## Letterbox bars, a small caption and the "skip" hint for in-world cinematics (arrival
## flight, ferry interludes). Layer 35: above the HUD (10) and dialogue (30), below the
## title card (40), so region titles stay readable over the bars.
##
##   overlay.show_bars(0.6)
##   overlay.set_caption("Sailing to Crimson Harbor Piers", "Ferry")
##   overlay.show_skip_hint(true)
##   overlay.hide_bars(0.8)

## Height of each bar as a fraction of the screen.
const BAR := 0.115

var root: Control
var top_bar: ColorRect
var bottom_bar: ColorRect
var caption: Label
var subcaption: Label
var skip_box: HBoxContainer
var skip_label: Label
var bars_shown := false

var _bar_tween: Tween
var _cap_tween: Tween


func _ready() -> void:
	layer = 35
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiTheme.get_theme()
	add_child(root)
	top_bar = _bar()
	top_bar.anchor_top = 0.0
	top_bar.anchor_bottom = 0.0
	bottom_bar = _bar()
	bottom_bar.anchor_top = 1.0
	bottom_bar.anchor_bottom = 1.0
	caption = UiTheme.make_label("", UiTheme.title_font(600, 8), UiTheme.SIZE_SMALL + 2, UiTheme.PARCHMENT, HORIZONTAL_ALIGNMENT_CENTER)
	caption.anchor_left = 0.5
	caption.anchor_right = 0.5
	caption.anchor_top = 1.0
	caption.anchor_bottom = 1.0
	caption.offset_left = -700
	caption.offset_right = 700
	caption.offset_top = -96
	caption.offset_bottom = -60
	caption.modulate.a = 0.0
	root.add_child(caption)
	subcaption = UiTheme.make_label("", UiTheme.title_font(600, 6), UiTheme.SIZE_TINY, UiTheme.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	subcaption.anchor_left = 0.5
	subcaption.anchor_right = 0.5
	subcaption.anchor_top = 1.0
	subcaption.anchor_bottom = 1.0
	subcaption.offset_left = -700
	subcaption.offset_right = 700
	subcaption.offset_top = -124
	subcaption.offset_bottom = -98
	subcaption.modulate.a = 0.0
	root.add_child(subcaption)
	skip_box = HBoxContainer.new()
	skip_box.anchor_left = 1.0
	skip_box.anchor_right = 1.0
	skip_box.anchor_top = 1.0
	skip_box.anchor_bottom = 1.0
	skip_box.offset_left = -560
	skip_box.offset_right = -56
	skip_box.offset_top = -86
	skip_box.offset_bottom = -50
	skip_box.alignment = BoxContainer.ALIGNMENT_END
	skip_box.add_theme_constant_override(&"separation", 12)
	skip_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	skip_box.modulate.a = 0.0
	root.add_child(skip_box)
	var mark := BrushStroke.new(Color(UiTheme.SEAL, 0.85), 3.3)
	mark.custom_minimum_size = Vector2(46, 18)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	skip_box.add_child(mark)
	skip_label = UiTheme.make_label("", UiTheme.title_font(600, 4), UiTheme.SIZE_TINY, Color(UiTheme.PARCHMENT, 0.8))
	skip_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	skip_box.add_child(skip_label)
	visible = false


func _bar() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(0.012, 0.01, 0.01, 1.0)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.anchor_left = 0.0
	r.anchor_right = 1.0
	root.add_child(r)
	return r


## Slides the letterbox bars in over `t` seconds (0 = instant).
func show_bars(t: float = 0.6) -> void:
	visible = true
	bars_shown = true
	_animate_bars(1.0, t)


func hide_bars(t: float = 0.8) -> void:
	bars_shown = false
	show_skip_hint(false)
	set_caption("")
	_animate_bars(0.0, t)


## 0 = no bars, 1 = full letterbox (tests / screenshots read it).
func bar_amount() -> float:
	return top_bar.anchor_bottom / BAR


func _animate_bars(k: float, t: float) -> void:
	if _bar_tween and _bar_tween.is_valid():
		_bar_tween.kill()
	if t <= 0.0:
		top_bar.anchor_bottom = BAR * k
		bottom_bar.anchor_top = 1.0 - BAR * k
		visible = k > 0.0 or caption.modulate.a > 0.0
		return
	_bar_tween = create_tween().set_parallel(true)
	_bar_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_bar_tween.tween_property(top_bar, "anchor_bottom", BAR * k, t).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_bar_tween.tween_property(bottom_bar, "anchor_top", 1.0 - BAR * k, t).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if k <= 0.0:
		_bar_tween.chain().tween_callback(func() -> void: visible = bars_shown)
	# offsets stay 0: the bars are pure anchor fractions of the screen
	top_bar.offset_top = 0.0
	top_bar.offset_bottom = 0.0
	bottom_bar.offset_top = 0.0
	bottom_bar.offset_bottom = 0.0


## Caption inside the bottom bar (empty text fades it out).
func set_caption(text: String, sub: String = "") -> void:
	if _cap_tween and _cap_tween.is_valid():
		_cap_tween.kill()
	_cap_tween = create_tween().set_parallel(true)
	_cap_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	if text.is_empty():
		_cap_tween.tween_property(caption, "modulate:a", 0.0, 0.3)
		_cap_tween.tween_property(subcaption, "modulate:a", 0.0, 0.3)
		return
	visible = true
	caption.text = text.to_upper()
	subcaption.text = sub.to_upper()
	_cap_tween.tween_property(caption, "modulate:a", 1.0, 0.5)
	_cap_tween.tween_property(subcaption, "modulate:a", 1.0 if not sub.is_empty() else 0.0, 0.5)


## "Press any key to skip" / "Tap to skip" in the bottom-right corner.
func show_skip_hint(on: bool) -> void:
	if on:
		match UiInput.device:
			&"pad": skip_label.text = "PRESS ANY BUTTON TO SKIP"
			&"touch": skip_label.text = "TAP TO SKIP"
			_: skip_label.text = "PRESS ANY KEY TO SKIP"
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(skip_box, "modulate:a", 0.85 if on else 0.0, 0.4)
