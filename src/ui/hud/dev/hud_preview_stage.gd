class_name HudPreviewStage
extends Node3D
## Small 3D stage for HUD playtests and UI previews: a snowy courtyard under the world sky
## shader, the player character seen over the shoulder, an enemy to lock on to and the
## element's companion. Uses the real HumanoidRig / CreatureRig. Not used by gameplay.

const SKY_SHADER := preload("res://assets/shaders/world/sky.gdshader")
const CLOUD_TEX := preload("res://assets/textures/world/clouds.png")

var camera: Camera3D
var player_rig: HumanoidRig
var enemy: Node3D
var companion: Node3D
var mock: HudMockPlayer


func build(element: int) -> void:
	var sm := ShaderMaterial.new()
	sm.shader = SKY_SHADER
	sm.set_shader_parameter(&"cloud_tex", CLOUD_TEX)
	sm.set_shader_parameter(&"zenith_color", Color(0.22, 0.42, 0.72))
	sm.set_shader_parameter(&"horizon_color", Color(0.78, 0.86, 0.94))
	sm.set_shader_parameter(&"sun_dir", Vector3(0.4, 0.45, -0.8).normalized())
	sm.set_shader_parameter(&"cloud_coverage", 0.42)
	var sky := Sky.new()
	sky.sky_material = sm
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_density = 0.0016
	env.fog_light_color = Color(0.62, 0.72, 0.86)
	Settings.configure_environment(env)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	add_child(sun)
	sun.look_at_from_position(Vector3.ZERO, Vector3(-0.4, -0.6, 0.7), Vector3.UP)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.72, 0.79, 0.88) if element == ElementDefs.Element.WATER else Color(0.38, 0.46, 0.30)
	gm.roughness = 1.0
	ground.material_override = gm
	add_child(ground)
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD
	var shape := CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	body.add_child(shape)
	add_child(body)
	# a few ice / stone blocks for depth
	for i in 7:
		var b := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(randf_range(2, 5), randf_range(2, 7), randf_range(2, 4))
		b.mesh = bm
		b.material_override = ToonMaterials.make(Color(0.72, 0.84, 0.95) if element == ElementDefs.Element.WATER else Color(0.55, 0.52, 0.48))
		b.position = Vector3(randf_range(-22, 22), bm.size.y * 0.5, randf_range(-40, -14))
		b.rotation.y = randf() * TAU
		add_child(b)
	var preset: StringName = ElementPreview.STAGING[element]["preset"]
	player_rig = HumanoidRig.create({"preset": preset, "seed": 5, "body": ElementPreview.STAGING[element]["body"]})
	player_rig.emit_footsteps = false
	add_child(player_rig)
	player_rig.position = Vector3(0, 0, 0)
	player_rig.set_combat_stance(true)
	enemy = Node3D.new()
	enemy.name = "Enemy"
	var er := HumanoidRig.create({"preset": &"fire_soldier", "seed": 2})
	er.emit_footsteps = false
	enemy.add_child(er)
	var eh := HealthComponent.new()
	eh.name = "HealthComponent"
	eh.max_health = 140.0
	enemy.add_child(eh)
	enemy.set_meta(&"display_name", "Fire Nation Soldier")
	add_child(enemy)
	enemy.position = Vector3(1.2, 0, -6.5)
	enemy.rotation.y = PI
	er.set_combat_stance(true)
	var st: Dictionary = ElementPreview.STAGING[element]
	var cr := CreatureRig.create(st["companion"], {"seed": 1, "sounds": false, "scale": 0.8 if not bool(st["flying"]) else 0.5})
	companion = Node3D.new()
	companion.name = "Companion"
	companion.add_child(cr)
	add_child(companion)
	companion.position = Vector3(-4.5, 0, -4.0)
	companion.rotation.y = 0.6
	camera = Camera3D.new()
	camera.fov = 62.0
	add_child(camera)
	camera.look_at_from_position(Vector3(0.9, 2.3, 4.2), Vector3(0.2, 1.4, -4.0), Vector3.UP)
	camera.make_current()
	mock = HudMockPlayer.new()
	mock.name = "MockPlayer"
	add_child(mock)
	mock.lock_target = enemy
	mock.companion = companion
	mock.setup_sample(element)
