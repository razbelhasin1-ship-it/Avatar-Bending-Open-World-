extends Node3D
## Creature showcase stage (scenes/dev/creature_showcase.tscn): painterly sky, sun,
## a ground plane with collision, 1.75 m human reference markers and helpers that
## playtest scenarios use to spawn creatures, drive them and frame the camera.
##
## Run interactively: godot --path . -- --scene=res://scenes/dev/creature_showcase.tscn
## (spawns every companion in a row; WASD-free, the camera orbits slowly).

var camera: Camera3D
var sun: DirectionalLight3D
var env: Environment
var creatures: Array[CreatureRig] = []
var drivers: Dictionary = {}
var orbit := true
var _orbit_t := 0.0
var _ground_color := Color(0.58, 0.66, 0.42)


func _ready() -> void:
	_build_stage()
	if get_tree().current_scene == self and not OS.get_cmdline_user_args().has("--test"):
		var x := -18.0
		for sp: StringName in CreatureRig.COMPANIONS:
			spawn(sp, Vector3(x, 0, 0), 0.6)
			add_reference_human(Vector3(x + 3.5, 0, 2.0))
			x += 12.0
	else:
		orbit = false


func _build_stage() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.32, 0.52, 0.82)
	sm.sky_horizon_color = Color(0.78, 0.84, 0.9)
	sm.ground_horizon_color = Color(0.72, 0.76, 0.78)
	sm.ground_bottom_color = Color(0.4, 0.45, 0.42)
	sm.sun_angle_max = 20.0
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.74, 0.8, 0.88)
	env.fog_density = 0.0009
	env.fog_sky_affect = 0.0
	Settings.configure_environment(env)
	# Light haze only: the showcase is about the creatures, not the atmosphere.
	env.volumetric_fog_density = 0.0025
	env.volumetric_fog_albedo = Color(0.85, 0.9, 0.95)
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, 38, 0)
	sun.light_energy = 1.25
	sun.light_color = Color(1.0, 0.96, 0.9)
	Settings.configure_sun(sun)
	sun.shadow_enabled = true
	add_child(sun)
	var ground := StaticBody3D.new()
	ground.collision_layer = Layers.WORLD
	ground.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(600, 2, 600)
	cs.shape = box
	cs.position = Vector3(0, -1, 0)
	ground.add_child(cs)
	var gm := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(600, 600)
	pm.subdivide_width = 1
	pm.subdivide_depth = 1
	gm.mesh = pm
	gm.material_override = _ground_material()
	ground.add_child(gm)
	add_child(ground)
	camera = Camera3D.new()
	camera.fov = 50.0
	camera.far = 2000.0
	add_child(camera)
	camera.position = Vector3(0, 6, 22)
	camera.look_at(Vector3(0, 2, 0))


func _ground_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_back;
uniform vec4 base : source_color = vec4(0.58, 0.66, 0.42, 1.0);
uniform vec4 alt : source_color = vec4(0.5, 0.6, 0.36, 1.0);
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n(vec2 p) { vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y); }
void fragment() {
	float m = n(wp.xz * 0.15) * 0.6 + n(wp.xz * 0.6) * 0.4;
	vec3 c = mix(base.rgb, alt.rgb, smoothstep(0.35, 0.75, m));
	float grid = smoothstep(0.97, 1.0, max(abs(fract(wp.x * 0.5) - 0.5), abs(fract(wp.z * 0.5) - 0.5)) * 2.0);
	ALBEDO = c * (1.0 - grid * 0.06);
	ROUGHNESS = 0.95;
}
void light() {
	float lit = smoothstep(-0.05, 0.05, dot(NORMAL, LIGHT)) * smoothstep(0.0, 0.25, ATTENUATION);
	DIFFUSE_LIGHT += LIGHT_COLOR / PI * mix(vec3(0.3, 0.32, 0.45), vec3(1.0), lit);
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter(&"base", _ground_color)
	m.set_shader_parameter(&"alt", _ground_color.darkened(0.12))
	return m


## Snow-white ground for arctic shots.
func set_ground(color: Color) -> void:
	_ground_color = color
	for c in get_children():
		if c is StaticBody3D:
			for g in c.get_children():
				if g is MeshInstance3D:
					(g as MeshInstance3D).material_override = _ground_material()


## A shallow toon pond (flat water disc slightly above the ground) for swimmers.
func add_pond(c: Vector3, r: float) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = 0.02
	cm.radial_segments = 48
	m.mesh = cm
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_back;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float w = sin(wp.x * 3.0 + TIME * 1.5) * sin(wp.z * 2.6 - TIME * 1.2);
	ALBEDO = mix(vec3(0.16, 0.42, 0.56), vec3(0.3, 0.6, 0.7), 0.5 + 0.5 * w);
	ROUGHNESS = 0.15;
	SPECULAR = 0.6;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	m.material_override = mat
	add_child(m)
	m.global_position = c + Vector3(0, 0.03, 0)
	return m


func spawn(species: StringName, pos: Vector3, yaw: float = 0.0, cfg: Dictionary = {}) -> CreatureRig:
	var rig := CreatureRig.create(species, cfg)
	add_child(rig)
	rig.global_position = pos
	rig.rotation.y = yaw
	rig.reset_feet()
	creatures.append(rig)
	var d := CreatureDriver.new(rig)
	d.name = "Driver_%s" % species
	add_child(d)
	drivers[rig] = d
	return rig


func driver(rig: CreatureRig) -> CreatureDriver:
	return drivers.get(rig)


## 1.75 m human stand-in: capsule body + head, warm cloth color.
func add_reference_human(pos: Vector3, yaw: float = 0.0) -> Node3D:
	var n := Node3D.new()
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.22
	cap.height = 1.45
	body.mesh = cap
	body.position = Vector3(0, 0.725, 0)
	body.material_override = ToonMaterials.make(Color(0.25, 0.42, 0.62))
	n.add_child(body)
	var head := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 0.12
	sp.height = 0.25
	head.mesh = sp
	head.position = Vector3(0, 1.62, 0)
	head.material_override = ToonMaterials.make(Color(0.86, 0.68, 0.54))
	n.add_child(head)
	add_child(n)
	n.global_position = pos
	n.rotation.y = yaw
	return n


func frame(cam_pos: Vector3, target: Vector3, fov: float = 50.0) -> void:
	orbit = false
	camera.fov = fov
	camera.global_position = cam_pos
	camera.look_at(target)


func _process(delta: float) -> void:
	if not orbit:
		return
	_orbit_t += delta * 0.05
	camera.global_position = Vector3(sin(_orbit_t) * 40.0, 9.0, cos(_orbit_t) * 40.0)
	camera.look_at(Vector3(0, 2.5, 0))
