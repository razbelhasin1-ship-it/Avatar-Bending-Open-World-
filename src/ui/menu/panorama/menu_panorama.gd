class_name MenuPanorama
extends Node3D
## Living 3D backdrop of the main menu, built entirely in code (needs no world data):
## golden-hour painterly sky (world sky shader), layered mountain ranges with atmospheric
## perspective, a sea with moving water and a sun glitter path, drifting mist banks and sky
## clouds, crepuscular rays, petals in the wind, distant birds and a slow camera drift.
## Hints of the four nations: an Air Temple on a far peak, ice spires with a glint, a
## smoking volcano and a great wall along a ridge.
##
## Honours Settings (environment toggles, shadows, effects budget) and re-applies on
## Events.graphics_settings_changed.

const SKY_SHADER := preload("res://assets/shaders/world/sky.gdshader")
const CLOUD_TEX := preload("res://assets/textures/world/clouds.png")
const NOISE_TEX := preload("res://assets/textures/world/noise.png")
const WATER_NRM := preload("res://assets/textures/world/water_nrm.png")
const TERRAIN_SHADER := preload("res://src/ui/shaders/panorama_terrain.gdshader")
const SEA_SHADER := preload("res://src/ui/shaders/panorama_sea.gdshader")
const MIST_SHADER := preload("res://src/ui/shaders/panorama_mist.gdshader")
const PETAL_SHADER := preload("res://src/ui/shaders/petal.gdshader")
const RAYS_SHADER := preload("res://src/ui/shaders/god_rays.gdshader")

## Direction toward the sun (low, right of centre: back-lit ranges, glitter path).
const SUN_DIR := Vector3(0.262, 0.115, -0.958)
const CAM_BASE := Vector3(0.0, 26.0, 40.0)

## Seconds of drift already elapsed (lets screenshots/tests pick a moment).
var time := 18.0
## Drift speed multiplier (0 freezes the camera).
var drift_speed := 1.0

var camera: Camera3D
var sun: DirectionalLight3D
var environment: Environment
var sky_material: ShaderMaterial
var ranges: Array[PanoramaRange] = []
var range_nodes: Array[MeshInstance3D] = []
var sea: MeshInstance3D
var petals: GPUParticles3D
var plume: GPUParticles3D
var glint: Sprite3D
var rays_rect: ColorRect
var landmarks: Dictionary = {}

var _rays_mat: ShaderMaterial
var _cloud_offset := Vector2.ZERO
var _mist: Array[MeshInstance3D] = []


func _ready() -> void:
	_build_environment()
	_build_camera()
	_build_sea()
	_build_ranges()
	_build_landmarks()
	_build_mist()
	_build_life()
	_build_rays()
	Events.graphics_settings_changed.connect(_apply_settings)
	_apply_settings()
	_update_camera(0.0)


func _process(delta: float) -> void:
	time += delta * drift_speed
	_update_camera(delta)
	_cloud_offset += Vector2(0.0022, 0.0006) * delta
	sky_material.set_shader_parameter(&"cloud_offset", _cloud_offset)
	sky_material.set_shader_parameter(&"sky_time", time)
	_update_glint()
	_update_rays()


# --- Build -------------------------------------------------------------------------------

