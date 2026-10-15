class_name ElementBackdrop
extends Control
## Full-screen painted landscape for one element on the selection screen, drawn in
## vectors (resolution independent) plus a few animated layers:
##   Earth — Ba Sing Se's great wall before jagged peaks at golden hour, drifting leaves.
##   Air   — temple towers on stone pillars above a sea of clouds, wind wisps.
##   Fire  — the palace's flared roofs and a glowing volcano under a crimson dusk, embers.
##   Water — ice walls and domes under a moon and aurora, falling snow.

const AURORA_SHADER := preload("res://src/ui/shaders/aurora.gdshader")
const NOISE := preload("res://assets/textures/world/clouds.png")
const P := preload("res://src/ui/select/backdrop_painter.gd")

var element := ElementDefs.Element.NONE
var particles: CPUParticles2D
var _cloud_layer: Control
var _rng := RandomNumberGenerator.new()


func setup(p_element: int) -> void:
	element = p_element
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_on_resized)
	match element:
		ElementDefs.Element.WATER: _add_aurora()
		ElementDefs.Element.AIR: _add_cloud_layer()
	_add_particles()


func _on_resized() -> void:
	queue_redraw()
	if particles:
		_place_particles()
	if _cloud_layer:
		_cloud_layer.queue_redraw()


func _process(delta: float) -> void:
	if _cloud_layer and is_visible_in_tree():
		_cloud_layer.position.x = fposmod(_cloud_layer.position.x + delta * 14.0, size.x) - size.x


func _draw() -> void:
	if size.x < 64.0 or size.y < 64.0:
		return
	var r := Rect2(Vector2.ZERO, size)
	match element:
		ElementDefs.Element.EARTH: _paint_earth(r)
		ElementDefs.Element.AIR: _paint_air(r)
		ElementDefs.Element.FIRE: _paint_fire(r)
		ElementDefs.Element.WATER: _paint_water(r)


# --- Earth ---------------------------------------------------------------------------------

func _paint_earth(r: Rect2) -> void:
	var W := r.size.x
	var H := r.size.y
	P.sky(self, r, [[0.0, Color(0.16, 0.30, 0.42)], [0.2, Color(0.42, 0.56, 0.58)], [0.38, Color(0.98, 0.82, 0.52)], [1.0, Color(0.88, 0.70, 0.44)]])
	P.glow(self, Vector2(W * 0.13, H * 0.33), H * 0.45, Color(1.0, 0.84, 0.50, 0.8))
	P.glow(self, Vector2(W * 0.13, H * 0.33), H * 0.06, Color(1.0, 0.97, 0.85, 1.0))
	var far := P.ridge(self, -20, W + 20, H * 0.36, H * 0.09, H, Color(0.56, 0.62, 0.64), 11, 0.004, false, 5.0,
			[[W * 0.05, H * 0.15, W * 0.035], [W * 0.27, H * 0.06, W * 0.03], [W * 0.70, H * 0.08, W * 0.035], [W * 0.90, H * 0.16, W * 0.04]], 5)
	P.ridge_rim(self, far, Color(1.0, 0.88, 0.62, 0.4), 2.0)
	P.ridge(self, -20, W + 20, H * 0.40, H * 0.06, H, Color(0.44, 0.52, 0.46), 12, 0.003, false, 6.0, [], 3)
	# Ba Sing Se outer wall with gate towers
	var top := H * 0.355
	var bottom := H * 0.47
	P.wall(self, -10, W + 10, top, bottom, Color(0.55, 0.50, 0.40), H * 0.012, H * 0.012)
	draw_rect(Rect2(-10, top + (bottom - top) * 0.55, W + 20, (bottom - top) * 0.45), Color(0.45, 0.41, 0.33))
	draw_line(Vector2(-10, top + 2), Vector2(W + 10, top + 2), Color(1.0, 0.88, 0.6, 0.45), 2.0)
	var x := W * 0.06
	while x < W:
		var tw := H * 0.06
		draw_rect(Rect2(x - tw * 0.5, top - H * 0.05, tw, H * 0.05 + 4), Color(0.52, 0.47, 0.37))
		P.pagoda_roof(self, x, top - H * 0.05, tw * 1.5, H * 0.032, Color(0.22, 0.38, 0.26), 0.25, Color(0.86, 0.70, 0.36, 0.9))
		x += W * 0.155
	P.ridge(self, -20, W + 20, H * 0.50, H * 0.03, H, Color(0.38, 0.44, 0.28), 13, 0.01, false)
	# foreground rocks (visible under the cards)
	P.ridge(self, -20, W + 20, H * 0.94, H * 0.07, H + 10, Color(0.14, 0.16, 0.12), 14, 0.008, true)


