class_name BodyFlames
extends Node3D
## Flames licking a burning character (FireStatus): three small banded flame
## sprites wrapped around the torso and legs plus rising embers, following the
## target until stop(). Pooled; the status caps how many burn visibly at once.
##
##   var f := BodyFlames.spawn(target)     # follows target (Node3D)
##   f.stop()                              # shrinks out, back to the pool

const OFFSETS: Array[Vector3] = [Vector3(0.16, 1.15, 0.05), Vector3(-0.18, 0.85, -0.04), Vector3(0.05, 0.45, 0.12)]

var sprites: Array[MeshInstance3D] = []
var mats: Array[ShaderMaterial] = []
var embers: GPUParticles3D
var target: Node3D = null
var _t := 0.0
var _dying := -1.0


static func spawn(p_target: Node3D) -> BodyFlames:
	if p_target == null or not is_instance_valid(p_target) or not p_target.is_inside_tree():
		return null
	var f := FxLib.take(p_target, &"body_flames", BodyFlames._make) as BodyFlames
	f.target = p_target
	f._t = 0.0
	f._dying = -1.0
	f.global_position = p_target.global_position
	for m in f.mats:
		m.set_shader_parameter(&"opacity", 1.0)
		m.set_shader_parameter(&"age", 0.0)
	f.embers.restart()
	f.embers.emitting = FxLib.scale() > 0.3
	return f


static func _make() -> BodyFlames:
	var f := BodyFlames.new()
	f.name = "BodyFlames"
	for i in OFFSETS.size():
		var m := MeshInstance3D.new()
		m.mesh = FireFx.quad()
		var mat := FireFx.flame_material(0.23 * i + 0.1, 0.85)
		mat.set_shader_parameter(&"scroll_speed", 2.4)
		m.material_override = mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.position = OFFSETS[i]
		var s := 0.55 - 0.08 * i
		m.scale = Vector3(s, s * 1.4, s)
		f.add_child(m)
		f.sprites.append(m)
		f.mats.append(mat)
	var p := GPUParticles3D.new()
	p.amount = FxLib.amount(10)
	p.lifetime = 0.8
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-3, -1, -3), Vector3(6, 6, 6))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.25, 0.6, 0.25)
	pm.direction = Vector3.UP
	pm.spread = 25.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 1.8
	pm.gravity = Vector3(0, 1.2, 0)
	pm.scale_min = 0.04
	pm.scale_max = 0.08
	pm.color = Color(1.0, 0.6, 0.2)
	p.process_material = pm
	p.position = Vector3(0, 0.9, 0)
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
	f.embers = p
	f.add_child(p)
	return f


func stop() -> void:
	if _dying < 0.0:
		_dying = 0.0
		embers.emitting = false


func fx_reset() -> void:
	_dying = 1.0
	target = null


func _process(delta: float) -> void:
	_t += delta
	if target != null and is_instance_valid(target) and target.is_inside_tree():
		global_position = target.global_position
		# Face the flames' offsets the way the body faces.
		global_basis = Basis(Vector3.UP, target.global_rotation.y)
	elif _dying < 0.0:
		stop()
	# Flicker the size so the flames lick rather than sit.
	for i in sprites.size():
		var k := 0.85 + 0.2 * sin(_t * (9.0 + i * 2.3) + i)
		var s := (0.55 - 0.08 * i) * k
		sprites[i].scale = Vector3(s, s * 1.45, s)
	if _dying >= 0.0:
		_dying += delta
		var a := clampf(1.0 - _dying / 0.3, 0.0, 1.0)
		for m in mats:
			m.set_shader_parameter(&"opacity", a)
			m.set_shader_parameter(&"age", 1.0 - a)
		if _dying >= 0.9:
			target = null
			FxLib.release(self)
