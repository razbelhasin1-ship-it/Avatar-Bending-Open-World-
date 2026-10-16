class_name FxDecal
extends Node3D
## Pooled ground marks that fade out: &"crack" (earth), &"scorch" (fire),
## &"wet" (water), &"frost" (ice). Uses a projected Decal on Forward+/Mobile
## and a flat ground quad on the Compatibility renderer (no decals there).
## Lifetime scales with Settings.detail_level().
##
##   FxDecal.spawn(self, ground_pos, &"scorch", 1.6)

var decal: Decal = null
var quad: MeshInstance3D = null
var quad_mat: StandardMaterial3D = null
var t := 0.0
var life := 6.0
var mark: StringName = &"crack"

static var _textures: Dictionary = {}


static func spawn(from: Node, pos: Vector3, p_mark: StringName, radius: float = 1.5, normal: Vector3 = Vector3.UP) -> FxDecal:
	var d := FxLib.take(from, StringName("decal_" + String(p_mark)), func() -> Node3D: return FxDecal._make(p_mark)) as FxDecal
	var n := normal.normalized() if normal.length_squared() > 0.01 else Vector3.UP
	var x := n.cross(Vector3.FORWARD)
	if x.length_squared() < 0.01:
		x = Vector3.RIGHT
	x = x.normalized()
	var b := Basis(x, n, x.cross(n)).orthonormalized().rotated(n, randf() * TAU)
	d.global_transform = Transform3D(b, pos + n * 0.02)
	d.scale = Vector3(radius, 1.0, radius)
	d.t = 0.0
	d.life = [3.0, 5.0, 8.0, 12.0][Settings.detail_level()] * (1.4 if p_mark == &"crack" else 1.0)
	d._set_alpha(1.0)
	return d


static func _make(p_mark: StringName) -> FxDecal:
	var d := FxDecal.new()
	d.mark = p_mark
	d.name = "Decal_%s" % p_mark
	var tex := texture(p_mark)
	if Settings.is_compatibility_renderer():
		d.quad = MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(2, 2)
		d.quad.mesh = pm
		d.quad_mat = StandardMaterial3D.new()
		d.quad_mat.albedo_texture = tex
		d.quad_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		d.quad_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		d.quad_mat.render_priority = -1
		d.quad.material_override = d.quad_mat
		d.quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		d.add_child(d.quad)
	else:
		d.decal = Decal.new()
		d.decal.size = Vector3(2, 0.5, 2)
		d.decal.texture_albedo = tex
		d.decal.upper_fade = 0.4
		d.decal.lower_fade = 0.4
		d.decal.cull_mask = 1
		d.add_child(d.decal)
	return d


func _set_alpha(a: float) -> void:
	if decal:
		decal.modulate = Color(1, 1, 1, a)
	elif quad_mat:
		quad_mat.albedo_color = Color(1, 1, 1, a)


func fx_reset() -> void:
	t = life


func _process(delta: float) -> void:
	t += delta
	var fade_start := life * 0.65
	if t > fade_start:
		_set_alpha(clampf(1.0 - (t - fade_start) / (life - fade_start), 0.0, 1.0))
	if t >= life:
		FxLib.release(self)


## Procedural mark textures (cached, 256^2 RGBA).
static func texture(p_mark: StringName) -> Texture2D:
	if _textures.has(p_mark):
		return _textures[p_mark]
	var size := 256
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var fn := FastNoiseLite.new()
	fn.seed = hash(p_mark) & 0xffff
	fn.frequency = 0.03
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	match p_mark:
		&"crack":
			_draw_cracks(img, rng, fn)
		_:
			for y in size:
				for x in size:
					var u := (float(x) / size) * 2.0 - 1.0
					var v := (float(y) / size) * 2.0 - 1.0
					var r := sqrt(u * u + v * v)
					var n := fn.get_noise_2d(x, y) * 0.5 + 0.5
					var edge := clampf((0.82 - r + (n - 0.5) * 0.5) * 5.0, 0.0, 1.0)
					var c := Color(0, 0, 0, 0)
					match p_mark:
						&"scorch":
							var core := clampf((0.45 - r) * 3.0 + n * 0.3, 0.0, 1.0)
							c = Color(0.06, 0.045, 0.04).lerp(Color(0.22, 0.12, 0.07), 1.0 - core)
							c.a = edge * (0.55 + 0.4 * core)
						&"wet":
							c = Color(0.18, 0.22, 0.26)
							c.a = edge * 0.45 * (0.7 + 0.3 * n)
						&"frost":
							c = Color(0.86, 0.95, 1.0)
							c.a = edge * (0.5 + 0.4 * n)
					img.set_pixel(x, y, c)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_textures[p_mark] = tex
	return tex


static func _draw_cracks(img: Image, rng: RandomNumberGenerator, fn: FastNoiseLite) -> void:
	var size := img.get_width()
	var c := Vector2(size, size) * 0.5
	var dark := Color(0.12, 0.09, 0.07, 0.95)
	# Crushed centre.
	for y in size:
		for x in size:
			var d := Vector2(x, y).distance_to(c) / (size * 0.5)
			var n := fn.get_noise_2d(x * 2.0, y * 2.0) * 0.5 + 0.5
			if d < 0.22 + n * 0.08:
				img.set_pixel(x, y, Color(0.2, 0.16, 0.12, 0.75 * (1.0 - d / 0.3)))
	# Branching radial cracks.
	for i in 9:
		var a := TAU * float(i) / 9.0 + rng.randf_range(-0.25, 0.25)
		_crack_line(img, c, a, size * rng.randf_range(0.32, 0.47), 3.2, rng, dark, 2)


static func _crack_line(img: Image, start: Vector2, angle: float, length: float, width: float, rng: RandomNumberGenerator, col: Color, depth: int) -> void:
	var p := start
	var a := angle
	var steps := int(length / 3.0)
	for s in steps:
		a += rng.randf_range(-0.35, 0.35)
		p += Vector2(cos(a), sin(a)) * 3.0
		var w := width * (1.0 - float(s) / steps) + 0.6
		for oy in range(-3, 4):
			for ox in range(-3, 4):
				if Vector2(ox, oy).length() <= w:
					var q := Vector2i(int(p.x) + ox, int(p.y) + oy)
					if q.x >= 0 and q.y >= 0 and q.x < img.get_width() and q.y < img.get_height():
						img.set_pixel(q.x, q.y, col)
		if depth > 0 and rng.randf() < 0.06:
			_crack_line(img, p, a + rng.randf_range(-0.9, 0.9), length * 0.4, w * 0.7, rng, col, depth - 1)
