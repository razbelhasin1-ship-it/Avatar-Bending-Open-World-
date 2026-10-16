class_name PlayableScene
extends Node3D
## Shared base of the two playable scenes, `WorldScene` (scenes/world/world.tscn) and
## `TutorialScene` (scenes/world/tutorial.tscn): composes the WorldRenderer, WorldContent,
## the PlayerCharacter, HUD, pause menu, dialogue box, title card, cinematic overlay and
## screen fader, runs the loading sequence (Router fade held + LoadingOverlay until terrain
## collision and nearby content exist at the spawn; never spawns into the void), installs
## module hooks (WorldHooks) and cleans up on exit (mouse, held input, fades, overlays).
##
## Subclasses override the virtual steps:
##   _configure()                        element / new_game / tutorial flags from options
##   _spawn_transform() -> Transform3D   where the player appears
##   _loading_text() -> String
##   _before_spawn(spawn)                build scene-specific props (await allowed)
##   _after_spawn()                      the player exists and stands on the ground
##   _prepare_first_frame()              choose the camera of the first visible frame
##   _play()                             after the reveal (cinematic, directors ...)
##
## Options (Router.params, or `options` set before adding the node in tests):
##   element: int, new_game: bool, skip_intro: bool, no_content: bool (no WorldContent),
##   spawn: Transform3D (override), time_of_day: float, collision_timeout: float (s, 25),
##   content_timeout: float (s, 25).

signal player_ready(player: PlayerCharacter)
## Loading finished, the scene is visible and controllable (after an arrival cinematic
## starts; WorldScene emits `gameplay_started` when control is handed to the player).
signal ready_for_play

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const HUD_SCENE := "res://scenes/ui/hud.tscn"
const PAUSE_SCENE := "res://scenes/ui/pause_menu.tscn"
const DIALOGUE_SCENE := "res://scenes/ui/dialogue_box.tscn"
const TITLE_SCENE := "res://scenes/ui/title_card.tscn"

var options: Dictionary = {}
var element: int = ElementDefs.Element.NONE
var is_tutorial := false
var new_game := true
## Extra hook scripts to install besides WorldHooks.HOOK_PATHS (tests, dev scenes).
var extra_hooks: Array[String] = []

var renderer: WorldRenderer
var content: WorldContent
var player: PlayerCharacter
var hud: Hud
var pause_menu: PauseMenu
var dialogue: DialogueBox
var title_card: TitleCard
var overlay: CinematicOverlay
var fader: ScreenFader
var hooks: Array[Node] = []
var hooks_root: Node
var companion_root: Node3D
var props_root: Node3D
var focus_marker: Node3D
var loading: LoadingOverlay
## True once the loading sequence finished and the scene was revealed.
var is_ready := false
## Diagnostics of the last boot: {"collision_ready", "collision_s", "content_settled",
## "content_s", "total_s", "safety_floor"}.
var load_report: Dictionary = {}

var _holding_fade := false
var _exiting := false
var _safety_floor: StaticBody3D = null
var _dialogue_open := false


func _ready() -> void:
	add_to_group(&"playable_scene")
	var merged := Router.params.duplicate()
	merged.merge(options, true)
	options = merged
	if Router.is_transitioning:
		Router.hold_fade()
		_holding_fade = true
	_configure()
	if not ElementDefs.is_valid(element):
		element = GameState.element if GameState.has_element() else ElementDefs.Element.WATER
	if not GameState.has_element():
		GameState.new_game(element, is_tutorial)
	if options.has("time_of_day"):
		GameState.time_of_day = float(options["time_of_day"])
	_build_scene()
	_boot()


func _exit_tree() -> void:
	_exiting = true
	WorldHooks.call_all(hooks, &"world_exit")
	if _holding_fade:
		_holding_fade = false
		Router.release_fade()
	if loading and is_instance_valid(loading):
		loading.queue_free()
	loading = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Never leak held actions (touch overlay, scripted input) into the next scene.
	for a in InputMap.get_actions():
		if Input.is_action_pressed(a):
			Input.action_release(a)
	Engine.time_scale = 1.0
	WorldData.clear_water_sources()
	if Events.companion_spawned.is_connected(_on_companion_spawned):
		Events.companion_spawned.disconnect(_on_companion_spawned)


