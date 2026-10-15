class_name HudCompass
extends Control
## Heading strip at the top centre: degree ticks, cardinal letters, markers for points of
## interest / quest targets / companion (with distance for the tracked one) and the current
## region name underneath. North is world -Z.
##
## Markers: Array of {"position": Vector3, "kind": &"quest"|&"poi"|&"companion"|&"discovered",
## "label": String (optional)}. The HUD fills them from WorldData POIs near the player and
## the quest provider; other modules may call `set_markers()`.

const SPAN_DEG := 200.0
const LABELS := {0: "N", 45: "NE", 90: "E", 135: "SE", 180: "S", 225: "SW", 270: "W", 315: "NW"}

var heading := 0.0          # degrees, 0 = north, 90 = east
var origin := Vector3.ZERO  # player position for marker bearings
var markers: Array[Dictionary] = []
var region_text := ""

var _region: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(780, 86)
	_region = UiTheme.make_label("", UiTheme.title_font(600, 6), UiTheme.SIZE_TINY - 1, Color(UiTheme.PARCHMENT, 0.75), HORIZONTAL_ALIGNMENT_CENTER)
	_region.position = Vector2(0, 64)  # below the quest-distance readout (y 48..62)
	_region.size = Vector2(780, 28)
	_region.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.7))
	_region.add_theme_constant_override(&"shadow_outline_size", 6)
	add_child(_region)


func set_heading_from_camera(cam: Camera3D) -> void:
	if cam == null:
		return
	var f := -cam.global_transform.basis.z
	heading = fposmod(rad_to_deg(atan2(f.x, -f.z)), 360.0)
	queue_redraw()


func set_markers(list: Array[Dictionary]) -> void:
	markers = list
	queue_redraw()


func set_region(text: String) -> void:
	if text == region_text:
		return
	region_text = text
	_region.text = text.to_upper()
	UiFx.fade_in(_region, 0.6)


## Screen x (local) of a world bearing, or NAN if outside the strip.
func x_for_bearing(bearing_deg: float) -> float:
	var rel := wrapf(bearing_deg - heading, -180.0, 180.0)
	if absf(rel) > SPAN_DEG * 0.5:
		return NAN
	return size.x * 0.5 + rel / SPAN_DEG * size.x


static func bearing(from: Vector3, to: Vector3) -> float:
	var d := to - from
	return fposmod(rad_to_deg(atan2(d.x, -d.z)), 360.0)


func _draw() -> void:
	var w := size.x
	var h := 44.0
	# lacquer band fading at both ends
	var ink := Color(UiTheme.INK, 0.72)
	var clear := Color(UiTheme.INK, 0.0)
	var e := w * 0.18
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(e, 0), Vector2(e, h), Vector2(0, h)]), PackedColorArray([clear, ink, ink, clear]))
	draw_rect(Rect2(e, 0, w - e * 2.0, h), ink)
	draw_polygon(PackedVector2Array([Vector2(w - e, 0), Vector2(w, 0), Vector2(w, h), Vector2(w - e, h)]), PackedColorArray([ink, clear, clear, ink]))
	draw_line(Vector2(e * 0.5, h), Vector2(w - e * 0.5, h), Color(UiTheme.GOLD, 0.35), 1.0)
	var font := UiTheme.title_font(700, 1)
	# ticks every 15 degrees
	var start := int(floor((heading - SPAN_DEG * 0.5) / 15.0)) * 15
	var deg := start
	while deg <= heading + SPAN_DEG * 0.5:
		var x := x_for_bearing(float(deg))
		if not is_nan(x):
			var fade := 1.0 - pow(absf(x - w * 0.5) / (w * 0.5), 2.0)
			var d := posmod(deg, 360)
			if LABELS.has(d):
				var t: String = LABELS[d]
				var cardinal := t.length() == 1
				var fs := 24 if cardinal else 17
				var col := (UiTheme.GOLD_HI if d == 0 else UiTheme.PARCHMENT) if cardinal else Color(UiTheme.PARCHMENT, 0.7)
				var ts := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
				draw_string(font, Vector2(x - ts.x * 0.5, h * 0.5 + fs * 0.36), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col, col.a * fade))
			else:
				draw_line(Vector2(x, h * 0.62), Vector2(x, h - 6), Color(UiTheme.PARCHMENT, 0.45 * fade), 1.5)
		deg += 15
	# markers
	var mi := UiTheme.icon("icon_marker")
	for m: Dictionary in markers:
		var pos: Vector3 = m.get("position", Vector3.ZERO)
		var x2 := x_for_bearing(bearing(origin, pos))
		if is_nan(x2):
			continue
		var kind: StringName = m.get("kind", &"poi")
		var col2 := UiTheme.GOLD_HI
		match kind:
			&"poi": col2 = Color(0.62, 0.86, 0.95)
			&"discovered": col2 = Color(UiTheme.PARCHMENT, 0.55)
			&"companion": col2 = UiTheme.element_light(GameState.element)
		var s := 22.0 if kind == &"quest" else 16.0
		if mi:
			draw_texture_rect(mi, Rect2(Vector2(x2 - s * 0.5, -s * 0.15), Vector2(s, s * 1.15)), false, col2)
		if kind == &"quest":
			var dist := origin.distance_to(pos)
			var dt := "%d m" % roundi(dist) if dist < 1000.0 else "%.1f km" % (dist / 1000.0)
			var ds := font.get_string_size(dt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15)
			draw_string(font, Vector2(x2 - ds.x * 0.5, h + 2 + 15), dt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(UiTheme.GOLD_HI, 0.9))
	# centre needle
	draw_colored_polygon(PackedVector2Array([Vector2(w * 0.5 - 7, -2), Vector2(w * 0.5 + 7, -2), Vector2(w * 0.5, 9)]), UiTheme.GOLD)
