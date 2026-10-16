class_name FireFx
extends RefCounted
## Firebending visuals in the animated-series style: banded flame sprites with
## a hot core, ember sparks, short-lived light. All pooled and budgeted.
##
##   var ball := FireFx.ball(self, 0.45)         # projectile visual; ball.finish() when it dies
##   FireFx.arc(self, xform, -1.2, 1.2, 1.6)     # kick arc / sweep wave
##   FireFx.burst(self, pos, 1.0)                # fist ignition / small explosion
##   FireFx.explosion(self, pos, 3.0)            # charged blast impact

static var _sprite_quad: QuadMesh = null


static func flame_material(seed_v: float = 0.0, tongue: float = 0.55) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://src/fx/shaders/fx_flame.gdshader")
	m.set_shader_parameter(&"noise_tex", FxLib.noise_texture(&"smooth"))
	m.set_shader_parameter(&"seed", seed_v)
	m.set_shader_parameter(&"tongue", tongue)
	return m


static func ribbon_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://src/fx/shaders/fx_flame_ribbon.gdshader")
	m.set_shader_parameter(&"noise_tex", FxLib.noise_texture(&"smooth"))
	return m


static func quad() -> QuadMesh:
	if _sprite_quad == null:
		_sprite_quad = QuadMesh.new()
		_sprite_quad.size = Vector2(1, 1)
	return _sprite_quad


## Fireball / fire bolt visual (core sprites + flame trail + embers). Position it
## every frame (projectiles do); call finish() to let the trail burn out.
static func ball(from: Node, size: float = 0.4, with_light: bool = true) -> FireBall:
	var b := FxLib.take(from, &"fire_ball", FireBall.make) as FireBall
	b.setup(size)
	if with_light:
		b.light = FxFlash.attach(from, b, Color(1.0, 0.55, 0.2), 1.6 + size * 2.0, 3.0 + size * 6.0)
	return b


## Flame arc on a crescent (kick arcs, flat) or a standing wall (sweep waves).
## `xform` places the arc centre; angles in radians around -Z of xform.
static func arc(from: Node, xform: Transform3D, a0: float, a1: float, radius: float, duration: float = 0.35,
		opts: Dictionary = {}) -> FireArc:
	var a := FxLib.take(from, &"fire_arc", FireArc.make) as FireArc
	a.setup(xform, a0, a1, radius, duration, opts)
	return a


## Quick flame burst (fists igniting, step trail, small impacts).
static func burst(from: Node, pos: Vector3, strength: float = 1.0, dir: Vector3 = Vector3.UP) -> void:
	FxBurst.spawn(from, &"flame", pos, {"size": 0.6 + strength * 0.5, "count": 0.6 + strength * 0.6, "dir": dir, "speed": 0.8 + strength * 0.4})
	FxBurst.spawn(from, &"embers", pos, {"count": 0.5 + strength * 0.5, "dir": dir})


## Explosion: flame ball, smoke, embers, ring, light, scorch.
static func explosion(from: Node, pos: Vector3, radius: float = 2.5, ground_y: float = INF) -> void:
	var k := radius / 2.5
	FxBurst.spawn(from, &"flame", pos, {"size": 1.4 * k, "count": 1.8, "speed": 2.2 * k, "radius": 1.5 * k, "spread": 180.0})
	FxBurst.spawn(from, &"embers", pos, {"count": 2.0, "speed": 2.0 * k, "spread": 180.0})
	FxBurst.spawn(from, &"smoke", pos + Vector3.UP * 0.4, {"size": 1.3 * k, "count": 1.2})
	FxBurst.spawn(from, &"sparks", pos, {"count": 1.2, "speed": 1.3 * k, "spread": 180.0})
	FxFlash.spawn(from, pos + Vector3.UP * 0.5, Color(1.0, 0.58, 0.22), 5.0 * k, 0.35, radius * 3.0)
	if ground_y < INF:
		var g := Vector3(pos.x, ground_y, pos.z)
		FxRing.spawn(from, g, radius * 1.2, Color(1.0, 0.6, 0.25), 0.4, {"inner": Color(1.0, 0.85, 0.5), "opacity": 0.75, "fill": 0.35})
		FxDecal.spawn(from, g, &"scorch", radius * 0.8)


