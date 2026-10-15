class_name ElementPreview
extends TextureRect
## Live 3D preview rendered into a SubViewport: a HumanoidRig in the nation's outfit
## looping real bending clips with a distinct element effect (PreviewFx), and the
## element's companion CreatureRig behind them. Transparent background so the card's
## painting shows through. `silhouette` renders the bender as a flat ink cut-out (the
## show-intro motif) with the effect still in colour.
##
## Active previews render every frame; inactive ones refresh at `idle_fps` to save GPU.

const GROUND_SHADER := preload("res://src/ui/shaders/stage_ground.gdshader")
const SILHOUETTE_SHADER := preload("res://src/ui/shaders/silhouette.gdshader")
const NOISE := preload("res://assets/textures/world/clouds.png")

## Per-element staging: outfit, companion and light palette.
const STAGING := {
	ElementDefs.Element.AIR: {"preset": &"air_nomad", "body": "male", "seed": 4, "companion": &"sky_bison", "companion_scale": 0.3,
		"companion_pos": Vector3(-1.9, 2.25, -7.0), "companion_yaw": 1.2, "flying": true,
		"ground": Color(0.80, 0.74, 0.62), "ground_edge": Color(0.62, 0.55, 0.45), "key": Color(1.0, 0.93, 0.80), "rim": Color(1.0, 0.78, 0.40), "ambient": Color(0.62, 0.70, 0.82)},
	ElementDefs.Element.EARTH: {"preset": &"earth_kingdom", "body": "female", "seed": 9, "companion": &"badgermole", "companion_scale": 0.5,
		"companion_pos": Vector3(-2.2, 0.0, -3.4), "companion_yaw": 0.9, "flying": false,
		"ground": Color(0.48, 0.46, 0.34), "ground_edge": Color(0.36, 0.40, 0.26), "key": Color(1.0, 0.92, 0.78), "rim": Color(0.62, 0.95, 0.50), "ambient": Color(0.55, 0.62, 0.52)},
	ElementDefs.Element.FIRE: {"preset": &"fire_nation", "body": "male", "seed": 3, "companion": &"dragon", "companion_scale": 0.17,
		"companion_pos": Vector3(-0.6, 2.55, -8.5), "companion_yaw": 1.45, "flying": true,
		"ground": Color(0.30, 0.24, 0.22), "ground_edge": Color(0.22, 0.14, 0.12), "key": Color(1.0, 0.82, 0.66), "rim": Color(1.0, 0.42, 0.18), "ambient": Color(0.62, 0.45, 0.42)},
	ElementDefs.Element.WATER: {"preset": &"water_tribe", "body": "female", "seed": 5, "companion": &"polar_bear_dog", "companion_scale": 0.55,
		"companion_pos": Vector3(-2.0, 0.0, -3.2), "companion_yaw": 0.85, "flying": false,
		"ground": Color(0.88, 0.93, 0.98), "ground_edge": Color(0.66, 0.78, 0.90), "key": Color(0.92, 0.96, 1.0), "rim": Color(0.55, 0.80, 1.0), "ambient": Color(0.58, 0.68, 0.85)},
}

const FX_CLASSES := {
	ElementDefs.Element.AIR: preload("res://src/ui/select/fx/air_preview_fx.gd"),
	ElementDefs.Element.EARTH: preload("res://src/ui/select/fx/earth_preview_fx.gd"),
	ElementDefs.Element.FIRE: preload("res://src/ui/select/fx/fire_preview_fx.gd"),
	ElementDefs.Element.WATER: preload("res://src/ui/select/fx/water_preview_fx.gd"),
}

var element := ElementDefs.Element.NONE
var silhouette := false
var viewport: SubViewport
var stage: Node3D
var camera: Camera3D
var rig: HumanoidRig
var companion: CreatureRig
var fx: PreviewFx
## Inactive previews redraw at this rate.
var idle_fps := 12.0
## Max render resolution multiplier relative to the on-screen size.
var max_scale := 1.5
var active := true:
	set(v):
		active = v
		_apply_update_mode()

var _seq: Array[Dictionary] = []
var _seq_i := 0
var _wait := 0.8
var _refresh := 0.0
var _clips_played := 0


func setup(p_element: int, p_silhouette: bool = false) -> void:
	element = p_element
	silhouette = p_silhouette
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport = SubViewport.new()
	viewport.name = "Viewport"
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_2X if not Settings.is_compatibility_renderer() else Viewport.MSAA_DISABLED
	viewport.size = Vector2i(400, 300)
	add_child(viewport)
	stage = Node3D.new()
	stage.name = "Stage"
	viewport.add_child(stage)
	_build_stage()
	texture = viewport.get_texture()
	resized.connect(_fit_viewport)
	_apply_update_mode()


