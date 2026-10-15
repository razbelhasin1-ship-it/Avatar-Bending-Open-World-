class_name Playtest
extends Node
## Scripted playtest runner with simulated input and screenshots.
##
## Run: tools/playtest.sh <scenario> [out_dir]
## Scenario files live in tests/playtest/scenarios/<name>.gd and look like:
##
##   extends RefCounted
##   func run(p: Playtest) -> void:
##       await p.load_scene("res://scenes/world/world.tscn", {"element": ElementDefs.Element.FIRE})
##       await p.wait_game(2.0)   # game time; p.wait() is wall clock
##       p.hold("move_forward")
##       await p.wait_game(1.0)
##       p.release("move_forward")
##       await p.tap("attack_light")
##       await p.screenshot("after_attack")
##       p.check(p.player() != null, "player exists")
##
## Exits with code 1 if any check failed. Screenshots need a real display
## (tools/playtest.sh wraps Godot in xvfb-run); headless runs skip them.

var out_dir: String = ""
var failures: Array[String] = []
var log_lines: Array[String] = []
var shots: Array[String] = []
var _scene: Node = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var scenario_path := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scenario="):
			scenario_path = a.substr(11)
		elif a.begins_with("--out="):
			out_dir = a.substr(6)
	if not scenario_path.begins_with("res://"):
		scenario_path = "res://tests/playtest/scenarios/%s.gd" % scenario_path.trim_suffix(".gd")
	if out_dir.is_empty():
		out_dir = OS.get_user_data_dir().path_join("playtest")
	DirAccess.make_dir_recursive_absolute(out_dir)
	await get_tree().process_frame
	var script := load(scenario_path) as GDScript
	if script == null:
		failures.append("cannot load scenario %s" % scenario_path)
		_finish()
		return
	var scenario: Object = script.new()
	note("scenario %s" % scenario_path)
	await scenario.run(self)
	_finish()


func _finish() -> void:
	release_all()
	print("")
	for s in shots:
		print("SCREENSHOT: ", s)
	if failures.is_empty():
		print("PLAYTEST PASSED")
	else:
		print("PLAYTEST FAILED")
		for f in failures:
			print("  - ", f)
	get_tree().quit(1 if not failures.is_empty() else 0)


# --- Scene control ----------------------------------------------------------------

## Instantiates a scene as the current scene (with Router.params set).
func load_scene(path: String, params: Dictionary = {}) -> Node:
	Router.params = params
	var packed := load(path) as PackedScene
	if packed == null:
		check(false, "cannot load scene %s" % path)
		return null
	if _scene and is_instance_valid(_scene):
		_scene.queue_free()
		await get_tree().process_frame
	_scene = packed.instantiate()
	get_tree().root.add_child(_scene)
	get_tree().current_scene = _scene
	await get_tree().process_frame
	await get_tree().process_frame
	return _scene


## Uses the real Router flow (fade + threaded load).
func goto_scene(path: String, params: Dictionary = {}) -> void:
	await Router.goto(path, params, 0.05)
	_scene = get_tree().current_scene


func scene() -> Node:
	return get_tree().current_scene


func player() -> Node3D:
	return get_tree().get_first_node_in_group(&"player") as Node3D


## Waits wall-clock seconds. Under software rendering frames are slow and physics
## is capped per frame, so prefer wait_game() for gameplay timing.
func wait(t: float) -> void:
	await get_tree().create_timer(t, true, false, true).timeout


## Waits `t` seconds of GAME time (physics ticks), independent of render speed.
## Use this for anything gameplay-timed: combos, cooldowns, AI, movement distances.
func wait_game(t: float) -> void:
	var ticks := maxi(1, int(round(t * Engine.physics_ticks_per_second)))
	for i in ticks:
		await get_tree().physics_frame


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## Waits until `cond` returns true or `timeout` passes. Returns success.
func wait_until(cond: Callable, timeout: float = 10.0) -> bool:
	var t := 0.0
	while t < timeout:
		if cond.call():
			return true
		await get_tree().process_frame
		t += get_process_delta_time()
	return false


# --- Input ------------------------------------------------------------------------

func hold(action: StringName, strength: float = 1.0) -> void:
	Input.action_press(action, strength)
	_emit_action(action, true, strength)


func release(action: StringName) -> void:
	Input.action_release(action)
	_emit_action(action, false, 0.0)


func tap(action: StringName, hold_time: float = 0.06) -> void:
	hold(action)
	await wait_game(hold_time)
	release(action)
	await get_tree().physics_frame


func release_all() -> void:
	for a in InputMap.get_actions():
		if Input.is_action_pressed(a):
			Input.action_release(a)


## Simulates mouse look (pixels of relative motion).
func look(dx: float, dy: float) -> void:
	var ev := InputEventMouseMotion.new()
	ev.relative = Vector2(dx, dy)
	ev.screen_relative = Vector2(dx, dy)
	Input.parse_input_event(ev)


func _emit_action(action: StringName, pressed: bool, strength: float) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	ev.strength = strength
	Input.parse_input_event(ev)


# --- Output -------------------------------------------------------------------------

func screenshot(shot_name: String) -> String:
	if DisplayServer.get_name() == "headless":
		note("skip screenshot %s (headless)" % shot_name)
		return ""
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := out_dir.path_join("%s.png" % shot_name)
	img.save_png(path)
	shots.append(path)
	return path


func check(cond: bool, msg: String) -> bool:
	if not cond:
		failures.append(msg)
		print("CHECK FAILED: ", msg)
	else:
		print("check ok: ", msg)
	return cond


func note(msg: String) -> void:
	log_lines.append(msg)
	print("[playtest] ", msg)
