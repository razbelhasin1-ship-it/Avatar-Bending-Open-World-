extends Node3D
## Combat arena (dev scene): a stone training courtyard on a flat test world
## with training dummies, a sparring bot, a water pool (water source), a snow
## patch (deep snow + skating) and an ice rink, steps / ramps / pillars for
## locomotion checks, the real HUD bound to the player and the pause menu.
##
##   godot --path . -- --scene=res://scenes/dev/combat_arena.tscn --element=fire
##   Router.goto("res://scenes/dev/combat_arena.tscn", {"element": ElementDefs.Element.AIR})
## Dev keys: F1-F4 switch element (air, earth, fire, water), F5 reset dummies,
## F6 toggle the bot, F7 infinite chi, F8 toggle the help text.

const POOL := Rect2(9.0, -4.0, 7.0, 7.0)
const POOL_DEPTH := 1.7
const SNOW := Rect2(-16.0, -6.0, 8.0, 8.0)
const ICE := Rect2(-16.0, 4.0, 8.0, 9.0)
const START := Vector3(0, 0, 4)

var player: PlayerCharacter
var hud: Node = null
var dummies: Array[TrainingDummy] = []
var bot: SparringBot
var sun: DirectionalLight3D
var env: Environment
var _help: Label
var _info: Label
var _source_id := -1


func _ready() -> void:
	WorldData.use_flat_world(true)
	WorldData.height_override = _height
	WorldData.clear_water_sources()
	_source_id = WorldData.register_water_source(Vector3(POOL.get_center().x, 0.0, POOL.get_center().y), 4.0, &"water")
	GroundSampler.clear_zones()
	GroundSampler.add_zone(&"arena_snow", SNOW, &"snow", 0.42)
	GroundSampler.add_zone(&"arena_ice", ICE, &"ice", 0.0)
	_build_environment()
	_build_ground()
	_build_props()
	var e := _element_from_params()
	if not GameState.has_element():
		GameState.new_game(e, true)
	player = PlayerCharacter.new()
	player.name = "Player"
	player.element = e
	add_child(player)
	player.teleport(Transform3D(Basis.IDENTITY, START))
	if player.camera_rig:
		# Dev/tests: mouse look works without capturing the cursor.
		player.camera_rig.require_capture = not OS.get_cmdline_user_args().has("--test")
	_spawn_targets()
	_add_ui()
	Events.player_died.connect(_on_player_died)


func _exit_tree() -> void:
	WorldData.height_override = Callable()
	WorldData.use_flat_world(false)
	WorldData.clear_water_sources()
	GroundSampler.clear_zones()


func _element_from_params() -> int:
	var e := int(Router.params.get("element", ElementDefs.Element.NONE))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--element="):
			e = ElementDefs.from_id(StringName(a.substr(10)))
	if not ElementDefs.is_valid(e):
		e = GameState.element if GameState.has_element() else ElementDefs.Element.FIRE
	return e


func _height(x: float, z: float) -> float:
	return -POOL_DEPTH if POOL.has_point(Vector2(x, z)) else 0.0


# --- environment ----------------------------------------------------------------------------

func _build_environment() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-42, 148, 0)
	sun.light_energy = 1.2
	sun.light_color = Color(1.0, 0.92, 0.8)
	add_child(sun)
	Settings.configure_sun(sun)
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var mat := ProceduralSkyMaterial.new()
	mat.sky_top_color = Color(0.16, 0.36, 0.74)
	mat.sky_horizon_color = Color(0.58, 0.7, 0.84)
	mat.ground_horizon_color = Color(0.5, 0.47, 0.42)
	mat.ground_bottom_color = Color(0.26, 0.23, 0.2)
	mat.sun_angle_max = 20.0
	sky.sky_material = mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.95
	env.glow_enabled = true
	env.glow_intensity = 0.25
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.1
	env.fog_enabled = true
	env.fog_light_color = Color(0.6, 0.68, 0.8)
	env.fog_density = 0.0012
	env.fog_aerial_perspective = 0.5
	Settings.configure_environment(env)
	env.volumetric_fog_enabled = false
	we.environment = env
	add_child(we)
	Events.graphics_settings_changed.connect(func() -> void:
		Settings.configure_environment(env)
		env.volumetric_fog_enabled = false
		Settings.configure_sun(sun))


func _static_box(pos: Vector3, size: Vector3, color: Color, tex: Texture2D = null, rot_deg: Vector3 = Vector3.ZERO) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = Layers.WORLD
	sb.position = pos
	sb.rotation_degrees = rot_deg
	add_child(sb)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	sb.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var opts := {"outline": false}
	if tex:
		opts["texture"] = tex
		opts["unique"] = true
	mi.material_override = ToonMaterials.make(color, opts)
	sb.add_child(mi)
	return sb


