class_name FireVortexFx
extends Node3D
## The Inferno's whirling column of fire: three spiral flame ribbons winding up
## around the bender and a ring of standing flame at their base, spinning fast and
## widening as it builds; embers swirl up the column. grow() animates it in,
## release() flings it outward and burns it out.
##
##   var v := FireVortexFx.spawn(self, ground_pos, 3.0, 4.5)
##   v.release()        # the column bursts outward (the ring wave takes over)

var spiral: MeshInstance3D
var base_ring: MeshInstance3D
var spiral_mat: ShaderMaterial
var ring_mat: ShaderMaterial
var embers: GPUParticles3D
var radius := 3.0
var height := 4.5
var t := 0.0
var _released := -1.0


static func spawn(from: Node, ground: Vector3, p_radius: float = 3.0, p_height: float = 4.5) -> FireVortexFx:
	FxLib.set_cap(&"fire_vortex", 2)
	var v := FxLib.take(from, &"fire_vortex", FireVortexFx._make) as FireVortexFx
	v.global_position = ground
	v.global_basis = Basis.IDENTITY
	v.radius = p_radius
	v.height = p_height
	v.t = 0.0
	v._released = -1.0
	v.spiral_mat.set_shader_parameter(&"fade", 0.0)
	v.ring_mat.set_shader_parameter(&"fade", 0.0)
	v.spiral_mat.set_shader_parameter(&"opacity", 1.0)
	v.ring_mat.set_shader_parameter(&"opacity", 1.0)
	v.embers.restart()
	v.embers.emitting = FxLib.scale() > 0.3
	return v


static func _make() -> FireVortexFx:
	var v := FireVortexFx.new()
	v.name = "FireVortex"
	v.spiral = MeshInstance3D.new()
	# Helix along -Z: rotate so it winds up along +Y.
	v.spiral.mesh = FxMeshes.helix(3, 1.35, 0.55, 1.0, 0.5, 1.0, 40)
	v.spiral.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	# Flame ribbons that thin out near the camera (the column often wraps the player's camera).
	v.spiral_mat = ShaderMaterial.new()
	v.spiral_mat.shader = preload("res://src/fx/fire/fx_flame_spiral.gdshader")
	v.spiral_mat.set_shader_parameter(&"noise_tex", FxLib.noise_texture(&"smooth"))
	v.spiral.material_override = v.spiral_mat
	v.spiral.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	v.add_child(v.spiral)
	v.base_ring = MeshInstance3D.new()
	v.base_ring.mesh = FxMeshes.arc_wall(-PI, PI, 1.0, 48, 0.2)
	v.ring_mat = FireRingWave.wall_material()
	v.base_ring.material_override = v.ring_mat
	v.base_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	v.add_child(v.base_ring)
	var p := GPUParticles3D.new()
	p.amount = FxLib.amount(28)
	p.lifetime = 1.1
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-8, -1, -8), Vector3(16, 10, 16))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_radius = 1.6
	pm.emission_ring_inner_radius = 0.8
	pm.emission_ring_height = 0.5
	pm.direction = Vector3.UP
	pm.spread = 20.0
	pm.initial_velocity_min = 3.0
	pm.initial_velocity_max = 6.0
	pm.orbit_velocity_min = 0.6
	pm.orbit_velocity_max = 1.0
	pm.gravity = Vector3(0, 1.0, 0)
	pm.scale_min = 0.05
	pm.scale_max = 0.1
	pm.color = Color(1.0, 0.62, 0.2)
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
	s.albedo_color = Color(2.5, 2.5, 2.5)
	p.material_override = s
	p.position = Vector3.UP * 0.3
	v.embers = p
	v.add_child(p)
	return v


## The column bursts outward and burns out.
func release() -> void:
	if _released < 0.0:
		_released = 0.0
		embers.emitting = false


func fx_reset() -> void:
	_released = 10.0


func _process(delta: float) -> void:
	t += delta
	var grow := clampf(t / 0.45, 0.0, 1.0)
	grow = 1.0 - pow(1.0 - grow, 2.0)
	var r := lerpf(0.8, radius, grow)
	var h := lerpf(1.2, height, grow)
	if _released >= 0.0:
		_released += delta
		var k := clampf(_released / 0.35, 0.0, 1.0)
		r *= 1.0 + 1.6 * k
		h *= 1.0 - 0.6 * k
		spiral_mat.set_shader_parameter(&"fade", k)
		ring_mat.set_shader_parameter(&"fade", k)
		spiral_mat.set_shader_parameter(&"opacity", 1.0 - k * k)
		ring_mat.set_shader_parameter(&"opacity", 1.0 - k * k)
		if _released >= 0.5:
			FxLib.release(self)
			return
	# The helix mesh spans radius 0.55..1.0 over its length (unit): scale to the column
	# (its top stays a little inside the hit radius: it must not swallow the camera).
	spiral.scale = Vector3(r * 0.9, r * 0.9, h)
	spiral.rotation.y = 0.0
	rotation.y = -t * 7.5
	base_ring.scale = Vector3(r * 0.62, 0.9 + 0.2 * grow, r * 0.62)
