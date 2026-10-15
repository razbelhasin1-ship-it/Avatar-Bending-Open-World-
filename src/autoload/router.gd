extends Node
## Scene flow and transitions (autoload "Router").
##
## Router.goto(path, params) fades out, loads the scene on a background thread,
## swaps it in, then fades in. The new scene reads Router.params in _ready().
## Scenes that need extra async setup (e.g. the world streaming terrain) can
## call Router.hold_fade() in _ready() and Router.release_fade() when ready.

signal scene_changed(path: String)

const MAIN_MENU := "res://scenes/ui/main_menu.tscn"
const ELEMENT_SELECT := "res://scenes/ui/element_select.tscn"
const WORLD := "res://scenes/world/world.tscn"
const TUTORIAL := "res://scenes/world/tutorial.tscn"

var params: Dictionary = {}
var current_path: String = ""
var is_transitioning: bool = false

var _layer: CanvasLayer
var _fade: ColorRect
var _label: Label
var _hold_count := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_layer = CanvasLayer.new()
	_layer.layer = 120
	add_child(_layer)
	_fade = ColorRect.new()
	_fade.color = Color(0.02, 0.018, 0.016, 1.0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.modulate.a = 0.0
	_layer.add_child(_fade)
	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_label.position = Vector2(-360, -80)
	_label.size = Vector2(320, 40)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.add_theme_font_size_override("font_size", 22)
	_label.modulate = Color(1, 1, 1, 0.75)
	_fade.add_child(_label)
	var scene := get_tree().current_scene
	if scene:
		current_path = scene.scene_file_path


## Changes scene with a fade. `loading_text` is shown while loading.
func goto(path: String, p_params: Dictionary = {}, fade_time: float = 0.45, loading_text: String = "") -> void:
	if is_transitioning:
		return
	is_transitioning = true
	params = p_params
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	_label.text = loading_text
	await _tween_fade(1.0, fade_time)
	get_tree().paused = false
	var err := ResourceLoader.load_threaded_request(path)
	if err != OK:
		push_error("Router: cannot load %s" % path)
		is_transitioning = false
		await _tween_fade(0.0, fade_time)
		return
	while true:
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			break
		if status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			push_error("Router: failed loading %s" % path)
			is_transitioning = false
			await _tween_fade(0.0, fade_time)
			return
		await get_tree().process_frame
	var packed := ResourceLoader.load_threaded_get(path) as PackedScene
	_hold_count = 0
	get_tree().change_scene_to_packed(packed)
	current_path = path
	await get_tree().process_frame
	await get_tree().process_frame
	while _hold_count > 0:
		await get_tree().process_frame
	scene_changed.emit(path)
	_label.text = ""
	await _tween_fade(0.0, fade_time * 1.4)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	is_transitioning = false


## Keep the screen black after the scene swap until release_fade() is called.
func hold_fade() -> void:
	_hold_count += 1


func release_fade() -> void:
	_hold_count = maxi(0, _hold_count - 1)


func set_loading_text(text: String) -> void:
	_label.text = text


func goto_main_menu() -> void:
	Events.returning_to_menu.emit()
	goto(MAIN_MENU)


## Fades to black and back without changing scene (e.g. fast travel, respawn).
## `midpoint` is awaited while the screen is black.
func fade_through(midpoint: Callable, fade_time: float = 0.4) -> void:
	await _tween_fade(1.0, fade_time)
	await midpoint.call()
	await _tween_fade(0.0, fade_time)


func _tween_fade(target: float, duration: float) -> void:
	var t := create_tween()
	t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	t.tween_property(_fade, "modulate:a", target, maxf(duration, 0.01))
	await t.finished
