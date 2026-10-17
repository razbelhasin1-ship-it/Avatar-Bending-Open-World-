class_name PropFx
extends RefCounted
## Main-thread helpers for the "extras" of structures: ambient particles (incense/camp smoke,
## steam vents, spirit motes, embers), small gatherable meshes for ResourcePickups and marker
## nodes that other modules discover through groups. Particle counts scale with
## Settings.effects_scale(); every emitter has a short visibility range.

const MIST_SHADER := preload("res://assets/shaders/content/mist.gdshader")

static var _mats: Dictionary = {}
static var _pickup_meshes: Dictionary = {}


## Ambient emitter: &"smoke" (thin rising wisps), &"steam" (vent plumes), &"motes" (floating
## glowing spirit lights), &"embers" (sparks over a fire).
static func particles(kind: StringName, color: Color = Color(-1, 0, 0)) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = String(kind).capitalize()
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	var q := QuadMesh.new()
	var fx := Settings.effects_scale()
	var tint := Color(0.85, 0.85, 0.85, 0.35)
	var glow := 0.0
	match kind:
		&"steam":
			p.amount = maxi(int(18 * fx), 5)
			p.lifetime = 5.0
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			pm.emission_sphere_radius = 2.5
			pm.direction = Vector3.UP
			pm.spread = 12.0
			pm.initial_velocity_min = 2.0
			pm.initial_velocity_max = 4.0
			pm.gravity = Vector3(0.3, 0.6, 0)
			pm.scale_min = 3.0
			pm.scale_max = 6.0
			tint = Color(0.95, 0.95, 0.95, 0.5)
			p.visibility_range_end = 600.0
		&"motes":
			p.amount = maxi(int(28 * fx), 8)
			p.lifetime = 7.0
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			pm.emission_sphere_radius = 9.0
			pm.direction = Vector3.UP
			pm.spread = 180.0
			pm.initial_velocity_min = 0.1
			pm.initial_velocity_max = 0.5
			pm.gravity = Vector3(0, 0.15, 0)
			pm.turbulence_enabled = true
			pm.turbulence_noise_strength = 0.6
			pm.turbulence_noise_speed = Vector3(0.1, 0.05, 0.1)
			pm.scale_min = 0.18
			pm.scale_max = 0.32
			tint = Color(0.6, 1.0, 0.9, 0.9) if color.r < 0.0 else color
			glow = 1.5
			p.visibility_range_end = 160.0
		&"embers":
			p.amount = maxi(int(14 * fx), 4)
			p.lifetime = 2.2
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			pm.emission_sphere_radius = 0.4
			pm.direction = Vector3.UP
			pm.spread = 25.0
			pm.initial_velocity_min = 1.0
			pm.initial_velocity_max = 2.4
			pm.gravity = Vector3(0, 0.5, 0)
			pm.turbulence_enabled = true
			pm.turbulence_noise_strength = 1.2
			pm.scale_min = 0.05
			pm.scale_max = 0.1
			tint = Color(1.0, 0.55, 0.15, 1.0)
			glow = 2.0
			p.visibility_range_end = 90.0
		_:
			p.amount = maxi(int(10 * fx), 4)
			p.lifetime = 6.0
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			pm.emission_sphere_radius = 0.15
			pm.direction = Vector3.UP
			pm.spread = 8.0
			pm.initial_velocity_min = 0.5
			pm.initial_velocity_max = 0.9
			pm.gravity = Vector3(0.25, 0.1, 0.1)
			pm.scale_min = 0.5
			pm.scale_max = 1.0
			tint = Color(0.75, 0.74, 0.72, 0.28)
			p.visibility_range_end = 160.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 1.0 if kind != &"embers" else 0.2))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0))
	grad.set_color(1, Color(1, 1, 1, 0))
	grad.add_point(0.25, Color(1, 1, 1, 1))
	grad.add_point(0.7, Color(1, 1, 1, 0.8))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	q.size = Vector2.ONE
	q.material = _material(tint, glow)
	p.draw_pass_1 = q
	p.preprocess = p.lifetime
	p.visibility_aabb = AABB(Vector3(-15, -3, -15), Vector3(30, 40, 30))
	if kind == &"smoke" or kind == &"embers":
		# a fire's smoke / embers stop while WorldFires has that fire put out
		p.add_to_group(&"fire_fx")
	return p