## A fire bolt / jab blast leaving the fist (muzzle flash).
static func muzzle(from: Node, pos: Vector3, dir: Vector3, size: float = 1.0) -> void:
	FxBurst.spawn(from, &"flame", pos, {"size": 0.55 * size, "count": 0.6, "dir": dir, "speed": 1.6, "spread": 30.0})
	FxFlash.spawn(from, pos, Color(1.0, 0.6, 0.25), 1.6 * size, 0.12, 4.0)


## Projectile visual: three flickering flame sprites around a hot core + trail.
class FireBall extends Node3D:
	var sprites: Array[MeshInstance3D] = []
	var mats: Array[ShaderMaterial] = []
	var trail: GPUParticles3D
	var embers: GPUParticles3D
	var light: FxFlash = null
	var size := 0.4
	var heat := 1.0
	var _dying := -1.0

	static func make() -> FireBall:
		var b := FireBall.new()
		b.name = "FireBall"
		for i in 3:
			var m := MeshInstance3D.new()
			m.mesh = FireFx.quad()
			var mat := FireFx.flame_material(float(i) * 0.31, 0.35 + 0.15 * i)
			m.material_override = mat
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			b.add_child(m)
			b.sprites.append(m)
			b.mats.append(mat)
		b.trail = _emitter(14, 0.32, true)
		b.add_child(b.trail)
		b.embers = _emitter(10, 0.6, false)
		b.add_child(b.embers)
		return b

	static func _emitter(count: int, life: float, flame: bool) -> GPUParticles3D:
		var p := GPUParticles3D.new()
		p.amount = FxLib.amount(count)
		p.lifetime = life
		p.local_coords = false
		p.emitting = false
		p.visibility_aabb = AABB(Vector3(-8, -8, -8), Vector3(16, 16, 16))
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = 0.12
		pm.direction = Vector3.UP
		pm.spread = 180.0
		pm.initial_velocity_min = 0.2
		pm.initial_velocity_max = 0.8 if flame else 2.0
		pm.gravity = Vector3(0, 1.5, 0)
		pm.damping_min = 1.0
		pm.damping_max = 2.0
		var sc := Curve.new()
		sc.add_point(Vector2(0.0, 1.0))
		sc.add_point(Vector2(1.0, 0.25))
		var ct := CurveTexture.new()
		ct.curve = sc
		pm.scale_curve = ct
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var gt := GradientTexture1D.new()
		gt.gradient = g
		pm.color_ramp = gt
		if flame:
			pm.scale_min = 0.45
			pm.scale_max = 0.7
			p.draw_pass_1 = FireFx.quad()
			p.material_override = FireFx.flame_material(0.5, 0.3)
		else:
			pm.scale_min = 0.04
			pm.scale_max = 0.08
			pm.color = Color(1.0, 0.65, 0.2)
			p.draw_pass_1 = FireFx.quad()
			var s := StandardMaterial3D.new()
			s.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			s.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
			s.billboard_keep_scale = true
			s.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			s.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			s.vertex_color_use_as_albedo = true
			s.albedo_texture = FxLib.soft_dot()
			s.albedo_color = Color(2.5, 2.5, 2.5)
			p.material_override = s
		p.process_material = pm
		return p

	func setup(p_size: float) -> void:
		size = p_size
		heat = 1.0
		_dying = -1.0
		for i in sprites.size():
			var s := 2.2 * size * (1.0 - 0.18 * i)
			sprites[i].scale = Vector3(s, s * 1.15, s)
			sprites[i].position = Vector3(0, 0.05 * size * i, 0)
			mats[i].set_shader_parameter(&"opacity", 1.0)
			mats[i].set_shader_parameter(&"intensity", 1.0)
			mats[i].set_shader_parameter(&"age", 0.0)
		var tpm := trail.process_material as ParticleProcessMaterial
		tpm.scale_min = 1.1 * size
		tpm.scale_max = 1.7 * size
		trail.restart()
		trail.emitting = true
		embers.restart()
		embers.emitting = FxLib.scale() > 0.3

	func set_heat(h: float) -> void:
		heat = h
		for m in mats:
			m.set_shader_parameter(&"intensity", h)

	func set_size(s: float) -> void:
		size = s
		for i in sprites.size():
			var k := 2.2 * size * (1.0 - 0.18 * i)
			sprites[i].scale = Vector3(k, k * 1.15, k)

	## Stops the core and lets the trail burn out, then returns to the pool.
	func finish() -> void:
		if _dying >= 0.0:
			return
		_dying = 0.0
		trail.emitting = false
		embers.emitting = false
		if light and is_instance_valid(light):
			light.fade_out(0.15)
		light = null

	func fx_reset() -> void:
		_dying = 10.0

	func _process(delta: float) -> void:
		if _dying < 0.0:
			return
		_dying += delta
		var a := clampf(1.0 - _dying / 0.12, 0.0, 1.0)
		for m in mats:
			m.set_shader_parameter(&"opacity", a)
		if _dying > 0.7:
			FxLib.release(self)


