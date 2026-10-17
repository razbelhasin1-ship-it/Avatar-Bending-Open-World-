class_name TechniquePreview
extends TextureRect
## Live preview of a bending technique for the skill tree: the player's own HumanoidRig
## (element preset, style and appearance) in a SubViewport with its own World3D, looping the
## technique's real animation clips (the same AnimLibrary clips the ability plays: combo
## steps, hold + release for charged moves, the dodge clip ...) with a PreviewFlourish on the
## clips' timed events. Also used as the character portrait (`show_idle()`).
##
## Renders every frame while visible, not at all while hidden; runs while the tree is
## paused (the Journey Book pauses the game).

const GROUND_SHADER := preload("res://src/ui/shaders/stage_ground.gdshader")
const NOISE := preload("res://assets/textures/world/clouds.png")

var element := ElementDefs.Element.NONE
var def: AbilityDef = null
var viewport: SubViewport
var stage: Node3D
var camera: Camera3D
var rig: HumanoidRig
var flourish: PreviewFlourish
var max_scale := 1.25
## Clips started since setup (tests).
var clips_played := 0
## Portrait mode: idle stance, slow turn, no flourish.
var portrait := false

var _steps: Array[Dictionary] = []
var _i := 0
var _wait := 0.0
var _holding := 0.0
var _turn := 0.0


func setup(p_element: int, appearance: Dictionary = {}, p_portrait: bool = false) -> void:
	element = p_element
	portrait = p_portrait
	process_mode = Node.PROCESS_MODE_ALWAYS
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport = SubViewport.new()
	viewport.name = "Viewport"
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_2X if not Settings.is_compatibility_renderer() else Viewport.MSAA_DISABLED
	viewport.size = Vector2i(640, 320)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	stage = Node3D.new()
	stage.name = "Stage"
	viewport.add_child(stage)
	_build_stage(appearance)
	texture = viewport.get_texture()
	resized.connect(_fit_viewport)


func _build_stage(appearance: Dictionary) -> void:
	var st: Dictionary = ElementPreview.STAGING.get(element, ElementPreview.STAGING[ElementDefs.Element.WATER])
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = st["ambient"]
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	stage.add_child(we)
	var key := DirectionalLight3D.new()
	key.light_color = st["key"]
	key.light_energy = 1.3
	key.shadow_enabled = Settings.detail_level() >= 1
	key.directional_shadow_max_distance = 12.0
	stage.add_child(key)
	key.look_at_from_position(Vector3(2.5, 4.0, 4.0), Vector3.ZERO, Vector3.UP)
	var rim := DirectionalLight3D.new()
	rim.light_color = st["rim"]
	rim.light_energy = 1.5
	stage.add_child(rim)
	rim.look_at_from_position(Vector3(-2.5, 2.4, -3.5), Vector3(0, 1, 0), Vector3.UP)
	camera = Camera3D.new()
	camera.fov = 30.0 if not portrait else 26.0
	camera.near = 0.1
	camera.far = 60.0
	stage.add_child(camera)
	if portrait:
		camera.look_at_from_position(Vector3(0.0, 1.3, 4.6), Vector3(0.0, 0.98, 0.0), Vector3.UP)
	else:
		camera.look_at_from_position(Vector3(0.75, 1.42, 5.0), Vector3(0.95, 0.9, 0.0), Vector3.UP)
	camera.current = true
	var ground := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 2.2
	disc.bottom_radius = 2.2
	disc.height = 0.02
	disc.radial_segments = 48
	ground.mesh = disc
	var gm := ShaderMaterial.new()
	gm.shader = GROUND_SHADER
	gm.set_shader_parameter(&"color", (st["ground"] as Color).darkened(0.18))
	gm.set_shader_parameter(&"edge_color", st["ground_edge"])
	gm.set_shader_parameter(&"noise_tex", NOISE)
	gm.set_shader_parameter(&"radius", 2.2)
	ground.material_override = gm
	ground.position = Vector3(0.3 if not portrait else 0.0, -0.01, 0.0)
	stage.add_child(ground)
	var prof := LocomotionProfile.for_element(element)
	var cfg := {"preset": prof.rig_preset, "style": prof.rig_style, "seed": int(appearance.get("seed", 11))}
	for k: String in appearance:
		cfg[k] = appearance[k]
	BendingClips.ensure()
	rig = HumanoidRig.create(cfg)
	rig.name = "Rig"
	rig.emit_footsteps = false
	rig.auto_lod = false
	stage.add_child(rig)
	rig.set_lod(0)
	rig.set_foot_ik(false)
	rig.set_style(prof.rig_style)
	rig.rotation.y = (-PI * 0.5 - 0.42) if not portrait else -0.35
	rig.set_combat_stance(not portrait)
	if not portrait:
		flourish = PreviewFlourish.new()
		flourish.name = "Flourish"
		stage.add_child(flourish)
		flourish.attach(rig, element)