func _build_stage() -> void:
	var st: Dictionary = STAGING[element]
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = st["ambient"]
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	stage.add_child(we)
	var key := DirectionalLight3D.new()
	key.light_color = st["key"]
	key.light_energy = 1.35
	key.shadow_enabled = not silhouette and Settings.detail_level() >= 1
	key.directional_shadow_max_distance = 14.0
	key.shadow_blur = 1.5
	stage.add_child(key)
	key.look_at_from_position(Vector3(2.0, 4.0, 3.5), Vector3.ZERO, Vector3.UP)
	var rim := DirectionalLight3D.new()
	rim.light_color = st["rim"]
	rim.light_energy = 1.6
	stage.add_child(rim)
	rim.look_at_from_position(Vector3(-2.0, 2.2, -4.0), Vector3(0, 1, 0), Vector3.UP)
	camera = Camera3D.new()
	camera.fov = 30.0
	camera.near = 0.1
	camera.far = 60.0
	stage.add_child(camera)
	if silhouette:
		camera.look_at_from_position(Vector3(0.25, 1.05, 4.4), Vector3(0.4, 0.95, 0.0), Vector3.UP)
	else:
		camera.look_at_from_position(Vector3(0.6, 1.3, 4.7), Vector3(0.05, 1.02, -0.6), Vector3.UP)
	camera.current = true
	# collision ground so rig/creature foot probes find the stage floor (own physics space)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = Layers.WORLD
	floor_body.collision_mask = 0
	var shape := CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(shape)
	stage.add_child(floor_body)
	if not silhouette:
		var ground := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = 3.2
		disc.bottom_radius = 3.2
		disc.height = 0.02
		disc.radial_segments = 48
		ground.mesh = disc
		var gm := ShaderMaterial.new()
		gm.shader = GROUND_SHADER
		gm.set_shader_parameter(&"color", st["ground"])
		gm.set_shader_parameter(&"edge_color", st["ground_edge"])
		gm.set_shader_parameter(&"noise_tex", NOISE)
		gm.set_shader_parameter(&"radius", 3.2)
		ground.material_override = gm
		ground.position = Vector3(-0.4, -0.01, -0.8)
		stage.add_child(ground)
	var cfg := {"preset": st["preset"], "body": st["body"], "seed": st["seed"]}
	rig = HumanoidRig.create(cfg)
	rig.emit_footsteps = false
	rig.auto_lod = false
	stage.add_child(rig)
	rig.rotation.y = -PI * 0.5 - 0.5
	rig.set_combat_stance(true)
	if silhouette:
		_ink_everything(rig)
	else:
		companion = CreatureRig.create(st["companion"], {"seed": 2, "sounds": false, "lod": 0, "scale": st["companion_scale"]})
		if companion:
			stage.add_child(companion)
			companion.position = st["companion_pos"]
			companion.rotation.y = st["companion_yaw"]
	var fx_class: GDScript = FX_CLASSES[element]
	fx = fx_class.new()
	fx.element = element
	fx.motif = silhouette
	stage.add_child(fx)
	fx.attach(rig, camera)
	_seq = fx.sequence()


func _ink_everything(n: Node) -> void:
	var m := ShaderMaterial.new()
	m.shader = SILHOUETTE_SHADER
	for c in n.find_children("*", "GeometryInstance3D", true, false):
		(c as GeometryInstance3D).material_override = m
		(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _process(delta: float) -> void:
	if rig == null:
		return
	if companion and STAGING[element]["flying"]:
		companion.set_flight(true, Vector3(0, 0.3, -4.5), sin(fx.time * 0.7) * 0.25, 0.08)
	elif companion:
		companion.set_locomotion(Vector3.ZERO, true, delta)
	_wait -= delta
	if _wait <= 0.0 and not _seq.is_empty():
		var step: Dictionary = _seq[_seq_i % _seq.size()]
		_seq_i += 1
		var d := rig.play_action(step["clip"], {"speed": float(step.get("speed", 1.0))})
		_clips_played += 1
		_wait = maxf(d, 0.2) + float(step.get("pause", 0.4))
	if not active:
		_refresh -= delta
		if _refresh <= 0.0:
			_refresh = 1.0 / idle_fps
			viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _apply_update_mode() -> void:
	if viewport:
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_ONCE


func _fit_viewport() -> void:
	if viewport == null or size.x < 4.0 or size.y < 4.0:
		return
	var s := clampf(get_viewport().get_final_transform().get_scale().x, 0.5, max_scale)
	var px := Vector2i(maxi(64, int(size.x * s)), maxi(64, int(size.y * s)))
	if px != viewport.size:
		viewport.size = px


## Number of showcase clips started so far (tests).
func clips_played() -> int:
	return _clips_played
