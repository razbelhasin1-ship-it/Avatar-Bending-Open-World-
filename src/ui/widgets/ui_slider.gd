class_name UiSlider
extends HBoxContainer
## Themed slider with a live value readout. Left/Right (keys, d-pad) step it when focused,
## mouse drags it. `format` turns the value into text (default: percent of the range).

signal value_changed(value: float)

var slider: HSlider
var readout: Label
var format: Callable


func _init(min_v: float = 0.0, max_v: float = 1.0, step_v: float = 0.05) -> void:
	add_theme_constant_override(&"separation", 18)
	custom_minimum_size = Vector2(380, 64)
	slider = HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step_v
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size = Vector2(240, 40)
	slider.focus_mode = Control.FOCUS_ALL
	add_child(slider)
	readout = UiTheme.make_label("", UiTheme.title_font(600, 1), UiTheme.SIZE_SMALL, UiTheme.PARCHMENT, HORIZONTAL_ALIGNMENT_RIGHT)
	readout.custom_minimum_size = Vector2(92, 0)
	readout.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(readout)


func _ready() -> void:
	UiFx.wire(slider)
	slider.value_changed.connect(_on_changed)
	slider.focus_entered.connect(_refresh_color)
	slider.focus_exited.connect(_refresh_color)
	_update_readout()


func set_value_no_signal(v: float) -> void:
	slider.set_value_no_signal(v)
	_update_readout()


func get_value() -> float:
	return slider.value


func set_disabled(on: bool) -> void:
	slider.editable = not on
	slider.focus_mode = Control.FOCUS_NONE if on else Control.FOCUS_ALL
	modulate.a = 0.4 if on else 1.0


func _on_changed(v: float) -> void:
	_update_readout()
	value_changed.emit(v)


func _update_readout() -> void:
	if format.is_valid():
		readout.text = String(format.call(slider.value))
	else:
		var span := slider.max_value - slider.min_value
		readout.text = "%d%%" % roundi((slider.value - slider.min_value) / maxf(span, 0.0001) * 100.0)


func _refresh_color() -> void:
	readout.add_theme_color_override(&"font_color", UiTheme.GOLD_HI if slider.has_focus() else UiTheme.PARCHMENT)
