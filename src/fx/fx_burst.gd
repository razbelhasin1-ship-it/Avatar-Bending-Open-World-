class_name FxBurst
extends Node3D
## Pooled one-shot particle bursts (GPUParticles3D) for every element:
##
##   FxBurst.spawn(self, &"dust", pos, {"color": FxLib.surface_color(surface), "dir": Vector3.UP})
##   FxBurst.spawn(self, &"embers", pos, {"count": 1.5})
##
## Kinds: dust, dust_ring, snow, embers, flame, smoke, steam, droplets, spray,
## sparkle, sparks, leaves. Counts scale with Settings.effects_scale().
## opts: color (Color), dir (Vector3, emission direction), count (mult),
## size (mult), speed (mult), radius (emission radius mult), spread (deg).

const KINDS := {
	&"dust": {"amount": 14, "life": 0.95, "mat": &"puff", "shape": &"sphere", "radius": 0.35, "dir": Vector3.UP, "spread": 70.0,
		"vel": [1.2, 3.2], "gravity": Vector3(0, -0.4, 0), "damping": [2.0, 3.5], "scale": [0.55, 1.1], "grow": 1.6, "alpha": 0.8},
	&"dust_ring": {"amount": 22, "life": 0.9, "mat": &"puff", "shape": &"ring", "radius": 0.5, "dir": Vector3.UP, "spread": 10.0,
		"vel": [0.3, 0.8], "radial": [3.5, 6.5], "gravity": Vector3(0, 0.0, 0), "damping": [4.0, 6.0], "scale": [0.5, 0.95], "grow": 1.8, "alpha": 0.75},
	&"snow": {"amount": 16, "life": 0.9, "mat": &"puff", "shape": &"sphere", "radius": 0.3, "dir": Vector3.UP, "spread": 60.0,
		"vel": [1.5, 3.5], "gravity": Vector3(0, -2.0, 0), "damping": [1.5, 3.0], "scale": [0.4, 0.85], "grow": 1.5, "alpha": 0.95, "crisp": 0.75,
		"color": Color(0.95, 0.97, 1.0)},
	&"embers": {"amount": 18, "life": 0.9, "mat": &"glow", "shape": &"sphere", "radius": 0.25, "dir": Vector3.UP, "spread": 65.0,
		"vel": [1.5, 4.5], "gravity": Vector3(0, 2.0, 0), "damping": [1.0, 2.0], "scale": [0.05, 0.11], "grow": 0.3, "alpha": 1.0,
		"color": Color(1.0, 0.62, 0.18), "hdr": 2.5},
	&"flame": {"amount": 10, "life": 0.5, "mat": &"flame", "shape": &"sphere", "radius": 0.3, "dir": Vector3.UP, "spread": 50.0,
		"vel": [1.0, 3.0], "gravity": Vector3(0, 2.5, 0), "damping": [2.0, 3.0], "scale": [0.55, 0.95], "grow": 0.55, "alpha": 1.0},
	&"smoke": {"amount": 8, "life": 1.4, "mat": &"puff", "shape": &"sphere", "radius": 0.35, "dir": Vector3.UP, "spread": 35.0,
		"vel": [0.6, 1.6], "gravity": Vector3(0, 0.8, 0), "damping": [1.0, 2.0], "scale": [0.6, 1.0], "grow": 2.0, "alpha": 0.55,
		"color": Color(0.24, 0.21, 0.2)},
	&"steam": {"amount": 10, "life": 1.1, "mat": &"puff", "shape": &"sphere", "radius": 0.35, "dir": Vector3.UP, "spread": 40.0,
		"vel": [0.8, 2.0], "gravity": Vector3(0, 1.2, 0), "damping": [1.0, 2.0], "scale": [0.5, 0.9], "grow": 2.2, "alpha": 0.6,
		"color": Color(0.92, 0.95, 0.97)},
	&"droplets": {"amount": 22, "life": 0.75, "mat": &"drop", "shape": &"sphere", "radius": 0.2, "dir": Vector3.UP, "spread": 70.0,
		"vel": [2.5, 6.0], "gravity": Vector3(0, -12.0, 0), "damping": [0.0, 0.5], "scale": [0.05, 0.11], "grow": 0.8, "alpha": 0.95,
		"color": Color(0.82, 0.94, 1.0)},
	&"spray": {"amount": 10, "life": 0.7, "mat": &"puff", "shape": &"sphere", "radius": 0.25, "dir": Vector3.UP, "spread": 55.0,
		"vel": [1.5, 3.5], "gravity": Vector3(0, -3.0, 0), "damping": [1.0, 2.0], "scale": [0.35, 0.7], "grow": 1.6, "alpha": 0.8, "crisp": 0.7,
		"color": Color(0.86, 0.95, 1.0)},
	&"sparkle": {"amount": 14, "life": 0.6, "mat": &"glow", "shape": &"sphere", "radius": 0.35, "dir": Vector3.UP, "spread": 90.0,
		"vel": [0.8, 2.5], "gravity": Vector3(0, -1.0, 0), "damping": [1.0, 2.0], "scale": [0.04, 0.08], "grow": 0.5, "alpha": 1.0,
		"color": Color(0.85, 0.97, 1.0), "hdr": 2.0},
	&"sparks": {"amount": 16, "life": 0.45, "mat": &"glow", "shape": &"sphere", "radius": 0.1, "dir": Vector3.UP, "spread": 80.0,
		"vel": [4.0, 9.0], "gravity": Vector3(0, -9.0, 0), "damping": [0.5, 1.0], "scale": [0.035, 0.07], "grow": 0.4, "alpha": 1.0,
		"color": Color(1.0, 0.75, 0.3), "hdr": 3.0},
	&"leaves": {"amount": 8, "life": 1.6, "mat": &"leaf", "shape": &"sphere", "radius": 0.5, "dir": Vector3.UP, "spread": 60.0,
		"vel": [2.0, 4.5], "gravity": Vector3(0, -2.2, 0), "damping": [1.0, 1.8], "scale": [0.07, 0.12], "grow": 1.0, "alpha": 1.0,
		"color": Color(0.5, 0.62, 0.25)},
}