## Plays `d`'s clips in a loop (null = idle stance).
func show_technique(d: AbilityDef) -> void:
	def = d
	_steps = clip_steps(d)
	_i = 0
	_wait = 0.25
	_holding = 0.0
	if rig and rig.is_playing_action():
		rig.stop_action(0.15)


func show_idle() -> void:
	show_technique(null)


## The clips a technique plays, in order: [{clip, speed, start, hold (s: loop clips), pause}].
static func clip_steps(d: AbilityDef) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if d == null:
		return out
	var p := d.params
	match d.slot:
		AbilityDef.Slot.LIGHT:
			for st: Variant in p.get("steps", []):
				if st is Dictionary:
					_add(out, StringName(str((st as Dictionary).get("clip", ""))), float((st as Dictionary).get("speed", 1.0)), 0.0, 0.0, 0.12)
			if not out.is_empty():
				out[out.size() - 1]["pause"] = 0.9
		AbilityDef.Slot.HEAVY:
			_add(out, StringName(str(p.get("tap_clip", ""))), 1.0, 0.0, 0.0, 0.6)
			_add(out, StringName(str(p.get("hold_clip", ""))), 1.0, 0.0, maxf(d.charge_time, 0.8), 0.0)
			_add(out, StringName(str(p.get("release_clip", d.clip))), 1.0, float(p.get("release_start", 0.0)), 0.0, 0.9)
		AbilityDef.Slot.DODGE:
			var clips: Dictionary = p.get("clips", {})
			_add(out, StringName(str(clips.get("fwd", ""))), 1.0, 0.0, 0.0, 0.5)
			_add(out, StringName(str(clips.get("left", ""))), 1.0, 0.0, 0.0, 0.5)
			_add(out, StringName(str(clips.get("back", ""))), 1.0, 0.0, 0.0, 0.9)
		AbilityDef.Slot.DEFENSE:
			var c := d.clip if d.clip != &"" else &"block_hold"
			_add(out, c, 1.0, 0.0, 1.4, 0.8)
		AbilityDef.Slot.INNATE, AbilityDef.Slot.PASSIVE:
			_add(out, &"air_jump_flip" if d.element == ElementDefs.Element.AIR else d.clip, 1.0, 0.0, 0.0, 0.9)
		_:
			if p.has("hold_clip"):
				_add(out, StringName(str(p["hold_clip"])), 1.0, 0.0, maxf(d.charge_time, 0.7), 0.0)
			_add(out, d.clip, d.clip_speed, d.clip_start, 1.6, 1.0)
	return out


static func _add(out: Array[Dictionary], clip: StringName, speed: float, start: float, hold: float, pause: float) -> void:
	if clip == &"":
		return
	var c := AnimLibrary.get_clip(clip)
	if c == null:
		return
	out.append({"clip": clip, "speed": speed, "start": start, "hold": hold if c.loop else 0.0, "pause": pause})


func _process(delta: float) -> void:
	if rig == null or viewport == null:
		return
	if not is_visible_in_tree():
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	if viewport.render_target_update_mode != SubViewport.UPDATE_ALWAYS:
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		_fit_viewport()
	if portrait:
		_turn += delta
		rig.rotation.y = -0.35 + sin(_turn * 0.4) * 0.3
		return
	if _holding > 0.0:
		_holding -= delta
		if _holding <= 0.0:
			rig.stop_action(0.12)
			_wait = 0.05
		return
	_wait -= delta
	if _wait > 0.0 or _steps.is_empty():
		return
	var step: Dictionary = _steps[_i % _steps.size()]
	_i += 1
	var dur := rig.play_action(step["clip"], {"speed": float(step["speed"]), "start": float(step["start"])})
	clips_played += 1
	if float(step["hold"]) > 0.0:
		_holding = float(step["hold"])
		_wait = 0.0
	else:
		_wait = maxf(dur * (1.0 - float(step["start"])), 0.2) + float(step["pause"])


func _fit_viewport() -> void:
	if viewport == null or size.x < 8.0 or size.y < 8.0 or not is_inside_tree():
		return
	var s := clampf(get_viewport().get_final_transform().get_scale().x, 0.5, max_scale)
	var px := Vector2i(maxi(64, int(size.x * s)), maxi(64, int(size.y * s)))
	if px != viewport.size:
		viewport.size = px
