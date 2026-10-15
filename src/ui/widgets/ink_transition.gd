class_name InkTransition
extends Control
## Short cinematic brush wipe: broad strokes in the element colour sweep across the
## screen, the element's emblem bursts in the centre with its name, then everything
## sinks to ink black (the Router fade continues from black). ~1.3 s.
##
##   var t := InkTransition.new(); add_child(t)
##   await t.play(ElementDefs.Element.FIRE)

signal finished

const STROKES := 6
var duration := 1.3
var _black: ColorRect
var _emblem: TextureRect
var _name: Label
var _strokes: Array[BrushStroke] = []


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


## Plays the wipe for `element` (gold if NONE). Await `finished` or this coroutine.
func play(element: int) -> void:
	visible = true
	var c := UiTheme.element_color(element)
	var vp := get_viewport_rect().size
	for s in _strokes:
		s.queue_free()
	_strokes.clear()
	for i in STROKES:
		var tint := c.darkened(0.1 + 0.1 * (i % 3)) if i % 2 == 0 else c.lerp(UiTheme.INK, 0.35 + 0.1 * i)
		var s := BrushStroke.new(tint, i * 1.7)
		s.set_param(&"thickness", 0.86).set_param(&"tail", 0.25).set_param(&"dryness", 0.5)
		var h := vp.y / STROKES * 1.9
		s.size = Vector2(vp.x * 1.5, h)
		s.position = Vector2(-vp.x * 0.25, -h * 0.35 + i * vp.y / STROKES * 0.98)
		s.rotation = deg_to_rad(-6.0 + i * 1.5)
		s.set_param(&"flip", i % 2 == 1)
		s.progress = 0.0
		add_child(s)
		_strokes.append(s)
		s.sweep(0.42, 0.0, 1.0, i * 0.05)
	_black = ColorRect.new()
	_black.color = Color(0.02, 0.018, 0.016, 0.0)
	_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_emblem = TextureRect.new()
	_emblem.texture = UiTheme.emblem(element)
	_emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_emblem.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_emblem.size = Vector2(300, 300)
	_emblem.position = vp * 0.5 - Vector2(150, 190)
	_emblem.pivot_offset = Vector2(150, 150)
	_emblem.modulate = Color(UiTheme.PARCHMENT, 0.0)
	_emblem.scale = Vector2.ONE * 0.6
	add_child(_emblem)
	_name = UiTheme.make_label(ElementDefs.display_name(element).to_upper() if ElementDefs.is_valid(element) else "",
			UiTheme.title_font(700, 18), 46, UiTheme.PARCHMENT, HORIZONTAL_ALIGNMENT_CENTER)
	_name.size = Vector2(vp.x, 60)
	_name.position = Vector2(0, vp.y * 0.5 + 140)
	_name.modulate.a = 0.0
	add_child(_name)
	add_child(_black)
	var t := create_tween()
	t.tween_interval(0.3)
	t.tween_property(_emblem, "modulate:a", 1.0, 0.18)
	t.parallel().tween_property(_emblem, "scale", Vector2.ONE * 1.08, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(_name, "modulate:a", 1.0, 0.25)
	t.tween_property(_emblem, "scale", Vector2.ONE, 0.25)
	t.tween_interval(maxf(0.0, duration - 1.05))
	t.tween_property(_black, "color:a", 1.0, 0.3)
	await t.finished
	finished.emit()