func _build_environment() -> void:
	sky_material = ShaderMaterial.new()
	sky_material.shader = SKY_SHADER
	var p := {
		&"zenith_color": Color(0.14, 0.27, 0.52), &"horizon_color": Color(0.98, 0.72, 0.48),
		&"ground_color": Color(0.22, 0.27, 0.36), &"gradient_curve": 0.42,
		&"sun_dir": SUN_DIR.normalized(), &"sun_color": Color(1.0, 0.86, 0.62), &"sun_visible": 1.0,
		&"sun_glow_color": Color(1.0, 0.55, 0.26), &"sun_glow": 0.62, &"sun_size": 0.028,
		&"haze": 0.32, &"haze_color": Color(0.96, 0.74, 0.56), &"cloud_tex": CLOUD_TEX,
		&"cloud_coverage": 0.40, &"cloud_softness": 0.2, &"cloud_lit": Color(1.0, 0.84, 0.66),
		&"cloud_shade": Color(0.44, 0.42, 0.58), &"cirrus": 0.6, &"stars": 0.0, &"aurora": 0.0,
		&"moon_visible": 0.0, &"sky_energy": 1.0,
	}
	for k: StringName in p:
		sky_material.set_shader_parameter(k, p[k])
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.75
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 0.96
	environment.tonemap_white = 5.0
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	environment.fog_light_color = Color(0.56, 0.62, 0.76)
	environment.fog_light_energy = 1.0
	environment.fog_sun_scatter = 0.28
	environment.fog_density = 0.00019
	environment.fog_aerial_perspective = 0.2
	environment.fog_sky_affect = 0.0
	environment.fog_height = 12.0
	environment.fog_height_density = 0.0025
	environment.glow_intensity = 0.65
	environment.glow_bloom = 0.08
	environment.glow_hdr_threshold = 1.1
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 1.16
	environment.adjustment_contrast = 1.1
	var we := WorldEnvironment.new()
	we.environment = environment
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.82, 0.6)
	sun.light_energy = 1.6
	add_child(sun)
	sun.look_at_from_position(Vector3.ZERO, -SUN_DIR, Vector3.UP)


func _build_camera() -> void:
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = 50.0
	camera.near = 0.5
	camera.far = 12000.0
	add_child(camera)
	camera.make_current()


func _build_sea() -> void:
	sea = MeshInstance3D.new()
	sea.name = "Sea"
	var pm := PlaneMesh.new()
	pm.size = Vector2(16000, 9000)
	pm.subdivide_width = 8
	pm.subdivide_depth = 8
	sea.mesh = pm
	sea.position = Vector3(0, 0, -4300)
	var m := ShaderMaterial.new()
	m.shader = SEA_SHADER
	m.set_shader_parameter(&"normal_tex", WATER_NRM)
	sea.material_override = m
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sea)


