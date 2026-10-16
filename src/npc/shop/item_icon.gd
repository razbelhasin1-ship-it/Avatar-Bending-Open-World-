class_name ItemIcon
extends Control
## Vector item glyph (no texture assets needed): a lacquered disc with a category shape tinted
## by the item colour — leaf (herb), bowl (food), cup (drink), coil (supply), gem (trinket),
## ore chunk (material), crate (goods), scroll (quest), square-holed coin (currency).
## Usable by any UI (shop, inventory, quest rewards): `ItemIcon.make(&"arctic_moss", 56)`.

var item: StringName = &"":
	set(v):
		item = v
		queue_redraw()
## Draw the currency coin instead of an item.
var coin := false


static func make(id: StringName, px: float = 56.0) -> ItemIcon:
	var i := ItemIcon.new()
	i.item = id
	i.custom_minimum_size = Vector2(px, px)
	i.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return i


static func make_coin(px: float = 28.0) -> ItemIcon:
	var i := ItemIcon.new()
	i.coin = true
	i.custom_minimum_size = Vector2(px, px)
	i.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return i


func _draw() -> void:
	var s := minf(size.x, size.y)
	var c := size * 0.5
	if coin:
		draw_coin(self, c, s * 0.46)
		return
	var col := TradeGoods.color(item) if item != &"" else UiTheme.GOLD
	draw_circle(c, s * 0.48, Color(UiTheme.INK_3, 0.95))
	draw_arc(c, s * 0.47, 0.0, TAU, 40, Color(UiTheme.GOLD, 0.55), maxf(1.0, s * 0.03), true)
	var r := s * 0.3
	var dark := col.darkened(0.45)
	match TradeGoods.category(item) if item != &"" else &"goods":
		&"herb":
			var leaf := PackedVector2Array()
			for i in 17:
				var t := float(i) / 16.0
				var a := lerpf(-PI * 0.5, PI * 1.5, t)
				var w := sin(t * PI)
				leaf.append(c + Vector2(cos(a) * r * 0.55 * w, sin(a) * r).rotated(0.6))
			draw_colored_polygon(leaf, col)
			draw_line(c + Vector2(0, r).rotated(0.6), c + Vector2(0, -r * 0.8).rotated(0.6), dark, maxf(1.0, s * 0.03), true)
		&"food":
			var bowl := PackedVector2Array()
			for i in 13:
				var a := PI * float(i) / 12.0
				bowl.append(c + Vector2(cos(a) * r * 1.05, sin(a) * r * 0.8 - r * 0.05))
			draw_colored_polygon(bowl, col)
			draw_rect(Rect2(c + Vector2(-r * 1.1, -r * 0.14), Vector2(r * 2.2, r * 0.18)), dark)
			for k in 3:
				draw_arc(c + Vector2((k - 1) * r * 0.45, -r * 0.5), r * 0.16, PI, TAU, 8, Color(1, 1, 1, 0.45), maxf(1.0, s * 0.02), true)
		&"drink":
			draw_rect(Rect2(c + Vector2(-r * 0.6, -r * 0.6), Vector2(r * 1.2, r * 1.3)), col)
			draw_arc(c + Vector2(r * 0.7, 0.0), r * 0.32, -PI * 0.5, PI * 0.5, 10, col, maxf(1.0, s * 0.05), true)
			draw_rect(Rect2(c + Vector2(-r * 0.6, -r * 0.6), Vector2(r * 1.2, r * 0.2)), dark)
		&"supply":
			for k in 3:
				draw_arc(c, r * (0.45 + k * 0.25), 0.0, TAU, 24, col if k % 2 == 0 else dark, maxf(1.0, s * 0.06), true)
		&"trinket":
			var gem := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.8, -r * 0.2), c + Vector2(0, r), c + Vector2(-r * 0.8, -r * 0.2)])
			draw_colored_polygon(gem, col)
			draw_line(c + Vector2(-r * 0.8, -r * 0.2), c + Vector2(r * 0.8, -r * 0.2), dark, maxf(1.0, s * 0.025), true)
			draw_line(c + Vector2(0, -r), c + Vector2(0, r), Color(1, 1, 1, 0.35), maxf(1.0, s * 0.02), true)
		&"material":
			var chunk := PackedVector2Array([c + Vector2(-r, r * 0.4), c + Vector2(-r * 0.6, -r * 0.6), c + Vector2(r * 0.2, -r * 0.9),
				c + Vector2(r * 0.9, -r * 0.2), c + Vector2(r * 0.7, r * 0.7), c + Vector2(-r * 0.2, r * 0.8)])
			draw_colored_polygon(chunk, col)
			draw_polyline(chunk + PackedVector2Array([chunk[0]]), dark, maxf(1.0, s * 0.025), true)
		&"quest":
			draw_rect(Rect2(c + Vector2(-r * 0.75, -r * 0.6), Vector2(r * 1.5, r * 1.2)), Color(0.94, 0.88, 0.72))
			draw_rect(Rect2(c + Vector2(-r * 0.9, -r * 0.75), Vector2(r * 0.25, r * 1.5)), col)
			draw_rect(Rect2(c + Vector2(r * 0.65, -r * 0.75), Vector2(r * 0.25, r * 1.5)), col)
			for k in 3:
				draw_line(c + Vector2(-r * 0.45, -r * 0.3 + k * r * 0.3), c + Vector2(r * 0.45, -r * 0.3 + k * r * 0.3), Color(0.3, 0.24, 0.2, 0.7), maxf(1.0, s * 0.02))
		_:
			draw_rect(Rect2(c + Vector2(-r * 0.8, -r * 0.7), Vector2(r * 1.6, r * 1.4)), col)
			draw_rect(Rect2(c + Vector2(-r * 0.8, -r * 0.7), Vector2(r * 1.6, r * 1.4)), dark, false, maxf(1.0, s * 0.04))
			draw_line(c + Vector2(-r * 0.8, -r * 0.1), c + Vector2(r * 0.8, -r * 0.1), dark, maxf(1.0, s * 0.03))


## A square-holed bronze coin.
static func draw_coin(ci: CanvasItem, c: Vector2, r: float) -> void:
	ci.draw_circle(c, r, Color(0.86, 0.66, 0.30))
	ci.draw_arc(c, r * 0.86, 0.0, TAU, 28, Color(0.62, 0.44, 0.16), maxf(1.0, r * 0.1), true)
	var h := r * 0.32
	ci.draw_rect(Rect2(c - Vector2(h, h), Vector2(h * 2.0, h * 2.0)), UiTheme.INK)
	ci.draw_arc(c + Vector2(-r * 0.2, -r * 0.25), r * 0.55, PI * 1.05, PI * 1.45, 6, Color(1, 0.95, 0.75, 0.6), maxf(1.0, r * 0.08), true)