## Flame ribbon on an arc: animates its head along the arc and burns out.
class FireArc extends Node3D:
	var mesh_i: MeshInstance3D
	var mat: ShaderMaterial
	var t := 0.0
	var duration := 0.35
	var hold := 0.15
	var r0 := 1.0
	var r1 := 1.0
	## Expanding waves reveal the whole arc at once and grow r0 -> r1 instead.
	var expanding := false

	static func make() -> FireArc:
		var a := FireArc.new()
		a.name = "FireArc"
		a.mesh_i = MeshInstance3D.new()
		a.mesh_i.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		a.mat = FireFx.ribbon_material()
		a.mesh_i.material_override = a.mat
		a.add_child(a.mesh_i)
		return a

	func setup(xform: Transform3D, a0: float, a1: float, radius: float, p_duration: float, opts: Dictionary) -> void:
		global_transform = xform
		duration = maxf(p_duration, 0.05)
		hold = float(opts.get("hold", 0.12))
		t = 0.0
		var standing := bool(opts.get("standing", false))
		if standing:
			mesh_i.mesh = FxMeshes.arc_wall(a0, a1, float(opts.get("height", 1.0)), 32, float(opts.get("lean", 0.2)))
			mesh_i.scale = Vector3(radius, 1.0, radius)
			mat.set_shader_parameter(&"symmetric", 0.0)
		else:
			mesh_i.mesh = FxMeshes.crescent(a0, a1, float(opts.get("width", 0.45)))
			mesh_i.scale = Vector3(radius, 1.0, radius)
			mat.set_shader_parameter(&"symmetric", 1.0)
		mat.set_shader_parameter(&"tail", float(opts.get("tail", 1.1)))
		mat.set_shader_parameter(&"head", 0.0)
		mat.set_shader_parameter(&"fade", 0.0)
		mat.set_shader_parameter(&"tongue_scale", float(opts.get("tongues", 5.0)))
		r0 = radius
		r1 = float(opts.get("grow_to", radius))
		expanding = r1 != r0

	func fx_reset() -> void:
		t = duration + hold + 1.0

	func _process(delta: float) -> void:
		t += delta
		var sweep := clampf(t / duration, 0.0, 1.0)
		if expanding:
			var r := lerpf(r0, r1, 1.0 - pow(1.0 - sweep, 1.6))
			mesh_i.scale = Vector3(r, mesh_i.scale.y, r)
			mat.set_shader_parameter(&"head", 1.02)
		else:
			mat.set_shader_parameter(&"head", 1.0 - pow(1.0 - sweep, 2.0) + 0.02)
		var burn := clampf((t - duration) / maxf(hold + 0.2, 0.05), 0.0, 1.0)
		mat.set_shader_parameter(&"fade", burn)
		if burn >= 1.0:
			FxLib.release(self)
