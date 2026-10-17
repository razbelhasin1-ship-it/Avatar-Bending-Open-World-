class_name SkillTreeCanvas
extends Control
## The drawn part of the skill tree. Reads left to right like a scroll: the CORE KIT column
## (the element's foundations, always known), then one column per tier (I, II, III ... with
## the level it opens at) and one band per branch row (Ice / Flow / Healing ...). Behind the
## SkillNode medallions it paints the element's brush glyph as a watermark, the tier headers,
## branch labels and tapered ink connectors from every prerequisite to the technique it opens
## (lit in the element colour once both ends are learned, gold when the next one is ready).

const CORE_W := 168.0
const HEADER_H := 46.0

var element := ElementDefs.Element.NONE
var nodes: Dictionary = {}            # id -> SkillNode
var foundation_nodes: Array[SkillNode] = []
var layout: Array[Dictionary] = []    # SkillTreeModel.nodes(element)
var tiers := 1
var rows := 1

var _glyph := ""


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func setup(p_element: int) -> void:
	element = p_element
	_glyph = String(ElementDefs.get_data(element).get("glyph", ""))
	for c in get_children():
		remove_child(c)
		c.queue_free()
	nodes.clear()
	foundation_nodes.clear()
	layout = SkillTreeModel.nodes(element)
	tiers = SkillTreeModel.tier_count(element)
	rows = maxi(3, SkillTreeModel.column_count(element))
	for d in SkillTreeModel.foundations(element):
		var f := SkillNode.new(d, true)
		f.name = "F_%s" % String(d.id)
		add_child(f)
		foundation_nodes.append(f)
	for n in layout:
		var sn := SkillNode.new(n["def"])
		sn.name = "N_%s" % String(n["id"])
		add_child(sn)
		nodes[n["id"]] = sn
	if not resized.is_connected(_relayout):
		resized.connect(_relayout)
	_relayout()


## Area of the tier columns (right of the core kit, under the tier headers).
func tree_rect() -> Rect2:
	return Rect2(Vector2(CORE_W + 18.0, HEADER_H), Vector2(maxf(size.x - CORE_W - 24.0, 100.0), maxf(size.y - HEADER_H - 4.0, 100.0)))


func tier_x(tier: int) -> float:
	var r := tree_rect()
	return r.position.x + r.size.x * (float(tier) - 0.5) / float(maxi(tiers, 1))


func row_y(row: int) -> float:
	var r := tree_rect()
	return r.position.y + r.size.y * (float(row) + 0.5) / float(rows)


func _relayout() -> void:
	if size.x < 10.0:
		return
	var n := foundation_nodes.size()
	if n > 0:
		var top := HEADER_H
		var span := size.y - top - 4.0
		for i in n:
			var f := foundation_nodes[i]
			f.size = f.custom_minimum_size
			var c := Vector2(CORE_W * 0.5, top + span * (float(i) + 0.5) / float(n))
			f.position = c - f.medallion_center() + Vector2(0, -8.0)
	for e in layout:
		var sn: SkillNode = nodes[e["id"]]
		sn.size = sn.custom_minimum_size
		var c := Vector2(tier_x(int(e["tier"])), row_y(int(e["column"])))
		sn.position = c - sn.medallion_center() + Vector2(0, -10.0)
	queue_redraw()


