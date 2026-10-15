class_name CharacterShowcase
extends Node3D
## Character showcase / dev stage (scenes/dev/character_showcase.tscn).
##
## Interactive (godot --path . -- --scene=res://scenes/dev/character_showcase.tscn):
##   Left/Right: preset   Up/Down: clip   Space: play clip   1-8: style
##   C: combat stance     W/S/A/D: walk the rig   Shift: run   Mouse drag: orbit
##   Wheel: zoom          F: flash   R: reaction (from the front)
## Playtest scenarios use spawn(), step() and frame_camera() for deterministic shots.

const STYLES: Array[StringName] = [&"civilian", &"air", &"earth", &"fire", &"water", &"soldier", &"elder", &"child"]

var camera: Camera3D
var sun: DirectionalLight3D
var env: Environment
var rigs: Array[HumanoidRig] = []
var _ground: StaticBody3D

var _interactive := false
var _preset_i := 0
var _clip_i := 0
var _style_i := 0
var _clips: Array = []
var _orbit := Vector2(0.3, 0.15)
var _dist := 4.0
var _focus := Vector3(0, 1.0, 0)
var _dragging := false
var _label: Label


func _ready() -> void:
	_build_stage()
	_interactive = get_tree().current_scene == self and not OS.get_cmdline_user_args().has("--test")
	if _interactive:
		_clips = AnimLibrary.clip_names()
		_spawn_interactive()
		_label = Label.new()
		_label.position = Vector2(16, 12)
		_label.add_theme_font_size_override(&"font_size", 18)
		var cl := CanvasLayer.new()
		add_child(cl)
		cl.add_child(_label)
		_update_label()


func _build_stage() -> void:
	camera = Camera3D.new()
	camera.fov = 34.0
	add_child(camera)
	camera.make_current()
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 140, 0)
	sun.light_energy = 1.1
	add_child(sun)
	Settings.configure_sun(sun)
	sun.shadow_enabled = true
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var mat := ProceduralSkyMaterial.new()
	mat.sky_top_color = Color(0.36, 0.55, 0.82)
	mat.sky_horizon_color = Color(0.78, 0.84, 0.9)
	mat.ground_horizon_color = Color(0.7, 0.68, 0.62)
	mat.ground_bottom_color = Color(0.4, 0.38, 0.34)
	sky.sky_material = mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	Settings.configure_environment(env)
	env.ssao_enabled = false
	env.volumetric_fog_enabled = false
	we.environment = env
	add_child(we)
	# Ground: stone courtyard tiles (collision on the world layer for foot IK).
	_ground = StaticBody3D.new()
	_ground.collision_layer = Layers.WORLD
	add_child(_ground)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(120, 1, 120)
	shape.shape = box
	shape.position = Vector3(0, -0.5, 0)
	_ground.add_child(shape)
	var far := MeshInstance3D.new()
	var fpm := PlaneMesh.new()
	fpm.size = Vector2(160, 160)
	far.mesh = fpm
	far.position.y = -0.003
	far.material_override = ToonMaterials.make(Color(0.66, 0.63, 0.55), {"outline": false})
	add_child(far)
	var mm := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(32, 32)
	mm.mesh = pm
	mm.material_override = ToonMaterials.make(Color(0.74, 0.7, 0.62), {"outline": false, "texture": _tile_texture(), "unique": true})
	add_child(mm)


func _tile_texture() -> Texture2D:
	# 16 x 16 stone tiles of 2 m over the 32 m courtyard.
	var img := Image.create(512, 512, false, Image.FORMAT_RGB8)
	for y in 512:
		for x in 512:
			var line := (x % 32) < 1 or (y % 32) < 1
			var n := 0.94 + 0.06 * sin(float(x) * 0.31 + float(y) * 0.17) * cos(float(y) * 0.23)
			img.set_pixel(x, y, Color(0.8, 0.78, 0.74) if line else Color(n, n * 0.98, n * 0.95))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Adds a block (stairs, ledges) with collision for foot IK checks.
func add_block(pos: Vector3, size: Vector3, color: Color = Color(0.66, 0.62, 0.55)) -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = Layers.WORLD
	sb.position = pos
	add_child(sb)
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = size
	cs.shape = bx
	sb.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = ToonMaterials.make(color, {"outline_width": 0.8})
	sb.add_child(mi)


## Adds a ramp (rotated box) of `angle` degrees around X.
func add_ramp(pos: Vector3, size: Vector3, angle_deg: float, color: Color = Color(0.6, 0.64, 0.52)) -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = Layers.WORLD
	sb.position = pos
	sb.rotation_degrees = Vector3(angle_deg, 0, 0)
	add_child(sb)
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = size
	cs.shape = bx
	sb.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = ToonMaterials.make(color, {"outline_width": 0.8})
	sb.add_child(mi)


## Spawns a rig. manual = true means it only moves when step() is called.
func spawn(cfg: Dictionary, pos: Vector3 = Vector3.ZERO, yaw_deg: float = 0.0, manual: bool = true) -> HumanoidRig:
	var rig := HumanoidRig.create(cfg)
	rig.manual_update = manual
	rig.auto_lod = false
	add_child(rig)
	rig.position = pos
	rig.rotation_degrees.y = yaw_deg
	rigs.append(rig)
	return rig