func _range_material(cfg: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TERRAIN_SHADER
	m.set_shader_parameter(&"noise_tex", NOISE_TEX)
	m.set_shader_parameter(&"sun_dir", SUN_DIR)
	for k: String in cfg:
		m.set_shader_parameter(StringName(k), cfg[k])
	return m


func _build_ranges() -> void:
	# [range config, material overrides]; near wings frame a gap to the open sea.
	var specs := [
		[{"x0": -880.0, "x1": -60.0, "z_front": -220.0, "depth": 320.0, "base_height": 22.0, "noise_height": 70.0, "roughness": 0.45,
				"peaks": [{"x": -500.0, "h": 85.0, "w": 120.0}, {"x": -250.0, "h": 30.0, "w": 50.0}], "crest": 0.42, "seed_value": 11, "res_x": 200, "res_z": 50},
				{"snow_line": 900.0, "layer_haze": 0.0, "grass_color": Color(0.17, 0.27, 0.16), "rock_color": Color(0.30, 0.27, 0.25), "rim_strength": 0.9}],
		[{"x0": 200.0, "x1": 1250.0, "z_front": -320.0, "depth": 340.0, "base_height": 12.0, "noise_height": 50.0, "roughness": 0.45,
				"peaks": [{"x": 520.0, "h": 38.0, "w": 120.0}], "crest": 0.4, "seed_value": 12, "res_x": 200, "res_z": 50},
				{"snow_line": 900.0, "layer_haze": 0.02, "grass_color": Color(0.18, 0.28, 0.17), "rock_color": Color(0.31, 0.28, 0.26), "rim_strength": 0.9}],
		[{"x0": -1800.0, "x1": 260.0, "z_front": -640.0, "depth": 480.0, "base_height": 40.0, "noise_height": 130.0, "roughness": 0.35,
				"peaks": [{"x": -640.0, "h": 70.0, "w": 260.0}], "crest": 0.45, "seed_value": 21, "res_x": 220},
				{"snow_line": 900.0, "layer_haze": 0.06, "grass_color": Color(0.24, 0.35, 0.22), "rock_color": Color(0.38, 0.34, 0.31)}],
		[{"x0": -500.0, "x1": 2700.0, "z_front": -1250.0, "depth": 720.0, "base_height": 60.0, "noise_height": 240.0, "roughness": 0.3,
				"peaks": [{"x": 820.0, "h": 300.0, "w": 240.0}, {"x": 1550.0, "h": 140.0, "w": 300.0}], "crest": 0.45, "seed_value": 31, "res_x": 240},
				{"snow_line": 300.0, "snow_soft": 35.0, "layer_haze": 0.1}],
		[{"x0": -3800.0, "x1": 4000.0, "z_front": -2500.0, "depth": 1200.0, "base_height": 90.0, "noise_height": 400.0, "roughness": 0.25,
				"peaks": [{"x": 600.0, "h": -260.0, "w": 700.0}, {"x": 2400.0, "h": 200.0, "w": 500.0}], "crest": 0.5, "seed_value": 41, "res_x": 260},
				{"snow_line": 400.0, "snow_soft": 50.0, "layer_haze": 0.22}],
	]
	for spec: Array in specs:
		var r := PanoramaRange.new(spec[0])
		ranges.append(r)
		var mi := MeshInstance3D.new()
		mi.name = "Range%d" % ranges.size()
		mi.mesh = r.build_mesh()
		mi.material_override = _range_material(spec[1])
		add_child(mi)
		range_nodes.append(mi)


func _build_landmarks() -> void:
	var mat := PanoramaLandmarks.material()
	# Air Temple crowning the tallest peak of the fourth range.
	var temple_peak := ranges[3].crest_point(820.0)
	var temple := MeshInstance3D.new()
	temple.name = "AirTemple"
	temple.mesh = PanoramaLandmarks.air_temple(1.5)
	temple.material_override = mat
	temple.position = temple_peak + Vector3(0, -12, 0)
	temple.rotation.y = 0.4
	add_child(temple)
	landmarks["air_temple"] = temple
	# Great wall snaking along the third range's crest.
	var pts := PackedVector3Array()
	var x := -1350.0
	while x <= 120.0:
		var v := ranges[2].crest - 0.08
		pts.append(Vector3(x, ranges[2].height_at(x, v), ranges[2].z_front - v * ranges[2].depth))
		x += 22.0
	var wall := MeshInstance3D.new()
	wall.name = "GreatWall"
	wall.mesh = PanoramaLandmarks.great_wall(pts, 15.0, 8.0, 8)
	wall.material_override = mat
	add_child(wall)
	landmarks["great_wall"] = wall
	# Ice spires floating in the open water between the near wings.
	var ice := MeshInstance3D.new()
	ice.name = "IceSpires"
	ice.mesh = PanoramaLandmarks.ice_spires(5)
	ice.material_override = PanoramaLandmarks.ice_material()
	ice.position = Vector3(70, 0, -500)
	ice.scale = Vector3.ONE * 1.4
	ice.rotation.y = 0.6
	add_child(ice)
	landmarks["ice"] = ice
	glint = Sprite3D.new()
	glint.name = "IceGlint"
	glint.texture = _make_glint_texture()
	glint.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	glint.shaded = false
	glint.no_depth_test = false
	glint.pixel_size = 0.5
	glint.modulate = Color(1.0, 0.97, 0.9, 0.0)
	glint.position = ice.position + Vector3(3, 62, 0)
	add_child(glint)
	landmarks["glint"] = glint
	# Fire Nation volcano far to the left with a smoking crater.
	var volcano := MeshInstance3D.new()
	volcano.name = "Volcano"
	volcano.mesh = PanoramaRange.build_cone(2100.0, 980.0, 140.0, 7)
	volcano.material_override = _range_material({"snow_line": 5000.0, "layer_haze": 0.0,
			"grass_color": Color(0.24, 0.20, 0.20), "rock_color": Color(0.20, 0.16, 0.16), "rim_color": Color(1.0, 0.5, 0.25), "rim_strength": 1.2})
	volcano.position = Vector3(520, -40, -4300)
	add_child(volcano)
	landmarks["volcano"] = volcano
	# glowing crater so the cone reads as a volcano through the haze
	var crater := Sprite3D.new()
	crater.name = "CraterGlow"
	crater.texture = BackdropPainter.glow_texture()
	crater.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	crater.shaded = false
	crater.pixel_size = 2.4
	crater.modulate = Color(1.0, 0.42, 0.12, 0.9)
	crater.position = volcano.position + Vector3(0, 940, 0)
	add_child(crater)
	landmarks["crater"] = crater
	plume = PanoramaLandmarks.smoke_plume(volcano.position + Vector3(0, 930, 0), SUN_DIR, Settings.effects_scale())
	var pmat := (plume.draw_pass_1 as QuadMesh).material as ShaderMaterial
	pmat.set_shader_parameter(&"alpha_scale", 1.35)
	pmat.set_shader_parameter(&"dark_color", Color(0.20, 0.16, 0.17))
	add_child(plume)
	landmarks["plume"] = plume
	# Pine forests on the near ranges give scale and depth.
	var budget := Settings.vegetation_density()
	for spec: Array in [[0, 520, 140.0, 3, 1.0], [1, 480, 150.0, 4, 1.0], [2, 600, 260.0, 5, 1.8]]:
		var forest := PanoramaLandmarks.pine_forest(ranges[spec[0]], int(spec[1] * minf(budget, 1.0)), spec[2], spec[3], spec[4])
		forest.name = "Forest%d" % spec[0]
		add_child(forest)


func _build_mist() -> void:
	# [z, y, width, height, opacity, seed]
	var cards := [
		[-620.0, 0.0, 2600.0, 46.0, 0.32, 1.3], [-1180.0, 8.0, 4200.0, 150.0, 0.6, 4.1],
		[-2350.0, 20.0, 7000.0, 260.0, 0.55, 7.7], [-3900.0, 60.0, 11000.0, 420.0, 0.5, 2.2],
	]
	for c: Array in cards:
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(c[2], c[3])
		mi.mesh = q
		var m := ShaderMaterial.new()
		m.shader = MIST_SHADER
		m.set_shader_parameter(&"cloud_tex", CLOUD_TEX)
		m.set_shader_parameter(&"opacity", c[4])
		m.set_shader_parameter(&"seed", c[5])
		m.set_shader_parameter(&"tiling", float(c[2]) / 1400.0)
		m.set_shader_parameter(&"drift", 0.006)
		mi.material_override = m
		mi.position = Vector3(0, float(c[1]) + float(c[3]) * 0.5, c[0])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_mist.append(mi)


func _build_life() -> void:
	# Petals drifting through the foreground on the breeze (follow the camera).
	petals = GPUParticles3D.new()
	petals.name = "Petals"
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(26, 12, 16)
	pm.direction = Vector3(1, -0.2, 0.15)
	pm.spread = 25.0
	pm.initial_velocity_min = 1.8
	pm.initial_velocity_max = 3.6
	pm.gravity = Vector3(0.5, -0.35, 0.0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.4
	pm.turbulence_noise_scale = 6.0
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.15
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	pm.angular_velocity_min = -90.0
	pm.angular_velocity_max = 90.0
	pm.scale_min = 0.3
	pm.scale_max = 0.55
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.58, 0.68))
	g.add_point(0.5, Color(1.0, 0.76, 0.80))
	g.set_color(g.get_point_count() - 1, Color(0.95, 0.46, 0.56))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_initial_ramp = gt
	petals.process_material = pm
	var m := ShaderMaterial.new()
	m.shader = PETAL_SHADER
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	quad.material = m
	petals.draw_pass_1 = quad
	petals.lifetime = 16.0
	petals.preprocess = 16.0
	petals.local_coords = false
	petals.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	petals.visibility_aabb = AABB(Vector3(-80, -40, -80), Vector3(160, 80, 160))
	petals.position = Vector3(-12, -3, -22)
	camera.add_child(petals)
	# Birds: gulls over the open water, crows along the wall.
	var gulls := BirdFlock.create(&"gull", 9, Vector3(60, 0, -210), 70.0, 34.0, 5)
	gulls.max_distance = 2500.0
	add_child(gulls)
	var crows := BirdFlock.create(&"crow", 6, Vector3(-420, 0, -720), 150.0, 210.0, 9)
	crows.max_distance = 2500.0
	add_child(crows)
	landmarks["gulls"] = gulls
	landmarks["crows"] = crows