# --- virtual steps -------------------------------------------------------------------------------

func _configure() -> void:
	element = int(options.get("element", GameState.element))
	new_game = bool(options.get("new_game", true))


func _spawn_transform() -> Transform3D:
	return WorldData.get_spawn(element)


func _loading_text() -> String:
	return "Entering the world"


func _before_spawn(_spawn: Transform3D) -> void:
	pass


func _after_spawn() -> void:
	pass


func _prepare_first_frame() -> void:
	if player and player.camera_rig:
		player.camera_rig.make_current()


func _play() -> void:
	capture_mouse()


# --- composition ---------------------------------------------------------------------------------

func _build_scene() -> void:
	focus_marker = Node3D.new()
	focus_marker.name = "SpawnFocus"
	add_child(focus_marker)
	renderer = WorldRenderer.new()
	renderer.name = "WorldRenderer"
	add_child(renderer)
	if not bool(options.get("no_content", false)):
		content = WorldContent.new()
		content.name = "WorldContent"
		add_child(content)
	props_root = Node3D.new()
	props_root.name = "Props"
	add_child(props_root)
	companion_root = Node3D.new()
	companion_root.name = "Companions"
	add_child(companion_root)
	hooks_root = Node.new()
	hooks_root.name = "Hooks"
	add_child(hooks_root)
	hud = (load(HUD_SCENE) as PackedScene).instantiate() as Hud
	hud.name = "Hud"
	add_child(hud)
	hud.visible = false
	var dl := CanvasLayer.new()
	dl.name = "DialogueLayer"
	dl.layer = 30
	add_child(dl)
	dialogue = (load(DIALOGUE_SCENE) as PackedScene).instantiate() as DialogueBox
	dl.add_child(dialogue)
	overlay = CinematicOverlay.new()
	overlay.name = "CinematicOverlay"
	add_child(overlay)
	var tl := CanvasLayer.new()
	tl.name = "TitleLayer"
	tl.layer = 40
	add_child(tl)
	title_card = (load(TITLE_SCENE) as PackedScene).instantiate() as TitleCard
	tl.add_child(title_card)
	fader = ScreenFader.new()
	fader.name = "Fader"
	add_child(fader)
	hooks = WorldHooks.install(hooks_root, extra_hooks)
	WorldHooks.call_all(hooks, &"world_setup", [self])


func _boot() -> void:
	var t0 := Time.get_ticks_msec()
	loading = LoadingOverlay.open(get_tree(), _loading_text(), element)
	loading.set_progress(0.05)
	var spawn: Transform3D = options.get("spawn", _spawn_transform())
	focus_marker.global_transform = spawn
	renderer.setup(focus_marker, null)
	if content:
		content.setup(focus_marker, null)
	await _before_spawn(spawn)
	if _exiting:
		return
	var tc := Time.get_ticks_msec()
	load_report["collision_ready"] = await wait_for_ground(spawn.origin, float(options.get("collision_timeout", 25.0)))
	load_report["collision_s"] = (Time.get_ticks_msec() - tc) / 1000.0
	if _exiting:
		return
	_set_progress(0.35)
	var tcont := Time.get_ticks_msec()
	load_report["content_settled"] = await _wait_content(float(options.get("content_timeout", 25.0)))
	load_report["content_s"] = (Time.get_ticks_msec() - tcont) / 1000.0
	if _exiting:
		return
	_set_progress(0.9)
	spawn = ground_transform(spawn)
	_spawn_player(spawn)
	for i in 3:
		await get_tree().physics_frame
	if _exiting:
		return
	await _after_spawn()
	if _exiting:
		return
	_prepare_first_frame()
	# Warm-up frames (shader compilation, first content instancing) behind the black.
	for i in 3:
		await get_tree().process_frame
	_set_progress(1.0)
	load_report["total_s"] = (Time.get_ticks_msec() - t0) / 1000.0
	_reveal()
	is_ready = true
	ready_for_play.emit()
	_play()


func _set_progress(r: float) -> void:
	if loading and is_instance_valid(loading):
		loading.set_progress(r)


func _reveal() -> void:
	if loading and is_instance_valid(loading):
		loading.close()
	loading = null
	if _holding_fade:
		_holding_fade = false
		Router.release_fade()


