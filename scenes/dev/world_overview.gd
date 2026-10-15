extends Node3D
## Dev overview of the baked world: whole-world mesh, sea/lakes/canals, markers, and
## GPU-displaced 2 m detail patches for close views of each nation.
##
##   godot --path . -- --scene=res://scenes/dev/world_overview.tscn
## Keys: 1-8 switch views (see VIEWS), M toggles markers.

const VIEWS := {
	"top": {"ortho": 8600.0, "pos": Vector3(0, 9000, 0.1), "look": Vector3(0, 0, 0)},
	"world_south": {"pos": Vector3(400, 3600, 7600), "look": Vector3(200, 0, 300), "fov": 50.0},
	"water_tribe": {"pos": Vector3(250, 520, -1820), "look": Vector3(-320, 30, -2900), "fov": 55.0,
			"patch": Vector3(-300, 0, -2780), "patch_size": 1700.0},
	"ba_sing_se": {"pos": Vector3(820, 640, 1150), "look": Vector3(1950, 60, 180), "fov": 52.0,
			"patch": Vector3(1950, 0, 200), "patch_size": 1900.0},
	"omashu": {"pos": Vector3(1250, 520, 250), "look": Vector3(380, 170, -420), "fov": 48.0,
			"patch": Vector3(420, 0, -380), "patch_size": 1500.0},
	"fire_nation": {"pos": Vector3(-1000, 760, 1300), "look": Vector3(-2450, 110, 2450), "fov": 52.0,
			"patch": Vector3(-2250, 0, 2350), "patch_size": 1900.0},
	"air_temple": {"pos": Vector3(1900, 1180, 1750), "look": Vector3(2450, 640, 3250), "fov": 50.0,
			"patch": Vector3(2350, 0, 2950), "patch_size": 1800.0},
	"air_temple_close": {"pos": Vector3(2130, 905, 2930), "look": Vector3(2500, 790, 3350), "fov": 55.0,
			"patch": Vector3(2420, 0, 3200), "patch_size": 1100.0},
}

var view_name: String = ""
var _camera: Camera3D
var _sun: DirectionalLight3D
var _env: Environment
var _world_mesh: MeshInstance3D
var _world_mat: ShaderMaterial
var _patch: MeshInstance3D
var _markers: Node3D


func _ready() -> void:
	WorldData.load_world()
	_build_environment()
	if not WorldData.has_world_data():
		push_warning("world_overview: no baked world data (%s)" % WorldData.load_error)
		return
	_world_mat = WorldPreviewBuilder.make_terrain_material(false)
	_world_mesh = MeshInstance3D.new()
	_world_mesh.name = "WorldMesh"
	_world_mesh.mesh = WorldPreviewBuilder.build_world_mesh(512)
	_world_mesh.material_override = _world_mat
	add_child(_world_mesh)
	add_child(WorldPreviewBuilder.build_sea())
	add_child(WorldPreviewBuilder.build_inland_water())
	_markers = WorldPreviewBuilder.build_markers()
	add_child(_markers)
	set_view(Router.params.get("view", "world_south"))


func _build_environment() -> void:
	_camera = Camera3D.new()
	_camera.far = 30000.0
	_camera.near = 1.0
	add_child(_camera)
	_camera.current = true
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-34, -40, 0)
	_sun.light_energy = 1.6
	_sun.light_color = Color(1.0, 0.95, 0.86)
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 3000.0
	add_child(_sun)
	var we := WorldEnvironment.new()
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.22, 0.42, 0.78)
	sm.sky_horizon_color = Color(0.70, 0.80, 0.90)
	sm.ground_horizon_color = Color(0.70, 0.80, 0.90)
	sm.ground_bottom_color = Color(0.20, 0.30, 0.42)
	sm.sun_angle_max = 20.0
	sky.sky_material = sm
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.ambient_light_energy = 0.55
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.tonemap_white = 4.0
	_env.fog_enabled = true
	_env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	_env.fog_light_color = Color(0.62, 0.72, 0.84)
	_env.fog_density = 0.00004
	_env.fog_aerial_perspective = 0.35
	_env.fog_sky_affect = 0.0
	Settings.configure_environment(_env)
	_env.volumetric_fog_enabled = false
	_env.ssao_enabled = false
	we.environment = _env
	add_child(we)


## Switches to one of VIEWS (camera + optional detail patch).
func set_view(vname: String) -> void:
	if not VIEWS.has(vname):
		return
	view_name = vname
	var v: Dictionary = VIEWS[vname]
	if v.has("ortho"):
		_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		_camera.size = v["ortho"]
	else:
		_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		_camera.fov = v.get("fov", 55.0)
	_camera.position = v["pos"]
	_camera.look_at(v["look"], Vector3.UP if not v.has("ortho") else Vector3.FORWARD)
	# light from the side and slightly behind the camera so slopes facing it are modelled
	var to_target: Vector3 = (v["look"] as Vector3) - (v["pos"] as Vector3)
	var cam_yaw := rad_to_deg(atan2(-to_target.x, -to_target.z))
	_sun.rotation_degrees = Vector3(-30.0, cam_yaw + 58.0, 0.0) if not v.has("ortho") else Vector3(-40, -40, 0)
	_env.fog_density = 0.0 if v.has("ortho") else (0.000035 if v.has("patch") else 0.000022)
	if _patch:
		_patch.queue_free()
		_patch = null
	if _world_mat:
		_world_mat.set_shader_parameter(&"hole_rect", Vector4.ZERO)
	if v.has("patch") and WorldData.has_world_data():
		var c: Vector3 = v["patch"]
		var size: float = v["patch_size"]
		_patch = WorldPreviewBuilder.build_patch(c.x, c.z, size)
		_patch.name = "DetailPatch"
		add_child(_patch)
		var inset := size * 0.5 - 6.0
		_world_mat.set_shader_parameter(&"hole_rect", Vector4(c.x - inset, c.z - inset, c.x + inset, c.z + inset))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var keys := VIEWS.keys()
		var k: int = (event as InputEventKey).keycode - KEY_1
		if k >= 0 and k < keys.size():
			set_view(keys[k])
		elif (event as InputEventKey).keycode == KEY_M and _markers:
			_markers.visible = not _markers.visible
