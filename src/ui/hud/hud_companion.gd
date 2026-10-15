class_name HudCompanion
extends Control
## Companion status (bottom left): portrait seal with the companion's paw/emblem, name,
## health and a short state line ("Following", "Resting", "Called", "Mounted").

var companion_name := ""
var state_text := "Following"
var health_ratio := 1.0
var element := ElementDefs.Element.NONE

var _name: Label
var _state: Label
var _bar: HudBar


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(360, 84)
	_name = UiTheme.make_label("", UiTheme.title_font(700, 3), UiTheme.SIZE_SMALL, UiTheme.PARCHMENT)
	_name.position = Vector2(92, 8)
	_name.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.8))
	_name.add_theme_constant_override(&"shadow_outline_size", 6)
	add_child(_name)
	_bar = HudBar.new(Color(0.45, 0.55, 0.30), Color(0.72, 0.85, 0.45))
	_bar.position = Vector2(94, 40)
	_bar.size = Vector2(220, 9)
	add_child(_bar)
	_state = UiTheme.make_label("", UiTheme.body_font(1), UiTheme.SIZE_TINY - 1, UiTheme.PARCHMENT_MUTED)
	_state.position = Vector2(94, 52)
	_state.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.8))
	_state.add_theme_constant_override(&"shadow_outline_size", 5)
	add_child(_state)


func set_companion(p_name: String, p_element: int) -> void:
	companion_name = p_name
	element = p_element
	_name.text = p_name.to_upper()
	visible = not p_name.is_empty()
	queue_redraw()


func set_status(ratio: float, text: String) -> void:
	health_ratio = clampf(ratio, 0.0, 1.0)
	state_text = text
	_bar.set_ratio(health_ratio)
	_state.text = text


func _draw() -> void:
	var c := Vector2(42, 42)
	draw_circle(c, 38, Color(UiTheme.INK, 0.86), true, -1.0, true)
	draw_circle(c, 38, Color(UiTheme.GOLD, 0.7), false, 2.0, true)
	var paw := UiTheme.icon("icon_paw")
	if paw:
		draw_texture_rect(paw, Rect2(c - Vector2(22, 22), Vector2(44, 44)), false, UiTheme.element_light(element))