static func _material(tint: Color, glow: float) -> ShaderMaterial:
	var key := "%s|%.2f" % [tint.to_html(), glow]
	if _mats.has(key):
		return _mats[key]
	WorldShaderGlobals.ensure()
	var m := ShaderMaterial.new()
	m.shader = MIST_SHADER
	m.set_shader_parameter(&"tint", tint)
	m.set_shader_parameter(&"glow", glow)
	_mats[key] = m
	return m


## Small mesh for a gatherable resource: &"jade" (green crystal cluster), &"bone" (whale rib),
## &"blossom" (glowing spirit flower), &"ore" (dark rock with metal flecks), &"herb".
static func pickup_mesh(kind: StringName) -> Mesh:
	if _pickup_meshes.has(kind):
		return _pickup_meshes[kind]
	NationPalette.prepare_materials()
	var kit := BuildingKit.new(NationPalette.get_palette(&"neutral"), 0, ContentHash.hash_name(String(kind)))
	kit.color_jitter = 0.0
	var rng := kit.rng
	match kind:
		&"jade":
			var gb := kit.g(&"glow")
			gb.uv = Vector2(0, 0.15)
			for k in 5:
				var a := TAU * k / 5.0
				var base := Vector3(cos(a) * 0.12, 0, sin(a) * 0.12)
				gb.cylinder(base, base + Vector3(cos(a) * 0.2, rng.randf_range(0.35, 0.6), sin(a) * 0.2), 0.09, 0.0, 5, Color(0.2, 0.8, 0.45), 1, false)
			kit.g().blob(Vector3(0, 0.02, 0), 0.22, 0, Color(0.35, 0.33, 0.3), rng, 0.2, Vector3(1.3, 0.4, 1.3), Vector3.INF, 0.0, Color(0.2, 0.2, 0.2), Vector2.ZERO, true)
		&"bone":
			var bone := Color(0.9, 0.86, 0.76).srgb_to_linear()
			kit.g().tube(PackedVector3Array([Vector3(-0.4, 0.05, 0), Vector3(-0.1, 0.25, 0.05), Vector3(0.3, 0.4, 0.0)]), PackedFloat32Array([0.07, 0.06, 0.04]), 5, bone)
			kit.g().blob(Vector3(-0.45, 0.06, 0), 0.1, 0, bone, rng, 0.1)
		&"blossom":
			var gb := kit.g(&"glow")
			gb.uv = Vector2(0, 0.4)
			kit.g().cylinder(Vector3.ZERO, Vector3(0, 0.35, 0), 0.015, 0.012, 4, Color(0.2, 0.45, 0.2), 0)
			for k in 6:
				var a := TAU * k / 6.0
				gb.blob(Vector3(cos(a) * 0.09, 0.38, sin(a) * 0.09), 0.07, 0, Color(0.85, 0.95, 1.0), null, 0.0, Vector3(1.4, 0.4, 1.0))
			gb.blob(Vector3(0, 0.4, 0), 0.05, 0, Color(1.0, 0.9, 0.5))
		&"herb":
			var leaf := Color(0.3, 0.6, 0.25).srgb_to_linear()
			for k in 7:
				var a := TAU * k / 7.0
				kit.g().cone(Vector3(0, 0, 0), Vector3(cos(a) * 0.25, 0.35, sin(a) * 0.25), 0.05, 3, leaf, false)
		_:
			kit.g().blob(Vector3(0, 0.15, 0), 0.3, 0, Color(0.22, 0.2, 0.2), rng, 0.3, Vector3(1.2, 0.8, 1.0), Vector3.INF, 0.0, Color(0.15, 0.14, 0.14), Vector2.ZERO, true)
			var gb := kit.g(&"glow")
			gb.uv = Vector2(0, 0.0)
			for k in 4:
				gb.box(Transform3D(Basis.from_euler(Vector3(rng.randf(), rng.randf() * 3.0, 0)), Vector3(rng.randf_range(-0.15, 0.15), 0.25, rng.randf_range(-0.15, 0.15))), Vector3(0.08, 0.08, 0.08), Color(0.9, 0.6, 0.3))
	var m := kit.build().make_mesh()
	_pickup_meshes[kind] = m
	return m


## Marker3D in `group` (and "world_markers") with metadata, for other modules: shrines (respawn
## points), enemy spawns of camps, training dummies, dock berths, vistas, cave entrances...
static func marker(group: StringName, pos: Vector3, yaw: float, meta: Dictionary = {}) -> Marker3D:
	var m := Marker3D.new()
	m.name = String(group).capitalize().replace(" ", "")
	m.transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	m.add_to_group(group)
	m.add_to_group(&"world_markers")
	for k: String in meta:
		m.set_meta(StringName(k), meta[k])
	return m
