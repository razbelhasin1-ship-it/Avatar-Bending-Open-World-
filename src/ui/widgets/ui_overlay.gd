class_name UiOverlay
extends Control
## Base for full-screen modal layers (settings, pause, confirms): dims and softly blurs
## what is behind, fades in/out with ui_open/ui_close, swallows input underneath, returns
## focus to whatever had it before opening, and routes Esc / controller B to `_on_back()`.

signal opened
signal closed

const BLUR_SHADER := preload("res://src/ui/shaders/backdrop_blur.gdshader")

## Dim amount of the backdrop (0..1).
var dim := 0.55
## Blur the scene behind (screen texture mip blur).
var blur := true
var is_open := false

var backdrop: ColorRect
var _prev_focus: Control = null
var _fade: Tween


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func _ready() -> void:
	theme = UiTheme.get_theme()
	backdrop = ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if blur:
		var m := ShaderMaterial.new()
		m.shader = BLUR_SHADER
		m.set_shader_parameter(&"dim", dim)
		backdrop.material = m
	else:
		backdrop.color = Color(0, 0, 0, dim)
	add_child(backdrop)
	move_child(backdrop, 0)
	if blur:
		# fresh screen copy here, so stacked overlays blur what is actually beneath them
		var bbc := BackBufferCopy.new()
		bbc.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
		add_child(bbc)
		move_child(bbc, 0)
	_build()


## Override: build the overlay content (called from _ready).
func _build() -> void:
	pass


## Override: first control to focus when opened.
func _initial_focus() -> Control:
	return null


## Override: Esc / B pressed while open. Default closes.
func _on_back() -> void:
	close()


func open() -> void:
	if is_open:
		return
	is_open = true
	_prev_focus = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	visible = true
	UiFx.sound(UiFx.OPEN)
	_kill()
	modulate.a = 0.0
	_fade = create_tween()
	_fade.tween_property(self, "modulate:a", 1.0, 0.18).set_trans(Tween.TRANS_SINE)
	var f := _initial_focus()
	if f:
		UiFx.focus_silently(f)
	opened.emit()


func close() -> void:
	if not is_open:
		return
	is_open = false
	UiFx.sound(UiFx.CLOSE)
	_kill()
	_fade = create_tween()
	_fade.tween_property(self, "modulate:a", 0.0, 0.14).set_trans(Tween.TRANS_SINE)
	_fade.tween_callback(func() -> void:
		visible = false)
	if is_instance_valid(_prev_focus) and _prev_focus.is_visible_in_tree():
		UiFx.focus_silently(_prev_focus)
	closed.emit()


func _kill() -> void:
	if _fade and _fade.is_valid():
		_fade.kill()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed(&"ui_cancel") or (event.is_action_pressed(&"pause") and not event.is_echo()):
		get_viewport().set_input_as_handled()
		UiFx.sound(UiFx.BACK)
		_on_back()
