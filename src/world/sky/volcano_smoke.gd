class_name VolcanoSmoke
extends GPUParticles3D
## The active Fire Nation volcano's smoke plume (POI fn_burning_maw): large billboard puffs
## rising from the crater, bending with the wind, lit by the sky and glowing from the lava at
## the vent. Visible across the archipelago; budgeted by Settings.effects_scale().

const SHADER := preload("res://assets/shaders/world/smoke_plume.gdshader")
const CLOUD_TEX := preload("res://assets/textures/world/clouds.png")
const FALLBACK_VENT := Vector3(-1735.0, 342.0, 3485.0)

var vent := FALLBACK_VENT
var _process_mat: ParticleProcessMaterial


func _ready() -> void:
	name = "VolcanoSmoke"
	var poi := WorldData.get_poi(&"fn_burning_maw")
	if not poi.is_empty():
		vent = poi["position"]
	global_position = vent + Vector3(0, 6, 0)
	_process_mat = ParticleProcessMaterial.new()
	_process_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	_process_mat.emission_sphere_radius = 40.0
	_process_mat.direction = Vector3(0, 1, 0)
	_process_mat.spread = 18.0
	_process_mat.initial_velocity_min = 7.0
	_process_mat.initial_velocity_max = 11.0
	_process_mat.gravity = Vector3(0, 0.6, 0)
	_process_mat.damping_min = 0.08
	_process_mat.damping_max = 0.15
	_process_mat.scale_min = 0.8
	_process_mat.scale_max = 1.3
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.35))
	curve.add_point(Vector2(1, 1.6))
	var ct := CurveTexture.new()
	ct.curve = curve
	_process_mat.scale_curve = ct
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.0))
	g.add_point(0.08, Color(1, 1, 1, 0.9))
	g.add_point(0.7, Color(1, 1, 1, 0.55))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	_process_mat.color_ramp = gt
	process_material = _process_mat
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter(&"cloud_tex", CLOUD_TEX)
	var quad := QuadMesh.new()
	quad.size = Vector2(120, 120)
	quad.material = m
	draw_pass_1 = quad
	lifetime = 55.0
	preprocess = 55.0
	local_coords = false
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visibility_aabb = AABB(Vector3(-900, -50, -900), Vector3(1800, 1300, 1800))
	sorting_offset = 0.0
	draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	Events.graphics_settings_changed.connect(_apply_budget)
	_apply_budget()
	emitting = WorldData.has_world_data()


func _apply_budget() -> void:
	amount = maxi(int(90.0 * Settings.effects_scale()), 32)


## Bends the plume with the wind (x/z m/s).
func set_wind(wind: Vector2) -> void:
	_process_mat.gravity = Vector3(wind.x * 0.35, 0.6, wind.y * 0.35)