func _build_ground() -> void:
	var tiles := _tile_texture()
	# Courtyard floor around the pool (top at y = 0), pool basin below.
	var big := 120.0
	var px0 := POOL.position.x
	var px1 := POOL.end.x
	var pz0 := POOL.position.y
	var pz1 := POOL.end.y
	_ground_slab(Rect2(-big * 0.5, -big * 0.5, px0 + big * 0.5, big), tiles)
	_ground_slab(Rect2(px1, -big * 0.5, big * 0.5 - px1, big), tiles)
	_ground_slab(Rect2(px0, -big * 0.5, px1 - px0, pz0 + big * 0.5), tiles)
	_ground_slab(Rect2(px0, pz1, px1 - px0, big * 0.5 - pz1), tiles)
	_static_box(Vector3(POOL.get_center().x, -POOL_DEPTH - 0.25, POOL.get_center().y), Vector3(POOL.size.x, 0.5, POOL.size.y), Color(0.42, 0.46, 0.44))
	# Water surface.
	var water := MeshInstance3D.new()
	var wm := PlaneMesh.new()
	wm.size = POOL.size
	water.mesh = wm
	water.position = Vector3(POOL.get_center().x, -0.06, POOL.get_center().y)
	var wmat := WaterStream.material()
	wmat.set_shader_parameter(&"opacity", 0.72)
	wmat.set_shader_parameter(&"wobble", 0.0)
	wmat.set_shader_parameter(&"flow_speed", 0.25)
	wmat.set_shader_parameter(&"foam_amount", 0.35)
	water.material_override = wmat
	add_child(water)
	# Low stone rim around the pool.
	var rim_c := Color(0.62, 0.58, 0.52)
	_static_box(Vector3(POOL.get_center().x, 0.12, pz0 - 0.2), Vector3(POOL.size.x + 0.8, 0.24, 0.4), rim_c)
	_static_box(Vector3(POOL.get_center().x, 0.12, pz1 + 0.2), Vector3(POOL.size.x + 0.8, 0.24, 0.4), rim_c)
	_static_box(Vector3(px1 + 0.2, 0.12, POOL.get_center().y), Vector3(0.4, 0.24, POOL.size.y), rim_c)
	# Snow patch and ice rink (surface zones; visual layers on the floor).
	_patch(SNOW, Color(0.86, 0.9, 0.96), 0.03, 0.9)
	_patch(ICE, Color(0.72, 0.88, 0.97), 0.02, 0.15)


func _ground_slab(r: Rect2, tex: Texture2D) -> void:
	if r.size.x <= 0.01 or r.size.y <= 0.01:
		return
	var sb := StaticBody3D.new()
	sb.collision_layer = Layers.WORLD
	sb.position = Vector3(r.get_center().x, -0.5, r.get_center().y)
	add_child(sb)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(r.size.x, 1.0, r.size.y)
	cs.shape = box
	sb.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.position = Vector3(0, 0.5, 0)
	# The tile texture holds 16 x 16 tiles: 2 m tiles -> one repeat per 32 m.
	mi.mesh = _uv_plane(r.size, r.size / 32.0)
	mi.material_override = ToonMaterials.make(Color(0.62, 0.57, 0.5), {"outline": false, "texture": tex, "unique": true})
	sb.add_child(mi)


func _uv_plane(size: Vector2, uv_scale: Vector2) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	var corners := [Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(hx, 0, hz), Vector3(-hx, 0, hz)]
	var uvs := [Vector2(0, 0), Vector2(uv_scale.x, 0), uv_scale, Vector2(0, uv_scale.y)]
	for i: int in [0, 1, 2, 0, 2, 3]:
		st.set_normal(Vector3.UP)
		st.set_uv(uvs[i])
		st.add_vertex(corners[i])
	return st.commit()


