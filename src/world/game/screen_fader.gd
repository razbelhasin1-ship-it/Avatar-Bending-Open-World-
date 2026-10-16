class_name ScreenFader
extends CanvasLayer
## Full-screen black fade owned by a playable scene (layer 110: above the HUD, pause menu
## and cinematic overlays, below the Router fade and the loading overlay). Used for
## respawns, travel and cinematic skips so they never depend on the Router.
##
##   await fader.fade_out(0.35)      # to black
##   ... teleport ...
##   await fader.fade_in(0.5)

var rect: ColorRect
var label: Label
var _tween: Tween


func _ready() -> void:
	layer = 110
	process_mode = Node.PROCESS_MODE_ALWAYS
	rect = ColorRect.new()
	rect.name = "Black"
	rect.color = Color(0.02, 0.018, 0.016, 1.0)
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.modulate.a = 0.0
	rect.visible = false
	add_child(rect)
	label = UiTheme.make_label("", UiTheme.title_font(600, 8), UiTheme.SIZE_SMALL + 2, Color(UiTheme.PARCHMENT, 0.85), HORIZONTAL_ALIGNMENT_CENTER)
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	label.offset_left = -800
	label.offset_right = 800
	label.offset_top = -24
	label.offset_bottom = 24
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.add_child(label)


## Text shown in the middle of the black screen ("Sailing to ..."); "" clears it.
func set_text(text: String) -> void:
	label.text = text.to_upper()


## Opacity 0..1 of the black layer.
func amount() -> float:
	return rect.modulate.a if rect.visible else 0.0


func is_black() -> bool:
	return amount() >= 0.999


## Fades to black over `t` seconds (real time; works while paused).
func fade_out(t: float = 0.35) -> void:
	await _fade(1.0, t)


## Fades from black back to the scene.
func fade_in(t: float = 0.45) -> void:
	await _fade(0.0, t)


## Jumps to an opacity without animating.
func set_amount(a: float) -> void:
	_kill()
	rect.modulate.a = clampf(a, 0.0, 1.0)
	rect.visible = rect.modulate.a > 0.0


func _fade(target: float, t: float) -> void:
	_kill()
	rect.visible = true
	if t <= 0.0:
		set_amount(target)
		return
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(rect, "modulate:a", target, t)
	_tween = tw
	# Poll instead of awaiting `finished`: a fade replaced by another one is killed and
	# would never emit it (the caller must not hang).
	var t0 := Time.get_ticks_msec()
	while is_instance_valid(tw) and tw.is_valid() and tw.is_running() and Time.get_ticks_msec() - t0 < int(t * 1000.0) + 2000:
		await get_tree().process_frame
	if _tween == tw:
		rect.modulate.a = target
		_tween = null
	rect.visible = rect.modulate.a > 0.001


func _kill() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = null
