class_name WeatherParticles
extends Node3D
## Precipitation around the camera: one GPUParticles3D per kind (snow, blizzard, rain, ash),
## each a box of particles wrapped around the camera by a custom particle shader
## (assets/shaders/world/precipitation.gdshader). Intensity 0..1 per kind maps to
## `amount_ratio`; counts are budgeted by Settings.effects_scale().

const PROCESS_SHADER := preload("res://assets/shaders/world/precipitation.gdshader")
const DRAW_SHADER := preload("res://assets/shaders/world/precipitation_draw.gdshader")

## kind -> {amount, box, fall, follow, turbulence, streak, size_min, size_max, tint, softness, opacity, embers, lifetime}
const KINDS := {
	&"snow": {"amount": 7000, "box": Vector3(46, 26, 46), "fall": 1.1, "follow": 0.9, "turbulence": 0.55,
			"streak": 0.0, "size_min": 0.025, "size_max": 0.055, "tint": Color(1, 1, 1, 0.95), "softness": 0.6, "opacity": 0.95},
	&"blizzard": {"amount": 14000, "box": Vector3(34, 20, 34), "fall": 2.6, "follow": 1.0, "turbulence": 1.4,
			"streak": 0.022, "size_min": 0.02, "size_max": 0.045, "tint": Color(1, 1, 1, 0.8), "softness": 0.7, "opacity": 0.8},
	&"rain": {"amount": 9000, "box": Vector3(34, 22, 34), "fall": 10.5, "follow": 0.3, "turbulence": 0.1,
			"streak": 0.05, "size_min": 0.008, "size_max": 0.012, "tint": Color(0.82, 0.88, 0.95, 0.45), "softness": 0.4, "opacity": 0.6},
	&"ash": {"amount": 3600, "box": Vector3(50, 28, 50), "fall": 0.55, "follow": 0.6, "turbulence": 0.9,
			"streak": 0.0, "size_min": 0.03, "size_max": 0.07, "tint": Color(0.28, 0.26, 0.25, 0.9), "softness": 0.5,
			"opacity": 0.9, "embers": 0.035},
}

var systems: Dictionary = {}
var _intensity: Dictionary = {}


func _ready() -> void:
	for kind: StringName in KINDS:
		systems[kind] = _make_system(kind, KINDS[kind])
		_intensity[kind] = 0.0
	Events.graphics_settings_changed.connect(_apply_budget)
	_apply_budget()


func _make_system(kind: StringName, spec: Dictionary) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = String(kind).capitalize()
	var pm := ShaderMaterial.new()
	pm.shader = PROCESS_SHADER
	WorldData.apply_height_uniforms(pm)
	pm.set_shader_parameter(&"has_world", WorldData.has_world_data())
	pm.set_shader_parameter(&"box_size", spec["box"])
	pm.set_shader_parameter(&"fall_speed", spec["fall"])
	pm.set_shader_parameter(&"wind_follow", spec["follow"])
	pm.set_shader_parameter(&"turbulence", spec["turbulence"])
	pm.set_shader_parameter(&"streak", spec["streak"])
	pm.set_shader_parameter(&"size_min", spec["size_min"])
	pm.set_shader_parameter(&"size_max", spec["size_max"])
	pm.set_shader_parameter(&"tint", spec["tint"])
	pm.set_shader_parameter(&"ember_fraction", spec.get("embers", 0.0))
	p.process_material = pm
	var dm := ShaderMaterial.new()
	dm.shader = DRAW_SHADER
	dm.set_shader_parameter(&"softness", spec["softness"])
	dm.set_shader_parameter(&"opacity", spec["opacity"])
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	quad.material = dm
	p.draw_pass_1 = quad
	p.local_coords = false
	# continuous respawn (no synchronous pops); preprocess fills the box instantly on restart
	p.lifetime = 6.0
	p.preprocess = 6.0
	p.explosiveness = 0.0
	p.fixed_fps = 0
	p.interpolate = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var b: Vector3 = spec["box"]
	p.visibility_aabb = AABB(-b * 0.5 - Vector3(2, 2, 2), b + Vector3(4, 4, 4))
	p.emitting = false
	p.amount_ratio = 0.0
	add_child(p)
	return p


func _apply_budget() -> void:
	var scale := Settings.effects_scale()
	for kind: StringName in systems:
		var p: GPUParticles3D = systems[kind]
		var n := maxi(int(float(KINDS[kind]["amount"]) * scale), 64)
		if p.amount != n:
			p.amount = n


## Intensity 0..1 of each precipitation kind (missing kinds = 0).
func set_intensities(values: Dictionary) -> void:
	for kind: StringName in systems:
		var v := clampf(float(values.get(kind, 0.0)), 0.0, 1.0)
		_intensity[kind] = v
		var p: GPUParticles3D = systems[kind]
		p.amount_ratio = v
		var on := v > 0.001
		if on and not p.emitting:
			p.emitting = true
			p.restart()
		elif not on and p.emitting:
			p.emitting = false


func get_intensity(kind: StringName) -> float:
	return float(_intensity.get(kind, 0.0))


## Keeps the particle boxes around the camera.
func follow(cam_pos: Vector3) -> void:
	global_position = cam_pos
	for kind: StringName in systems:
		var p: GPUParticles3D = systems[kind]
		if p.emitting:
			(p.process_material as ShaderMaterial).set_shader_parameter(&"camera_pos", cam_pos)