# --- Air -----------------------------------------------------------------------------------

func _paint_air(r: Rect2) -> void:
	var W := r.size.x
	var H := r.size.y
	P.sky(self, r, [[0.0, Color(0.18, 0.42, 0.78)], [0.3, Color(0.55, 0.74, 0.92)], [0.5, Color(0.93, 0.90, 0.84)], [1.0, Color(0.88, 0.86, 0.82)]])
	P.glow(self, Vector2(W * 0.84, H * 0.1), H * 0.4, Color(1.0, 0.95, 0.80, 0.55))
	P.ridge(self, -20, W + 20, H * 0.43, H * 0.1, H, Color(0.72, 0.79, 0.88), 21, 0.004, true)
	P.cloud_bank(self, -60, W + 60, H * 0.45, H * 0.07, Color(1.0, 0.98, 0.95), Color(0.78, 0.84, 0.93), 22)
	var stone := Color(0.62, 0.55, 0.50)
	var stone_shade := Color(0.46, 0.40, 0.38, 0.85)
	P.pillar(self, W * 0.07, H * 0.24, H * 0.62, W * 0.075, stone, 23, stone_shade)
	P.pillar(self, W * 0.17, H * 0.36, H * 0.62, W * 0.05, stone.darkened(0.08), 24, stone_shade)
	P.pillar(self, W * 0.885, H * 0.21, H * 0.62, W * 0.15, stone, 25, stone_shade)
	P.pillar(self, W * 0.76, H * 0.34, H * 0.62, W * 0.05, stone.darkened(0.06), 26, stone_shade)
	# Southern Air Temple on the great pillar
	var wall := Color(0.93, 0.89, 0.80)
	var roof := Color(0.24, 0.40, 0.66)
	var base := H * 0.215
	draw_rect(Rect2(W * 0.825, base - H * 0.02, W * 0.12, H * 0.025), wall.darkened(0.08))
	for t: Array in [[0.84, 0.06, 0.012], [0.885, 0.115, 0.016], [0.925, 0.075, 0.012], [0.862, 0.035, 0.009], [0.905, 0.045, 0.01]]:
		P.spire_tower(self, W * float(t[0]), base, W * float(t[2]), H * float(t[1]), wall, roof, W * float(t[2]) * 2.2)
	P.spire_tower(self, W * 0.07, H * 0.24, W * 0.008, H * 0.03, wall, roof, W * 0.02)
	# foreground clouds at the bottom
	P.cloud_bank(self, -60, W + 60, H * 0.95, H * 0.05, Color(1.0, 0.98, 0.95), Color(0.80, 0.85, 0.93), 27)