func _patch(r: Rect2, color: Color, h: float, rough: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _uv_plane(r.size, Vector2.ONE)
	mi.position = Vector3(r.get_center().x, h, r.get_center().y)
	var m := ToonMaterials.make(color, {"outline": false, "specular": 0.6 if rough < 0.5 else 0.05, "rim": 0.1})
	mi.material_override = m
	add_child(mi)


func _tile_texture() -> Texture2D:
	var img := Image.create(256, 256, false, Image.FORMAT_RGB8)
	var fn := FastNoiseLite.new()
	fn.frequency = 0.05
	for y in 256:
		for x in 256:
			var line := (x % 16) == 0 or (y % 16) == 0
			var cell := Vector2i(x / 16, y / 16)
			var tone := 0.9 + 0.08 * fn.get_noise_2d(cell.x * 7.0, cell.y * 7.0) + 0.03 * fn.get_noise_2d(x * 3.0, y * 3.0)
			img.set_pixel(x, y, Color(0.72, 0.69, 0.64) if line else Color(tone, tone * 0.97, tone * 0.92))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _build_props() -> void:
	var stone := Color(0.6, 0.56, 0.5)
	# Steps (0.25 m risers) up to a platform: step-up check.
	for i in 4:
		_static_box(Vector3(-6.0, 0.125 + i * 0.25, -2.0 - i * 0.6), Vector3(3.0, 0.25 + i * 0.5, 0.6), stone)
	_static_box(Vector3(-6.0, 0.5, -5.6), Vector3(3.0, 1.0, 2.4), stone)
	# Walkable ramp (25 deg) and a steep one (50 deg, not walkable).
	_static_box(Vector3(5.0, 0.6, 8.0), Vector3(3.0, 0.3, 5.0), stone, null, Vector3(25, 0, 0))
	_static_box(Vector3(9.5, 1.0, 8.0), Vector3(2.0, 0.3, 4.0), stone, null, Vector3(50, 0, 0))
	# Pillars (line of sight / camera collision) and an enclosing low wall.
	for p: Vector3 in [Vector3(-4, 0, -14), Vector3(4, 0, -14), Vector3(-9, 0, -20), Vector3(9, 0, -20)]:
		_static_box(p + Vector3(0, 1.6, 0), Vector3(0.9, 3.2, 0.9), Color(0.55, 0.47, 0.4))
	for side in [-1, 1]:
		_static_box(Vector3(side * 24.0, 0.6, -4.0), Vector3(0.8, 1.2, 50.0), stone)
	_static_box(Vector3(0, 0.6, -29.0), Vector3(48.8, 1.2, 0.8), stone)


func _spawn_targets() -> void:
	for p: Vector3 in [Vector3(-3.2, 0, -6.0), Vector3(0.0, 0, -7.0), Vector3(3.2, 0, -6.0)]:
		var d := TrainingDummy.new()
		d.look = &"post"
		d.position = p
		add_child(d)
		d.home = d.global_transform
		dummies.append(d)
	var h := TrainingDummy.new()
	h.look = &"humanoid"
	h.display_name = "Sparring Dummy"
	h.position = Vector3(6.5, 0, -9.0)
	add_child(h)
	h.home = h.global_transform
	dummies.append(h)
	bot = SparringBot.new()
	bot.position = Vector3(0, 0, -15.0)
	add_child(bot)


func _add_ui() -> void:
	var hud_scene := load("res://scenes/ui/hud.tscn") as PackedScene
	if hud_scene:
		hud = hud_scene.instantiate()
		add_child(hud)
		if hud.has_method("bind_player"):
			hud.call("bind_player", player)
	var pause_scene := load("res://scenes/ui/pause_menu.tscn") as PackedScene
	if pause_scene:
		add_child(pause_scene.instantiate())
	var cl := CanvasLayer.new()
	cl.layer = 20
	add_child(cl)
	# Top-right corner: the HUD uses the other corners and the top centre.
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	box.offset_top = 64.0
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(box)
	_info = Label.new()
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_info.add_theme_font_size_override(&"font_size", 14)
	_info.add_theme_constant_override(&"outline_size", 4)
	_info.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.6))
	_info.modulate = Color(1, 0.95, 0.8, 0.9)
	box.add_child(_info)
	_help = Label.new()
	_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_help.add_theme_font_size_override(&"font_size", 12)
	_help.add_theme_constant_override(&"outline_size", 4)
	_help.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.6))
	_help.modulate = Color(1, 1, 1, 0.75)
	_help.text = "COMBAT ARENA\nF1-F4 element · F5 reset dummies · F6 bot · F7 infinite chi · F8 hide\nLMB light · RMB heavy (hold) · Q defend · C dodge · 1-4 techniques · Tab lock-on"
	box.add_child(_help)


func _process(_delta: float) -> void:
	if _info and player:
		_info.text = "%s · %s · chi %d · focus %d · %d fps" % [ElementDefs.display_name(player.element), player.get_state_name(),
				int(player.resources.chi), int(player.resources.focus), Engine.get_frames_per_second()]


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	match k.physical_keycode:
		KEY_F1: switch_element(ElementDefs.Element.AIR)
		KEY_F2: switch_element(ElementDefs.Element.EARTH)
		KEY_F3: switch_element(ElementDefs.Element.FIRE)
		KEY_F4: switch_element(ElementDefs.Element.WATER)
		KEY_F5: reset_dummies()
		KEY_F6: bot.active = not bot.active
		KEY_F7: player.resources.infinite_chi = not player.resources.infinite_chi
		KEY_F8: _help.visible = not _help.visible


## Dev: switches the player's element (GameState.element too, so the HUD emblem follows).
func switch_element(e: int) -> void:
	if e == player.element:
		return
	GameState.element = e
	# Dev only: technique slots start empty so the new element's starters
	# fill them from slot 1.
	GameState.equipped_abilities = [&"", &"", &"", &""] as Array[StringName]
	player.set_element(e)
	if hud and hud.has_method("bind_player"):
		var cb := Callable(hud, &"set_resource")
		if player.resource_changed.is_connected(cb):
			player.resource_changed.disconnect(cb)
		hud.call("bind_player", player)


func reset_dummies() -> void:
	for d in dummies:
		d.reset()
		d.clear_stats()


func _on_player_died() -> void:
	await get_tree().create_timer(2.0, false).timeout
	if is_instance_valid(player):
		player.respawn_at(Transform3D(Basis.IDENTITY, START), 1.0)
