class_name BackdropPainter
extends RefCounted
## Vector painting helpers for the element-select backdrops (resolution independent,
## drawn once into a Control's canvas): sky gradients, glows, noisy ridgelines, and the
## architecture vocabulary of the four nations (flared pagoda roofs, crenellated walls,
## cone-roofed towers, ice domes and spires, volcanoes, puffy cloud banks).

static var _glow_tex: Texture2D = null


## Radial white->transparent texture for glows (cached).
static func glow_texture() -> Texture2D:
	if _glow_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.add_point(0.35, Color(1, 1, 1, 0.45))
		g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 256
		t.height = 256
		_glow_tex = t
	return _glow_tex


## Vertical gradient through `stops` ([[t, Color], ...], t from top 0 to bottom 1).
static func sky(ci: CanvasItem, rect: Rect2, stops: Array) -> void:
	for i in stops.size() - 1:
		var a: Array = stops[i]
		var b: Array = stops[i + 1]
		var y0 := rect.position.y + rect.size.y * float(a[0])
		var y1 := rect.position.y + rect.size.y * float(b[0])
		var ca: Color = a[1]
		var cb: Color = b[1]
		ci.draw_polygon(PackedVector2Array([Vector2(rect.position.x, y0), Vector2(rect.end.x, y0), Vector2(rect.end.x, y1), Vector2(rect.position.x, y1)]),
				PackedColorArray([ca, ca, cb, cb]))


static func glow(ci: CanvasItem, center: Vector2, radius: float, color: Color) -> void:
	ci.draw_texture_rect(glow_texture(), Rect2(center - Vector2(radius, radius), Vector2(radius, radius) * 2.0), false, color)


## Ridge line from x0..x1 around y (noise amplitude `amp`), closed down to `bottom`.
static func ridge(ci: CanvasItem, x0: float, x1: float, y: float, amp: float, bottom: float, color: Color, seed_v: int,
		freq: float = 0.004, ridged: bool = true, step: float = 6.0, peaks: Array = [], octaves: int = 5) -> PackedVector2Array:
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.frequency = freq
	n.fractal_octaves = octaves
	n.fractal_type = FastNoiseLite.FRACTAL_RIDGED if ridged else FastNoiseLite.FRACTAL_FBM
	var top := PackedVector2Array()
	step = maxf(step, 1.0)
	var x := x0
	while x <= x1 + step:
		var h := (n.get_noise_1d(x) * 0.5 + 0.5) * amp
		for p: Array in peaks:
			var d := (x - float(p[0])) / float(p[2])
			h += float(p[1]) * exp(-d * d)
		top.append(Vector2(minf(x, x1), y - h))
		x += step
	var poly := top.duplicate()
	poly.append(Vector2(x1, bottom))
	poly.append(Vector2(x0, bottom))
	ci.draw_colored_polygon(poly, color)
	return top


## Soft highlight along a ridge top (rim light), e.g. sun-catching edges.
static func ridge_rim(ci: CanvasItem, top: PackedVector2Array, color: Color, width: float) -> void:
	if top.size() >= 2:
		ci.draw_polyline(top, color, width, true)