## Waits until terrain collision exists under (and around) `pos`, building the patch now
## if needed. Returns false on timeout (a temporary safety floor then holds the spawn).
func wait_for_ground(pos: Vector3, timeout: float = 25.0) -> bool:
	var probes: Array[Vector3] = [pos, pos + Vector3(6, 0, 0), pos + Vector3(-6, 0, 0), pos + Vector3(0, 0, 6), pos + Vector3(0, 0, -6)]
	var t0 := Time.get_ticks_msec()
	for p in probes:
		renderer.ensure_collision_now(p)
	while Time.get_ticks_msec() - t0 < int(timeout * 1000.0):
		var all := true
		for p in probes:
			if not renderer.is_collision_ready_at(p):
				all = false
				renderer.ensure_collision_now(p)
		if all:
			return true
		await get_tree().physics_frame
		if _exiting:
			return false
	return false


func _wait_content(timeout: float) -> bool:
	if content == null:
		return true
	var t0 := Time.get_ticks_msec()
	# One scan has to happen before "settled" means anything.
	await get_tree().process_frame
	await get_tree().process_frame
	var start_left := -1
	while Time.get_ticks_msec() - t0 < int(timeout * 1000.0):
		if _exiting:
			return false
		if content.is_settled():
			return true
		var st := content.get_stats()
		var left := int(st.get("queue", 0)) + int(st.get("jobs", 0)) + int(st.get("built_waiting", 0))
		start_left = maxi(start_left, left)
		if start_left > 0:
			_set_progress(0.35 + 0.5 * (1.0 - float(left) / float(start_left)))
		await get_tree().process_frame
	return content.is_settled()


## `xform` moved onto the physical ground below/at it (raycast against Layers.WORLD). When
## nothing solid is found a temporary safety floor is placed so the player never falls.
func ground_transform(xform: Transform3D) -> Transform3D:
	var o := xform.origin
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(o + Vector3.UP * 1.6, o + Vector3.DOWN * 8.0, Layers.WORLD | Layers.CONSTRUCT)
	var r := space.intersect_ray(q)
	if not r.is_empty():
		xform.origin = (r["position"] as Vector3) + Vector3.UP * 0.04
		load_report["safety_floor"] = false
		return xform
	var gy := WorldData.get_height(o.x, o.z)
	xform.origin.y = maxf(o.y, gy) + 0.05
	_add_safety_floor(xform.origin)
	load_report["safety_floor"] = true
	return xform


func _add_safety_floor(at: Vector3) -> void:
	if _safety_floor and is_instance_valid(_safety_floor):
		_safety_floor.queue_free()
	_safety_floor = StaticBody3D.new()
	_safety_floor.name = "SafetyFloor"
	_safety_floor.collision_layer = Layers.WORLD
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(8, 0.4, 8)
	cs.shape = b
	_safety_floor.add_child(cs)
	add_child(_safety_floor)
	_safety_floor.global_position = at - Vector3(0, 0.2, 0)
	_retire_safety_floor(_safety_floor, at)


func _retire_safety_floor(body: StaticBody3D, at: Vector3) -> void:
	var t0 := Time.get_ticks_msec()
	while is_instance_valid(body) and Time.get_ticks_msec() - t0 < 60000:
		await get_tree().physics_frame
		if _exiting:
			return
		if renderer.is_collision_ready_at(at):
			break
	if is_instance_valid(body):
		body.queue_free()


func _spawn_player(spawn: Transform3D) -> void:
	player = (load(PLAYER_SCENE) as PackedScene).instantiate() as PlayerCharacter
	player.name = "Player"
	player.element = element
	# The scene's respawn logic runs first; the player's own auto respawn is a backstop.
	player.auto_respawn_time = 15.0
	# Placed before entering the tree, so Events.player_spawned already carries the spawn.
	player.transform = Transform3D(Basis(Vector3.UP, spawn.basis.get_euler().y), spawn.origin)
	add_child(player)
	if player.camera_rig:
		player.camera_rig.require_capture = not Settings.is_test_run()
	hud.bind_player(player)
	renderer.set_focus(player)
	if content:
		content.set_focus(player)
	WorldHooks.call_all(hooks, &"player_spawned", [player])
	# No companion module yet -> no companion panel (never show a feature that is not there).
	hud.companion_panel.visible = player.get_companion() != null
	if not Events.companion_spawned.is_connected(_on_companion_spawned):
		Events.companion_spawned.connect(_on_companion_spawned)
	player_ready.emit(player)


