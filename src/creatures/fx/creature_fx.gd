class_name CreatureFx
extends RefCounted
## Lightweight creature effects built from CPUParticles3D (works on every renderer):
## dirt/rock debris and dust for digging, burrowing, emerging and heavy landings.
## Amounts scale with Settings.effects_scale(); every emitter frees itself.

const SURFACE_COLORS := {
	&"snow": Color(0.92, 0.95, 1.0), &"ice": Color(0.8, 0.9, 1.0), &"stone": Color(0.55, 0.53, 0.5),
	&"grass": Color(0.45, 0.38, 0.28), &"dirt": Color(0.5, 0.4, 0.3), &"sand": Color(0.86, 0.76, 0.55),
	&"ash": Color(0.32, 0.3, 0.3), &"wood": Color(0.5, 0.38, 0.25), &"water": Color(0.7, 0.85, 0.95),
}

static var _chunk_mesh: Mesh = null
static var _dust_mesh: Mesh = null


static func color_for(surface: StringName) -> Color:
	return SURFACE_COLORS.get(surface, Color(0.5, 0.4, 0.3))


## Rock chunks + dust thrown up and outward from `pos`. `power` ~1 for a dig scoop,
## 3 for bursting out of the ground.
static func debris_burst(parent: Node, pos: Vector3, surface: StringName, power: float = 1.0, radius: float = 0.6) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var scale := _effects_scale()
	if scale <= 0.0:
		return
	var col := color_for(surface)
	var chunks := CPUParticles3D.new()
	chunks.mesh = _chunk()
	chunks.amount = maxi(4, int(14.0 * power * scale))
	chunks.one_shot = true
	chunks.explosiveness = 0.92
	chunks.lifetime = 1.3
	chunks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	chunks.emission_sphere_radius = radius
	chunks.direction = Vector3.UP
	chunks.spread = 55.0
	chunks.initial_velocity_min = 2.5 * sqrt(power)
	chunks.initial_velocity_max = 5.5 * sqrt(power)
	chunks.gravity = Vector3(0, -14.0, 0)
	chunks.angular_velocity_min = -360.0
	chunks.angular_velocity_max = 360.0
	chunks.scale_amount_min = 0.5
	chunks.scale_amount_max = 1.4 * clampf(power, 0.6, 2.0)
	chunks.color = col.darkened(0.15)
	chunks.local_coords = false
	_spawn(parent, chunks, pos, 1.6)
	var dust := CPUParticles3D.new()
	dust.mesh = _dust()
	dust.amount = maxi(3, int(10.0 * power * scale))
	dust.one_shot = true
	dust.explosiveness = 0.8
	dust.lifetime = 1.8
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	dust.emission_sphere_radius = radius * 1.2
	dust.direction = Vector3.UP
	dust.spread = 80.0
	dust.initial_velocity_min = 0.6
	dust.initial_velocity_max = 2.0 * sqrt(power)
	dust.gravity = Vector3(0, 0.3, 0)
	dust.damping_min = 1.5
	dust.damping_max = 2.5
	dust.scale_amount_min = 0.8 * radius
	dust.scale_amount_max = 2.2 * radius * clampf(power, 0.7, 2.0)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(col.r, col.g, col.b, 0.75))
	ramp.set_color(1, Color(col.r, col.g, col.b, 0.0))
	dust.color_ramp = ramp
	dust.local_coords = false
	_spawn(parent, dust, pos + Vector3.UP * 0.2, 2.0)


static func _spawn(parent: Node, p: CPUParticles3D, pos: Vector3, life: float) -> void:
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	var t := parent.get_tree().create_timer(life + 0.2, false)
	t.timeout.connect(p.queue_free)


static func _effects_scale() -> float:
	var s := Engine.get_main_loop() as SceneTree
	if s and s.root.has_node(^"Settings"):
		return s.root.get_node(^"Settings").effects_scale()
	return 1.0


static func _chunk() -> Mesh:
	if _chunk_mesh == null:
		var b := BoxMesh.new()
		b.size = Vector3(0.12, 0.09, 0.1)
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = 1.0
		b.material = m
		_chunk_mesh = b
	return _chunk_mesh


static func _dust() -> Mesh:
	if _dust_mesh == null:
		var q := QuadMesh.new()
		q.size = Vector2(1, 1)
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.albedo_texture = _soft_dot()
		q.material = m
		_dust_mesh = q
	return _dust_mesh


static func _soft_dot() -> Texture2D:
	var img := Image.create_empty(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var d := Vector2(x - 15.5, y - 15.5).length() / 15.5
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	return ImageTexture.create_from_image(img)