func _build_rays() -> void:
	var layer := CanvasLayer.new()
	layer.name = "GodRays"
	layer.layer = -1
	add_child(layer)
	rays_rect = ColorRect.new()
	rays_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rays_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rays_mat = ShaderMaterial.new()
	_rays_mat.shader = RAYS_SHADER
	_rays_mat.set_shader_parameter(&"intensity", 0.28)
	rays_rect.material = _rays_mat
	layer.add_child(rays_rect)


func _make_glint_texture() -> Texture2D:
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) * 0.5
	for y in size:
		for x in size:
			var dx := (x - c) / c
			var dy := (y - c) / c
			var cross := exp(-absf(dx) * 22.0) * exp(-absf(dy) * 2.2) + exp(-absf(dy) * 22.0) * exp(-absf(dx) * 2.2)
			var core := exp(-(dx * dx + dy * dy) * 18.0)
			var a := clampf(cross * 0.8 + core, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


# --- Runtime -------------------------------------------------------------------------------

func _update_camera(_delta: float) -> void:
	var t := time
	var pos := CAM_BASE + Vector3(sin(t * 0.045) * 14.0, sin(t * 0.063) * 2.0, sin(t * 0.031) * 10.0 - t * 0.0)
	camera.position = pos
	camera.rotation = Vector3(deg_to_rad(3.2 + sin(t * 0.05) * 0.5), deg_to_rad(-3.0 + sin(t * 0.027) * 2.2), 0.0)


func _update_glint() -> void:
	# a sparkle every few seconds as the ice catches the sun
	var ph := fposmod(time, 5.5)
	var a := exp(-pow((ph - 1.0) / 0.35, 2.0))
	glint.modulate.a = a
	glint.scale = Vector3.ONE * (0.6 + a * 0.8)
	glint.rotation.z = time * 0.4


func _update_rays() -> void:
	if not rays_rect.visible:
		return
	var vp := get_viewport()
	var sun_world := camera.global_position + SUN_DIR.normalized() * 2000.0
	if camera.is_position_behind(sun_world):
		_rays_mat.set_shader_parameter(&"visible", 0.0)
		return
	var sp := camera.unproject_position(sun_world)
	var size := vp.get_visible_rect().size
	_rays_mat.set_shader_parameter(&"sun_uv", sp / size)
	_rays_mat.set_shader_parameter(&"visible", 1.0)


func _apply_settings() -> void:
	Settings.configure_environment(environment)
	environment.ssao_enabled = false
	environment.ssil_enabled = false
	environment.sdfgi_enabled = false
	environment.volumetric_fog_enabled = false
	Settings.configure_sun(sun)
	sun.directional_shadow_max_distance = 600.0
	var fx := Settings.effects_scale()
	if petals:
		petals.amount = maxi(12, int(70.0 * fx))
	if plume:
		plume.amount = maxi(16, int(48.0 * fx))
	if rays_rect:
		rays_rect.visible = Settings.detail_level() >= 1


## Moves the drift clock (screenshots, tests).
func set_time(t: float) -> void:
	time = t
	_update_camera(0.0)