func _add_cloud_layer() -> void:
	_cloud_layer = Control.new()
	_cloud_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cloud_layer.anchor_bottom = 1.0
	_cloud_layer.draw.connect(func() -> void:
		if size.x < 64.0:
			return
		var W := size.x
		var H := size.y
		for k in 2:
			var ox := k * W
			for c: Array in [[0.15, 0.16, 0.035], [0.42, 0.10, 0.028], [0.62, 0.19, 0.03], [0.9, 0.08, 0.025]]:
				var cx := ox + W * float(c[0])
				var cy := H * float(c[1])
				var rr := H * float(c[2])
				# opaque flat clouds (cartoon style): shaded underside first, lit puffs on top
				for j in 5:
					var pc := Vector2(cx + (j - 2) * rr * 0.9, cy - sin(j * 1.3) * rr * 0.4)
					_cloud_layer.draw_circle(pc + Vector2(rr * 0.08, rr * 0.22), rr * (0.8 + 0.25 * sin(j * 2.1)), Color(0.70, 0.80, 0.92), true, -1.0, true)
				for j in 5:
					var pc2 := Vector2(cx + (j - 2) * rr * 0.9, cy - sin(j * 1.3) * rr * 0.4)
					_cloud_layer.draw_circle(pc2, rr * (0.8 + 0.25 * sin(j * 2.1)), Color(0.95, 0.97, 1.0), true, -1.0, true))
	_cloud_layer.anchor_right = 2.0
	add_child(_cloud_layer)


# --- Fire ----------------------------------------------------------------------------------

func _paint_fire(r: Rect2) -> void:
	var W := r.size.x
	var H := r.size.y
	P.sky(self, r, [[0.0, Color(0.09, 0.03, 0.05)], [0.2, Color(0.32, 0.07, 0.07)], [0.4, Color(0.90, 0.38, 0.13)], [1.0, Color(0.55, 0.16, 0.08)]])
	P.glow(self, Vector2(W * 0.66, H * 0.38), H * 0.38, Color(1.0, 0.45, 0.15, 0.7))
	draw_circle(Vector2(W * 0.66, H * 0.37), H * 0.055, Color(1.0, 0.62, 0.30), true, -1.0, true)
	# smoke from the volcano
	for k in 7:
		P.glow(self, Vector2(W * (0.80 + k * 0.025), H * (0.2 - k * 0.025)), H * (0.07 + k * 0.012), Color(0.12, 0.05, 0.05, 0.45))
	P.volcano(self, W * 0.81, H * 0.45, W * 0.36, H * 0.25, Color(0.14, 0.06, 0.06), Color(1.0, 0.45, 0.12, 0.85))
	P.ridge(self, -20, W + 20, H * 0.44, H * 0.05, H, Color(0.12, 0.04, 0.05), 31, 0.006, true)
	# the palace terrace and halls (left)
	var red := Color(0.56, 0.10, 0.08)
	var roof := Color(0.16, 0.05, 0.05)
	var gold := Color(0.96, 0.66, 0.24)
	draw_rect(Rect2(W * 0.0, H * 0.41, W * 0.36, H * 0.06), Color(0.20, 0.07, 0.06))
	draw_line(Vector2(0, H * 0.41), Vector2(W * 0.36, H * 0.41), Color(gold, 0.6), 2.0)
	P.pagoda(self, W * 0.17, H * 0.41, W * 0.17, 3, H * 0.075, red, roof, gold, 0.24)
	P.pagoda(self, W * 0.045, H * 0.41, W * 0.08, 2, H * 0.05, red.darkened(0.15), roof, Color(gold, 0.7), 0.24)
	P.pagoda(self, W * 0.30, H * 0.41, W * 0.09, 2, H * 0.055, red.darkened(0.1), roof, Color(gold, 0.7), 0.24)
	P.ridge(self, -20, W + 20, H * 0.95, H * 0.06, H + 10, Color(0.08, 0.03, 0.03), 32, 0.009, true)
	# lava cracks in the foreground rock
	for k in 4:
		var x0 := W * (0.3 + k * 0.12)
		var crack := PackedVector2Array()
		for i in 6:
			crack.append(Vector2(x0 + i * 18.0 + sin(i * 2.0 + k) * 8.0, H * 0.995 - i * 3.0 + cos(i + k) * 3.0))
		draw_polyline(crack, Color(1.0, 0.42, 0.1, 0.55), 1.5, true)


# --- Water ---------------------------------------------------------------------------------

