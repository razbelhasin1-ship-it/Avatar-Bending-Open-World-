class_name UiFrameStyle
extends StyleBox
## Lacquer-and-gold StyleBox used across the UI: translucent ink fill with optional
## paper grain, a fine gold border, ruyi cloud corner ornaments, L-shaped focus brackets,
## an underline (tabs) or a left accent bar (toasts). Drawn with RenderingServer calls
## so a single style covers what would otherwise need nested nodes.

var fill := Color(0, 0, 0, 0)
var border := Color(0, 0, 0, 0)
var border_width := 0.0
## Opacity of the tiled paper/lacquer grain over the fill (0 = none).
var grain := 0.0
## Soft highlight at the top edge (0..1), reads as lacquer sheen.
var sheen := 0.12
## Ruyi cloud ornaments in the four corners.
var corner_ornaments := false
var ornament_size := 44.0
## L-shaped brackets around the rect (the focus look).
var brackets := false
var bracket_color := Color(1, 1, 1, 1)
var bracket_length := 18.0
var bracket_width := 2.5
## Brackets sit this far outside the rect (negative = inside).
var bracket_offset := 6.0
var underline := 0.0
var underline_color := Color(0, 0, 0, 0)
var accent_left := 0.0
var accent_color := Color(0, 0, 0, 0)

static var _corner_tex: Texture2D = null


## Standard panel/button frame.
static func make(p_fill: Color, p_border: Color, p_width: float) -> UiFrameStyle:
	var s := UiFrameStyle.new()
	s.fill = p_fill
	s.border = p_border
	s.border_width = p_width
	s.content_margin_left = 22
	s.content_margin_right = 22
	s.content_margin_top = 12
	s.content_margin_bottom = 12
	return s


## Focus indicator: corner brackets only (drawn over the normal/hover style).
static func make_focus(color: Color, offset: float = 6.0) -> UiFrameStyle:
	var s := UiFrameStyle.new()
	s.brackets = true
	s.bracket_color = color
	s.bracket_offset = offset
	s.sheen = 0.0
	return s


func _draw(ci: RID, rect: Rect2) -> void:
	if fill.a > 0.0:
		RenderingServer.canvas_item_add_rect(ci, rect, fill)
		if sheen > 0.0 and rect.size.y > 8.0:
			var h := minf(rect.size.y * 0.45, 60.0)
			var top := Color(1.0, 0.92, 0.75, sheen * 0.35)
			var clear := Color(1.0, 0.92, 0.75, 0.0)
			RenderingServer.canvas_item_add_polygon(ci,
					PackedVector2Array([rect.position, rect.position + Vector2(rect.size.x, 0), rect.position + Vector2(rect.size.x, h), rect.position + Vector2(0, h)]),
					PackedColorArray([top, top, clear, clear]))
	if grain > 0.0 and fill.a > 0.0:
		var g := UiTheme.grain_texture()
		RenderingServer.canvas_item_add_texture_rect(ci, rect, g.get_rid(), true, Color(1, 1, 1, grain * 0.14))
	if accent_left > 0.0:
		RenderingServer.canvas_item_add_rect(ci, Rect2(rect.position, Vector2(accent_left, rect.size.y)), accent_color)
	if border_width > 0.0 and border.a > 0.0:
		var p := rect.grow(-border_width * 0.5)
		var pts := PackedVector2Array([p.position, Vector2(p.end.x, p.position.y), p.end, Vector2(p.position.x, p.end.y), p.position])
		RenderingServer.canvas_item_add_polyline(ci, pts, PackedColorArray([border]), border_width, true)
	if underline > 0.0 and underline_color.a > 0.0:
		var inset := rect.size.x * 0.18
		RenderingServer.canvas_item_add_rect(ci, Rect2(rect.position.x + inset, rect.end.y - underline, rect.size.x - inset * 2.0, underline), underline_color)
	if corner_ornaments:
		_draw_ornaments(ci, rect)
	if brackets:
		_draw_brackets(ci, rect.grow(bracket_offset))


func _draw_ornaments(ci: RID, rect: Rect2) -> void:
	if _corner_tex == null:
		_corner_tex = UiTheme.icon("ui_corner")
	if _corner_tex == null:
		return
	var s := minf(ornament_size, minf(rect.size.x, rect.size.y) * 0.35)
	var col := Color(border.r, border.g, border.b, minf(1.0, border.a * 1.6))
	var r := Rect2(Vector2(-3, -3), Vector2(s, s))
	var corners := [
		Transform2D(0.0, Vector2(1, 1), 0.0, rect.position),
		Transform2D(0.0, Vector2(-1, 1), 0.0, Vector2(rect.end.x, rect.position.y)),
		Transform2D(0.0, Vector2(1, -1), 0.0, Vector2(rect.position.x, rect.end.y)),
		Transform2D(0.0, Vector2(-1, -1), 0.0, rect.end),
	]
	for xf: Transform2D in corners:
		RenderingServer.canvas_item_add_set_transform(ci, xf)
		RenderingServer.canvas_item_add_texture_rect(ci, r, _corner_tex.get_rid(), false, col)
	RenderingServer.canvas_item_add_set_transform(ci, Transform2D.IDENTITY)


func _draw_brackets(ci: RID, r: Rect2) -> void:
	var L := minf(bracket_length, minf(r.size.x, r.size.y) * 0.4)
	var w := bracket_width
	var c := bracket_color
	for corner: Vector2 in [r.position, Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), r.end]:
		var sx := 1.0 if corner.x <= r.position.x + 0.1 else -1.0
		var sy := 1.0 if corner.y <= r.position.y + 0.1 else -1.0
		RenderingServer.canvas_item_add_rect(ci, Rect2(corner + Vector2(0 if sx > 0 else -L, 0 if sy > 0 else -w), Vector2(L, w)), c)
		RenderingServer.canvas_item_add_rect(ci, Rect2(corner + Vector2(0 if sx > 0 else -w, 0 if sy > 0 else -L), Vector2(w, L)), c)