## Flared East-Asian roof: eaves curl up past the walls. Returns the roof polygon.
static func pagoda_roof(ci: CanvasItem, cx: float, base_y: float, w: float, h: float, color: Color, flare: float = 0.18, trim: Color = Color(0, 0, 0, 0)) -> void:
	var half := w * 0.5
	var tip := half * (1.0 + flare)
	var pts := PackedVector2Array()
	var steps := 14
	# left eave tip -> ridge (concave curve), ridge -> right tip
	for i in steps + 1:
		var t := float(i) / steps
		var x := lerpf(cx - tip, cx - half * 0.22, t)
		var y := base_y - h * (1.0 - pow(1.0 - t, 2.2)) - h * 0.12 * (1.0 - t) * 0.0
		pts.append(Vector2(x, y + flare * h * 0.6 * pow(1.0 - t, 3.0) * -1.0))
	for i in steps + 1:
		var t := float(i) / steps
		var x := lerpf(cx + half * 0.22, cx + tip, t)
		var y := base_y - h * (1.0 - pow(t, 2.2))
		pts.append(Vector2(x, y + flare * h * 0.6 * pow(t, 3.0) * -1.0))
	# underside of the eaves
	pts.append(Vector2(cx + half * 0.92, base_y + h * 0.08))
	pts.append(Vector2(cx - half * 0.92, base_y + h * 0.08))
	ci.draw_colored_polygon(pts, color)
	if trim.a > 0.0:
		ci.draw_line(Vector2(cx - half * 0.92, base_y + h * 0.08), Vector2(cx + half * 0.92, base_y + h * 0.08), trim, maxf(2.0, h * 0.06), true)
		ci.draw_line(Vector2(cx - half * 0.22, base_y - h), Vector2(cx + half * 0.22, base_y - h), trim, maxf(2.0, h * 0.06), true)


## Multi-tier pagoda hall: walls + stacked flared roofs.
static func pagoda(ci: CanvasItem, cx: float, base_y: float, w: float, tiers: int, tier_h: float, wall: Color, roof: Color, trim: Color = Color(0, 0, 0, 0), flare: float = 0.2) -> void:
	var y := base_y
	var ww := w
	for i in tiers:
		var wh := tier_h * (0.62 if i > 0 else 0.8)
		ci.draw_rect(Rect2(cx - ww * 0.36, y - wh, ww * 0.72, wh), wall)
		y -= wh
		pagoda_roof(ci, cx, y, ww, tier_h * 0.5, roof, flare, trim)
		y -= tier_h * 0.42
		ww *= 0.74


## Crenellated wall from x0..x1 with top at `top_y`.
static func wall(ci: CanvasItem, x0: float, x1: float, top_y: float, bottom_y: float, color: Color, merlon_w: float = 14.0, merlon_h: float = 10.0) -> void:
	ci.draw_rect(Rect2(x0, top_y, x1 - x0, bottom_y - top_y), color)
	if merlon_w < 1.0:
		return
	var x := x0
	while x < x1 - merlon_w * 0.5:
		ci.draw_rect(Rect2(x, top_y - merlon_h, merlon_w, merlon_h), color)
		x += merlon_w * 2.0


## Slender tower with a pointed (slightly concave) cone roof, Air Temple style.
static func spire_tower(ci: CanvasItem, cx: float, base_y: float, w: float, h: float, wall: Color, roof: Color, roof_h: float = -1.0) -> void:
	ci.draw_rect(Rect2(cx - w * 0.5, base_y - h, w, h), wall)
	var rh := roof_h if roof_h > 0.0 else w * 1.6
	var rw := w * 0.82
	var pts := PackedVector2Array()
	var steps := 10
	for i in steps + 1:
		var t := float(i) / steps
		pts.append(Vector2(cx - rw * (1.0 - t) * (1.0 - 0.25 * sin(PI * t)), base_y - h - rh * t))
	for i in range(steps, -1, -1):
		var t := float(i) / steps
		pts.append(Vector2(cx + rw * (1.0 - t) * (1.0 - 0.25 * sin(PI * t)), base_y - h - rh * t))
	ci.draw_colored_polygon(pts, roof)
	ci.draw_line(Vector2(cx, base_y - h - rh), Vector2(cx, base_y - h - rh - rh * 0.22), roof, maxf(1.5, w * 0.06), true)


