class_name SettingRow
extends PanelContainer
## One labelled option row of the settings menu: name on the left, the editing widget
## (UiChoice / UiSlider / UiToggle) on the right. The row lights up (lacquer band + gold
## accent) while its widget has focus and reports itself through `row_focused` so the
## menu can show the help text. Unsupported options are disabled with a tooltip.

signal row_focused(row: SettingRow)
## Emitted with the new value when the player edits the widget.
signal edited(row: SettingRow, value: Variant)

const HEIGHT := 76.0

var spec: Dictionary = {}
var label: Label
var widget: Control
## The focusable control inside the widget.
var focus_target: Control
var unsupported := false
var unsupported_reason := ""

var _hot := false
var _hl := 0.0


func _init(p_spec: Dictionary = {}) -> void:
	spec = p_spec
	theme_type_variation = &"RowPanel"
	custom_minimum_size = Vector2(0, HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_PASS


func _ready() -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 24)
	add_child(h)
	label = UiTheme.make_label(String(spec.get("label", "")), UiTheme.body_font(1), UiTheme.SIZE_BODY, UiTheme.PARCHMENT)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(label)
	widget = _make_widget()
	widget.custom_minimum_size.x = 440
	widget.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(widget)
	var feature := String(spec.get("feature", ""))
	if not feature.is_empty() and not Settings.is_feature_supported(feature):
		set_unsupported(SettingRow.unsupported_text(feature))
	focus_target.focus_entered.connect(_on_focus.bind(true))
	focus_target.focus_exited.connect(_on_focus.bind(false))
	mouse_entered.connect(func() -> void:
		if unsupported:
			row_focused.emit(self))
	refresh()


func _make_widget() -> Control:
	match String(spec.get("kind", "")):
		"choice":
			var c := UiChoice.new()
			var items: Array = []
			for it: Dictionary in spec.get("items", []):
				var d := it.duplicate()
				var f := String(it.get("feature", ""))
				if not f.is_empty() and not Settings.is_feature_supported(f):
					d["disabled"] = true
				items.append(d)
			c.set_items(items)
			c.value_changed.connect(func(v: Variant) -> void: edited.emit(self, v))
			focus_target = c
			return c
		"slider":
			var s := UiSlider.new(float(spec.get("min", 0.0)), float(spec.get("max", 1.0)), float(spec.get("step", 0.05)))
			var fmt := String(spec.get("format", "percent"))
			s.format = func(v: float) -> String: return SettingsSchema.format_value(fmt, v)
			s.value_changed.connect(func(v: float) -> void: edited.emit(self, v))
			focus_target = s.slider
			return s
		"toggle":
			var t := UiToggle.new()
			t.toggled.connect(func(on: bool) -> void: edited.emit(self, on))
			focus_target = t
			return t
	var l := Label.new()
	focus_target = l
	return l


## Re-reads the value from Settings without emitting `edited`.
func refresh() -> void:
	var v: Variant = Settings.get_value(String(spec.get("section", "")), String(spec.get("key", "")))
	if widget is UiChoice:
		(widget as UiChoice).select_value(v)
	elif widget is UiSlider:
		(widget as UiSlider).set_value_no_signal(float(v))
	elif widget is UiToggle:
		(widget as UiToggle).set_on(bool(v))


func get_widget_value() -> Variant:
	if widget is UiChoice:
		return (widget as UiChoice).get_value()
	if widget is UiSlider:
		return (widget as UiSlider).get_value()
	if widget is UiToggle:
		return (widget as UiToggle).button_pressed
	return null


func set_unsupported(reason: String) -> void:
	unsupported = true
	unsupported_reason = reason
	tooltip_text = reason
	label.modulate.a = 0.45
	if widget is UiChoice:
		(widget as UiChoice).disabled = true
	elif widget is UiSlider:
		(widget as UiSlider).set_disabled(true)
	elif widget is UiToggle:
		(widget as UiToggle).disabled = true
		(widget as UiToggle).focus_mode = Control.FOCUS_NONE
	widget.tooltip_text = reason
	mouse_filter = Control.MOUSE_FILTER_STOP


static func unsupported_text(feature: String) -> String:
	match feature:
		"display_mode", "resolution", "vsync", "exclusive", "borderless":
			return "Not available on this platform."
		"rebinding":
			return "Use the on-screen controls on this device."
	var r := Settings.rendering_method()
	var nice := {"gl_compatibility": "Compatibility (OpenGL)", "mobile": "Mobile"}.get(r, r) as String
	return "Not supported by the %s renderer." % nice


func _on_focus(on: bool) -> void:
	_hot = on
	if on:
		row_focused.emit(self)
	var t := create_tween()
	t.tween_method(func(v: float) -> void:
		_hl = v
		queue_redraw(), _hl, 1.0 if on else 0.0, 0.14)
	label.add_theme_color_override(&"font_color", UiTheme.GOLD_HI if on else UiTheme.PARCHMENT)


func _draw() -> void:
	if _hl <= 0.001:
		return
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(UiTheme.GOLD, 0.07 * _hl))
	draw_rect(Rect2(0, 6, 4, size.y - 12), Color(UiTheme.GOLD, _hl))