func _paint_water(r: Rect2) -> void:
	var W := r.size.x
	var H := r.size.y
	P.sky(self, r, [[0.0, Color(0.02, 0.04, 0.11)], [0.28, Color(0.05, 0.12, 0.25)], [0.44, Color(0.13, 0.28, 0.44)], [1.0, Color(0.05, 0.12, 0.20)]])
	_rng.seed = 41
	for i in 220:
		var p := Vector2(_rng.randf() * W, _rng.randf() * H * 0.36)
		var b := _rng.randf()
		draw_circle(p, 0.8 + b * 1.4, Color(0.9, 0.95, 1.0, 0.25 + b * 0.6), true, -1.0, true)
	P.glow(self, Vector2(W * 0.86, H * 0.11), H * 0.2, Color(0.75, 0.88, 1.0, 0.45))
	draw_circle(Vector2(W * 0.86, H * 0.11), H * 0.035, Color(0.94, 0.96, 1.0), true, -1.0, true)
	P.ridge(self, -20, W + 20, H * 0.41, H * 0.12, H, Color(0.20, 0.34, 0.50), 41, 0.006, true)
	# ice city: walls with arches, domes and tiered towers
	var ice := Color(0.66, 0.80, 0.93)
	var ice_lit := Color(0.86, 0.94, 1.0)
	var ice_dark := Color(0.40, 0.56, 0.74)
	var top := H * 0.38
	var bottom := H * 0.47
	P.wall(self, -10, W + 10, top, bottom, ice_dark, H * 0.01, H * 0.008)
	draw_line(Vector2(-10, top), Vector2(W + 10, top), ice_lit, 2.0)
	var x := W * 0.04
	while x < W:
		draw_rect(Rect2(x - H * 0.02, top + H * 0.03, H * 0.04, bottom - top), Color(0.10, 0.20, 0.32))
		P.dome(self, x, top + H * 0.032, H * 0.02, Color(0.10, 0.20, 0.32))
		x += W * 0.09
	for d: Array in [[0.06, 0.05, 0.12], [0.16, 0.035, 0.08], [0.85, 0.045, 0.1], [0.94, 0.03, 0.07]]:
		var cx := W * float(d[0])
		draw_rect(Rect2(cx - H * float(d[1]), top - H * float(d[2]) * 0.6, H * float(d[1]) * 2.0, H * float(d[2]) * 0.6), ice)
		P.dome(self, cx, top - H * float(d[2]) * 0.6, H * float(d[1]), ice_lit, Color(1, 1, 1, 0.6))
	for s: Array in [[0.24, 0.05, 0.13, 0.08], [0.27, 0.03, 0.08, -0.1], [0.74, 0.045, 0.12, -0.06], [0.71, 0.03, 0.07, 0.1]]:
		P.shard(self, W * float(s[0]), top + 4, H * float(s[1]), H * float(s[2]), float(s[3]), ice, ice_lit)
	# dark sea with moon glints, then snow drifts in the foreground
	draw_rect(Rect2(-10, bottom, W + 20, H * 0.06), Color(0.03, 0.08, 0.15))
	for i in 12:
		var gx := W * 0.86 + sin(i * 2.3) * W * 0.03
		draw_line(Vector2(gx - 20 - i * 3, bottom + 6 + i * 4), Vector2(gx + 20 + i * 3, bottom + 6 + i * 4), Color(0.8, 0.9, 1.0, 0.35 - i * 0.025), 1.5)
	P.ridge(self, -20, W + 20, H * 0.95, H * 0.05, H + 10, Color(0.80, 0.88, 0.96), 42, 0.006, false)


func _add_aurora() -> void:
	var a := ColorRect.new()
	a.mouse_filter = Control.MOUSE_FILTER_IGNORE
	a.anchor_right = 1.0
	a.anchor_bottom = 0.42
	var m := ShaderMaterial.new()
	m.shader = AURORA_SHADER
	m.set_shader_parameter(&"noise_tex", NOISE)
	a.material = m
	add_child(a)


# --- Particles -----------------------------------------------------------------------------

