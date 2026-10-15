class_name SkyController
extends Node3D
## Owns the world's WorldEnvironment (sky shader, fog, ambient, exposure, grading) and the
## sun + moon DirectionalLight3Ds, and applies an atmosphere state (AtmospherePalettes) plus
## weather modifiers to them every frame. Honours Settings.configure_environment/configure_sun
## and re-applies on Events.graphics_settings_changed.

const SKY_SHADER := preload("res://assets/shaders/world/sky.gdshader")
const CLOUD_TEX := preload("res://assets/textures/world/clouds.png")
const MOON_LIGHT_COLOR := Color(0.62, 0.72, 1.0)

var environment: Environment
var world_environment: WorldEnvironment
var sky_material: ShaderMaterial
var sun: DirectionalLight3D
var moon: DirectionalLight3D
## Last applied, fully resolved state (palette + weather) for queries/tests.
var current: Dictionary = {}

var _cloud_offset := Vector2.ZERO
var _sky_time := 0.0
var _sky_accum := 0.0
var _sun_up := true


func _ready() -> void:
	_build()
	if not Events.graphics_settings_changed.is_connected(_on_graphics_changed):
		Events.graphics_settings_changed.connect(_on_graphics_changed)


func _build() -> void:
	sky_material = ShaderMaterial.new()
	sky_material.shader = SKY_SHADER
	sky_material.set_shader_parameter(&"cloud_tex", CLOUD_TEX)
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	sky.radiance_size = Sky.RADIANCE_SIZE_64 if Settings.detail_level() <= 1 else Sky.RADIANCE_SIZE_128
	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_sky_contribution = 0.55
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_white = 6.0
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	environment.fog_aerial_perspective = 0.55
	environment.fog_sky_affect = 0.0
	environment.fog_sun_scatter = 0.12
	environment.adjustment_enabled = true
	environment.glow_intensity = 0.55
	environment.glow_strength = 0.9
	environment.glow_bloom = 0.02
	environment.glow_hdr_threshold = 1.1
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	environment.ssao_radius = 1.6
	environment.ssao_intensity = 1.4
	environment.volumetric_fog_density = 0.0
	environment.volumetric_fog_length = 96.0
	environment.volumetric_fog_sky_affect = 0.0
	environment.volumetric_fog_detail_spread = 2.0
	environment.volumetric_fog_gi_inject = 0.0
	world_environment = WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_environment.environment = environment
	add_child(world_environment)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_angular_distance = 0.6
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 1.2
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_fade_start = 0.85
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(sun)
	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = MOON_LIGHT_COLOR
	moon.light_angular_distance = 0.4
	moon.shadow_bias = 0.04
	moon.shadow_normal_bias = 1.2
	moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(moon)
	_apply_settings()


func _on_graphics_changed() -> void:
	_apply_settings()


func _apply_settings() -> void:
	Settings.configure_environment(environment)
	Settings.configure_sun(sun)
	var shadow_on := sun.shadow_enabled
	sun.shadow_enabled = shadow_on and _sun_up
	moon.shadow_enabled = shadow_on and not _sun_up
	moon.directional_shadow_max_distance = sun.directional_shadow_max_distance
	moon.directional_shadow_mode = sun.directional_shadow_mode
	if environment.sky:
		environment.sky.radiance_size = Sky.RADIANCE_SIZE_64 if Settings.detail_level() <= 1 else Sky.RADIANCE_SIZE_128