func _on_companion_spawned(_c: Node3D) -> void:
	if hud and is_instance_valid(hud):
		hud.companion_panel.visible = true


# --- services for directors, hooks and tests ---------------------------------------------------------

## Captures the mouse for camera look (desktop only; never in touch mode or test runs).
func capture_mouse() -> void:
	if Settings.touch_controls_enabled() or Settings.is_test_run() or _exiting:
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func release_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Shows/hides the gameplay HUD (cinematics). Fades when `t` > 0.
func set_hud_visible(on: bool, t: float = 0.5) -> void:
	if hud == null:
		return
	if on:
		hud.visible = true
		if t > 0.0:
			hud.root.modulate.a = 0.0
			var tw := hud.create_tween()
			tw.tween_property(hud.root, "modulate:a", 1.0, t)
		else:
			hud.root.modulate.a = 1.0
	else:
		hud.visible = false


## Adds a companion (companions module hook): parents it under "Companions", places it,
## links it to the player (HUD companion panel) and emits Events.companion_spawned.
func spawn_companion(node: Node3D, at: Transform3D = Transform3D.IDENTITY) -> void:
	if node.get_parent():
		node.get_parent().remove_child(node)
	companion_root.add_child(node)
	if at != Transform3D.IDENTITY:
		node.global_transform = at
	if player:
		player.companion = node
	Events.companion_spawned.emit(node)


## Quest system hook: forwards to Hud.bind_quest_provider.
func set_quest_provider(provider: Object) -> void:
	if hud:
		hud.bind_quest_provider(provider)


## Seconds of unpaused scene time (pause-aware wait for directors).
func wait_seconds(t: float) -> void:
	var left := t
	while left > 0.0 and not _exiting:
		await get_tree().process_frame
		if not get_tree().paused:
			left -= get_process_delta_time()


## Fades to black, runs `midpoint` (may await), fades back in.
func fade_through(midpoint: Callable, out_t: float = 0.35, in_t: float = 0.45) -> void:
	await fader.fade_out(out_t)
	if _exiting:
		return
	await midpoint.call()
	if _exiting:
		return
	await fader.fade_in(in_t)


## A choice through the DialogueBox with the player held still (no stuck state: the
## dialogue times out to the last option after `timeout` seconds). Returns the index.
func ask_choice(speaker: String, text: String, choices: Array, opts: Dictionary = {}, timeout: float = 90.0) -> int:
	if _dialogue_open or choices.is_empty():
		return choices.size() - 1
	_dialogue_open = true
	var mouse_before := Input.mouse_mode
	if not Settings.touch_controls_enabled():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if player:
		player.enter_cinematic(timeout + 5.0)
	Events.dialogue_started.emit(self)
	var result := {"index": -1}
	var on_choice := func(i: int) -> void: result["index"] = i
	dialogue.choice_made.connect(on_choice)
	dialogue.open()
	dialogue.ask(speaker, text, choices, opts)
	var t0 := Time.get_ticks_msec()
	while int(result["index"]) < 0 and not _exiting:
		if Time.get_ticks_msec() - t0 > int(timeout * 1000.0):
			dialogue.choose(choices.size() - 1)
			if int(result["index"]) < 0:
				result["index"] = choices.size() - 1
			break
		await get_tree().process_frame
	if dialogue.choice_made.is_connected(on_choice):
		dialogue.choice_made.disconnect(on_choice)
	dialogue.close()
	Events.dialogue_ended.emit(self)
	if player and not _exiting:
		player.exit_cinematic()
	if not _exiting and mouse_before == Input.MOUSE_MODE_CAPTURED:
		capture_mouse()
	_dialogue_open = false
	return int(result["index"])


func is_dialogue_open() -> bool:
	return _dialogue_open


## True once the scene started leaving the tree (coroutines bail out).
func is_exiting() -> bool:
	return _exiting


func _unhandled_input(event: InputEvent) -> void:
	# Back out of an open choice with B / Esc picks the last ("cancel") option.
	if _dialogue_open and dialogue.choices.size() > 0 and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		dialogue.choose(dialogue.choices.size() - 1)