func _draw() -> void:
	var light := UiTheme.element_light(element)
	var r := tree_rect()
	# watermark glyph
	if _glyph != "":
		var bf := UiTheme.brush_font()
		var gs := int(minf(size.y * 1.05, 720.0))
		var gsz := bf.get_string_size(_glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, gs)
		draw_string(bf, Vector2(r.get_center().x - gsz.x * 0.5, size.y * 0.5 + gs * 0.36), _glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, gs,
			Color(light, 0.05))
	# core kit column
	var shelf := Rect2(Vector2(4.0, 6.0), Vector2(CORE_W - 8.0, size.y - 10.0))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(UiTheme.INK_2, 0.6)
	sb.border_color = Color(UiTheme.GOLD, 0.2)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	draw_style_box(sb, shelf)
	_header("CORE KIT", "ALWAYS KNOWN", CORE_W * 0.5, true)
	# branch bands
	var bf2 := UiTheme.title_font(600, 4)
	for row in rows:
		var y0 := r.position.y + r.size.y * float(row) / float(rows)
		if row > 0:
			draw_dashed_line(Vector2(r.position.x, y0), Vector2(r.end.x, y0), Color(UiTheme.GOLD, 0.1), 1.0, 8.0)
		var br := SkillTreeModel.column_branch(element, row)
		if br != &"":
			var t := SkillTreeModel.branch_name(br).to_upper()
			draw_string(bf2, Vector2(r.position.x + 4.0, y0 + 20.0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(UiTheme.GOLD, 0.55))
	# tier headers
	for tier in range(1, tiers + 1):
		var lvl := SkillTreeModel.tier_level(element, tier)
		_header(_roman(tier), "LEVEL %d" % lvl, tier_x(tier), GameState.level >= lvl)
	# connectors (behind the medallions: children draw after the parent)
	for e in layout:
		var pre: StringName = e["requires"]
		if pre == &"" or not nodes.has(pre):
			continue
		var a: SkillNode = nodes[pre]
		var b: SkillNode = nodes[e["id"]]
		var ca := a.position + a.medallion_center()
		var cb := b.position + b.medallion_center()
		var pa := ca + Vector2(a.medallion_size() * 0.5 + 4.0, 0)
		var pb := cb - Vector2(b.medallion_size() * 0.5 + 8.0, 0)
		var both := a.state == &"learned" and b.state == &"learned"
		var ready := a.state == &"learned" and b.state == &"available"
		var col := Color(UiTheme.PARCHMENT, 0.2)
		var width := 5.0
		if both:
			col = Color(light, 0.9)
			width = 8.0
		elif ready:
			col = Color(UiTheme.GOLD_HI, 0.85)
			width = 7.0
		if both or ready:
			_brush_curve(pa, pb, Color(col, 0.16), width * 2.6)
		_brush_curve(pa, pb, col, width)


func _header(big: String, small: String, x: float, lit: bool) -> void:
	var f := UiTheme.title_font(700, 3)
	var fs := 26 if big.length() <= 4 else 19
	var bw := f.get_string_size(big, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(f, Vector2(x - bw * 0.5, 22.0), big, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		Color(UiTheme.GOLD_HI, 0.92) if lit else Color(UiTheme.PARCHMENT, 0.35))
	var sf := UiTheme.title_font(600, 2)
	var sw := sf.get_string_size(small, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	draw_string(sf, Vector2(x - sw * 0.5, 40.0), small, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
		Color(UiTheme.PARCHMENT, 0.62) if lit else Color(UiTheme.PARCHMENT, 0.3))


## A tapered ink stroke along a horizontal S-curve (thick in the middle, thin at the ends).
func _brush_curve(a: Vector2, b: Vector2, col: Color, width: float) -> void:
	var dx := (b.x - a.x) * 0.5
	var c1 := a + Vector2(dx, 0)
	var c2 := b - Vector2(dx, 0)
	var steps := 28
	var prev := a
	for i in range(1, steps + 1):
		var t := float(i) / steps
		var p := a.bezier_interpolate(c1, c2, b, t)
		var w := width * (0.4 + 0.6 * sin(PI * t))
		draw_line(prev, p, Color(0, 0, 0, col.a * 0.35), w + 3.0, true)
		draw_line(prev, p, col, w, true)
		prev = p
	# arrow tip: a small diamond where the ink meets the next medallion
	var tip := PackedVector2Array([b + Vector2(6, 0), b + Vector2(0, -5), b + Vector2(-6, 0), b + Vector2(0, 5)])
	draw_colored_polygon(tip, col)


static func _roman(n: int) -> String:
	return ["", "I", "II", "III", "IV", "V", "VI", "VII"][clampi(n, 0, 7)]