## Applies a palette state and weather modifiers. `mods` keys (all optional):
## coverage, cloud_darkness, sun_mult, fog_mult, fog_tint (Color), fog_tint_amount, ambient_mult,
## saturation_mult, haze_add, exposure_mult, fog_height_density, volumetric (density),
## cirrus, cloud_speed. `wind` is the x/z wind velocity (m/s) moving the clouds.
func apply(state: Dictionary, sun_dir: Vector3, moon_dir: Vector3, moon_phase: float, hour: float,
		mods: Dictionary, wind: Vector2, delta: float) -> void:
	var s := state.duplicate()
	var fog_col: Color = s[&"fog"]
	if mods.has(&"fog_tint"):
		fog_col = fog_col.lerp(mods[&"fog_tint"], float(mods.get(&"fog_tint_amount", 0.0)))
	s[&"fog"] = fog_col
	s[&"horizon"] = (s[&"horizon"] as Color).lerp(fog_col, float(mods.get(&"fog_tint_amount", 0.0)) * 0.7)
	s[&"coverage"] = maxf(float(s[&"coverage"]), float(mods.get(&"coverage", 0.0)))
	s[&"fog_density"] = float(s[&"fog_density"]) * float(mods.get(&"fog_mult", 1.0))
	s[&"sun_energy"] = float(s[&"sun_energy"]) * float(mods.get(&"sun_mult", 1.0))
	s[&"moon_energy"] = float(s[&"moon_energy"]) * float(mods.get(&"sun_mult", 1.0))
	s[&"ambient_energy"] = float(s[&"ambient_energy"]) * float(mods.get(&"ambient_mult", 1.0))
	s[&"saturation"] = float(s[&"saturation"]) * float(mods.get(&"saturation_mult", 1.0))
	s[&"haze"] = clampf(float(s[&"haze"]) + float(mods.get(&"haze_add", 0.0)), 0.0, 1.0)
	s[&"exposure"] = float(s[&"exposure"]) * float(mods.get(&"exposure_mult", 1.0))
	s[&"stars"] = float(s[&"stars"]) * (1.0 - smoothstep(0.55, 0.95, float(s[&"coverage"])))
	current = s
	var cloud_dark := float(mods.get(&"cloud_darkness", 0.0))

	# --- lights ---
	var sun_vis := smoothstep(-0.06, 0.04, sun_dir.y)
	var moon_vis := smoothstep(-0.05, 0.08, moon_dir.y) * (1.0 - smoothstep(-0.10, 0.02, sun_dir.y))
	var sun_up_now := sun_dir.y > -0.02
	if sun_up_now != _sun_up:
		_sun_up = sun_up_now
		_apply_settings()
	_orient(sun, sun_dir)
	_orient(moon, moon_dir)
	sun.light_color = s[&"sun"]
	sun.light_energy = float(s[&"sun_energy"]) * sun_vis
	sun.visible = sun.light_energy > 0.001
	moon.light_energy = float(s[&"moon_energy"]) * moon_vis * (0.35 + 0.65 * (1.0 - absf(moon_phase - 0.5) * 2.0))
	moon.visible = moon.light_energy > 0.001

	# --- environment ---
	var env := environment
	env.ambient_light_color = s[&"ambient"]
	env.ambient_light_energy = float(s[&"ambient_energy"])
	env.fog_light_color = fog_col
	env.fog_density = float(s[&"fog_density"])
	env.fog_height = float(mods.get(&"fog_height", 40.0))
	env.fog_height_density = float(s[&"fog_height_density"]) + float(mods.get(&"fog_height_density", 0.0))
	env.tonemap_exposure = float(s[&"exposure"])
	env.adjustment_saturation = float(s[&"saturation"])
	if env.volumetric_fog_enabled:
		env.volumetric_fog_density = float(mods.get(&"volumetric", 0.004))
		env.volumetric_fog_albedo = fog_col
	env.glow_intensity = 0.55 if sun_vis > 0.5 else 0.8

	# --- sky ---
	var cloud_speed := float(mods.get(&"cloud_speed", 1.0))
	_cloud_offset += wind * delta * 0.0009 * cloud_speed
	_sky_time += delta
	var m := sky_material
	m.set_shader_parameter(&"zenith_color", s[&"zenith"])
	m.set_shader_parameter(&"horizon_color", s[&"horizon"])
	m.set_shader_parameter(&"ground_color", s[&"ground"])
	m.set_shader_parameter(&"sun_dir", sun_dir)
	m.set_shader_parameter(&"sun_color", (s[&"sun"] as Color).lerp(Color(1, 1, 1), 0.25))
	m.set_shader_parameter(&"sun_visible", sun_vis * (1.0 - smoothstep(0.6, 1.0, float(s[&"coverage"])) * 0.85))
	m.set_shader_parameter(&"sun_glow_color", s[&"glow"])
	m.set_shader_parameter(&"sun_glow", float(s[&"glow_strength"]) * (1.0 - cloud_dark * 0.7))
	m.set_shader_parameter(&"moon_dir", moon_dir)
	m.set_shader_parameter(&"moon_visible", moon_vis * (1.0 - smoothstep(0.6, 1.0, float(s[&"coverage"])) * 0.9))
	m.set_shader_parameter(&"moon_phase", moon_phase)
	m.set_shader_parameter(&"stars", float(s[&"stars"]))
	m.set_shader_parameter(&"star_rotation", Basis(Vector3(0.0, cos(deg_to_rad(40.0)), -sin(deg_to_rad(40.0))).normalized(), hour / 24.0 * TAU))
	m.set_shader_parameter(&"haze", float(s[&"haze"]))
	m.set_shader_parameter(&"haze_color", fog_col)
	m.set_shader_parameter(&"cloud_coverage", float(s[&"coverage"]))
	m.set_shader_parameter(&"cloud_lit", s[&"cloud_lit"])
	m.set_shader_parameter(&"cloud_shade", s[&"cloud_shade"])
	m.set_shader_parameter(&"cloud_darkness", cloud_dark)
	m.set_shader_parameter(&"cirrus", float(mods.get(&"cirrus", 0.35)))
	m.set_shader_parameter(&"cloud_offset", _cloud_offset)
	m.set_shader_parameter(&"sky_time", _sky_time)

	# --- shader globals ---
	var sun_lin := (s[&"sun"] as Color).srgb_to_linear() * (float(s[&"sun_energy"]) * sun_vis)
	WorldShaderGlobals.set_value(&"world_sun_direction", sun_dir)
	WorldShaderGlobals.set_value(&"world_sun_color", sun_lin)
	WorldShaderGlobals.set_value(&"world_moon_direction", moon_dir)
	WorldShaderGlobals.set_value(&"world_sky_zenith", (s[&"zenith"] as Color).srgb_to_linear())
	WorldShaderGlobals.set_value(&"world_sky_horizon", (s[&"horizon"] as Color).srgb_to_linear())
	WorldShaderGlobals.set_value(&"world_fog_color", fog_col.srgb_to_linear())
	WorldShaderGlobals.set_value(&"world_time_of_day", hour)


static func _orient(light: DirectionalLight3D, towards: Vector3) -> void:
	var d := -towards.normalized()
	var up := Vector3.UP if absf(d.y) < 0.98 else Vector3.FORWARD
	light.global_transform = Transform3D(Basis.looking_at(d, up), light.global_position)
