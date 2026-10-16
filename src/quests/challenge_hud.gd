class_name ChallengeHud
extends CanvasLayer
## Top-centre banner of a running BendingChallenge: title, progress line, a draining timer
## bar with seconds, a pulse on each counted hit, a red flash for the wrong move, and the
## result ("WELL DONE" / "TRY AGAIN") before it fades. Sits under the compass.

var _root: Control
var _title: Label
var _progress: Label
var _bar: ColorRect
var _bar_bg: ColorRect
var _secs: Label
var _panel: PanelContainer


func _ready() -> void:
	layer = 12
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UiTheme.get_theme()
	add_child(_root)
	_panel = PanelContainer.new()
	_panel.theme_type_variation = &"InkPanel"
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.offset_left = -330
	_panel.offset_right = 330
	_panel.offset_top = 150
	_panel.offset_bottom = 290
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 6)
	_panel.add_child(v)
	_title = UiTheme.make_label("", UiTheme.title_font(700, 6), UiTheme.SIZE_BODY, UiTheme.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(_title)
	_progress = UiTheme.make_label("", UiTheme.body_font(1), UiTheme.SIZE_BODY - 2, UiTheme.PARCHMENT, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(_progress)
	var bar_box := Control.new()
	bar_box.custom_minimum_size = Vector2(0, 14)
	v.add_child(bar_box)
	_bar_bg = ColorRect.new()
	_bar_bg.color = Color(UiTheme.INK_LINE, 0.9)
	_bar_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bar_bg.offset_left = 40
	_bar_bg.offset_right = -110
	bar_box.add_child(_bar_bg)
	_bar = ColorRect.new()
	_bar.color = UiTheme.GOLD
	_bar.anchor_bottom = 1.0
	_bar_bg.add_child(_bar)
	_secs = UiTheme.make_label("", UiTheme.title_font(700, 1), UiTheme.SIZE_SMALL, UiTheme.PARCHMENT_DIM)
	_secs.anchor_left = 1.0
	_secs.anchor_right = 1.0
	_secs.offset_left = -96
	_secs.offset_right = -30
	_secs.offset_top = -9
	bar_box.add_child(_secs)
	UiTheme.apply_safe_area(_root)


func show_challenge(title: String, progress: String, ratio: float) -> void:
	_title.text = title.to_upper()
	_progress.text = progress
	_set_ratio(ratio)
	UiFx.slide_in(_panel, Vector2(0, -30), 0.35)


func set_progress(progress: String, ratio: float, seconds: float) -> void:
	_progress.text = progress
	_set_ratio(ratio)
	_secs.text = "%d s" % int(ceil(maxf(0.0, seconds)))
	_bar.color = UiTheme.GOLD if ratio > 0.25 else UiTheme.DANGER


func _set_ratio(r: float) -> void:
	if _bar_bg.size.x > 0.0:
		_bar.size = Vector2(_bar_bg.size.x * clampf(r, 0.0, 1.0), _bar_bg.size.y)


func pulse() -> void:
	UiFx.pop(_panel, 1.04, 0.14)
	Audio.play_ui(&"ui_confirm", -8.0)


func flash_wrong() -> void:
	UiFx.shake(_panel, 6.0, 0.25)
	_progress.add_theme_color_override(&"font_color", UiTheme.DANGER)
	get_tree().create_timer(0.4).timeout.connect(func() -> void:
		if is_instance_valid(_progress):
			_progress.remove_theme_color_override(&"font_color"))


func show_result(success: bool, why: String) -> void:
	_title.text = "WELL DONE" if success else "TRY AGAIN"
	_title.add_theme_color_override(&"font_color", UiTheme.SUCCESS if success else UiTheme.DANGER)
	if why != "":
		_progress.text = why
	UiFx.pop(_panel, 1.06, 0.2)
	var tw := create_tween()
	tw.tween_interval(1.8)
	tw.tween_property(_root, "modulate:a", 0.0, 0.4)
