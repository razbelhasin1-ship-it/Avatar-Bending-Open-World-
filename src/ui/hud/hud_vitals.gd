class_name HudVitals
extends Control
## Top-left cluster: element medallion with level, health bar (red ink), chi bar (element
## secondary tone) and the focus gauge that fills toward the signature technique.

var health_bar: HudBar
var chi_bar: HudBar
var element := ElementDefs.Element.NONE
var focus := 0.0
var focus_max := 100.0
var level := 1

var _health_text: Label
var _focus_ready := false
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(560, 130)
	size = custom_minimum_size
	health_bar = HudBar.new(Color(0.62, 0.10, 0.08), Color(0.92, 0.30, 0.20))
	health_bar.position = Vector2(118, 30)
	health_bar.size = Vector2(400, 24)
	add_child(health_bar)
	chi_bar = HudBar.new(Color(0.12, 0.42, 0.62), Color(0.42, 0.78, 0.92))
	chi_bar.position = Vector2(118, 62)
	chi_bar.size = Vector2(320, 13)
	add_child(chi_bar)
	_health_text = UiTheme.make_label("", UiTheme.title_font(700, 1), UiTheme.SIZE_TINY - 1, UiTheme.PARCHMENT)
	_health_text.position = Vector2(124, 2)
	_health_text.add_theme_color_override(&"font_outline_color", Color(0.04, 0.03, 0.02, 0.85))
	_health_text.add_theme_constant_override(&"outline_size", 5)
	add_child(_health_text)


func set_element(e: int) -> void:
	element = e
	var sec := UiTheme.element_secondary(e)
	chi_bar.set_colors(sec.darkened(0.45), sec.lightened(0.1))
	queue_redraw()


func set_health(value: float, max_value: float, instant: bool = false) -> void:
	health_bar.set_ratio(value / maxf(max_value, 0.001), instant)
	_health_text.text = "%d / %d" % [ceili(value), roundi(max_value)]
	health_bar.set_pulse(1.0 if value / maxf(max_value, 0.001) < 0.25 else 0.0)


func set_chi(value: float, max_value: float, instant: bool = false) -> void:
	chi_bar.set_ratio(value / maxf(max_value, 0.001), instant)


func set_focus(value: float, max_value: float) -> void:
	focus = value
	focus_max = maxf(max_value, 1.0)
	_focus_ready = focus >= focus_max - 0.01
	queue_redraw()


func set_level(l: int) -> void:
	level = l
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	if _focus_ready:
		queue_redraw()


func _draw() -> void:
	var c := Vector2(54, 54)
	var light := UiTheme.element_light(element)
	# medallion
	draw_circle(c, 50, Color(UiTheme.INK, 0.88), true, -1.0, true)
	draw_circle(c, 50, Color(UiTheme.GOLD, 0.8), false, 2.0, true)
	draw_circle(c, 44, Color(light, 0.35), false, 1.0, true)
	var em := UiTheme.emblem(element)
	if em:
		draw_texture_rect(em, Rect2(c - Vector2(30, 30), Vector2(60, 60)), false, light)
	# focus ring around the medallion (signature gauge)
	var k := clampf(focus / focus_max, 0.0, 1.0)
	if k > 0.0:
		var glow := 0.6 + 0.4 * sin(_t * 6.0) if _focus_ready else 0.0
		draw_arc(c, 55, -PI * 0.5, -PI * 0.5 + TAU * k, 64, UiTheme.GOLD_HI.lerp(Color.WHITE, glow * 0.5), 4.0, true)
		if _focus_ready:
			draw_arc(c, 59, 0, TAU, 64, Color(UiTheme.GOLD_HI, 0.35 * glow), 3.0, true)
	# level seal
	var lc := c + Vector2(38, 38)
	draw_circle(lc, 15, UiTheme.SEAL, true, -1.0, true)
	draw_circle(lc, 15, Color(UiTheme.GOLD, 0.8), false, 1.5, true)
	var f := UiTheme.title_font(700)
	var t := str(level)
	var ts := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 17)
	draw_string(f, lc + Vector2(-ts.x * 0.5, 6), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, UiTheme.PARCHMENT)
	# small resource icons
	var hi := UiTheme.icon("icon_health")
	if hi:
		draw_texture_rect(hi, Rect2(Vector2(523, 31), Vector2(22, 22)), false, Color(0.95, 0.45, 0.35))
	var ci := UiTheme.icon("icon_chi")
	if ci:
		draw_texture_rect(ci, Rect2(Vector2(444, 59), Vector2(19, 19)), false, Color(0.55, 0.85, 0.95))