var particles: GPUParticles3D
var process_mat: ParticleProcessMaterial
var life := 0.0
var kind: StringName = &""
var amount_base := 10

static var _materials: Dictionary = {}
static var _quad: QuadMesh = null


## Spawns a burst of `kind` at `pos`. Returns the pooled node (or null if the kind is unknown).
static func spawn(from: Node, p_kind: StringName, pos: Vector3, opts: Dictionary = {}) -> FxBurst:
	if not KINDS.has(p_kind):
		push_warning("FxBurst: unknown kind %s" % p_kind)
		return null
	var b := FxLib.take(from, StringName("burst_" + String(p_kind)), func() -> Node3D: return FxBurst._make(p_kind)) as FxBurst
	b.global_position = pos
	b._configure(opts)
	return b


static func _make(p_kind: StringName) -> FxBurst:
	var b := FxBurst.new()
	b.kind = p_kind
	b.name = "Burst_%s" % p_kind
	var cfg: Dictionary = KINDS[p_kind]
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.9
	p.local_coords = false
	p.emitting = false
	p.lifetime = cfg["life"]
	p.visibility_aabb = AABB(Vector3(-6, -3, -6), Vector3(12, 9, 12))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	match StringName(cfg["shape"]):
		&"ring":
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
			pm.emission_ring_axis = Vector3.UP
			pm.emission_ring_height = 0.05
			pm.emission_ring_radius = cfg["radius"]
			pm.emission_ring_inner_radius = float(cfg["radius"]) * 0.7
		_:
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			pm.emission_sphere_radius = cfg["radius"]
	pm.direction = cfg["dir"]
	pm.spread = cfg["spread"]
	pm.initial_velocity_min = cfg["vel"][0]
	pm.initial_velocity_max = cfg["vel"][1]
	if cfg.has("radial"):
		pm.radial_velocity_min = cfg["radial"][0]
		pm.radial_velocity_max = cfg["radial"][1]
	pm.gravity = cfg["gravity"]
	pm.damping_min = cfg["damping"][0]
	pm.damping_max = cfg["damping"][1]
	pm.scale_min = cfg["scale"][0]
	pm.scale_max = cfg["scale"][1]
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	var grow: float = cfg["grow"]
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.45 if grow > 1.0 else 1.0))
	sc.add_point(Vector2(0.35, lerpf(0.9, grow, 0.5)))
	sc.add_point(Vector2(1.0, grow))
	var ct := CurveTexture.new()
	ct.curve = sc
	pm.scale_curve = ct
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, float(cfg["alpha"])))
	g.set_color(1, Color(1, 1, 1, 0.0))
	g.add_point(0.6, Color(1, 1, 1, float(cfg["alpha"]) * 0.8))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	pm.color = cfg.get("color", Color.WHITE)
	p.process_material = pm
	p.draw_pass_1 = _quad_mesh()
	p.material_override = _material(StringName(cfg["mat"]), cfg)
	b.add_child(p)
	b.particles = p
	b.process_mat = pm
	b.amount_base = int(cfg["amount"])
	return b