func _add_particles() -> void:
	particles = CPUParticles2D.new()
	var dot := _soft_dot()
	particles.texture = dot
	particles.local_coords = false
	var budget := Settings.effects_scale()
	match element:
		ElementDefs.Element.WATER:
			particles.amount = int(160 * budget) + 30
			particles.lifetime = 9.0
			particles.direction = Vector2(0.15, 1)
			particles.spread = 15.0
			particles.initial_velocity_min = 30.0
			particles.initial_velocity_max = 70.0
			particles.gravity = Vector2(6, 8)
			particles.scale_amount_min = 0.12
			particles.scale_amount_max = 0.3
			particles.color = Color(1, 1, 1, 0.8)
		ElementDefs.Element.FIRE:
			particles.amount = int(110 * budget) + 20
			particles.lifetime = 6.0
			particles.direction = Vector2(0.2, -1)
			particles.spread = 25.0
			particles.initial_velocity_min = 40.0
			particles.initial_velocity_max = 110.0
			particles.gravity = Vector2(10, -12)
			particles.scale_amount_min = 0.06
			particles.scale_amount_max = 0.16
			var g := Gradient.new()
			g.set_color(0, Color(1.0, 0.85, 0.4, 1.0))
			g.add_point(0.5, Color(1.0, 0.45, 0.1, 0.8))
			g.set_color(g.get_point_count() - 1, Color(0.6, 0.1, 0.05, 0.0))
			particles.color_ramp = g
		ElementDefs.Element.EARTH:
			particles.amount = int(40 * budget) + 10
			particles.lifetime = 12.0
			particles.direction = Vector2(1, 0.35)
			particles.spread = 20.0
			particles.initial_velocity_min = 40.0
			particles.initial_velocity_max = 80.0
			particles.gravity = Vector2(4, 10)
			particles.angular_velocity_min = -120.0
			particles.angular_velocity_max = 120.0
			particles.scale_amount_min = 0.12
			particles.scale_amount_max = 0.22
			particles.texture = _leaf()
			var g2 := Gradient.new()
			g2.set_color(0, Color(0.78, 0.72, 0.30, 0.9))
			g2.set_color(1, Color(0.45, 0.60, 0.25, 0.9))
			particles.color_initial_ramp = g2
		ElementDefs.Element.AIR:
			particles.amount = int(36 * budget) + 8
			particles.lifetime = 5.0
			particles.direction = Vector2(1, -0.05)
			particles.spread = 6.0
			particles.initial_velocity_min = 240.0
			particles.initial_velocity_max = 380.0
			particles.gravity = Vector2.ZERO
			particles.scale_amount_min = 0.5
			particles.scale_amount_max = 1.0
			particles.texture = _streak()
			particles.color = Color(1, 1, 1, 0.35)
	add_child(particles)
	_place_particles()
	particles.preprocess = particles.lifetime


func _place_particles() -> void:
	var W := maxf(size.x, 1920.0)
	var H := maxf(size.y, 1080.0)
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	match element:
		ElementDefs.Element.FIRE:
			particles.position = Vector2(W * 0.5, H * 1.02)
			particles.emission_rect_extents = Vector2(W * 0.55, 10)
		ElementDefs.Element.EARTH, ElementDefs.Element.AIR:
			particles.position = Vector2(-60, H * 0.5)
			particles.emission_rect_extents = Vector2(40, H * 0.5)
		_:
			particles.position = Vector2(W * 0.5, -20)
			particles.emission_rect_extents = Vector2(W * 0.6, 10)


static func _soft_dot() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 48
	t.height = 48
	return t


static func _leaf() -> Texture2D:
	var img := Image.create(48, 24, false, Image.FORMAT_RGBA8)
	for y in 24:
		for x in 48:
			var u := (x - 23.5) / 24.0
			var v := (y - 11.5) / 12.0
			var w := 1.0 - u * u
			var a := clampf((w - absf(v)) * 6.0, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


static func _streak() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.add_point(0.7, Color(1, 1, 1, 0.9))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 160
	t.height = 3
	return t