func clear_rigs() -> void:
	for r in rigs:
		if is_instance_valid(r):
			r.queue_free()
	rigs.clear()


## Steps every manual rig by `dt`, optionally moving them with `velocity`
## (world) and feeding locomotion.
func step(dt: float, velocity: Vector3 = Vector3.ZERO, move: bool = false) -> void:
	for r in rigs:
		if not is_instance_valid(r):
			continue
		if move:
			r.position += velocity * dt
		r.set_locomotion(velocity if move else Vector3.ZERO, true)
		r.advance(dt)


## Steps `seconds` worth of fixed 60 Hz frames.
func run_for(seconds: float, velocity: Vector3 = Vector3.ZERO, move: bool = false) -> void:
	var n := int(round(seconds * 60.0))
	for i in n:
		step(1.0 / 60.0, velocity, move)


func frame_camera(pos: Vector3, look: Vector3, fov: float = 34.0) -> void:
	camera.fov = fov
	camera.position = pos
	camera.look_at(look)


# --- Interactive -------------------------------------------------------------------

func _spawn_interactive() -> void:
	clear_rigs()
	var preset: StringName = CharacterOutfits.PRESETS[_preset_i]
	var r := spawn({"preset": preset}, Vector3.ZERO, 180.0, false)
	r.auto_lod = false
	_style_i = maxi(STYLES.find(r.get_style()), 0)
	_update_camera()


func _update_camera() -> void:
	var dir := Vector3(sin(_orbit.x) * cos(_orbit.y), sin(_orbit.y), cos(_orbit.x) * cos(_orbit.y))
	camera.position = _focus + dir * _dist
	camera.look_at(_focus)


func _update_label() -> void:
	if _label == null or rigs.is_empty():
		return
	var r := rigs[0]
	_label.text = "%s  |  style: %s%s  |  clip: %s\n←/→ preset  ↑/↓ clip  Space play  1-8 style  C stance  WASD move  F flash  R hit" % [
		CharacterOutfits.PRESETS[_preset_i], r.get_style(), " (combat)" if r.is_combat_stance() else "", _clips[_clip_i] if not _clips.is_empty() else "-"]


func _unhandled_input(event: InputEvent) -> void:
	if not _interactive:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_dist = maxf(_dist * 0.9, 0.8)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_dist = minf(_dist * 1.1, 20.0)
		_update_camera()
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_orbit += Vector2(-mm.relative.x, mm.relative.y) * 0.008
		_orbit.y = clampf(_orbit.y, -0.4, 1.3)
		_update_camera()
	elif event is InputEventKey and event.pressed and not event.echo:
		var r := rigs[0] if not rigs.is_empty() else null
		match (event as InputEventKey).keycode:
			KEY_RIGHT:
				_preset_i = (_preset_i + 1) % CharacterOutfits.PRESETS.size()
				_spawn_interactive()
			KEY_LEFT:
				_preset_i = (_preset_i - 1 + CharacterOutfits.PRESETS.size()) % CharacterOutfits.PRESETS.size()
				_spawn_interactive()
			KEY_UP:
				_clip_i = (_clip_i - 1 + _clips.size()) % _clips.size()
			KEY_DOWN:
				_clip_i = (_clip_i + 1) % _clips.size()
			KEY_SPACE:
				if r:
					r.play_action(_clips[_clip_i])
			KEY_C:
				if r:
					r.set_combat_stance(not r.is_combat_stance())
			KEY_F:
				if r:
					r.flash_hit()
			KEY_R:
				if r:
					r.play_reaction(&"stagger", -r.global_basis.z * -1.0)
			_:
				var k := (event as InputEventKey).keycode - KEY_1
				if r and k >= 0 and k < STYLES.size():
					r.set_style(STYLES[k])
		_update_label()


func _process(delta: float) -> void:
	if not _interactive or rigs.is_empty():
		return
	var r := rigs[0]
	var v := Vector3.ZERO
	var f := -camera.global_basis.z
	f.y = 0.0
	f = f.normalized()
	var rt := camera.global_basis.x
	if Input.is_key_pressed(KEY_W):
		v += f
	if Input.is_key_pressed(KEY_S):
		v -= f
	if Input.is_key_pressed(KEY_D):
		v += rt
	if Input.is_key_pressed(KEY_A):
		v -= rt
	var spd := 4.6 if Input.is_key_pressed(KEY_SHIFT) else 1.5
	v = v.normalized() * spd if v.length_squared() > 0.0 else Vector3.ZERO
	r.position += v * delta
	if v.length_squared() > 0.01 and not r.is_combat_stance():
		var target := atan2(-v.x, -v.z)
		r.rotation.y = lerp_angle(r.rotation.y, target, 1.0 - exp(-delta * 10.0))
	r.set_locomotion(v, true)
	_focus = _focus.lerp(r.position + Vector3(0, 1.0, 0), 1.0 - exp(-delta * 6.0))
	_update_camera()