func _configure(opts: Dictionary) -> void:
	var cfg: Dictionary = KINDS[kind]
	var cnt := FxLib.amount(int(round(amount_base * float(opts.get("count", 1.0)))))
	if particles.amount != cnt:
		particles.amount = cnt
	process_mat.color = opts.get("color", cfg.get("color", Color.WHITE))
	var d: Vector3 = opts.get("dir", cfg["dir"])
	process_mat.direction = d.normalized() if d.length_squared() > 1e-6 else Vector3.UP
	process_mat.spread = float(opts.get("spread", cfg["spread"]))
	var sp := float(opts.get("speed", 1.0))
	process_mat.initial_velocity_min = float(cfg["vel"][0]) * sp
	process_mat.initial_velocity_max = float(cfg["vel"][1]) * sp
	if cfg.has("radial"):
		process_mat.radial_velocity_min = float(cfg["radial"][0]) * sp
		process_mat.radial_velocity_max = float(cfg["radial"][1]) * sp
	var sz := float(opts.get("size", 1.0))
	process_mat.scale_min = float(cfg["scale"][0]) * sz
	process_mat.scale_max = float(cfg["scale"][1]) * sz
	var rad := float(opts.get("radius", 1.0))
	if process_mat.emission_shape == ParticleProcessMaterial.EMISSION_SHAPE_RING:
		process_mat.emission_ring_radius = float(cfg["radius"]) * rad
		process_mat.emission_ring_inner_radius = float(cfg["radius"]) * rad * 0.7
	else:
		process_mat.emission_sphere_radius = float(cfg["radius"]) * rad
	life = particles.lifetime + 0.15
	particles.restart()
	particles.emitting = true


func fx_reset() -> void:
	particles.emitting = false


func _process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		particles.emitting = false
		FxLib.release(self)


static func _quad_mesh() -> QuadMesh:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2(1, 1)
	return _quad


static func _material(mat_kind: StringName, cfg: Dictionary) -> Material:
	var key := "%s_%s_%s" % [mat_kind, str(cfg.get("crisp", 0.4)), str(cfg.get("hdr", 1.0))]
	if _materials.has(key):
		return _materials[key]
	var m: Material
	match mat_kind:
		&"puff":
			var sm := ShaderMaterial.new()
			sm.shader = preload("res://src/fx/shaders/fx_puff.gdshader")
			sm.set_shader_parameter(&"noise_tex", FxLib.noise_texture(&"smooth"))
			sm.set_shader_parameter(&"crisp", float(cfg.get("crisp", 0.4)))
			m = sm
		&"flame":
			var fm := ShaderMaterial.new()
			fm.shader = preload("res://src/fx/shaders/fx_flame.gdshader")
			fm.set_shader_parameter(&"noise_tex", FxLib.noise_texture(&"smooth"))
			fm.set_shader_parameter(&"tongue", 0.45)
			m = fm
		&"glow", &"drop", &"leaf":
			var s := StandardMaterial3D.new()
			s.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			s.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
			s.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			s.vertex_color_use_as_albedo = true
			s.albedo_texture = FxLib.soft_dot() if mat_kind != &"leaf" else _leaf_texture()
			if mat_kind == &"glow":
				s.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
				var h := float(cfg.get("hdr", 1.0))
				s.albedo_color = Color(h, h, h, 1.0)
			if mat_kind == &"leaf":
				s.cull_mode = BaseMaterial3D.CULL_DISABLED
				s.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			s.disable_receive_shadows = true
			m = s
	_materials[key] = m
	return m


static func _leaf_texture() -> Texture2D:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var u := (float(x) - 15.5) / 15.5
			var v := (float(y) - 15.5) / 15.5
			var inside := u * u / 0.22 + v * v < 0.85
			var vein := absf(u) < 0.06 and absf(v) < 0.8
			var c := Color(1, 1, 1, 1) if inside else Color(1, 1, 1, 0)
			if vein and inside:
				c = Color(0.8, 0.8, 0.7, 1)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
