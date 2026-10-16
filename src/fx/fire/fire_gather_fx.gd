class_name FireGatherFx
extends Node3D
## Heat being drawn in (Blaze Charge): embers spawn on a shell around a point and
## accelerate INTO it, faster and denser as the charge builds - the reverse of a burst,
## so the build-up reads as gathering. Follows a node until stop(); pooled.
##
##   var g := FireGatherFx.attach(self, fireball_node, 1.1)
##   g.set_strength(charge)       # 0..1
##   g.stop()

var particles: GPUParticles3D
var pm: ParticleProcessMaterial
var follow: Node3D = null
var _dying := -1.0


static func attach(from: Node, node: Node3D, radius: float = 1.1) -> FireGatherFx:
	if node == null or not is_instance_valid(node):
		return null
	FxLib.set_cap(&"fire_gather", 3)
	var g := FxLib.take(from, &"fire_gather", FireGatherFx._make) as FireGatherFx
	g.follow = node
	g._dying = -1.0
	g.global_position = node.global_position
	g.pm.emission_sphere_radius = radius
	g.particles.amount_ratio = 0.3
	g.particles.restart()
	g.particles.emitting = true
	return g


static func _make() -> FireGatherFx:
	var g := FireGatherFx.new()
	g.name = "FireGather"
	var p := GPUParticles3D.new()
	p.amount = FxLib.amount(26)
	p.lifetime = 0.42
	p.local_coords = true
	p.visibility_aabb = AABB(Vector3(-3, -3, -3), Vector3(6, 6, 6))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
	pm.emission_sphere_radius = 1.1
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.3
	pm.radial_accel_min = -14.0
	pm.radial_accel_max = -9.0
	pm.tangential_accel_min = -2.0
	pm.tangential_accel_max = 2.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.04
	pm.scale_max = 0.08
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.4))
	sc.add_point(Vector2(0.7, 1.0))
	sc.add_point(Vector2(1.0, 0.0))
	var ct := CurveTexture.new()
	ct.curve = sc
	pm.scale_curve = ct
	var gr := Gradient.new()
	gr.set_color(0, Color(1.0, 0.45, 0.12, 0.0))
	gr.add_point(0.25, Color(1.0, 0.55, 0.18, 1.0))
	gr.set_color(gr.get_point_count() - 1, Color(1.0, 0.9, 0.55, 1.0))
	var gt := GradientTexture1D.new()
	gt.gradient = gr
	pm.color_ramp = gt
	p.process_material = pm
	p.draw_pass_1 = FireFx.quad()
	var s := StandardMaterial3D.new()
	s.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	s.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	s.billboard_keep_scale = true
	s.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	s.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	s.vertex_color_use_as_albedo = true
	s.albedo_texture = FxLib.soft_dot()
	s.albedo_color = Color(2.4, 2.4, 2.4)
	p.material_override = s
	g.particles = p
	g.pm = pm
	g.add_child(p)
	return g


func set_strength(k: float) -> void:
	particles.amount_ratio = clampf(0.25 + 0.75 * k, 0.05, 1.0)
	particles.speed_scale = 0.8 + 0.6 * k


func stop() -> void:
	if _dying < 0.0:
		_dying = 0.0
		particles.emitting = false
		follow = null


func fx_reset() -> void:
	_dying = 1.0
	follow = null


func _process(delta: float) -> void:
	if follow != null:
		if is_instance_valid(follow) and follow.is_inside_tree():
			global_position = follow.global_position
		else:
			stop()
	if _dying >= 0.0:
		_dying += delta
		if _dying >= 0.5:
			FxLib.release(self)