## Rock pillar / mesa rising from below (optional shaded right side).
static func pillar(ci: CanvasItem, cx: float, top_y: float, bottom_y: float, w: float, color: Color, seed_v: int, shade: Color = Color(0, 0, 0, 0)) -> void:
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.frequency = 0.03
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var steps := 24
	for i in steps + 1:
		var t := float(i) / steps
		var y := lerpf(top_y, bottom_y, t)
		var widen := 1.0 + t * 0.35
		left.append(Vector2(cx - w * 0.5 * widen + n.get_noise_1d(y) * w * 0.12, y))
		right.append(Vector2(cx + w * 0.5 * widen + n.get_noise_1d(y + 500.0) * w * 0.12, y))
	var pts := left.duplicate()
	for i in range(steps, -1, -1):
		pts.append(right[i])
	ci.draw_colored_polygon(pts, color)
	if shade.a > 0.0:
		var sh := PackedVector2Array()
		for i in steps + 1:
			sh.append(right[i])
		for i in range(steps, -1, -1):
			sh.append(Vector2(lerpf(left[i].x, right[i].x, 0.6), right[i].y))
		ci.draw_colored_polygon(sh, shade)


## Puffy cloud bank: overlapping discs with a lit top and shaded base.
static func cloud_bank(ci: CanvasItem, x0: float, x1: float, y: float, height: float, lit: Color, shade: Color, seed_v: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	if height < 1.0:
		return
	var x := x0
	while x < x1:
		var r := rng.randf_range(height * 0.45, height * 1.0)
		var cy := y - rng.randf_range(0.0, height * 0.5)
		ci.draw_circle(Vector2(x, cy + r * 0.25), r, shade, true, -1.0, true)
		ci.draw_circle(Vector2(x - r * 0.12, cy), r * 0.9, lit, true, -1.0, true)
		x += r * rng.randf_range(0.7, 1.1)
	ci.draw_rect(Rect2(x0 - height, y, x1 - x0 + height * 2.0, height * 2.0), shade)


## Ice dome (Water Tribe).
static func dome(ci: CanvasItem, cx: float, base_y: float, r: float, color: Color, rim: Color = Color(0, 0, 0, 0)) -> void:
	var pts := PackedVector2Array()
	for i in 25:
		var a := PI + PI * float(i) / 24.0
		pts.append(Vector2(cx + cos(a) * r, base_y + sin(a) * r * 0.9))
	ci.draw_colored_polygon(pts, color)
	if rim.a > 0.0:
		ci.draw_polyline(pts, rim, 2.0, true)


## Ice shard / spire.
static func shard(ci: CanvasItem, x: float, base_y: float, w: float, h: float, lean: float, color: Color, light: Color = Color(0, 0, 0, 0)) -> void:
	var tip := Vector2(x + lean * h, base_y - h)
	ci.draw_colored_polygon(PackedVector2Array([Vector2(x - w * 0.5, base_y), tip, Vector2(x + w * 0.5, base_y)]), color)
	if light.a > 0.0:
		ci.draw_colored_polygon(PackedVector2Array([Vector2(x - w * 0.5, base_y), tip, Vector2(x - w * 0.05, base_y)]), light)


## Volcano with a glowing crater.
static func volcano(ci: CanvasItem, cx: float, base_y: float, w: float, h: float, color: Color, glow_color: Color) -> void:
	var crater := w * 0.09
	var pts := PackedVector2Array()
	var steps := 16
	for i in steps + 1:
		var t := float(i) / steps
		pts.append(Vector2(lerpf(cx - w * 0.5, cx - crater, t), base_y - h * pow(t, 1.8)))
	pts.append(Vector2(cx - crater * 0.4, base_y - h * 0.97))
	pts.append(Vector2(cx + crater * 0.4, base_y - h * 0.97))
	for i in steps + 1:
		var t := 1.0 - float(i) / steps
		pts.append(Vector2(lerpf(cx + w * 0.5, cx + crater, t), base_y - h * pow(t, 1.8)))
	ci.draw_colored_polygon(pts, color)
	glow(ci, Vector2(cx, base_y - h), w * 0.22, glow_color)
	# lava runnels
	for k in 3:
		var x0 := cx + (k - 1) * crater * 0.6
		var lava := PackedVector2Array()
		for i in 9:
			var t := float(i) / 8.0
			lava.append(Vector2(x0 + (k - 1) * w * 0.12 * t + sin(t * 9.0 + k) * 6.0, base_y - h + h * 0.55 * t))
		ci.draw_polyline(lava, Color(glow_color, glow_color.a * 0.8), 3.0, true)
